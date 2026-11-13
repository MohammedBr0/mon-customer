# frozen_string_literal: true

# Something a person should know about (a seat request, a message, a matching trip). Stores only the kind and
# the ids and names involved; the wording is built when it is read, so it follows the reader's language.
class Notification < ApplicationRecord
  KINDS = %w[booking_requested booking_confirmed booking_declined booking_cancelled date_skipped itinerary_cancelled
             new_message review_received alert_match identity_approved identity_rejected trip_started
             wallet_topup payment_received payment_refunded withdrawal_paid withdrawal_rejected announcement].freeze
  AUDIENCES = %w[everyone drivers passengers].freeze

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

  # Puts one message from the admins in many people's notifications at once. Returns how many received it.
  def self.announce!(title:, body:, audience: 'everyone')
    users = User.where(banned: false)
    users = users.where(app_mode: 'driver') if audience == 'drivers'
    users = users.where(app_mode: 'passenger') if audience == 'passengers'
    now = Time.current
    data = { 'title' => title.to_s.strip, 'body' => body.to_s.strip }
    users.in_batches(of: 1000).sum do |batch|
      rows = batch.pluck(:id).map { |id| { user_id: id, kind: 'announcement', data:, created_at: now, updated_at: now } }
      rows.empty? ? 0 : insert_all(rows).length # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def title
    return data['title'].to_s if kind == 'announcement'

    I18n.t("notifications.#{kind}.title")
  end

  def body
    return data['body'].to_s if kind == 'announcement'

    values = data.symbolize_keys.transform_values(&:to_s)
    values[:document] = I18n.t("identity.kinds.#{values[:document]}", default: values[:document]) if values[:document]
    I18n.t("notifications.#{kind}.body", **values, default: '')
  end
end
