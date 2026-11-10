# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'API maps' do
  let(:user) { create(:user) }

  before { allow(GoogleMapsClient).to receive(:key).and_return('k') }

  it 'searches places inside Ethiopia only' do
    stub = stub_request(:post, 'https://places.googleapis.com/v1/places:searchText').with { |req| JSON.parse(req.body).dig('locationRestriction', 'rectangle', 'low', 'latitude') == 3.4 }
           .to_return(body: { places: [{ displayName: { text: 'Bole Medhanialem' }, formattedAddress: 'Bole, Addis Ababa', location: { latitude: 8.99, longitude: 38.78 } }] }.to_json)
    get '/api/v1/maps/search', params: { q: 'Bole', lat: 9.0, lng: 38.7 }, headers: api_headers(user)
    expect(json['places']).to eq [{ 'name' => 'Bole Medhanialem', 'address' => 'Bole, Addis Ababa', 'lat' => 8.99, 'lng' => 38.78 }]
    expect(stub).to have_been_requested
  end

  it 'names a point on the map' do
    stub_request(:get, %r{https://geocode.googleapis.com/v4beta/geocode/location/9.01,38.74}).to_return(body: { results: [{ formattedAddress: 'Mexico, Addis Ababa' }] }.to_json)
    get '/api/v1/maps/reverse', params: { lat: 9.01, lng: 38.74 }, headers: api_headers(user)
    expect(json['place']).to eq('address' => 'Mexico, Addis Ababa', 'lat' => 9.01, 'lng' => 38.74)
  end

  it 'previews a route' do
    stub_request(:post, 'https://routes.googleapis.com/directions/v2:computeRoutes').to_return(body: { routes: [{ distanceMeters: 7131, duration: '1260s', polyline: { encodedPolyline: '_p~iF~ps|U_ulLnnqC' } }] }.to_json)
    get '/api/v1/maps/route', params: { from: '9.0,38.78', to: '9.03,38.74' }, headers: api_headers(user)
    expect(json['route']).to include('distance_text' => '7.1 km', 'duration_text' => '21 min', 'overview_polyline' => '_p~iF~ps|U_ulLnnqC')
  end

  it 'says so when maps are not configured, and requires sign-in' do
    allow(GoogleMapsClient).to receive(:key).and_return(nil)
    get '/api/v1/maps/search', params: { q: 'x' }, headers: api_headers(user)
    expect(response).to have_http_status(:service_unavailable)
    get '/api/v1/maps/search', params: { q: 'x' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'uses a real road route when a trip is posted from the app' do
    stub_request(:post, 'https://routes.googleapis.com/directions/v2:computeRoutes').to_return(body: { routes: [{ distanceMeters: 100, duration: '60s', polyline: { encodedPolyline: '_p~iF~ps|U_ulLnnqC' } }] }.to_json)
    post '/api/v1/itineraries', headers: api_headers(user), params: { itinerary: { start: { lat: 9.0, lng: 38.7, name: 'Bole' }, end: { lat: 9.03, lng: 38.74, name: 'Piassa' },
                                                                                   leave_date: 2.days.from_now.iso8601, price_per_seat: 50, num_people: 2, description: 'x' } }
    expect(response).to have_http_status(:created), response.body
    expect(json['itinerary']['overview_polyline']).to eq '_p~iF~ps|U_ulLnnqC'
  end

  describe 'searching an area of the map' do
    let(:driver) { create(:user) }

    it 'lists trips that start near a point, nearest first' do
      near = create(:itinerary, user: driver)
      lat, lng = near.start_location.lat, near.start_location.lon

      get '/api/v1/itineraries', params: { near_lat: lat, near_lng: lng, radius_km: 5 }, headers: api_headers(user)
      expect(json['itineraries'].pluck('id')).to include(near.id)

      get '/api/v1/itineraries', params: { near_lat: lat + 1.0, near_lng: lng, radius_km: 5 }, headers: api_headers(user)
      expect(json['itineraries']).to be_empty
    end

    it 'ignores a bad point instead of failing' do
      get '/api/v1/itineraries', params: { near_lat: 'x', near_lng: 'y' }, headers: api_headers(user)
      expect(response).to have_http_status(:ok)
    end
  end
end

RSpec.describe 'API trip details for riders and drivers' do
  it 'shows the distance and who has a confirmed seat, without their contact details' do
    driver = create(:user)
    rider = create(:user, name: 'Rahel Rider', phone: '0922334455')
    trip = create(:itinerary, user: driver, num_people: 3)
    create(:booking, itinerary: trip, passenger: rider, seats: 2).confirm!

    get "/api/v1/itineraries/#{trip.id}", headers: api_headers(create(:user))

    expect(json['itinerary']['distance_km']).to be > 0
    expect(json['itinerary']['passengers']).to eq [{ 'id' => rider.id, 'first_name' => 'Rahel', 'image' => nil, 'seats' => 2 }]
    expect(response.body).not_to include('922334455')
  end
end

RSpec.describe RouteBuilder, '.road' do
  let(:routes_url) { 'https://routes.googleapis.com/directions/v2:computeRoutes' }

  it 'stores Google\'s driving route for a city commute too' do
    allow(GoogleMapsClient).to receive(:key).and_return('k')
    stub_request(:post, routes_url).to_return(body: { routes: [{ distanceMeters: 5000, duration: '600s', polyline: { encodedPolyline: '_p~iF~ps|U_ulLnnqC' } }] }.to_json)
    trip = create(:user).itineraries.new
    trip.use_city_areas(city: 'addis-ababa', from: 'addis-ababa:bole', to: 'addis-ababa:piassa')
    expect(trip.overview_polyline).to eq '_p~iF~ps|U_ulLnnqC'
    expect(trip.start_location.lat).to be_within(0.001).of(8.9967)
  end

  it 'falls back to a straight line when Google fails or is not set up' do
    allow(GoogleMapsClient).to receive(:key).and_return('k')
    stub_request(:post, routes_url).to_return(status: 500, body: 'x')
    expect(JSON.parse(described_class.road(from: [9.0, 38.7], to: [9.1, 38.8]))['overview_path'].size).to eq RouteBuilder::STEPS + 1

    allow(GoogleMapsClient).to receive(:key).and_return(nil)
    expect(JSON.parse(described_class.road(from: [9.0, 38.7], to: [9.1, 38.8]))['overview_polyline']).to be_present
  end
end
