# frozen_string_literal: true

class AlertMailer < ApplicationMailer
  # To someone whose saved route just got a matching trip.
  def match
    @alert = params[:alert]
    @itinerary = params[:itinerary]
    @recipient = @alert.user
    mail_to @recipient, 'mailers.alert.match.subject', trip: @itinerary.title
  end
end
