# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Commutes, ride alerts and reports' do
  let(:driver) { create(:user, name: 'Dawit Driver') }
  let(:rider) { create(:user, name: 'Rahel Rider') }
  let(:today) { Itinerary.today }
  let(:next_monday) { today + (((1 - today.wday) % 7).zero? ? 7 : (1 - today.wday) % 7) }
  let(:commute) do
    leave = Itinerary::RIDE_ZONE.local(next_monday.year, next_monday.month, next_monday.day, 7, 30)
    create(:itinerary, user: driver, num_people: 3, price_per_seat: 100, leave_date: leave, commute_days: [1, 2, 3, 4, 5],
                       pickup_point: 'Mexico Square', dropoff_point: 'Bole Gate', start_address: 'Addis Ababa', end_address: 'Adama')
  end
  let(:route) do
    { start_location: [38.74, 9.03], end_location: [39.27, 8.54], via_waypoints: [], overview_path: [[38.74, 9.03], [39.27, 8.54]], overview_polyline: '_p~iF~ps|U_ulLnnqC' }.to_json
  end

  describe 'posting a weekly commute' do
    it 'saves the weekdays, end date and meeting points and alerts matching riders' do
      sign_in driver
      create(:ride_alert, user: rider)

      expect do
        post itineraries_path, params: { itinerary: { start_address: 'Addis Ababa', end_address: 'Adama', description: 'Daily to Adama',
                                                      leave_date: 2.days.from_now.to_s, price_per_seat: '90', num_people: '3', route:,
                                                      commute_days: ['', '1', '2', '3'], commute_until: (today + 60).to_s,
                                                      pickup_point: 'Mexico Square', dropoff_point: 'Adama bus station' } }
      end.to change(Itinerary, :count).by(1).and have_enqueued_job(RideAlertMatchJob)

      expect(Itinerary.last).to have_attributes(commute_days: [1, 2, 3], commute_until: today + 60, pickup_point: 'Mexico Square', daily: true)
      get itinerary_path(Itinerary.last)
      expect(response.body).to include('Mon, Tue, Wed', 'Mexico Square', 'Adama bus station')
    end

    it 'shows the weekday picker on the new trip form' do
      sign_in driver

      get new_itinerary_path

      expect(response.body).to include('itinerary[commute_days][]', 'commute_day_1', 'itinerary[pickup_point]')
    end
  end

  describe 'booking days of a commute' do
    before { sign_in rider }

    it 'offers the upcoming days and books the ones picked at the right total' do
      PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
      get itinerary_path(commute)
      expect(response.body).to include('booking[ride_dates][]', next_monday.iso8601)

      days = commute.occurrence_dates.first(3).map(&:iso8601)
      expect do
        post itinerary_bookings_path(commute), params: { booking: { seats: 1, ride_dates: days } }
      end.to change(Booking, :count).by(1)

      expect(Booking.last).to have_attributes(ride_dates: days.map { |day| Date.parse(day) }, fare_total: 300, passenger_total: 330)
    end

    it 'rejects a day the commute does not run' do
      saturday = (next_monday + 5).iso8601

      expect { post itinerary_bookings_path(commute), params: { booking: { seats: 1, ride_dates: [saturday] } } }.not_to change(Booking, :count)
      expect(flash[:error]).to be_present
    end

    it 'lets the passenger and the driver skip a single day and notifies the other side' do
      days = commute.occurrence_dates.first(3)
      booking = create(:booking, :confirmed, itinerary: commute, passenger: rider, ride_dates: days)

      expect { patch skip_date_booking_path(booking, date: days.second.iso8601) }.to have_enqueued_mail(BookingMailer, :date_skipped)
      expect(booking.reload.ride_dates).to eq [days.first, days.third]

      sign_in driver
      patch skip_date_booking_path(booking, date: days.third.iso8601)
      expect(booking.reload.ride_dates).to eq [days.first]
    end

    it 'does not let strangers skip days and ignores bad dates' do
      booking = create(:booking, itinerary: commute, passenger: rider, ride_dates: commute.occurrence_dates.first(2))
      sign_in create(:user)

      patch skip_date_booking_path(booking, date: booking.ride_dates.first.iso8601)
      expect(booking.reload.ride_dates.size).to eq 2

      sign_in rider
      patch skip_date_booking_path(booking, date: 'not-a-date')
      expect(booking.reload.ride_dates.size).to eq 2
    end

    it 'shows the days of an existing booking with skip buttons' do
      create(:booking, itinerary: commute, passenger: rider, ride_dates: commute.occurrence_dates.first(2))

      get itinerary_path(commute)

      expect(response.body).to include('skip_date', 'Skip this day')
    end
  end

  describe 'ride alerts' do
    before { sign_in rider }

    it 'saves a route from the search page as JSON' do
      expect do
        post ride_alerts_path(format: :json), params: { ride_alert: { from: 'Addis Ababa', to: 'Adama', start_location_lng: '38.75', start_location_lat: '9.02',
                                                                      end_location_lng: '39.27', end_location_lat: '8.54' } }
      end.to change(rider.ride_alerts, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['message']).to include('Alert saved')
    end

    it 'refuses an alert without coordinates' do
      post ride_alerts_path(format: :json), params: { ride_alert: { from: 'Addis Ababa', to: 'Adama' } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'lists alerts with their current matches and lets the person delete them' do
      alert = create(:ride_alert, user: rider)
      create(:itinerary, start_location: [38.75, 9.02], end_location: [39.27, 8.54], start_address: 'Addis match', end_address: 'Adama match')

      get ride_alerts_path
      expect(response.body).to include('Addis Ababa → Adama', '1 matching trip', 'Addis match')

      expect { delete ride_alert_path(alert) }.to change(RideAlert, :count).by(-1)
    end

    it 'cannot delete someone elses alert' do
      other = create(:ride_alert)

      expect { delete ride_alert_path(other) }.not_to change(RideAlert, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'adds the alert button to the search page' do
      get itineraries_path

      expect(response.body).to include('create-alert-button')
    end
  end

  describe 'reports' do
    before { sign_in rider }

    it 'lets a rider report a trip, once' do
      get new_report_path(type: 'Itinerary', id: commute.id)
      expect(response).to have_http_status(:ok)

      expect do
        post reports_path, params: { report: { reportable_type: 'Itinerary', reportable_id: commute.id, reason: 'fake_or_scam', details: 'Price changed at pickup' } }
      end.to change(Report, :count).by(1)
      expect(Report.last).to have_attributes(reporter: rider, status: 'open', reason: 'fake_or_scam')

      expect do
        post reports_path, params: { report: { reportable_type: 'Itinerary', reportable_id: commute.id, reason: 'other' } }
      end.not_to change(Report, :count)
    end

    it 'does not let people report themselves or unknown kinds of things' do
      expect do
        post reports_path, params: { report: { reportable_type: 'User', reportable_id: rider.id, reason: 'other' } }
      end.not_to change(Report, :count)

      get new_report_path(type: 'Booking', id: 1)
      expect(response).to redirect_to(root_path)
    end

    it 'shows report links on trip and profile pages' do
      get itinerary_path(commute)
      expect(response.body).to include('Report this trip')

      get user_path(driver)
      expect(response.body).to include('Report this person')
    end
  end
end
