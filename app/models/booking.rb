# frozen_string_literal: true

# A passenger's request for seats on an itinerary. The driver confirms or declines it,
# and either side can cancel it. Only confirmed bookings take seats.
class Booking < ApplicationRecord
  STATUSES = %w[pending confirmed declined cancelled].freeze
  PAYMENT_METHODS = %w[cash wallet].freeze
  PAYMENT_STATES = %w[none held released refunded].freeze
  ACTIVE_STATUSES = %w[pending confirmed].freeze
  MAX_SEATS = 8
  MAX_NOTE_LENGTH = 500

  belongs_to :itinerary
  belongs_to :passenger, class_name: 'User'
  belongs_to :cancelled_by, class_name: 'User', optional: true

  has_many :reviews, dependent: :destroy

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :pending, -> { where(status: 'pending') }
  scope :confirmed, -> { where(status: 'confirmed') }

  # Wallet-paid seats: the money is set aside in the same transaction that creates the request.
  after_create { BookingPayment.new(self).hold! }
  after_update :settle_cancelled_payment, if: :saved_change_to_status?
  after_create_commit :notify_driver_of_request
  after_update_commit :notify_of_status_change, if: :saved_change_to_status?

  before_validation :default_ride_dates, on: :create
  before_validation :snapshot_pricing, on: :create

  validates :status, inclusion: { in: STATUSES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validate :wallet_covers_the_seat, on: :create
  validates :seats, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SEATS }
  validates :note, length: { maximum: MAX_NOTE_LENGTH }
  validates :pickup_label, length: { maximum: 200 }
  validates :pickup_lat, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :pickup_lng, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validate :passenger_is_not_the_driver, on: :create
  validate :itinerary_accepts_bookings, on: :create
  validate :no_other_active_booking, on: :create
  validate :ride_dates_are_bookable, on: :create
  validate :seats_are_available, on: :create

  STATUSES.each do |status|
    define_method(:"#{status}?") { self.status == status }
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def driver
    itinerary.user
  end

  def participant?(user)
    user.present? && [passenger_id, driver.id].include?(user.id)
  end

  def counterpart_of(user)
    user == passenger ? driver : passenger
  end

  # The driver accepts the request. Locks the itinerary so two concurrent confirmations
  # cannot oversell the last seats.
  def confirm!
    itinerary.with_lock do
      raise_unless pending?, :not_pending
      raise_unless seats_fit?, :not_enough_seats

      update!(status: 'confirmed', decided_at: Time.current)
    end
    self
  end

  def decline!
    raise_unless pending?, :not_pending
    update!(status: 'declined', decided_at: Time.current)
    self
  end

  # Either the passenger or the driver can cancel a live booking.
  def cancel!(by:)
    raise_unless active?, :not_active
    update!(status: 'cancelled', cancelled_at: Time.current, cancelled_by: by)
    self
  end

  # Called when the whole itinerary is cancelled by its driver.
  def cancel_with_itinerary!
    return self unless active?

    update!(status: 'cancelled', cancelled_at: Time.current, cancelled_by: driver)
    self
  end

  # A confirmed booking is complete once its trip has run: for a commute, once its first day has gone.
  def completed?
    return false unless confirmed?

    itinerary.commute? ? ride_dates.min.present? && ride_dates.min < Itinerary.today : itinerary.past?
  end

  def wallet_paid?
    payment_method == 'wallet'
  end

  # When the first booked ride leaves, and when the last one is over (the trip's clock time on those days).
  def first_ride_at
    ride_at(ride_dates.min)
  end

  def ride_finished_at
    return itinerary.live_ended_at if itinerary.live_ended_at.present? && !multi_day? && itinerary.live_ended_at >= (first_ride_at || itinerary.live_ended_at)

    last = ride_at(ride_dates.max)
    last && (last + 3.hours) # no "finished" signal: assume a ride is over three hours after it leaves
  end

  # The passenger says the ride went well, which pays the driver straight away.
  def confirm_completed!
    raise_unless confirmed? && wallet_paid? && payment_state == 'held' && first_ride_at && first_ride_at <= Time.current, :not_active
    update!(passenger_confirmed_at: Time.current)
    BookingPayment.new(self).release!
    self
  end

  def pickup?
    pickup_lat.present? && pickup_lng.present?
  end

  def multi_day?
    ride_dates.size > 1
  end

  # Drops one day from a commute booking and reprices it. Cancels the booking when no days remain.
  def skip_date!(date, by:)
    raise_unless active? && ride_dates.include?(date) && date >= Itinerary.today, :not_active
    remaining = ride_dates - [date]
    return cancel!(by:) if remaining.empty?

    self.ride_dates = remaining
    snapshot_pricing(keep_fee_terms: true)
    save!
    BookingPayment.new(self).adjust_hold!
    Notification.notify(counterpart_of(by), 'date_skipped', booking_id: id, itinerary_id: itinerary_id, trip: itinerary.title, person: by.to_s, date: date.iso8601)
    self
  end

  def upcoming_ride_dates
    ride_dates.select { |date| date >= Itinerary.today }
  end

  def reviewed_by?(user)
    reviews.exists?(reviewer: user)
  end

  class InvalidTransition < StandardError; end

  # What the passenger pays and what the driver gets, frozen when the booking is made so that
  # later price or fee changes never alter an existing booking.
  def price_breakdown
    PriceBreakdown.new(price_per_seat, seats, fee_percent, fee_charged_to, ride_dates.size)
  end

  private

  def ride_at(date)
    clock = itinerary.departure_time
    return unless date && clock

    Itinerary::RIDE_ZONE.local(date.year, date.month, date.day, clock.hour, clock.min)
  end

  def wallet_covers_the_seat
    return unless wallet_paid? && passenger && passenger_total

    errors.add(:base, :wallet_disabled) unless ChapaClient.enabled?
    errors.add(:base, :wallet_too_low, needed: passenger_total.to_f, balance: Wallet.for(passenger).available.to_f) if passenger_total > Wallet.for(passenger).available
  end

  # Declined, or cancelled by either side: the held money goes back (or is split, for a late passenger cancellation).
  def settle_cancelled_payment
    case status
    when 'declined' then BookingPayment.new(self).refund_all!
    when 'cancelled' then BookingPayment.new(self).cancel!(by: cancelled_by)
    end
  end

  def notify_driver_of_request
    Notification.notify(driver, 'booking_requested', booking_id: id, itinerary_id:, trip: itinerary.title, person: passenger.to_s, seats:)
  end

  def notify_of_status_change
    common = { booking_id: id, itinerary_id:, trip: itinerary.title }
    case status
    when 'confirmed' then Notification.notify(passenger, 'booking_confirmed', **common, person: driver.to_s)
    when 'declined' then Notification.notify(passenger, 'booking_declined', **common, person: driver.to_s)
    when 'cancelled'
      if cancelled_by == driver && itinerary.cancelled?
        Notification.notify(passenger, 'itinerary_cancelled', **common, person: driver.to_s)
      else
        recipient = cancelled_by == passenger ? driver : passenger
        Notification.notify(recipient, 'booking_cancelled', **common, person: (cancelled_by || passenger).to_s)
      end
    end
  end

  def default_ride_dates
    return unless itinerary

    dates = Array(ride_dates).compact_blank
    dates = [itinerary.first_ride_date] if dates.empty? && !itinerary.commute?
    self.ride_dates = dates.map { |date| date.respond_to?(:to_date) ? date.to_date : Date.parse(date.to_s) }.uniq.sort
  rescue ArgumentError
    self.ride_dates = []
  end

  # Fee terms are frozen when the booking is made; skipping a day reprices with those same terms.
  def snapshot_pricing(keep_fee_terms: false)
    return unless itinerary

    setting = PlatformSetting.current
    unless keep_fee_terms
      self.fee_percent = setting.fee_percent
      self.fee_charged_to = setting.fee_charged_to
    end
    self.price_per_seat = itinerary.price_per_seat unless keep_fee_terms
    breakdown = PriceBreakdown.new(price_per_seat, seats.to_i.clamp(1, MAX_SEATS), fee_percent, fee_charged_to, [ride_dates.size, 1].max)
    self.fare_total = breakdown.fare_total
    self.fee_amount = breakdown.fee_amount
    self.passenger_total = breakdown.passenger_total
    self.driver_payout = breakdown.driver_payout
  end

  def seats_fit?
    ride_dates.all? do |date|
      available = itinerary.seats_available(date)
      available.nil? || seats <= available
    end
  end

  def ride_dates_are_bookable
    return unless itinerary

    if ride_dates.empty?
      errors.add(:ride_dates, :blank)
    elsif (ride_dates - itinerary.occurrence_dates).any?
      errors.add(:ride_dates, :not_available)
    end
  end

  def raise_unless(condition, reason)
    raise InvalidTransition, reason.to_s unless condition
  end

  def passenger_is_not_the_driver
    errors.add(:base, :own_itinerary) if itinerary && passenger_id == itinerary.user_id
  end

  def itinerary_accepts_bookings
    return unless itinerary

    errors.add(:base, :itinerary_cancelled) if itinerary.cancelled?
    errors.add(:base, :itinerary_in_the_past) if itinerary.past?
  end

  def no_other_active_booking
    return unless itinerary && passenger

    errors.add(:base, :already_booked) if Booking.active.exists?(itinerary_id: itinerary.id, passenger_id: passenger.id)
  end

  def seats_are_available
    return unless itinerary && seats.to_i.positive? && ride_dates.any?

    available = ride_dates.filter_map { |date| itinerary.seats_available(date) }.min
    errors.add(:seats, :not_enough_seats, count: available) if available && seats > available
  end
end
