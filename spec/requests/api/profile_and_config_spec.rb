# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API config and profile' do
  let(:user) { create(:user, name: 'Dawit Driver', phone: '0911223344') }

  it 'publishes public settings without sign-in' do
    create(:vehicle_field, key: 'plate', label: 'Plate number', required: true, visibility: 'confirmed')
    PopularRoute.create!(from_label: 'Addis Ababa', to_label: 'Jimma')
    PlatformSetting.current.update!(fee_percent: 12.5, fee_charged_to: 'passenger', announcement: 'Hello', announcement_active: true)

    get '/api/v1/config'

    expect(response).to have_http_status(:ok)
    expect(json).to include('currency' => { 'code' => 'ETB', 'symbol' => 'Br' }, 'announcement' => 'Hello', 'api_version' => 1, 'commutes_enabled' => true)
    expect(json['fee']).to eq('percent' => 12.5, 'charged_to' => 'passenger')
    expect(json['vehicle_fields'].first).to include('key' => 'plate', 'required' => true, 'visibility' => 'confirmed')
    expect(json['popular_routes']).to eq([{ 'from' => 'Addis Ababa', 'to' => 'Jimma' }])
    expect(json['places'].map { |place| place['name'] }).to include('Addis Ababa', 'Adama', 'Hawassa')
    expect(json['languages']).to include('en-US', 'am-ET')
  end

  it 'hides the announcement once switched off' do
    PlatformSetting.current.update!(announcement: 'Hello', announcement_active: false)

    get '/api/v1/config'

    expect(json['announcement']).to be_nil
  end

  it 'lists every place inside the Ethiopian service area' do
    outline = eval(Rails.root.join('config/settings/application.rb').read[/set :bounds, (\[.*?\n    \])/m, 1]) # rubocop:disable Security/Eval
    ring = GeoItinerary::RGEO_FACTORY.linear_ring(outline.map { |p| RGeo::Geographic.spherical_factory.point(*p) })
    area = GeoItinerary::RGEO_FACTORY.polygon(ring)

    outside = EthiopianPlace.all.reject { |place| area.contains?(RGeo::Geographic.spherical_factory.point(place.lng, place.lat)) }

    expect(outside.map(&:name)).to eq []
    expect(EthiopianPlace.all.map(&:key).uniq.size).to eq EthiopianPlace.all.size
  end

  it 'finds the nearest place and labels in Amharic' do
    expect(EthiopianPlace.nearest(9.05, 38.7).name).to eq 'Addis Ababa'
    expect(EthiopianPlace.find('addis-ababa').label('am-ET')).to eq 'አዲስ አበባ'
  end

  describe 'GET and PATCH /api/v1/me' do
    it 'returns the profile with vehicle completeness' do
      create(:vehicle_field, key: 'plate', label: 'Plate', required: true)

      get '/api/v1/me', headers: api_headers(user)

      expect(json['user']).to include('name' => 'Dawit Driver', 'phone' => '+251911223344', 'vehicle_complete' => false, 'missing_vehicle_fields' => ['plate'], 'role' => 'user')
    end

    it 'updates phone, language and vehicle answers' do
      create(:vehicle_field, key: 'make', label: 'Make')

      patch '/api/v1/me', params: { user: { phone: '0922 33 44 55', locale: 'am-ET', send_email_messages: true, vehicle_data: { make: 'Toyota', ghost: 'x' } } }, headers: api_headers(user)

      expect(response).to have_http_status(:ok)
      expect(user.reload).to have_attributes(phone: '+251922334455', locale: 'am-ET', send_email_messages: true)
      expect(user.vehicle_data).to eq('make' => 'Toyota')
    end

    it 'rejects an invalid phone number' do
      patch '/api/v1/me', params: { user: { phone: '12345' } }, headers: api_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']['code']).to eq 'invalid_record'
    end

    it 'deletes the account' do
      headers = api_headers(user)

      expect { delete '/api/v1/me', headers: headers }.to change(User, :count).by(-1)
      expect(response).to have_http_status(:no_content)
      expect(ApiToken.count).to eq 0
    end
  end

  it 'answers in Amharic for people who chose it' do
    user.update!(locale: 'am-ET')

    get '/api/v1/itineraries/nothing', headers: api_headers(user)

    expect(response).to have_http_status(:not_found)
    expect(json['error']['message']).to eq 'አልተገኘም'
  end
end
