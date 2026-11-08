# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API bookings, messages, alerts, reviews and reports' do
  let(:driver) { create(:user, name: 'Dawit Driver', phone: '0911223344') }
  let(:rider) { create(:user, name: 'Rahel Rider', phone: '0922334455') }
  let(:trip) { create(:itinerary, user: driver, num_people: 3, price_per_seat: 200) }

  describe 'bookings' do
    before { PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger') }

    it 'requests seats with the fee frozen into the booking, and emails the driver' do
      expect { post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 2, note: 'At the station' } }, headers: api_headers(rider) }
        .to change(Booking, :count).by(1).and have_enqueued_mail(BookingMailer, :requested)

      expect(response).to have_http_status(:created)
      expect(json['booking']).to include('status' => 'pending', 'seats' => 2, 'note' => 'At the station')
      expect(json['booking']['price']).to include('fare_total' => 400.0, 'fee_amount' => 40.0, 'passenger_total' => 440.0, 'driver_payout' => 400.0)
    end

    it 'books several days of a commute' do
      commute_day = Itinerary.today + (((1 - Itinerary.today.wday) % 7).zero? ? 7 : (1 - Itinerary.today.wday) % 7)
      leave = Itinerary::RIDE_ZONE.local(commute_day.year, commute_day.month, commute_day.day, 7, 30)
      commute = create(:itinerary, user: driver, num_people: 2, price_per_seat: 100, leave_date: leave, commute_days: [1, 2, 3, 4, 5])
      days = commute.occurrence_dates.first(3).map(&:iso8601)

      post "/api/v1/itineraries/#{commute.id}/bookings", params: { booking: { seats: 1, ride_dates: days } }, headers: api_headers(rider)

      expect(json['booking']['ride_dates']).to eq days
      expect(json['booking']['price']).to include('rides' => 3, 'fare_total' => 300.0, 'passenger_total' => 330.0)
    end

    it 'refuses the driver, a cancelled trip and too many seats' do
      post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 1 } }, headers: api_headers(driver)
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 9 } }, headers: api_headers(rider)
      expect(response).to have_http_status(:unprocessable_entity)

      trip.cancel!
      post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 1 } }, headers: api_headers(rider)
      expect(response).to have_http_status(:forbidden)
    end

    it 'lets the driver confirm and decline, and refuses to oversell' do
      first = create(:booking, itinerary: trip, passenger: rider, seats: 2)
      second = create(:booking, itinerary: trip, passenger: create(:user), seats: 2)

      patch "/api/v1/bookings/#{first.id}/confirm", headers: api_headers(rider)
      expect(response).to have_http_status(:forbidden)

      expect { patch "/api/v1/bookings/#{first.id}/confirm", headers: api_headers(driver) }.to have_enqueued_mail(BookingMailer, :confirmed)
      expect(json['booking']).to include('status' => 'confirmed')

      patch "/api/v1/bookings/#{second.id}/confirm", headers: api_headers(driver)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']['code']).to eq 'not_enough_seats'

      expect { patch "/api/v1/bookings/#{second.id}/decline", headers: api_headers(driver) }.to have_enqueued_mail(BookingMailer, :declined)
      expect(second.reload).to be_declined
    end

    it 'lists made and received bookings and shares phones only after confirmation' do
      booking = create(:booking, itinerary: trip, passenger: rider)

      get '/api/v1/bookings', headers: api_headers(driver)
      expect(json['received'].first['passenger']).not_to have_key('phone')
      expect(json['made']).to eq []

      booking.confirm!
      get '/api/v1/bookings', headers: api_headers(driver)
      expect(json['received'].first['passenger']['phone']).to eq '+251922334455'
      get '/api/v1/bookings', headers: api_headers(rider)
      expect(json['made'].first['driver']['phone']).to eq '+251911223344'
    end

    it 'cancels and skips a day, and keeps strangers out' do
      days = [Itinerary.today + 1, Itinerary.today + 2]
      commute = create(:itinerary, user: driver, num_people: 2, commute_days: [0, 1, 2, 3, 4, 5, 6], leave_date: 1.day.from_now)
      booking = create(:booking, :confirmed, itinerary: commute, passenger: rider, ride_dates: commute.occurrence_dates.first(2))

      patch "/api/v1/bookings/#{booking.id}/skip_date", params: { date: booking.ride_dates.first.iso8601 }, headers: api_headers(create(:user))
      expect(response).to have_http_status(:forbidden)

      expect { patch "/api/v1/bookings/#{booking.id}/skip_date", params: { date: booking.ride_dates.first.iso8601 }, headers: api_headers(rider) }.to have_enqueued_mail(BookingMailer, :date_skipped)
      expect(json['booking']['ride_dates'].size).to eq 1

      patch "/api/v1/bookings/#{booking.id}/skip_date", params: { date: 'garbage' }, headers: api_headers(rider)
      expect(response).to have_http_status(:unprocessable_entity)

      expect { patch "/api/v1/bookings/#{booking.id}/cancel", headers: api_headers(rider) }.to have_enqueued_mail(BookingMailer, :cancelled)
      expect(booking.reload).to be_cancelled
      expect(days).to be_present
    end
  end

  describe 'messages' do
    it 'starts a conversation with the driver and continues it' do
      expect { post '/api/v1/conversations', params: { itinerary_id: trip.id, body: 'Is there room?' }, headers: api_headers(rider) }.to change(Conversation, :count).by(1)
      expect(response).to have_http_status(:created)
      id = json['conversation']['id']
      expect(json['conversation']['messages'].pluck('body')).to eq ['Is there room?']

      expect { post '/api/v1/conversations', params: { itinerary_id: trip.id, body: 'And Friday?' }, headers: api_headers(rider) }.not_to change(Conversation, :count)

      post "/api/v1/conversations/#{id}/message", params: { body: 'Yes, one seat.' }, headers: api_headers(driver)
      expect(json['conversation']['messages'].pluck('body')).to eq ['Is there room?', 'And Friday?', 'Yes, one seat.']
    end

    it 'lists conversations with unread counts and marks them read on opening' do
      conversation = create(:conversation, conversable: trip, sender: rider, receiver: driver)
      create(:message, conversation:, sender: rider, body: 'Hello driver')

      get '/api/v1/conversations', headers: api_headers(driver)
      expect(json['unread']).to eq 1
      expect(json['conversations'].first).to include('unread' => true)
      expect(json['conversations'].first['last_message']).to include('body' => 'Hello driver')

      get "/api/v1/conversations/#{conversation.id}", headers: api_headers(driver)
      expect(json['conversation']['messages'].pluck('body')).to eq ['Hello driver']
      get '/api/v1/conversations', headers: api_headers(driver)
      expect(json['unread']).to eq 0
    end

    it 'keeps other people out and the driver from messaging themselves' do
      conversation = create(:conversation, conversable: trip, sender: rider, receiver: driver)

      get "/api/v1/conversations/#{conversation.id}", headers: api_headers(create(:user))
      expect(response).to have_http_status(:not_found)

      post '/api/v1/conversations', params: { itinerary_id: trip.id, body: 'Hi me' }, headers: api_headers(driver)
      expect(response).to have_http_status(:forbidden)

      post '/api/v1/conversations', params: { itinerary_id: trip.id, body: '' }, headers: api_headers(rider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'ride alerts' do
    it 'creates, lists with matches and deletes' do
      create(:itinerary, start_location: [38.75, 9.02], end_location: [39.27, 8.54], start_address: 'Addis Ababa', end_address: 'Adama')

      post '/api/v1/ride_alerts', params: { ride_alert: { start: { key: 'addis-ababa' }, end: { key: 'adama' } } }, headers: api_headers(rider)
      expect(response).to have_http_status(:created)
      expect(json['ride_alert']).to include('start_label' => 'Addis Ababa', 'end_label' => 'Adama', 'matches' => 1)

      get '/api/v1/ride_alerts', headers: api_headers(rider)
      expect(json['ride_alerts'].size).to eq 1

      expect { delete "/api/v1/ride_alerts/#{json['ride_alerts'].first['id']}", headers: api_headers(rider) }.to change(RideAlert, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'accepts coordinates, needs both ends and cannot touch others alerts' do
      post '/api/v1/ride_alerts', params: { ride_alert: { start: { lat: 9.01, lng: 38.75 }, end: { lat: 8.54, lng: 39.27 } } }, headers: api_headers(rider)
      expect(response).to have_http_status(:created)
      expect(json['ride_alert']['start_label']).to eq 'Addis Ababa'

      post '/api/v1/ride_alerts', params: { ride_alert: { start: { key: 'addis-ababa' } } }, headers: api_headers(rider)
      expect(response).to have_http_status(:unprocessable_entity)

      delete "/api/v1/ride_alerts/#{create(:ride_alert).id}", headers: api_headers(rider)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'reviews' do
    let(:booking) { create(:booking, :completed) }

    it 'lets a participant review once, after the trip' do
      post "/api/v1/bookings/#{booking.id}/reviews", params: { review: { rating: 5, comment: 'Great' } }, headers: api_headers(booking.passenger)
      expect(response).to have_http_status(:created)
      expect(Review.last).to have_attributes(reviewer: booking.passenger, reviewee: booking.driver, rating: 5)

      post "/api/v1/bookings/#{booking.id}/reviews", params: { review: { rating: 1 } }, headers: api_headers(booking.passenger)
      expect(json['error']['code']).to eq 'already_reviewed'
    end

    it 'blocks outsiders, early reviews and bad ratings' do
      post "/api/v1/bookings/#{booking.id}/reviews", params: { review: { rating: 5 } }, headers: api_headers(create(:user))
      expect(response).to have_http_status(:forbidden)

      upcoming = create(:booking, :confirmed)
      post "/api/v1/bookings/#{upcoming.id}/reviews", params: { review: { rating: 5 } }, headers: api_headers(upcoming.passenger)
      expect(json['error']['code']).to eq 'not_completed'

      post "/api/v1/bookings/#{booking.id}/reviews", params: { review: { rating: 9 } }, headers: api_headers(booking.driver)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'reports' do
    it 'files a report once and refuses invalid targets' do
      post '/api/v1/reports', params: { type: 'Itinerary', id: trip.id, reason: 'fake_or_scam', details: 'Asked for money upfront' }, headers: api_headers(rider)
      expect(response).to have_http_status(:created)
      expect(Report.last).to have_attributes(reporter: rider, status: 'open')

      post '/api/v1/reports', params: { type: 'Itinerary', id: trip.id, reason: 'other' }, headers: api_headers(rider)
      expect(response).to have_http_status(:unprocessable_entity)

      post '/api/v1/reports', params: { type: 'Booking', id: 1, reason: 'other' }, headers: api_headers(rider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
