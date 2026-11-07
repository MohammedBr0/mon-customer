# frozen_string_literal: true

# After a trip, driver and passenger can each rate the other once.
class Review < ApplicationRecord
  MAX_COMMENT_LENGTH = 1000

  belongs_to :booking
  belongs_to :reviewer, class_name: 'User'
  belongs_to :reviewee, class_name: 'User'

  validates :rating, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
  validates :comment, length: { maximum: MAX_COMMENT_LENGTH }
  validates :reviewer_id, uniqueness: { scope: :booking_id }
  validate :trip_is_completed
  validate :reviewer_and_reviewee_are_the_two_participants

  scope :recent, -> { order(created_at: :desc) }

  private

  def trip_is_completed
    errors.add(:base, :trip_not_completed) unless booking&.completed?
  end

  def reviewer_and_reviewee_are_the_two_participants
    return unless booking && reviewer && reviewee

    participants = [booking.passenger_id, booking.driver.id]
    valid = participants.include?(reviewer.id) && participants.include?(reviewee.id) && reviewer != reviewee
    errors.add(:base, :not_a_participant) unless valid
  end
end
