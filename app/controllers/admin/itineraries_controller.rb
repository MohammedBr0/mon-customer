# frozen_string_literal: true

module Admin
  class ItinerariesController < BaseController
    def index
      @itineraries = Itinerary.includes(:user).order(created_at: :desc).page params[:page]
    end

    def cancel
      itinerary = Itinerary.friendly.find(params[:id])
      bookings = itinerary.bookings.active.includes(:passenger).to_a
      itinerary.cancel!
      audit!('itinerary.cancel', itinerary)
      bookings.each { |booking| ItineraryMailer.with(booking:).cancelled.deliver_later }
      redirect_to admin_itineraries_path, flash: { success: t('flash.admin.itineraries.cancelled') }
    end
  end
end
