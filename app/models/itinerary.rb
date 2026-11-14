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
    self.route = RouteBuilder.road(from: [start.lat, start.lng], to: [finish.lat, finish.lng])
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

  LIVE_STALE_AFTER = 2.minutes
  EDIT_LOCK = 30.minutes        # trips can be changed until this long before they leave
  START_OPENS = 30.minutes      # and started from this long before they leave
  START_CLOSES = 6.hours        # until this long after
  ARRIVAL_RADIUS_METERS = 400   # this close to the destination counts as arrived
  ARRIVED_AUTO_FINISH = 30.minutes

  # When the ride leaves on [date] (Ethiopian time).
  def ride_at(date)
    clock = departure_time
    return unless date && clock

    RIDE_ZONE.local(date.year, date.month, date.day, clock.hour, clock.min)
  end

  # The ride the driver is about to do, is doing, or did today: its day, or nil.
  # A one-off trip has one day; a commute has today if today is one of its days.
  def current_ride_date(now = Time.current)
    return live_ride_date if live? && live_ride_date
    return if cancelled?

    day = now.in_time_zone(RIDE_ZONE).to_date
    candidates = commute? ? occurrence_dates(from: day, horizon: 0) : [first_ride_date]
    candidates.find { |date| date && now >= ride_at(date) - START_OPENS && now <= ride_at(date) + START_CLOSES }
  end

  # When the next ride leaves (now or later), for the edit lock and the start button.
  def next_departure_at(now = Time.current)
    return if cancelled?
    return leave_date unless commute?

    occurrence_dates(from: now.in_time_zone(RIDE_ZONE).to_date).map { |date| ride_at(date) }.find { |at| at > now }
  end

  # Changes are allowed until 30 minutes before the next ride, and never while one is under way.
  def editable?(now = Time.current)
    departure = next_departure_at(now)
    !cancelled? && !live? && departure.present? && departure - EDIT_LOCK > now
  end

  # Confirmed passengers riding on [date].
  def riders(date)
    bookings.confirmed.includes(:passenger, :boardings).select { |booking| booking.rides_on?(date) }
  end

  # Why the driver can't start yet, or nil when they can.
  #   :too_early       more than 30 minutes before departure (opens_at says when)
  #   :not_today       no ride today, or today's ride is long past
  #   :waiting         some passengers are neither picked up nor marked as no-shows
  def start_blocker(now = Time.current)
    return :cancelled if cancelled?

    date = current_ride_date(now)
    return :finished if date && ride_finished?(date)
    unless date
      departure = next_departure_at(now)
      return departure && departure - START_OPENS > now ? :too_early : :not_today
    end
    return :waiting if riders(date).any? { |booking| !booking.boarding_for(date)&.resolved? }

    nil
  end

  # Whether the ride on [date] has already been driven and finished.
  def ride_finished?(date)
    live_ended_at.present? && live_started_at.present? && (live_ride_date.nil? ? !commute? : live_ride_date == date)
  end

  TRIP_STATUSES = %w[scheduled boarding in_progress arrived completed cancelled].freeze

  # Where the trip is at, for badges on lists and the trip page:
  #   scheduled    waiting for its next ride
  #   boarding     the start window is open (30 minutes before): passengers are getting in
  #   in_progress  the driver started it and the car is on its way
  #   arrived      the car reached the destination; waiting for drop-off confirmations
  #   completed    a one-off trip that was driven or has gone; a commute whose last day has gone
  #   cancelled
  def trip_status(now = Time.current)
    return 'cancelled' if cancelled?
    return(arrived_at ? 'arrived' : 'in_progress') if live?
    return 'completed' if !commute? && ride_finished?(first_ride_date)

    date = current_ride_date(now)
    return 'boarding' if date && !ride_finished?(date)

    past? ? 'completed' : 'scheduled'
  end

  def start_opens_at(now = Time.current)
    next_departure_at(now)&.then { |at| at - START_OPENS }
  end

  # How far the car is from the destination, in metres.
  def meters_to_destination(lat, lng)
    return unless end_location

    rad = Math::PI / 180
    dlat = (end_location.lat - lat) * rad
    dlng = (end_location.lon - lng) * rad
    a = (Math.sin(dlat / 2)**2) + (Math.cos(lat * rad) * Math.cos(end_location.lat * rad) * (Math.sin(dlng / 2)**2))
    2 * 6_371_000 * Math.asin(Math.sqrt(a))
  end

  def arrived?
    live? && arrived_at.present?
  end

  # Ends a ride that has arrived once every passenger confirmed being dropped off, or half an hour after arriving.
  def close_if_done!(now = Time.current)
    return unless arrived?

    on_board = riders(live_ride_date).map { |booking| booking.boarding_for(live_ride_date) }.select { |boarding| boarding&.boarded_at }
    finish_live! if (on_board.any? && on_board.all?(&:dropped_off_at)) || arrived_at <= now - ARRIVED_AUTO_FINISH
  end

  # A ride is "live" from the moment the driver starts it until they finish it.
  def live?
    live_started_at.present? && live_ended_at.nil?
  end

  # The driver sets off: confirmed passengers are told and can follow the car.
  def start_live!(now = Time.current)
    date = current_ride_date(now)
    update!(live_started_at: now, live_ended_at: nil, live_ride_date: date, arrived_at: nil, live_lat: nil, live_lng: nil, live_heading: nil, live_updated_at: nil)
    riders(date).each do |booking|
      next if booking.boarding_for(date)&.no_show_at

      Notification.notify(booking.passenger, 'trip_started', itinerary_id: id, booking_id: booking.id, trip: title, person: user.to_s)
    end
    self
  end

  # The car's latest position. The first time it comes within reach of the destination, passengers are asked
  # to confirm they were dropped off, and the driver is told they can finish.
  def update_live_position!(lat:, lng:, heading: nil)
    update_columns(live_lat: lat, live_lng: lng, live_heading: heading, live_updated_at: Time.current)
    distance = meters_to_destination(lat, lng)
    return unless arrived_at.nil? && distance && distance <= ARRIVAL_RADIUS_METERS

    update_columns(arrived_at: Time.current)
    riders(live_ride_date).each do |booking|
      next unless booking.boarding_for(live_ride_date)&.boarded_at

      Notification.notify(booking.passenger, 'dropoff_confirm', itinerary_id: id, booking_id: booking.id, trip: title)
    end
    Notification.notify(user, 'arrived', itinerary_id: id, trip: title)
  end

  def finish_live!
    update!(live_ended_at: Time.current)
    # Anyone still on board when the ride ends was dropped off.
    riders(live_ride_date).each do |booking|
      boarding = booking.boarding_for(live_ride_date)
      boarding.update!(dropped_off_at: Time.current) if boarding&.boarded_at && boarding.dropped_off_at.nil?
    end
  end

  # Who may follow the car: the driver and passengers with a confirmed seat.
  def trackable_by?(person)
    person.present? && (person.id == user_id || bookings.confirmed.exists?(passenger_id: person.id))
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
