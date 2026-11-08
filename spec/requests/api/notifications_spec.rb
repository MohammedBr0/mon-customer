# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API notifications' do
  let(:driver) { create(:user, name: 'Dawit Driver') }
  let(:rider) { create(:user, name: 'Rahel Rider') }
  let(:trip) { create(:itinerary, user: driver, num_people: 3, price_per_seat: 100) }

  def request_seat
    post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 1 } }, headers: api_headers(rider)
    Booking.find(json['booking']['id'])
  end

  it 'tells the driver about a seat request, then the rider about the answer' do
    booking = request_seat
    expect(driver.notifications.pluck(:kind)).to eq(['booking_requested'])

    patch "/api/v1/bookings/#{booking.id}/confirm", headers: api_headers(driver)
    expect(rider.notifications.pluck(:kind)).to eq(['booking_confirmed'])

    get '/api/v1/notifications', headers: api_headers(rider)
    expect(json['unread']).to eq 1
    expect(json['notifications'].first).to include('kind' => 'booking_confirmed', 'read' => false)
    expect(json['notifications'].first['body']).to include('Dawit Driver')
    expect(json['notifications'].first['data']).to include('booking_id' => booking.id)
  end

  it 'tells the other side about a cancellation, and everyone when the trip is cancelled' do
    booking = request_seat
    patch "/api/v1/bookings/#{booking.id}/cancel", headers: api_headers(rider)
    expect(driver.notifications.pluck(:kind)).to include('booking_cancelled')

    second = create(:user)
    post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 1 } }, headers: api_headers(second)
    patch "/api/v1/itineraries/#{trip.id}/cancel", headers: api_headers(driver)
    expect(second.notifications.pluck(:kind)).to eq(['itinerary_cancelled'])
  end

  it 'tells the receiver about a message, in their language' do
    rider.update!(locale: 'am-ET')
    post '/api/v1/conversations', params: { itinerary_id: trip.id, body: 'Hello there' }, headers: api_headers(rider)
    expect(driver.notifications.pluck(:kind)).to eq(['new_message'])

    driver.update!(locale: 'am-ET')
    get '/api/v1/notifications', headers: api_headers(driver)
    expect(json['notifications'].first['title']).to eq 'አዲስ መልእክት'
  end

  it 'polls for newer ones only, and marks them read' do
    request_seat
    other = create(:user)
    first = Notification.notify(other, 'new_message', person: 'A', preview: 'one')
    second = Notification.notify(other, 'new_message', person: 'B', preview: 'two')

    get '/api/v1/notifications', params: { after: first.id }, headers: api_headers(other)
    expect(json['notifications'].pluck('id')).to eq [second.id]

    patch "/api/v1/notifications/#{first.id}/read", headers: api_headers(other)
    expect(json['unread']).to eq 1
    post '/api/v1/notifications/read_all', headers: api_headers(other)
    expect(json['unread']).to eq 0
  end

  it 'never shows someone else’s notifications' do
    note = Notification.notify(driver, 'new_message', person: 'A', preview: 'secret')
    patch "/api/v1/notifications/#{note.id}/read", headers: api_headers(rider)
    expect(response).to have_http_status(:not_found)
  end

  it 'requires sign-in' do
    get '/api/v1/notifications'
    expect(response).to have_http_status(:unauthorized)
  end
end
