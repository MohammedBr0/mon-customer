# frozen_string_literal: true

class BookingMailer < ApplicationMailer
  before_action { @booking = params[:booking] }

  # To the driver: a passenger asks for seats.
  def requested
    @recipient = @booking.driver
    mail_to @recipient, 'mailers.booking.requested.subject', passenger: @booking.passenger.to_s, trip: @booking.itinerary.title
  end

  # To the passenger: the driver accepted.
  def confirmed
    @recipient = @booking.passenger
    mail_to @recipient, 'mailers.booking.confirmed.subject', trip: @booking.itinerary.title
  end

  # To the passenger: the driver declined.
  def declined
    @recipient = @booking.passenger
    mail_to @recipient, 'mailers.booking.declined.subject', trip: @booking.itinerary.title
  end

  # To whoever did not cancel.
  def cancelled
    @recipient = @booking.cancelled_by == @booking.passenger ? @booking.driver : @booking.passenger
    @cancelled_by = @booking.cancelled_by || @booking.driver
    mail_to @recipient, 'mailers.booking.cancelled.subject', trip: @booking.itinerary.title
  end
end
