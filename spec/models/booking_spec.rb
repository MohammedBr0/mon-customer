# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Booking do
  let(:itinerary) { create(:itinerary, num_people: 3) }
  let(:passenger) { create(:user) }

  describe 'validations' do
    it 'is valid for another user on an open itinerary' do
      expect(build(:booking, itinerary:, passenger:)).to be_valid
    end

    it 'rejects the driver booking their own itinerary' do
      booking = build(:booking, itinerary:, passenger: itinerary.user)

      expect(booking).not_to be_valid
      expect(booking.errors[:base]).to be_present
    end

    it 'rejects more seats than are free' do
      booking = build(:booking, itinerary:, passenger:, seats: 4)

      expect(booking).not_to be_valid
      expect(booking.errors[:seats]).to be_present
    end

    it 'counts only confirmed seats against capacity' do
      create(:booking, :confirmed, itinerary:, seats: 2)

      expect(build(:booking, itinerary:, passenger:, seats: 2)).not_to be_valid
      expect(build(:booking, itinerary:, passenger:, seats: 1)).to be_valid
    end

    it 'does not limit seats when the driver set no capacity' do
      itinerary.update!(num_people: nil)

      expect(build(:booking, itinerary:, passenger:, seats: 5)).to be_valid
    end

    it 'rejects bookings on a cancelled itinerary' do
      itinerary.cancel!

      expect(build(:booking, itinerary:, passenger:)).not_to be_valid
    end

    it 'rejects bookings on a trip that already left' do
      itinerary.update_columns(leave_date: 1.hour.ago)

      expect(build(:booking, itinerary:, passenger:)).not_to be_valid
    end

    it 'allows only one live booking per passenger and itinerary' do
      create(:booking, itinerary:, passenger:)

      expect(build(:booking, itinerary:, passenger:)).not_to be_valid
      expect { build(:booking, itinerary:, passenger:).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'lets a passenger book again after cancelling' do
      create(:booking, itinerary:, passenger:).cancel!(by: passenger)

      expect(build(:booking, itinerary:, passenger:)).to be_valid
    end
  end

  describe '#confirm!' do
    it 'confirms a pending booking and takes its seats' do
      booking = create(:booking, itinerary:, passenger:, seats: 2)

      booking.confirm!

      expect(booking).to be_confirmed
      expect(booking.decided_at).to be_present
      expect(itinerary.seats_available).to eq 1
    end

    it 'refuses to oversell the last seats' do
      first = create(:booking, itinerary:, seats: 2)
      second = create(:booking, itinerary:, seats: 2)

      first.confirm!

      expect { second.confirm! }.to raise_error(Booking::InvalidTransition, 'not_enough_seats')
      expect(second.reload).to be_pending
    end

    it 'refuses to confirm twice' do
      booking = create(:booking, :confirmed, itinerary:)

      expect { booking.confirm! }.to raise_error(Booking::InvalidTransition)
    end
  end

  describe '#decline!' do
    it 'declines a pending booking without taking seats' do
      booking = create(:booking, itinerary:, seats: 2)

      booking.decline!

      expect(booking).to be_declined
      expect(itinerary.seats_available).to eq 3
    end

    it 'cannot decline a confirmed booking' do
      expect { create(:booking, :confirmed, itinerary:).decline! }.to raise_error(Booking::InvalidTransition)
    end
  end

  describe '#cancel!' do
    it 'frees the seats of a confirmed booking' do
      booking = create(:booking, :confirmed, itinerary:, seats: 3)
      expect(itinerary.reload).to be_full

      booking.cancel!(by: booking.passenger)

      expect(booking).to be_cancelled
      expect(booking.cancelled_by).to eq booking.passenger
      expect(itinerary.seats_available).to eq 3
    end

    it 'cannot cancel a declined booking' do
      expect { create(:booking, itinerary:).decline!.cancel!(by: passenger) }.to raise_error(Booking::InvalidTransition)
    end
  end

  describe '#participant?' do
    it 'is true only for the passenger and the driver' do
      booking = create(:booking, itinerary:, passenger:)

      expect(booking.participant?(passenger)).to be true
      expect(booking.participant?(itinerary.user)).to be true
      expect(booking.participant?(create(:user))).to be false
      expect(booking.participant?(nil)).to be false
    end
  end
end
