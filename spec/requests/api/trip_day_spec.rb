# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API trip editing, boarding, starting and arriving' do
  let(:driver) { create(:user, name: 'Dawit Driver') }
  let(:rider) { create(:user, name: 'Rahel Rider') }
  let(:other) { create(:user, name: 'Sara Second') }
  let(:departure) { 3.hours.from_now.change(sec: 0) }
  let(:trip) { create(:itinerary, user: driver, num_people: 3, leave_date: departure) }
  let!(:booking) { create(:booking, itinerary: trip, passenger: rider).tap(&:confirm!) }

  describe 'editing' do
    it 'is allowed until 30 minutes before departure, and booked passengers hear about a new time' do
      new_time = departure + 1.hour
      patch "/api/v1/itineraries/#{trip.id}", params: { itinerary: { leave_date: new_time.iso8601, num_people: 2, price_per_seat: 60 } }, headers: api_headers(driver)
      expect(response).to have_http_status(:ok), response.body
      expect(json['itinerary']).to include('editable' => true)
      expect(trip.reload.num_people).to eq 2
      expect(rider.notifications.pluck(:kind)).to include('trip_changed')

      travel_to(new_time - 29.minutes) do
        patch "/api/v1/itineraries/#{trip.id}", params: { itinerary: { description: 'Too late' } }, headers: api_headers(driver)
        expect(json['error']['code']).to eq 'edit_locked'
      end
    end

    it 'cannot cut the seats below those already booked' do
      create(:booking, itinerary: trip, passenger: other, seats: 2).confirm!
      patch "/api/v1/itineraries/#{trip.id}", params: { itinerary: { num_people: 2 } }, headers: api_headers(driver)
      expect(json['error']['code']).to eq 'seats_taken'
    end
  end

  describe 'starting' do
    it 'waits until 30 minutes before departure' do
      post "/api/v1/itineraries/#{trip.id}/start", headers: api_headers(driver)
      expect(json['error']['code']).to eq 'start_too_early'

      get "/api/v1/itineraries/#{trip.id}", headers: api_headers(driver)
      expect(json['itinerary']['start']).to include('allowed' => false, 'reason' => 'too_early', 'opens_at' => (departure - 30.minutes).iso8601)
    end

    it 'waits until every passenger is picked up or marked as a no-show' do
      create(:booking, itinerary: trip, passenger: other).confirm!
      travel_to(departure - 20.minutes) do
        post "/api/v1/itineraries/#{trip.id}/start", headers: api_headers(driver)
        expect(json['error']['code']).to eq 'start_waiting'

        get "/api/v1/itineraries/#{trip.id}", headers: api_headers(driver)
        expect(json['itinerary']['riders'].pluck('status')).to eq %w[waiting waiting]

        # The passenger checks in themselves; the other can't be a no-show before departure time.
        patch "/api/v1/bookings/#{booking.id}/board", headers: api_headers(rider)
        expect(json['booking']['today']).to include('status' => 'boarded')
        other_booking = trip.bookings.find_by(passenger: other)
        patch "/api/v1/bookings/#{other_booking.id}/no_show", headers: api_headers(driver)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      travel_to(departure + 5.minutes) do
        other_booking = trip.bookings.find_by(passenger: other)
        patch "/api/v1/bookings/#{other_booking.id}/no_show", headers: api_headers(driver)
        expect(response).to have_http_status(:ok), response.body

        post "/api/v1/itineraries/#{trip.id}/start", headers: api_headers(driver)
        expect(json['live']).to include('active' => true)
        expect(rider.notifications.pluck(:kind)).to include('trip_started')
        expect(other.notifications.pluck(:kind)).not_to include('trip_started')
      end
    end

    it 'does not let strangers check a passenger in' do
      travel_to(departure - 10.minutes) do
        patch "/api/v1/bookings/#{booking.id}/board", headers: api_headers(other)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'arriving' do
    before do
      travel_to(departure - 10.minutes)
      booking.board!(trip.current_ride_date)
      trip.start_live!
    end

    after { travel_back }

    it 'asks passengers to confirm the drop-off once the car is near the destination, and closes the trip' do
      post "/api/v1/itineraries/#{trip.id}/location", params: { lat: 45.4642, lng: 9.19 }, headers: api_headers(driver)
      expect(trip.reload.arrived_at).to be_nil

      destination = trip.end_location
      post "/api/v1/itineraries/#{trip.id}/location", params: { lat: destination.lat + 0.001, lng: destination.lon }, headers: api_headers(driver)
      expect(trip.reload.arrived_at).to be_present
      expect(rider.notifications.pluck(:kind)).to include('dropoff_confirm')
      expect(driver.notifications.pluck(:kind)).to include('arrived')

      get '/api/v1/bookings', headers: api_headers(rider)
      expect(json['made'].first['today']).to include('can_drop_off' => true, 'arrived' => true)

      patch "/api/v1/bookings/#{booking.id}/dropoff", headers: api_headers(rider)
      expect(json['booking']['today']).to include('status' => 'dropped_off')
      expect(trip.reload.live?).to be false
    end

    it 'closes by itself half an hour after arriving' do
      destination = trip.end_location
      trip.update_live_position!(lat: destination.lat, lng: destination.lon)
      travel(31.minutes)
      get "/api/v1/itineraries/#{trip.id}/live", headers: api_headers(rider)
      expect(json['live']['active']).to be false
      expect(booking.boarding_for(trip.live_ride_date).reload.dropped_off_at).to be_present
    end

    it 'pays the driver when a wallet passenger confirms the drop-off' do
      wallet_booking = booking
      wallet_booking.update_columns(payment_method: 'wallet', payment_state: 'held')
      allow(BookingPayment).to receive(:new).and_call_original
      payment = instance_double(BookingPayment, release!: true)
      allow(BookingPayment).to receive(:new).with(wallet_booking).and_return(payment)
      wallet_booking.drop_off!(trip.live_ride_date)
      expect(payment).to have_received(:release!)
    end
  end
  describe 'trip status' do
    it 'goes scheduled, boarding, in progress, arrived, completed' do
      expect(trip.trip_status).to eq 'scheduled'
      travel_to(departure + 10.minutes) { expect(trip.trip_status).to eq 'boarding' } # late, but not started: not completed
      travel_to(departure + 7.hours) { expect(trip.trip_status).to eq 'completed' }
      travel_to(departure - 10.minutes) do
        expect(trip.trip_status).to eq 'boarding'
        booking.board!(trip.current_ride_date)
        trip.start_live!
        get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)
        expect(json['itinerary']['status']).to eq 'in_progress'
        get '/api/v1/bookings', headers: api_headers(rider)
        expect(json['made'].first['itinerary']['status']).to eq 'in_progress'

        trip.update_live_position!(lat: trip.end_location.lat, lng: trip.end_location.lon)
        expect(trip.reload.trip_status).to eq 'arrived'
        trip.finish_live!
        expect(trip.trip_status).to eq 'completed'
        expect(booking.reload.completed?).to be true
        get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)
        expect(json['itinerary']['status']).to eq 'completed'
        expect(trip.start_blocker).to eq :finished
      end
      trip.cancel!
      expect(trip.trip_status).to eq 'cancelled'
    end
  end
end
