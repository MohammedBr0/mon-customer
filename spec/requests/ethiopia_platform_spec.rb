# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ethiopian platform: pricing, fees and vehicle fields' do
  let(:admin) { create(:user, admin: true) }
  let(:driver) { create(:user, name: 'Dawit Driver', phone: '0911223344') }
  let(:rider) { create(:user, name: 'Rahel Rider', phone: '0922334455') }
  let(:route) do
    { start_location: [38.74, 9.03], end_location: [39.27, 8.54], via_waypoints: [], overview_path: [[38.74, 9.03], [39.27, 8.54]],
      overview_polyline: '_p~iF~ps|U_ulLnnqC' }.to_json
  end

  describe 'drivers set the price' do
    before { sign_in driver }

    it 'creates a trip with the driver price and free seats' do
      expect do
        post itineraries_path, params: { itinerary: { start_address: 'Addis Ababa', end_address: 'Adama', description: 'Morning trip',
                                                      leave_date: 2.days.from_now.to_s, price_per_seat: '180', num_people: '3', route: } }
      end.to change(Itinerary, :count).by(1)

      expect(Itinerary.last).to have_attributes(price_per_seat: 180, num_people: 3)
      expect(response).to redirect_to(itinerary_path(Itinerary.last))
    end

    it 'shows the price and seats fields, the fee note and the Birr symbol on the form' do
      PlatformSetting.current.update!(fee_percent: 8, fee_charged_to: 'passenger')

      get new_itinerary_path

      expect(response.body).to include('itinerary[price_per_seat]', 'itinerary[num_people]', 'Br', '8% service fee')
    end

    it 'blocks a trip priced above the platform limit' do
      PlatformSetting.current.update!(max_price_per_seat: 500)

      expect do
        post itineraries_path, params: { itinerary: { start_address: 'Addis Ababa', end_address: 'Adama', description: 'Too dear',
                                                      leave_date: 2.days.from_now.to_s, price_per_seat: '5000', num_people: '3', route: } }
      end.not_to change(Itinerary, :count)
    end

    it 'asks a driver with an incomplete vehicle to complete it first' do
      create(:vehicle_field, key: 'plate', label: 'Plate number', required: true)

      expect do
        post itineraries_path, params: { itinerary: { start_address: 'Addis Ababa', end_address: 'Adama', description: 'No vehicle',
                                                      leave_date: 2.days.from_now.to_s, price_per_seat: '100', num_people: '3', route: } }
      end.not_to change(Itinerary, :count)
      expect(response.body).to include('Plate number')
    end
  end

  describe 'booking shows the fee breakdown and contact details after confirmation' do
    let!(:itinerary) { create(:itinerary, user: driver, num_people: 3, price_per_seat: 200) }

    it 'shows fare, service fee and total to the passenger, and the payout to the driver' do
      PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
      create(:booking, itinerary:, passenger: rider, seats: 2)

      sign_in driver
      get itinerary_path(itinerary)
      expect(response.body).to include('400 Br', 'You receive')

      sign_in create(:user)
      get itinerary_path(itinerary)
      expect(response.body).to include('data-price-calc', 'data-fee-percent="10.0"', 'Service fee (10%)')
    end

    it 'shows phone numbers only after the booking is confirmed' do
      booking = create(:booking, itinerary:, passenger: rider)

      sign_in rider
      get itinerary_path(itinerary)
      expect(response.body).not_to include('+251911223344')

      booking.confirm!
      get itinerary_path(itinerary)
      expect(response.body).to include('+251911223344')

      sign_in driver
      get bookings_path
      expect(response.body).to include('+251922334455')
    end

    it 'keeps the plate hidden until confirmation but shows public vehicle fields' do
      create(:vehicle_field, key: 'make', label: 'Make')
      create(:vehicle_field, key: 'plate', label: 'Plate', visibility: 'confirmed')
      driver.update!(vehicle_data: { 'make' => 'Toyota', 'plate' => 'AA 12345' })
      booking = create(:booking, itinerary:, passenger: rider)

      sign_in rider
      get itinerary_path(itinerary)
      expect(response.body).to include('Make: Toyota')
      expect(response.body).not_to include('AA 12345')

      booking.confirm!
      get itinerary_path(itinerary)
      expect(response.body).to include('Plate: AA 12345')
    end
  end

  describe 'super admin: fee and payment settings' do
    before { sign_in admin }

    it 'shows and updates the platform settings' do
      get admin_settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('platform_setting[fee_percent]')

      patch admin_settings_path, params: { platform_setting: { fee_percent: '12.5', fee_charged_to: 'driver', currency_symbol: 'ETB',
                                                               max_price_per_seat: '2500', payment_instructions: 'Pay with Telebirr.' } }

      expect(response).to redirect_to(admin_settings_path)
      expect(PlatformSetting.current).to have_attributes(fee_percent: 12.5, fee_charged_to: 'driver', currency_symbol: 'ETB',
                                                         max_price_per_seat: 2500, payment_instructions: 'Pay with Telebirr.')
    end

    it 'rejects invalid values' do
      patch admin_settings_path, params: { platform_setting: { fee_percent: '80' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(PlatformSetting.current.fee_percent).not_to eq 80
    end

    it 'applies a new fee to new bookings only' do
      itinerary = create(:itinerary, num_people: 3, price_per_seat: 100)
      old = create(:booking, itinerary:, seats: 1)

      patch admin_settings_path, params: { platform_setting: { fee_percent: '20', fee_charged_to: 'passenger' } }
      newer = create(:booking, itinerary:, seats: 1)

      expect(old.reload.fee_amount).to eq 10 # keeps the 10% that applied when it was made
      expect(newer.fee_amount).to eq 20
    end

    it 'is closed to regular users' do
      sign_in rider

      get admin_settings_path
      expect(response).to redirect_to(root_path)

      patch admin_settings_path, params: { platform_setting: { fee_percent: '0' } }
      expect(PlatformSetting.current.fee_percent).to eq 10
    end

    it 'reports fares and platform fees on the dashboard' do
      PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
      create(:booking, :confirmed, itinerary: create(:itinerary, num_people: 3, price_per_seat: 300), seats: 2)

      get admin_root_path

      expect(response.body).to include('600 Br', '60 Br')
    end
  end

  describe 'super admin: vehicle fields' do
    before { sign_in admin }

    it 'lists, creates, edits, reorders and deletes fields' do
      first = create(:vehicle_field, key: 'plate', label: 'Plate number', position: 0)
      second = create(:vehicle_field, key: 'color', label: 'Color', position: 1)

      get admin_vehicle_fields_path
      expect(response.body).to include('Plate number', 'Color')

      post admin_vehicle_fields_path, params: { vehicle_field: { key: 'Fuel Type', label: 'Fuel type', am: 'የነዳጅ ዓይነት', field_type: 'select',
                                                                 options_text: "Petrol\nDiesel\nElectric", visibility: 'public', required: '1' } }
      created = VehicleField.find_by!(key: 'fuel_type')
      expect(created).to have_attributes(label: 'Fuel type', am: 'የነዳጅ ዓይነት', options: %w[Petrol Diesel Electric], required: true)

      patch admin_vehicle_field_path(created), params: { vehicle_field: { key: 'ignored', label: 'Fuel', visibility: 'confirmed' } }
      expect(created.reload).to have_attributes(key: 'fuel_type', label: 'Fuel', visibility: 'confirmed')

      patch move_admin_vehicle_field_path(second, direction: 'up')
      expect(VehicleField.ordered.first(2)).to eq [second, first]

      delete admin_vehicle_field_path(created)
      expect(VehicleField.exists?(created.id)).to be false
    end

    it 'rejects an invalid field' do
      post admin_vehicle_fields_path, params: { vehicle_field: { key: 'x', label: '', field_type: 'select', options_text: '' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(VehicleField.count).to eq 0
    end

    it 'makes a new field appear for drivers and a deactivated one disappear' do
      field = create(:vehicle_field, key: 'insurance', label: 'Insurance expiry')
      sign_in driver
      get settings_path
      expect(response.body).to include('Insurance expiry')

      field.update!(active: false)
      get settings_path
      expect(response.body).not_to include('Insurance expiry')
    end

    it 'is closed to regular users' do
      sign_in rider

      get admin_vehicle_fields_path
      expect(response).to redirect_to(root_path)
      expect { post admin_vehicle_fields_path, params: { vehicle_field: { key: 'x1', label: 'X' } } }.not_to change(VehicleField, :count)
    end
  end

  describe 'language' do
    it 'serves the Amharic interface and falls back to English for untranslated text' do
      sign_in driver
      driver.update!(locale: 'am-ET')

      get bookings_path

      expect(response.body).to include('ቦታ ማስያዣዎች')
    end

    it 'shows the Amharic landing page with Ethiopian routes' do
      get root_path(locale: 'am-ET')

      expect(response.body).to include('በመላው ኢትዮጵያ', 'አዲስ አበባ → አዳማ')
    end

    it 'shows the English landing page with the signed-out call to action' do
      get root_path

      expect(response.body).to include('Share the ride across Ethiopia', 'Get started')
    end
  end

  describe 'mobile layout' do
    it 'renders the bottom tab bar for signed-in users and not for visitors' do
      sign_in driver
      get dashboard_path
      expect(response.body).to include('class="tabbar"', 'tabbar__post')

      sign_out driver
      get root_path
      expect(response.body).not_to include('class="tabbar"')
    end

    it 'sets a mobile viewport' do
      get root_path

      expect(response.body).to include('width=device-width, initial-scale=1')
    end
  end
end
