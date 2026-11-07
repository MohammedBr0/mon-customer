# frozen_string_literal: true

class ItineraryMailer < ApplicationMailer
  # To a passenger whose trip the driver cancelled.
  def cancelled
    @booking = params[:booking]
    @recipient = @booking.passenger
    mail_to @recipient, 'mailers.itinerary.cancelled.subject', trip: @booking.itinerary.title
  end
end
