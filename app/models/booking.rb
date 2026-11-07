# frozen_string_literal: true

# A passenger's request for seats on an itinerary. The driver confirms or declines it,
# and either side can cancel it. Only confirmed bookings take seats.
class Booking < ApplicationRecord
  STATUSES = %w[pending confirmed declined cancelled].freeze
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

  validates :status, inclusion: { in: STATUSES }
  validates :seats, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_SEATS }
  validates :note, length: { maximum: MAX_NOTE_LENGTH }
  validate :passenger_is_not_the_driver, on: :create
  validate :itinerary_accepts_bookings, on: :create
  validate :no_other_active_booking, on: :create
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
      raise_unless itinerary.seats_available.nil? || seats <= itinerary.seats_available, :not_enough_seats

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

  def completed?
    confirmed? && itinerary.past?
  end

  def reviewed_by?(user)
    reviews.exists?(reviewer: user)
  end

  class InvalidTransition < StandardError; end

  private

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
    return unless itinerary && seats.to_i.positive?

    available = itinerary.seats_available
    errors.add(:seats, :not_enough_seats, count: available) if available && seats > available
  end
end
