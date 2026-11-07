# frozen_string_literal: true

class Itinerary < ApplicationRecord
  include GeoItinerary
  extend FriendlyId

  DAYNAME = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  MAX_DESCRIPTION_LENGTH = 1000

  friendly_id :name, use: :slugged

  def name
    [start_address, end_address].join ' '
  end

  has_many :conversations, as: :conversable, dependent: :destroy
  has_many :bookings, dependent: :destroy

  scope :not_cancelled, -> { where(cancelled_at: nil) }
  scope :upcoming, -> { where(leave_date: Time.current..) }

  belongs_to :user
  delegate :name, to: :user, prefix: true
  delegate :first_name, to: :user, prefix: true

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

  # A trip is in the past once its (first) departure has gone. Daily trips have no single departure.
  def past?
    !daily? && leave_date.present? && leave_date < Time.current
  end

  # Seats already promised to confirmed passengers.
  def seats_taken
    bookings.confirmed.sum(:seats)
  end

  # nil means the driver did not set a capacity, so there is no limit.
  def seats_available
    return if num_people.blank?

    [num_people - seats_taken, 0].max
  end

  def full?
    seats_available == 0
  end

  # What one seat costs the passenger: the driver's price plus the platform fee when passengers pay it.
  def passenger_price_per_seat
    PriceBreakdown.for(price_per_seat:, seats: 1).passenger_total
  end

  def price_breakdown(seats = 1)
    PriceBreakdown.for(price_per_seat:, seats:)
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
