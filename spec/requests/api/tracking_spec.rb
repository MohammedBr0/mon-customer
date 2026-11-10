# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API pickups, reminders, names and live tracking' do
  let(:driver) { create(:user, name: 'Dawit Driver') }
  let(:rider) { create(:user, name: 'Rahel Rider') }
  let(:stranger) { create(:user) }
  let(:trip) { create(:itinerary, user: driver, num_people: 3) }

  describe 'pickup point' do
    it 'goes to the driver with the seat request, before they accept' do
      post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 1, pickup: { lat: 9.0105, lng: 38.7612, label: 'Mexico Square' } } }, headers: api_headers(rider)
      expect(response).to have_http_status(:created), response.body
      expect(json['booking']['pickup']).to eq('lat' => 9.0105, 'lng' => 38.7612, 'label' => 'Mexico Square')

      get '/api/v1/bookings', headers: api_headers(driver)
      request = json['received'].first
      expect(request).to include('status' => 'pending')
      expect(request['pickup']).to include('label' => 'Mexico Square')
    end

    it 'is optional, and bad coordinates are refused' do
      post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 1 } }, headers: api_headers(rider)
      expect(json['booking']['pickup']).to be_nil

      post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 1, pickup: { lat: 400, lng: 38 } } }, headers: api_headers(stranger)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'reminders and price suggestion' do
    it 'stores how long before a ride someone wants to be reminded' do
      get '/api/v1/me', headers: api_headers(rider)
      expect(json['user']['reminder_minutes']).to eq 15

      patch '/api/v1/me', params: { user: { reminder_minutes: 30 } }, headers: api_headers(rider)
      expect(json['user']['reminder_minutes']).to eq 30
      patch '/api/v1/me', params: { user: { reminder_minutes: 45 } }, headers: api_headers(rider)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'gives the app the admins\' suggested price per km' do
      PlatformSetting.current.update!(suggested_price_per_km: 7.5)
      get '/api/v1/config'
      expect(json['suggested_price_per_km']).to eq 7.5
    end
  end

  describe 'short place names' do
    it 'names a point by its neighbourhood, a town by its name, and falls back to the address' do
      bole = RGeo::Geographic.spherical_factory(srid: 4326).point(38.7867, 8.9967)
      adama = RGeo::Geographic.spherical_factory(srid: 4326).point(39.27, 8.54)
      nowhere = RGeo::Geographic.spherical_factory(srid: 4326).point(40.5, 6.0)
      expect(ApiSerializer.short_name(bole, 'XQWR+7CV, Unnamed Road, Addis Ababa')).to eq 'Bole'
      expect(ApiSerializer.short_name(adama, 'Some street, Adama, Ethiopia')).to eq 'Adama'
      expect(ApiSerializer.short_name(nowhere, 'Ginir Junction, Bale')).to eq 'Ginir Junction'
    end

    it 'sends the names with every trip' do
      get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)
      expect(json['itinerary']).to include('start_name', 'end_name', 'live' => false)
    end
  end

  describe 'live tracking' do
    before { create(:booking, itinerary: trip, passenger: rider, pickup_lat: 9.01, pickup_lng: 38.76, pickup_label: 'Mexico').confirm! }

    it 'lets only the driver start, move and finish the ride' do
      post "/api/v1/itineraries/#{trip.id}/start", headers: api_headers(rider)
      expect(response).to have_http_status(:forbidden)
      post "/api/v1/itineraries/#{trip.id}/location", params: { lat: 9.0, lng: 38.7 }, headers: api_headers(driver)
      expect(json['error']['code']).to eq 'not_live'

      post "/api/v1/itineraries/#{trip.id}/start", headers: api_headers(driver)
      expect(json['live']).to include('active' => true, 'position' => nil)
      expect(rider.notifications.pluck(:kind)).to include('trip_started')

      post "/api/v1/itineraries/#{trip.id}/location", params: { lat: 9.0123, lng: 38.7456, heading: 92.5 }, headers: api_headers(driver)
      expect(response).to have_http_status(:no_content)
      post "/api/v1/itineraries/#{trip.id}/location", params: { lat: 999, lng: 38 }, headers: api_headers(driver)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'shows the car to confirmed passengers and the driver, and nobody else' do
      trip.start_live!
      trip.update_live_position!(lat: 9.0123, lng: 38.7456, heading: 90)

      get "/api/v1/itineraries/#{trip.id}/live", headers: api_headers(rider)
      expect(json['live']).to include('active' => true, 'fresh' => true)
      expect(json['live']['position']).to eq('lat' => 9.0123, 'lng' => 38.7456, 'heading' => 90.0)
      expect(json['live']).not_to have_key('pickups') # other passengers' pickup points are the driver's business

      get "/api/v1/itineraries/#{trip.id}/live", headers: api_headers(driver)
      expect(json['live']['pickups']).to eq [{ 'name' => 'Rahel', 'lat' => 9.01, 'lng' => 38.76, 'label' => 'Mexico', 'seats' => 1 }]

      get "/api/v1/itineraries/#{trip.id}/live", headers: api_headers(stranger)
      expect(response).to have_http_status(:forbidden)
    end

    it 'stops sharing the position when the driver finishes' do
      trip.start_live!
      trip.update_live_position!(lat: 9.0, lng: 38.7)
      post "/api/v1/itineraries/#{trip.id}/finish", headers: api_headers(driver)
      expect(json['live']).to include('active' => false, 'position' => nil)
      get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)
      expect(json['itinerary']['live']).to be false
    end
  end
end
