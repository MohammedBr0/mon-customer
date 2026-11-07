# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Bookings' do
  let(:driver) { create(:user, name: 'Dave Driver') }
  let(:passenger) { create(:user, name: 'Paula Passenger') }
  let(:itinerary) { create(:itinerary, user: driver, num_people: 3, start_address: 'Milan', end_address: 'Turin') }

  describe 'POST /itineraries/:id/bookings' do
    before { sign_in passenger }

    it 'creates a pending booking and emails the driver' do
      expect do
        post itinerary_bookings_path(itinerary), params: { booking: { seats: 2, note: 'At the station' } }
      end.to change(Booking, :count).by(1).and have_enqueued_mail(BookingMailer, :requested)

      booking = Booking.last
      expect(booking).to have_attributes(passenger:, itinerary:, seats: 2, status: 'pending', note: 'At the station')
      expect(response).to redirect_to(itinerary_path(itinerary))
    end

    it 'does not allow booking twice' do
      create(:booking, itinerary:, passenger:)

      expect { post itinerary_bookings_path(itinerary), params: { booking: { seats: 1 } } }.not_to change(Booking, :count)
      expect(response).to redirect_to(itinerary_path(itinerary))
      expect(flash[:error]).to include('already have a booking')
    end

    it 'does not allow booking more seats than are free' do
      expect { post itinerary_bookings_path(itinerary), params: { booking: { seats: 4 } } }.not_to change(Booking, :count)
      expect(flash[:error]).to be_present
    end

    it 'does not allow the driver to book their own trip' do
      sign_in driver

      expect { post itinerary_bookings_path(itinerary), params: { booking: { seats: 1 } } }.not_to change(Booking, :count)
    end

    it 'does not allow booking a cancelled trip' do
      itinerary.cancel!

      expect { post itinerary_bookings_path(itinerary), params: { booking: { seats: 1 } } }.not_to change(Booking, :count)
    end

    it 'keeps women-only trips closed to men' do
      driver.update!(gender: 'female')
      itinerary.update!(pink: true)

      expect { post itinerary_bookings_path(itinerary), params: { booking: { seats: 1 } } }.not_to change(Booking, :count)
    end
  end

  describe 'driver decisions' do
    let!(:booking) { create(:booking, itinerary:, passenger:, seats: 2) }

    it 'lets the driver confirm and emails the passenger' do
      sign_in driver

      expect { patch confirm_booking_path(booking) }.to have_enqueued_mail(BookingMailer, :confirmed)

      expect(booking.reload).to be_confirmed
      expect(itinerary.seats_available).to eq 1
    end

    it 'lets the driver decline and emails the passenger' do
      sign_in driver

      expect { patch decline_booking_path(booking) }.to have_enqueued_mail(BookingMailer, :declined)

      expect(booking.reload).to be_declined
    end

    it 'refuses to confirm when seats ran out' do
      other = create(:booking, itinerary:, seats: 2)
      sign_in driver
      patch confirm_booking_path(other)

      patch confirm_booking_path(booking)

      expect(booking.reload).to be_pending
      expect(flash[:error]).to eq I18n.t('flash.bookings.not_enough_seats')
    end

    it 'does not let the passenger confirm their own booking' do
      sign_in passenger

      patch confirm_booking_path(booking)

      expect(booking.reload).to be_pending
      expect(response).to redirect_to(root_path)
    end

    it 'does not let strangers decide' do
      sign_in create(:user)

      patch decline_booking_path(booking)

      expect(booking.reload).to be_pending
    end
  end

  describe 'PATCH /bookings/:id/cancel' do
    let!(:booking) { create(:booking, :confirmed, itinerary:, passenger:) }

    it 'lets the passenger cancel and emails the driver' do
      sign_in passenger

      expect { patch cancel_booking_path(booking) }.to have_enqueued_mail(BookingMailer, :cancelled)

      expect(booking.reload).to be_cancelled
      expect(booking.cancelled_by).to eq passenger
    end

    it 'lets the driver cancel' do
      sign_in driver

      patch cancel_booking_path(booking)

      expect(booking.reload).to be_cancelled
    end

    it 'does not let strangers cancel' do
      sign_in create(:user)

      patch cancel_booking_path(booking)

      expect(booking.reload).to be_confirmed
    end
  end

  describe 'GET /bookings' do
    it 'lists requests received and bookings made' do
      create(:booking, itinerary:, passenger:)
      other_trip = create(:itinerary, user: create(:user, name: 'Olivia Other'), num_people: 2, start_address: 'Rome', end_address: 'Naples')
      create(:booking, itinerary: other_trip, passenger: driver)

      sign_in driver
      get bookings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Paula Passenger', 'Rome', 'Olivia Other')
    end

    it 'requires login' do
      get bookings_path

      expect(response).to be_redirect
    end
  end

  describe 'itinerary page' do
    it 'shows the request form to a passenger and the seat requests to the driver' do
      create(:booking, itinerary:, passenger:, note: 'See you at the station')

      sign_in create(:user)
      get itinerary_path(itinerary)
      expect(response.body).to include(I18n.t('bookings.request_title'))

      sign_in driver
      get itinerary_path(itinerary)
      expect(response.body).to include('Paula Passenger', 'See you at the station', I18n.t('bookings.confirm'))
    end

    it 'shows price per seat, seats left and vehicle details' do
      driver.update!(car_make: 'Fiat', car_model: 'Panda', car_color: 'red')
      itinerary.update!(fuel_cost: 30, tolls: 10)

      sign_in passenger
      get itinerary_path(itinerary)

      expect(response.body).to include('3 of 3 left', '10.00 €', 'red Fiat Panda')
    end
  end

  describe 'cancelling a trip' do
    it 'lets the driver cancel it, cancelling bookings and emailing passengers' do
      booking = create(:booking, :confirmed, itinerary:, passenger:)
      sign_in driver

      expect { patch cancel_itinerary_path(itinerary) }.to have_enqueued_mail(ItineraryMailer, :cancelled)

      expect(itinerary.reload).to be_cancelled
      expect(booking.reload).to be_cancelled
    end

    it 'does not let others cancel it' do
      sign_in passenger

      patch cancel_itinerary_path(itinerary)

      expect(response).to have_http_status(:not_found)
      expect(itinerary.reload).not_to be_cancelled
    end

    it 'hides cancelled trips from the dashboard' do
      cancelled = create(:itinerary, user: driver, start_address: 'Hidden', end_address: 'Away')
      cancelled.cancel!
      sign_in passenger

      get dashboard_path

      expect(response.body).not_to include('Hidden')
    end
  end
end
