# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Search and settings' do
  let(:user) { create(:user) }
  let(:search_params) do
    { itineraries_search: { start_location_lng: '9.19', start_location_lat: '45.46', end_location_lng: '7.69', end_location_lat: '45.07' } }
  end

  before { sign_in user }

  def search(extra = {})
    post search_itineraries_path(format: :json), params: { itineraries_search: search_params[:itineraries_search].merge(extra) }
    response.parsed_body
  end

  it 'finds open trips and exposes seats and price per seat' do
    create(:itinerary, num_people: 3, fuel_cost: 30, tolls: 10)

    result = search

    expect(result.size).to eq 1
    expect(result.first).to include('seats_available' => 3, 'cost_per_seat' => 10.0)
  end

  it 'leaves out cancelled trips' do
    create(:itinerary).cancel!

    expect(search).to be_empty
  end

  it 'never lists fully booked trips, even when one seat is enough' do
    full_trip = create(:itinerary, num_people: 2)
    create(:booking, :confirmed, itinerary: full_trip, seats: 2)
    roomy = create(:itinerary, num_people: 4)

    expect(search.pluck('id')).to eq [roomy.id.to_s]
    expect(search(seats: '1').pluck('id')).to eq [roomy.id.to_s]
  end

  it 'filters by seats needed' do
    full_trip = create(:itinerary, num_people: 2)
    create(:booking, :confirmed, itinerary: full_trip, seats: 2)
    roomy = create(:itinerary, num_people: 4)

    ids = search(seats: '2').pluck('id')

    expect(ids).to eq [roomy.id.to_s]
  end

  it 'sorts by earliest departure or by price' do
    late_cheap = create(:itinerary, num_people: 3, fuel_cost: 4, tolls: 0, leave_date: 5.days.from_now)
    early_dear = create(:itinerary, num_people: 3, fuel_cost: 60, tolls: 0, leave_date: 1.day.from_now)

    expect(search(sort: 'date').pluck('id')).to eq [early_dear, late_cheap].map { |i| i.id.to_s }
    expect(search(sort: 'price').pluck('id')).to eq [late_cheap, early_dear].map { |i| i.id.to_s }
  end

  it 'saves vehicle details and the email preference from settings' do
    patch user_path(user), params: { user: { car_make: 'Fiat', car_model: 'Panda', car_color: 'red', car_plate: 'AB123CD', send_email_messages: '1' } }

    expect(user.reload).to have_attributes(car_make: 'Fiat', car_model: 'Panda', car_color: 'red', car_plate: 'AB123CD', send_email_messages: true)
    expect(user.vehicle_description).to eq 'red Fiat Panda'
  end

  it 'renders the settings page with the vehicle fields' do
    get settings_path

    expect(response.body).to include('user[car_make]', 'user[car_plate]')
  end
end
