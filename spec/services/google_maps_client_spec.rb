# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe GoogleMapsClient do
  before { allow(described_class).to receive(:key).and_return('test-key') }

  let(:places) { 'https://places.googleapis.com/v1/places:searchText' }
  let(:routes) { 'https://routes.googleapis.com/directions/v2:computeRoutes' }

  def place(name, lat, lng)
    { places: [{ formattedAddress: name, location: { latitude: lat, longitude: lng } }] }.to_json
  end

  it 'decodes Google polylines' do
    expect(described_class.decode('_p~iF~ps|U_ulLnnqC_mqNvxq`@')).to eq [[38.5, -120.2], [40.7, -120.95], [43.252, -126.453]]
  end

  it 'finds a place in Ethiopia' do
    stub = stub_request(:post, places).with(headers: { 'X-Goog-Api-Key' => 'test-key' }) { |req| JSON.parse(req.body)['regionCode'] == 'ET' }
                                      .to_return(body: place('Bole, Addis Ababa', 8.98, 38.81))
    expect(described_class.new.geocode('Bole')).to eq(address: 'Bole, Addis Ababa', lat: 8.98, lng: 38.81)
    expect(stub).to have_been_requested
  end

  it 'takes plain coordinates without calling Google' do
    expect(described_class.new.geocode('9.0, 38.7')).to include(lat: 9.0, lng: 38.7)
  end

  it 'returns nil when nothing matches' do
    stub_request(:post, places).to_return(body: '{}')
    expect(described_class.new.geocode('zzzz')).to be_nil
  end

  it 'builds a route in the shape the trip form stores' do
    stub_request(:post, places).to_return(body: place('A', 9.0, 38.7), headers: {}).then.to_return(body: place('B', 9.03, 38.74))
    stub_request(:post, routes).to_return(body: { routes: [{ distanceMeters: 7131, duration: '1260s', polyline: { encodedPolyline: '_p~iF~ps|U_ulLnnqC' } }] }.to_json)

    route = described_class.new.route(origin: 'A', destination: 'B')
    expect(route).to include(start_address: 'A', end_address: 'B', distance_text: '7.1 km', duration_text: '21 min', start_location: [38.7, 9.0], end_location: [38.74, 9.03])
    expect(route[:overview_path]).to eq [[-120.2, 38.5], [-120.95, 40.7]]
  end

  it 'reports a missing route and Google failures' do
    stub_request(:post, places).to_return(body: place('A', 9, 38))
    stub_request(:post, routes).to_return(body: '{}')
    expect { described_class.new.route(origin: 'A', destination: 'B') }.to raise_error(described_class::Error, 'zero_results')

    stub_request(:post, places).to_return(status: 403, body: '{}')
    expect { described_class.new.geocode('x') }.to raise_error(described_class::Error, 'google_403')
  end
end
