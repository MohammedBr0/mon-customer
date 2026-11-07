# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin' do
  let(:admin) { create(:user, admin: true) }

  it 'shows platform statistics to admins' do
    create(:booking, :confirmed)
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t('admin_extra.stats.users'), I18n.t('bookings.statuses.confirmed'))
  end

  it 'lists itineraries and lets an admin cancel one' do
    booking = create(:booking, :confirmed)
    sign_in admin

    get admin_itineraries_path
    expect(response.body).to include(booking.itinerary.title)

    expect { patch cancel_admin_itinerary_path(booking.itinerary) }.to have_enqueued_mail(ItineraryMailer, :cancelled)
    expect(booking.itinerary.reload).to be_cancelled
    expect(booking.reload).to be_cancelled
  end

  it 'keeps regular users out' do
    sign_in create(:user)

    get admin_root_path
    expect(response).to redirect_to(root_path)

    get admin_itineraries_path
    expect(response).to redirect_to(root_path)
  end
end
