# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Review do
  let(:booking) { create(:booking, :completed) }
  let(:passenger) { booking.passenger }
  let(:driver) { booking.driver }

  it 'lets the passenger rate the driver after the trip' do
    expect(build(:review, booking:, reviewer: passenger, reviewee: driver)).to be_valid
  end

  it 'lets the driver rate the passenger after the trip' do
    expect(build(:review, booking:, reviewer: driver, reviewee: passenger)).to be_valid
  end

  it 'rejects a rating outside 1 to 5' do
    expect(build(:review, booking:, rating: 0)).not_to be_valid
    expect(build(:review, booking:, rating: 6)).not_to be_valid
  end

  it 'allows one review per reviewer and booking' do
    create(:review, booking:, reviewer: passenger, reviewee: driver)

    expect(build(:review, booking:, reviewer: passenger, reviewee: driver)).not_to be_valid
    expect(build(:review, booking:, reviewer: driver, reviewee: passenger)).to be_valid
  end

  it 'rejects reviews before the trip has happened' do
    upcoming = create(:booking, :confirmed)

    expect(build(:review, booking: upcoming, reviewer: upcoming.passenger, reviewee: upcoming.driver)).not_to be_valid
  end

  it 'rejects reviews of an unconfirmed booking' do
    pending_booking = create(:booking)
    pending_booking.itinerary.update_columns(leave_date: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(build(:review, booking: pending_booking, reviewer: pending_booking.passenger, reviewee: pending_booking.driver)).not_to be_valid
  end

  it 'rejects outsiders and self-reviews' do
    outsider = create(:user)

    expect(build(:review, booking:, reviewer: outsider, reviewee: driver)).not_to be_valid
    expect(build(:review, booking:, reviewer: passenger, reviewee: passenger)).not_to be_valid
  end

  it 'feeds the reviewee average rating' do
    create(:review, booking:, reviewer: passenger, reviewee: driver, rating: 5)
    other = create(:booking, :completed, itinerary: create(:itinerary, user: driver, num_people: 3))
    create(:review, booking: other, reviewer: other.passenger, reviewee: driver, rating: 4)

    expect(driver.reviews_count).to eq 2
    expect(driver.average_rating).to eq 4.5
  end
end
