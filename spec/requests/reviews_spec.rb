# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reviews' do
  let(:booking) { create(:booking, :completed) }
  let(:passenger) { booking.passenger }
  let(:driver) { booking.driver }

  it 'lets the passenger rate the driver after the trip' do
    sign_in passenger

    get new_booking_review_path(booking)
    expect(response).to have_http_status(:ok)

    expect do
      post booking_reviews_path(booking), params: { review: { rating: 4, comment: 'Smooth ride' } }
    end.to change(Review, :count).by(1)

    expect(Review.last).to have_attributes(reviewer: passenger, reviewee: driver, rating: 4, comment: 'Smooth ride')
    expect(response).to redirect_to(user_path(driver))
  end

  it 'lets the driver rate the passenger' do
    sign_in driver

    post booking_reviews_path(booking), params: { review: { rating: 5 } }

    expect(Review.last).to have_attributes(reviewer: driver, reviewee: passenger)
  end

  it 'blocks a second review of the same booking' do
    create(:review, booking:, reviewer: passenger, reviewee: driver)
    sign_in passenger

    expect { post booking_reviews_path(booking), params: { review: { rating: 1 } } }.not_to change(Review, :count)
    expect(response).to redirect_to(bookings_path)
  end

  it 'blocks reviews before the trip has happened' do
    upcoming = create(:booking, :confirmed)
    sign_in upcoming.passenger

    expect { post booking_reviews_path(upcoming), params: { review: { rating: 5 } } }.not_to change(Review, :count)
  end

  it 'blocks outsiders' do
    sign_in create(:user)

    expect { post booking_reviews_path(booking), params: { review: { rating: 5 } } }.not_to change(Review, :count)
  end

  it 're-renders the form for an invalid rating' do
    sign_in passenger

    post booking_reviews_path(booking), params: { review: { rating: 9 } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'shows ratings and reviews on the profile' do
    create(:review, booking:, reviewer: passenger, reviewee: driver, rating: 5, comment: 'Wonderful company')
    sign_in passenger

    get user_path(driver)

    expect(response.body).to include('5.0 (1 review)', 'Wonderful company')
  end
end
