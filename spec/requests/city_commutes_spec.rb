# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'City commutes' do
  let(:driver) { create(:user, name: 'Dawit Driver', phone: '0911223344') }
  let(:rider) { create(:user, name: 'Rahel Rider') }
  let(:next_monday) { Itinerary.today + (((1 - Itinerary.today.wday) % 7).zero? ? 7 : (1 - Itinerary.today.wday) % 7) }

  def post_commute(from: 'addis-ababa:bole', to: 'addis-ababa:piassa', as: driver, days: %w[1 2 3 4 5])
    post '/api/v1/itineraries', headers: api_headers(as),
                                params: { itinerary: { city: 'addis-ababa', start: { key: from }, end: { key: to }, leave_date: Itinerary::RIDE_ZONE.local(next_monday.year, next_monday.month, next_monday.day, 7, 30).iso8601,
                                                       price_per_seat: 60, num_people: 3, commute_days: days, description: 'Daily to work'  } }
  end

  describe 'the places' do
    it 'offers neighbourhoods for Addis Ababa in the app config' do
      get '/api/v1/config'
      addis = json['cities'].find { |city| city['key'] == 'addis-ababa' }
      expect(addis['areas'].pluck('name')).to include('Bole', 'Piassa', 'Megenagna')
      expect(addis['areas'].first['city']).to eq 'addis-ababa'
    end
  end

  describe 'posting through the API' do
    it 'creates a weekly commute between two neighbourhoods' do
      post_commute
      expect(response).to have_http_status(:created), response.body
      expect(json['itinerary']).to include('city' => 'addis-ababa', 'city_commute' => true, 'commute' => true, 'start_address' => 'Bole, Addis Ababa', 'end_address' => 'Piassa, Addis Ababa')
    end

    it 'rejects an area from another city, or the same area twice' do
      post_commute(to: 'adama')
      expect(response).to have_http_status(:unprocessable_entity)
      post_commute(to: 'addis-ababa:bole')
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'searching' do
    before do
      post_commute
      post_commute(from: 'addis-ababa:megenagna', to: 'addis-ababa:mexico')
      create(:itinerary, user: driver, price_per_seat: 900) # an ordinary trip must never show in a city search
    end

    it 'lists only trips in that city' do
      get '/api/v1/itineraries', params: { city: 'addis-ababa' }, headers: api_headers(rider)
      expect(json['itineraries'].size).to eq 2
      expect(json['itineraries']).to all(include('city_commute' => true))
    end

    it 'narrows by neighbourhood, in the direction of travel' do
      get '/api/v1/itineraries', params: { city: 'addis-ababa', from_area: 'addis-ababa:bole', to_area: 'addis-ababa:piassa' }, headers: api_headers(rider)
      expect(json['itineraries'].pluck('start_address')).to eq ['Bole, Addis Ababa']

      get '/api/v1/itineraries', params: { city: 'addis-ababa', from_area: 'addis-ababa:piassa', to_area: 'addis-ababa:bole' }, headers: api_headers(rider)
      expect(json['itineraries']).to be_empty
    end
  end

  describe 'on the web' do
    before { sign_in driver }

    it 'shows the page and the empty state' do
      get '/city_commutes'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Bole')
    end

    it 'posts a commute from the form and lists it' do
      expect do
        post '/city_commutes', params: { city: 'addis-ababa', from_area: 'addis-ababa:bole', to_area: 'addis-ababa:megenagna', start_date: next_monday.iso8601, time: '07:30',
                                         itinerary: { price_per_seat: '70', num_people: '3', commute_days: ['', '1', '3'], pickup_point: 'Total station', description: 'Daily to work' } }
      end.to change(Itinerary, :count).by(1)

      trip = Itinerary.last
      expect(response).to redirect_to(itinerary_path(trip))
      expect(trip).to have_attributes(city: 'addis-ababa', commute_days: [1, 3], start_address: 'Bole, Addis Ababa', pickup_point: 'Total station')
      expect(trip.leave_date.in_time_zone(Itinerary::RIDE_ZONE).strftime('%H:%M')).to eq '07:30'

      get '/city_commutes', params: { city: 'addis-ababa', from: 'addis-ababa:bole', to: 'addis-ababa:megenagna' }
      expect(response.body).to include('Megenagna, Addis Ababa')
    end

    it 'shows errors instead of saving a bad form' do
      expect do
        post '/city_commutes', params: { city: 'addis-ababa', from_area: 'addis-ababa:bole', to_area: 'addis-ababa:bole', start_date: next_monday.iso8601, time: '07:30', itinerary: { price_per_seat: '70', description: 'x' } }
      end.not_to change(Itinerary, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
