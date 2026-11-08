# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API trips' do
  let(:driver) { create(:user, name: 'Dawit Driver', phone: '0911223344') }
  let(:rider) { create(:user, name: 'Rahel Rider', phone: '0922334455') }
  let(:addis) { { start_lat: 9.0192, start_lng: 38.7525 } }
  let(:adama) { { end_lat: 8.54, end_lng: 39.27 } }
  let(:trip_params) do
    { itinerary: { start: { key: 'addis-ababa' }, end: { key: 'adama' }, description: 'Morning trip to Adama', leave_date: 2.days.from_now.iso8601,
                   price_per_seat: 180, num_people: 3, pickup_point: 'Mexico Square' } }
  end

  describe 'POST /api/v1/itineraries' do
    it 'creates a trip from two known places, building the route on the server' do
      expect { post '/api/v1/itineraries', params: trip_params, headers: api_headers(driver) }.to change(Itinerary, :count).by(1).and have_enqueued_job(RideAlertMatchJob)

      expect(response).to have_http_status(:created)
      trip = Itinerary.last
      expect(trip).to have_attributes(start_address: 'Addis Ababa', end_address: 'Adama', price_per_seat: 180, num_people: 3, pickup_point: 'Mexico Square')
      expect(trip.overview_path.coordinates.size).to eq RouteBuilder::STEPS + 1
      expect(trip.overview_polyline).to be_present
      expect(json['itinerary']).to include('title' => 'Addis Ababa - Adama', 'price_per_seat' => 180.0, 'seats_available' => 3, 'bookable' => false)
    end

    it 'accepts custom coordinates and names' do
      params = { itinerary: { start: { name: 'Bole', lat: 8.99, lng: 38.8 }, end: { name: 'Mojo', lat: 8.58, lng: 39.11 }, description: 'x', leave_date: 2.days.from_now.iso8601, price_per_seat: 100, num_people: 2 } }

      post '/api/v1/itineraries', params:, headers: api_headers(driver)

      expect(response).to have_http_status(:created)
      expect(Itinerary.last).to have_attributes(start_address: 'Bole', end_address: 'Mojo')
    end

    it 'creates a weekly commute' do
      params = trip_params.deep_merge(itinerary: { commute_days: %w[1 2 3], commute_until: (Date.current + 30).iso8601 })

      post '/api/v1/itineraries', params:, headers: api_headers(driver)

      expect(response).to have_http_status(:created)
      expect(Itinerary.last).to have_attributes(commute_days: [1, 2, 3], daily: true)
      expect(json['itinerary']).to include('commute' => true)
      expect(json['itinerary']['occurrence_dates']).to be_present
    end

    it 'rejects a trip outside Ethiopia when the area is restricted' do
      APP_CONFIG.itineraries.set :geo_restricted, true
      params = { itinerary: { start: { name: 'Milan', lat: 45.46, lng: 9.19 }, end: { name: 'Turin', lat: 45.07, lng: 7.69 }, description: 'x', leave_date: 2.days.from_now.iso8601, price_per_seat: 100, num_people: 2 } }

      expect { post '/api/v1/itineraries', params:, headers: api_headers(driver) }.not_to change(Itinerary, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    ensure
      APP_CONFIG.itineraries.set :geo_restricted, false
    end

    it 'asks the driver to finish required vehicle details first' do
      create(:vehicle_field, key: 'plate', label: 'Plate', required: true)

      post '/api/v1/itineraries', params: trip_params, headers: api_headers(driver)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']['message']).to include('Plate')
    end

    it 'enforces the price limit and ignores women-only for men' do
      PlatformSetting.current.update!(max_price_per_seat: 500)
      post '/api/v1/itineraries', params: trip_params.deep_merge(itinerary: { price_per_seat: 900 }), headers: api_headers(driver)
      expect(response).to have_http_status(:unprocessable_entity)

      post '/api/v1/itineraries', params: trip_params.deep_merge(itinerary: { pink: true }), headers: api_headers(driver)
      expect(response).to have_http_status(:created)
      expect(Itinerary.last).not_to be_pink
    end

    it 'needs both ends' do
      post '/api/v1/itineraries', params: { itinerary: { description: 'x', start: { key: 'addis-ababa' } } }, headers: api_headers(driver)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /api/v1/itineraries' do
    let!(:trip) { create(:itinerary, user: driver, num_people: 3, price_per_seat: 200, start_location: [38.7525, 9.0192], end_location: [39.27, 8.54], start_address: 'Addis Ababa', end_address: 'Adama') }

    it 'lists the latest trips with prices and pagination' do
      create(:itinerary, start_address: 'Hidden', end_address: 'Cancelled').cancel!

      get '/api/v1/itineraries', headers: api_headers(rider)

      expect(response).to have_http_status(:ok)
      expect(json['itineraries'].pluck('title')).to eq ['Addis Ababa - Adama']
      expect(json['itineraries'].first).to include('price_per_seat' => 200.0, 'passenger_price_per_seat' => 220.0, 'seats_available' => 3)
      expect(json['meta']).to include('page' => 1, 'total' => 1, 'last' => true)
    end

    it 'pages through many trips, 20 at a time by default' do
      create_list(:itinerary, 24)

      get '/api/v1/itineraries', headers: api_headers(rider)
      expect(json['itineraries'].size).to eq 20
      expect(json['meta']).to include('total' => 25, 'last' => false)

      get '/api/v1/itineraries', params: { page: 2, per: 20 }, headers: api_headers(rider)
      expect(json['itineraries'].size).to eq 5
      expect(json['meta']).to include('page' => 2, 'last' => true)

      get '/api/v1/itineraries', params: { per: 500 }, headers: api_headers(rider)
      expect(json['meta']['per']).to eq 50
    end

    it 'searches by route and filters by seats' do
      far = create(:itinerary, start_location: [41.87, 9.59], end_location: [42.12, 9.31], start_address: 'Dire Dawa', end_address: 'Harar')

      get '/api/v1/itineraries', params: addis.merge(adama), headers: api_headers(rider)
      expect(json['itineraries'].pluck('id')).to eq [trip.id]
      expect(json['itineraries'].pluck('id')).not_to include(far.id)

      get '/api/v1/itineraries', params: addis.merge(adama).merge(seats: 5), headers: api_headers(rider)
      expect(json['itineraries']).to eq([])
    end

    it 'sorts by price' do
      cheap = create(:itinerary, price_per_seat: 20, start_location: [38.7525, 9.0192], end_location: [39.27, 8.54])

      get '/api/v1/itineraries', params: addis.merge(adama).merge(sort: 'price'), headers: api_headers(rider)

      expect(json['itineraries'].pluck('id')).to eq [cheap.id, trip.id]
    end

    it 'keeps women-only trips from men and lists my own trips' do
      driver.update!(gender: 'female')
      create(:itinerary, user: driver, pink: true, start_address: 'Pink', end_address: 'Trip')

      get '/api/v1/itineraries', headers: api_headers(rider)
      expect(json['itineraries'].pluck('title')).not_to include('Pink - Trip')

      get '/api/v1/itineraries/mine', headers: api_headers(driver)
      expect(json['itineraries'].pluck('title')).to include('Pink - Trip', 'Addis Ababa - Adama')
    end
  end

  describe 'GET /api/v1/itineraries/:id' do
    let(:trip) { create(:itinerary, user: driver, num_people: 3, price_per_seat: 200, description: 'Early start') }

    before do
      create(:vehicle_field, key: 'make', label: 'Make')
      create(:vehicle_field, key: 'plate', label: 'Plate', visibility: 'confirmed')
      driver.update!(vehicle_data: { 'make' => 'Toyota', 'plate' => 'AA 12345' })
    end

    it 'shows the public vehicle details but hides the plate and phone until confirmed' do
      get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)

      driver_json = json['itinerary']['driver']
      expect(driver_json['vehicle']).to eq([{ 'key' => 'make', 'label' => 'Make', 'value' => 'Toyota' }])
      expect(driver_json).not_to have_key('phone')
      expect(json['itinerary']).to include('bookable' => true, 'my_booking' => nil)
      expect(json['itinerary']['price_preview']).to include('fee_percent' => 10.0, 'fee_charged_to' => 'passenger')
    end

    it 'unlocks the plate and phone once the booking is confirmed' do
      create(:booking, :confirmed, itinerary: trip, passenger: rider)

      get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)

      driver_json = json['itinerary']['driver']
      expect(driver_json['phone']).to eq '+251911223344'
      expect(driver_json['vehicle'].pluck('key')).to eq %w[make plate]
      expect(json['itinerary']['my_booking']).to include('status' => 'confirmed')
    end

    it 'closes women-only trips to men and finds trips by slug' do
      driver.update!(gender: 'female')
      trip.update!(pink: true)

      get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/itineraries/#{trip.slug}", headers: api_headers(driver)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /api/v1/itineraries/:id and /cancel' do
    let(:trip) { create(:itinerary, user: driver, num_people: 3) }

    it 'lets only the driver edit and cancel, cancelling bookings and notifying' do
      booking = create(:booking, :confirmed, itinerary: trip, passenger: rider)

      patch "/api/v1/itineraries/#{trip.id}", params: { itinerary: { price_per_seat: 99 } }, headers: api_headers(rider)
      expect(response).to have_http_status(:forbidden)
      patch "/api/v1/itineraries/#{trip.id}/cancel", headers: api_headers(rider)
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/itineraries/#{trip.id}", params: { itinerary: { price_per_seat: 99 } }, headers: api_headers(driver)
      expect(trip.reload.price_per_seat).to eq 99

      expect { patch "/api/v1/itineraries/#{trip.id}/cancel", headers: api_headers(driver) }.to have_enqueued_mail(ItineraryMailer, :cancelled)
      expect(json['itinerary']).to include('cancelled' => true)
      expect(booking.reload).to be_cancelled
    end
  end
end
