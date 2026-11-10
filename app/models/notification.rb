# frozen_string_literal: true

# Something a person should know about (a seat request, a message, a matching trip). Stores only the kind and
# the ids and names involved; the wording is built when it is read, so it follows the reader's language.
class Notification < ApplicationRecord
  KINDS = %w[booking_requested booking_confirmed booking_declined booking_cancelled date_skipped itinerary_cancelled
             new_message review_received alert_match identity_approved identity_rejected].freeze

  belongs_to :user

  validates :kind, inclusion: { in: KINDS }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(id: :desc) }

  # Records a notification without ever breaking the action that caused it.
  def self.notify(user, kind, **data)
    return if user.blank?

    create!(user:, kind:, data: data.compact.stringify_keys)
  rescue StandardError => e
    Rails.logger.warn("Notification #{kind} failed: #{e.message}")
    nil
  end

  def read?
    read_at.present?
  end

  def title
    I18n.t("notifications.#{kind}.title")
  end

  def body
    values = data.symbolize_keys.transform_values(&:to_s)
    values[:document] = I18n.t("identity.kinds.#{values[:document]}", default: values[:document]) if values[:document]
    I18n.t("notifications.#{kind}.body", **values, default: '')
  end
end
