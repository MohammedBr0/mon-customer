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
    PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
    create(:itinerary, num_people: 3, price_per_seat: 100)

    result = search

    expect(result.size).to eq 1
    expect(result.first).to include('seats_available' => 3, 'price_per_seat' => '100.0', 'passenger_price_per_seat' => '110.0')
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
    late_cheap = create(:itinerary, num_people: 3, price_per_seat: 20, leave_date: 5.days.from_now)
    early_dear = create(:itinerary, num_people: 3, price_per_seat: 300, leave_date: 1.day.from_now)

    expect(search(sort: 'date').pluck('id')).to eq([early_dear, late_cheap].map { |i| i.id.to_s })
    expect(search(sort: 'price').pluck('id')).to eq([late_cheap, early_dear].map { |i| i.id.to_s })
  end

  it 'saves admin-configured vehicle details, phone and the email preference from settings' do
    create(:vehicle_field, key: 'make', label: 'Make')
    create(:vehicle_field, key: 'color', label: 'Color', field_type: 'select', options: %w[Red Blue])
    create(:vehicle_field, key: 'seats', label: 'Seats', field_type: 'number', min_value: 1, max_value: 20)

    patch user_path(user), params: { user: { phone: '0911 22 33 44', send_email_messages: '1',
                                              vehicle_data: { make: 'Toyota', color: 'Red', seats: '4', unknown: 'dropped' } } }

    expect(user.reload.vehicle_data).to eq('make' => 'Toyota', 'color' => 'Red', 'seats' => 4)
    expect(user).to have_attributes(phone: '+251911223344', send_email_messages: true)
    expect(user.vehicle_description).to eq 'Red Toyota'
  end

  it 'does not ship the strict phone pattern to the browser, which would block numbers typed as 0911 22 33 44' do
    get settings_path

    expect(response.body).not_to include('must be an Ethiopian number')
  end

  it 'renders the settings page with the configured vehicle fields and phone' do
    create(:vehicle_field, key: 'plate', label: 'Plate number')

    get settings_path

    expect(response.body).to include('user[vehicle_data][plate]', 'Plate number', 'user[phone]')
  end
end
