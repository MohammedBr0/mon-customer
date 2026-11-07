# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Weekly commutes' do
  let(:today) { Itinerary.today }
  let(:next_monday) { today + (((1 - today.wday) % 7).zero? ? 7 : (1 - today.wday) % 7) }
  # Leaves 07:30 Ethiopian time on the next Monday, repeating Monday to Friday.
  let(:commute) do
    leave = Itinerary::RIDE_ZONE.local(next_monday.year, next_monday.month, next_monday.day, 7, 30)
    create(:itinerary, num_people: 2, price_per_seat: 100, leave_date: leave, commute_days: [1, 2, 3, 4, 5])
  end

  describe Itinerary do
    it 'normalises the weekdays and flags the trip as a commute' do
      itinerary = build(:itinerary, commute_days: ['', '3', '1', '1'])

      expect(itinerary.commute_days).to eq [1, 3]
      expect(itinerary).to be_commute
      expect(build(:itinerary)).not_to be_commute
    end

    it 'rejects impossible weekdays, round trips and an end date before the start' do
      expect(build(:itinerary, commute_days: [9])).not_to be_valid
      expect(build(:itinerary, commute_days: [1], round_trip: true, return_date: 3.days.from_now)).not_to be_valid
      expect(build(:itinerary, commute_days: [1], commute_until: 3.days.ago.to_date)).not_to be_valid
    end

    it 'lists the bookable days inside the horizon and honours the end date' do
      PlatformSetting.current.update!(commute_horizon_days: 14)

      dates = commute.occurrence_dates
      expect(dates).to all(satisfy { |date| (1..5).cover?(date.wday) })
      expect(dates.first).to eq next_monday
      expect(dates.last).to be <= today + 14

      commute.update!(commute_until: next_monday + 1)
      expect(commute.occurrence_dates).to eq [next_monday, next_monday + 1]
    end

    it 'treats a one-off trip as a single bookable day' do
      one_off = create(:itinerary, leave_date: 3.days.from_now)

      expect(one_off.occurrence_dates).to eq [one_off.first_ride_date]
    end

    it 'counts seats per day, not for the whole commute' do
      create(:booking, :confirmed, itinerary: commute, seats: 2, ride_dates: [next_monday])

      expect(commute.seats_available(next_monday)).to eq 0
      expect(commute.seats_available(next_monday + 1)).to eq 2
      expect(commute.full?(next_monday)).to be true
      expect(commute.full?).to be false
    end

    it 'describes the schedule' do
      expect(commute.schedule_summary).to eq 'Mon, Tue, Wed, Thu, Fri · 07:30 AM'
    end

    it 'can be switched off by a super admin for new trips only' do
      commute
      PlatformSetting.current.update!(commutes_enabled: false)

      expect(build(:itinerary, commute_days: [1])).not_to be_valid
      expect(commute.reload).to be_valid
    end

    it 'ends once its end date has passed' do
      commute.update_columns(commute_until: today - 1)

      expect(commute).to be_past
      expect(commute.occurrence_dates).to be_empty
    end
  end

  describe Booking do
    let(:passenger) { create(:user) }

    it 'books several days at once and prices every day' do
      PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
      days = commute.occurrence_dates.first(3)
      booking = create(:booking, itinerary: commute, passenger:, seats: 1, ride_dates: days)

      expect(booking.ride_dates).to eq days
      expect(booking).to have_attributes(fare_total: 300, fee_amount: 30, passenger_total: 330, driver_payout: 300)
      expect(booking.price_breakdown.ride_count).to eq 3
    end

    it 'requires at least one day and only days the commute runs' do
      expect(build(:booking, itinerary: commute, passenger:, ride_dates: [])).not_to be_valid
      expect(build(:booking, itinerary: commute, passenger:, ride_dates: [next_monday + 5])).not_to be_valid # Saturday
      expect(build(:booking, itinerary: commute, passenger:, ride_dates: [today - 3])).not_to be_valid
    end

    it 'refuses a day that is already full but accepts the other days' do
      create(:booking, :confirmed, itinerary: commute, seats: 2, ride_dates: [next_monday])

      expect(build(:booking, itinerary: commute, passenger:, seats: 1, ride_dates: [next_monday])).not_to be_valid
      expect(build(:booking, itinerary: commute, passenger:, seats: 1, ride_dates: [next_monday, next_monday + 1])).not_to be_valid
      expect(build(:booking, itinerary: commute, passenger:, seats: 1, ride_dates: [next_monday + 1])).to be_valid
    end

    it 'refuses to confirm when a day filled up in the meantime' do
      booking = create(:booking, itinerary: commute, passenger:, seats: 2, ride_dates: [next_monday, next_monday + 1])
      create(:booking, :confirmed, itinerary: commute, seats: 1, ride_dates: [next_monday + 1])

      expect { booking.confirm! }.to raise_error(Booking::InvalidTransition, 'not_enough_seats')
    end

    it 'skips one day, reprices with the original fee terms and frees that day' do
      PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
      days = commute.occurrence_dates.first(3)
      booking = create(:booking, :confirmed, itinerary: commute, passenger:, seats: 1, ride_dates: days)
      PlatformSetting.current.update!(fee_percent: 50) # must not affect the existing booking

      booking.skip_date!(days.second, by: passenger)

      expect(booking.reload.ride_dates).to eq [days.first, days.third]
      expect(booking).to have_attributes(fare_total: 200, fee_percent: 10, fee_amount: 20, passenger_total: 220)
      expect(commute.seats_available(days.second)).to eq 2
      expect(booking).to be_confirmed
    end

    it 'cancels the booking when its last day is skipped' do
      booking = create(:booking, itinerary: commute, passenger:, ride_dates: [next_monday])

      booking.skip_date!(next_monday, by: passenger)

      expect(booking).to be_cancelled
    end

    it 'does not skip a day it does not cover or one that has passed' do
      booking = create(:booking, itinerary: commute, passenger:, ride_dates: [next_monday])

      expect { booking.skip_date!(next_monday + 1, by: passenger) }.to raise_error(Booking::InvalidTransition)
      booking.update_columns(ride_dates: [today - 1])
      expect { booking.skip_date!(today - 1, by: passenger) }.to raise_error(Booking::InvalidTransition)
    end

    it 'counts as completed, and reviewable, once the first day has passed' do
      booking = create(:booking, :confirmed, itinerary: commute, passenger:, ride_dates: [next_monday])
      expect(booking).not_to be_completed

      booking.update_columns(ride_dates: [today - 2, today + 1])
      expect(booking.reload).to be_completed
    end
  end
end
