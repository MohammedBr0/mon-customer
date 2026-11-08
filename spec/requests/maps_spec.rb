# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Maps endpoints' do
  let(:user) { create(:user) }

  it 'needs sign-in' do
    get '/maps/geocode', params: { q: 'Bole' }
    expect(response).not_to have_http_status(:ok)
  end

  it 'explains when maps are not configured' do
    allow(GoogleMapsClient).to receive(:key).and_return(nil)
    sign_in user
    get '/maps/geocode', params: { q: 'Bole' }
    expect(response).to have_http_status(:service_unavailable)
  end

  it 'answers with the place and the route' do
    allow(GoogleMapsClient).to receive(:key).and_return('k')
    stub_request(:post, 'https://places.googleapis.com/v1/places:searchText').to_return(body: { places: [{ formattedAddress: 'Bole', location: { latitude: 9, longitude: 38 } }] }.to_json)
    sign_in user
    get '/maps/geocode', params: { q: 'Bole' }
    expect(response.parsed_body).to include('address' => 'Bole', 'lat' => 9.0)

    stub_request(:post, 'https://routes.googleapis.com/directions/v2:computeRoutes').to_return(body: { routes: [{ distanceMeters: 1000, duration: '120s', polyline: { encodedPolyline: '_p~iF~ps|U_ulLnnqC' } }] }.to_json)
    get '/maps/route', params: { origin: 'A', destination: 'B' }
    expect(response.parsed_body).to include('distance_text' => '1.0 km', 'duration_text' => '2 min')
  end
end
