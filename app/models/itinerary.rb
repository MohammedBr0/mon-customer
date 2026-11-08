# frozen_string_literal: true

class Itinerary < ApplicationRecord
  include GeoItinerary
  extend FriendlyId

  DAYNAME = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  MAX_DESCRIPTION_LENGTH = 1000
  # Ride days are calendar days in Ethiopia, whatever the viewer's own time zone.
  RIDE_ZONE = ActiveSupport::TimeZone['Nairobi']

  def self.today
    RIDE_ZONE.today
  end

  friendly_id :name, use: :slugged

  def name
    [start_address, end_address].join ' '
  end

  has_many :conversations, as: :conversable, dependent: :destroy
  has_many :bookings, dependent: :destroy

  scope :in_city, ->(key) { where(city: key) }
  scope :not_cancelled, -> { where(cancelled_at: nil) }
  scope :upcoming, -> { where(leave_date: Time.current..) }
  # Trips a person could still ride: one-offs that have not left, and commutes that have not ended.
  scope :upcoming_or_commute, lambda {
    where('itineraries.leave_date >= :now OR (cardinality(itineraries.commute_days) > 0 AND (itineraries.commute_until IS NULL OR itineraries.commute_until >= :today))',
          now: Time.current, today: Itinerary.today)
  }

  belongs_to :user
  delegate :name, to: :user, prefix: true
  delegate :first_name, to: :user, prefix: true

  before_validation :clean_commute_days
  before_save { self.daily = commute? }

  validate :commute_schedule_is_valid
  validate :city_areas_are_valid, if: -> { city_commute? && start_area_key }
  validates :city, inclusion: { in: EthiopianPlace::AREAS.keys }, allow_nil: true
  validates :pickup_point, :dropoff_point, length: { maximum: 120 }
  validates :price_per_seat, numericality: { greater_than_or_equal_to: 0 }
  validate :price_within_platform_limit
  validate :driver_vehicle_is_complete, on: :create

  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }, presence: true
  validates :num_people, numericality: { only_integer: true, greater_than: 0, less_than: 10 }, allow_blank: true
  validates :fuel_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 10_000 }
  validates :tolls, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 10_000 }
  validates :leave_date, comparison: { greater_than_or_equal_to: -> { Time.current } }, if: :will_save_change_to_leave_date?
  validates :return_date, presence: true, comparison: { greater_than_or_equal_to: :leave_date }, if: :round_trip?

  validate :driver_is_female, if: -> { pink }

  def driver_is_female
    errors.add(:pink, :driver_must_be_female) unless user.female?
  end

  def price_within_platform_limit
    max = PlatformSetting.current.max_price_per_seat
    errors.add(:price_per_seat, :less_than_or_equal_to, count: max.to_i) if price_per_seat.to_d > max
  end

  # Passengers need to recognise the car, so required vehicle details come before the first trip.
  def city_areas_are_valid
    start = EthiopianPlace.find(start_area_key)
    finish = EthiopianPlace.find(end_area_key)
    errors.add(:base, :city_area_invalid) unless start&.city == city && finish&.city == city
    errors.add(:base, :city_same_area) if start && finish && start.key == finish.key
  end

  def clean_commute_days
    self.commute_days = commute_days # normalises and sorts
  end

  def commute_schedule_is_valid
    return unless commute?

    errors.add(:commute_days, :invalid) unless commute_days.all? { |day| day.between?(0, 6) }
    errors.add(:base, :commutes_disabled) unless PlatformSetting.current.commutes_enabled? || persisted?
    errors.add(:commute_until, :on_or_after_start) if commute_until && first_ride_date && commute_until < first_ride_date
    errors.add(:round_trip, :not_for_commutes) if round_trip?
  end

  def driver_vehicle_is_complete
    return if user.blank? || user.vehicle_complete?

    errors.add(:base, :vehicle_incomplete, fields: user.missing_vehicle_fields.map(&:label_for).to_sentence)
  end

  before_create do
    self.driver_gender = user.gender
    true
  end

  def title
    [start_address, end_address].join ' - '
  end

  def cancelled?
    cancelled_at.present?
  end

  attr_accessor :start_area_key, :end_area_key

  # Fills in a trip that stays inside one city: addresses and a simple route come from the chosen neighbourhoods.
  def use_city_areas(city:, from:, to:)
    self.city = city.presence
    self.start_area_key = from
    self.end_area_key = to
    start = EthiopianPlace.find(from)
    finish = EthiopianPlace.find(to)
    return unless city_commute? && start && finish && start.city == city && finish.city == city && start.key != finish.key

    city_name = city_place&.name
    self.start_address = "#{start.name}, #{city_name}"
    self.end_address = "#{finish.name}, #{city_name}"
    self.route = RouteBuilder.call(from: [start.lat, start.lng], to: [finish.lat, finish.lng])
  end

  # A trip that stays inside one city, between neighbourhoods.
  def city_commute?
    city.present?
  end

  def city_place
    EthiopianPlace.find(city) if city.present?
  end

  # A weekly commute repeats on these weekdays (0 = Sunday ... 6 = Saturday).
  def commute?
    commute_days.present?
  end

  def commute_days=(value)
    super(Array(value).compact_blank.map(&:to_i).uniq.sort)
  end

  # The calendar day of the first (or only) ride.
  def first_ride_date
    leave_date&.in_time_zone(RIDE_ZONE)&.to_date
  end

  # Departure time of day, in Ethiopian time.
  def departure_time
    leave_date&.in_time_zone(RIDE_ZONE)
  end

  # Days a commuter can book: the schedule's weekdays within the booking horizon.
  def occurrence_dates(from: self.class.today, horizon: PlatformSetting.current.commute_horizon_days)
    return [] if cancelled?
    return [first_ride_date].select { |date| date >= from } unless commute?

    start = [from, first_ride_date].compact.max
    last = [from + horizon, commute_until].compact.min
    (start..last).select { |date| commute_days.include?(date.wday) }
  end

  # The day used when a seat count is shown without a specific day.
  def default_ride_date
    occurrence_dates.first || first_ride_date
  end

  # A one-off trip is past once it has left; a commute once its end date has gone.
  def past?
    return commute_until.present? && commute_until < self.class.today if commute?

    leave_date.present? && leave_date < Time.current
  end

  # Seats promised to confirmed passengers on one day.
  def seats_taken(date = default_ride_date)
    bookings.confirmed.where('? = ANY(bookings.ride_dates)', date).sum(:seats)
  end

  # nil means the driver did not set a capacity, so there is no limit.
  def seats_available(date = default_ride_date)
    return if num_people.blank?

    [num_people - seats_taken(date), 0].max
  end

  # With a day: that day is full. Without: a one-off trip is full, or every bookable day of a commute is.
  def full?(date = nil)
    return seats_available(date) == 0 if date
    return occurrence_dates.all? { |day| seats_available(day) == 0 } if commute?

    seats_available == 0
  end

  # "Mon, Tue, Wed at 07:30" for commutes.
  def schedule_summary
    return unless commute?

    days = commute_days.map { |wday| I18n.t('date.abbr_day_names')[wday] }.join(', ')
    "#{days} · #{I18n.l(departure_time, format: :time_only)}"
  end

  # What one seat costs the passenger: the driver's price plus the platform fee when passengers pay it.
  def passenger_price_per_seat
    PriceBreakdown.for(price_per_seat:, seats: 1).passenger_total
  end

  def price_breakdown(seats = 1, rides = 1)
    PriceBreakdown.for(price_per_seat:, seats:, rides:)
  end

  def bookable_by?(user)
    user.present? && user != self.user && !cancelled? && !past? && !full? && (!pink? || user.female?)
  end

  # Cancelling an itinerary also cancels every live booking on it.
  def cancel!
    transaction do
      update!(cancelled_at: Time.current)
      bookings.active.find_each(&:cancel_with_itinerary!)
    end
    self
  end

  def to_s
    title || id
  end
end
