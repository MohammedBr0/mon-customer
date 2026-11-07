# frozen_string_literal: true

# "Tell me when someone offers a ride on this route." Matches trips whose start and end are both
# within MATCH_RADIUS_METERS of the alert's start and end.
class RideAlert < ApplicationRecord
  MATCH_RADIUS_METERS = 5000
  MAX_PER_USER = 10

  belongs_to :user

  scope :active, -> { where(active: true) }

  validates :start_label, :end_label, presence: true, length: { maximum: 120 }
  validates :start_location, :end_location, presence: true
  validate :user_alert_limit, on: :create

  %i[start_location end_location].each do |field|
    define_method(:"#{field}=") do |value|
      super(value.is_a?(Array) ? "POINT(#{value.join(' ')})" : value)
    end
  end

  # Build from the coordinates the search form carries ("lng,lat" order matches the rest of the app).
  def self.from_search(user, params)
    new(user:, start_label: params[:from], end_label: params[:to],
        start_location: point(params[:start_location_lng], params[:start_location_lat]),
        end_location: point(params[:end_location_lng], params[:end_location_lat]))
  end

  def self.point(lng, lat)
    return if lng.blank? || lat.blank?

    "POINT(#{lng.to_f} #{lat.to_f})"
  end

  # Alerts that a freshly posted trip satisfies.
  def self.matching(itinerary)
    active.where.not(user_id: itinerary.user_id)
          .where('ST_DWithin(start_location, :from::geography, :radius) AND ST_DWithin(end_location, :to::geography, :radius)',
                 from: itinerary.start_location.to_s, to: itinerary.end_location.to_s, radius: MATCH_RADIUS_METERS)
  end

  # Open trips that already match this alert.
  def current_matches
    Itinerary.not_cancelled.upcoming_or_commute.where.not(user_id: user_id)
             .where('ST_DWithin(itineraries.start_location, :from::geography, :radius) AND ST_DWithin(itineraries.end_location, :to::geography, :radius)',
                    from: start_location.to_s, to: end_location.to_s, radius: MATCH_RADIUS_METERS)
  end

  private

  def user_alert_limit
    errors.add(:base, :too_many_alerts, count: MAX_PER_USER) if user && user.ride_alerts.count >= MAX_PER_USER
  end
end
