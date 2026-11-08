# frozen_string_literal: true

# When a trip is posted, tells everyone whose saved route it matches.
class RideAlertMatchJob < ApplicationJob
  queue_as :default

  def perform(itinerary)
    return if itinerary.cancelled?

    RideAlert.matching(itinerary).includes(:user).find_each do |alert|
      next if itinerary.pink? && !alert.user.female?

      alert.update_columns(last_notified_at: Time.current)
      Notification.notify(alert.user, 'alert_match', itinerary_id: itinerary.id, trip: itinerary.title, route: "#{alert.start_label} → #{alert.end_label}")
      AlertMailer.with(alert:, itinerary:).match.deliver_later
    end
  end
end
