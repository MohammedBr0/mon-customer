# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def show
      @stats = {
        users:                 User.count,
        verified_drivers:      User.where.not(verified_at: nil).count,
        commutes:              Itinerary.not_cancelled.where('cardinality(commute_days) > 0').count,
        ride_alerts:           RideAlert.active.count,
        open_reports:          Report.open.count,
        banned_users:          User.where(banned: true).count,
        itineraries:           Itinerary.count,
        upcoming_itineraries:  Itinerary.not_cancelled.upcoming.count,
        cancelled_itineraries: Itinerary.where.not(cancelled_at: nil).count,
        conversations:         Conversation.count,
        bookings:              Booking.group(:status).count,
        reviews:               Review.count,
        gross_fares:           Booking.confirmed.sum(:fare_total),
        platform_fees:         Booking.confirmed.sum(:fee_amount),
        average_rating:        Review.visible.average(:rating)&.to_f&.round(2)
      }
    end
  end
end
