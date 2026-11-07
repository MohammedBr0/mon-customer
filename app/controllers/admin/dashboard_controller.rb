# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def show
      @stats = {
        users:               User.count,
        banned_users:        User.where(banned: true).count,
        itineraries:         Itinerary.count,
        upcoming_itineraries: Itinerary.not_cancelled.upcoming.count,
        cancelled_itineraries: Itinerary.where.not(cancelled_at: nil).count,
        conversations:       Conversation.count,
        bookings:            Booking.group(:status).count,
        reviews:             Review.count,
        average_rating:      Review.average(:rating)&.to_f&.round(2)
      }
    end
  end
end
