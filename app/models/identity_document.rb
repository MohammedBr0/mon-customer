# frozen_string_literal: true

# A photo of a driving licence or national ID that someone sent in to be verified. The picture is kept in the
# database and shown only to staff. A person is verified once both of their documents are approved.
class IdentityDocument < ApplicationRecord
  KINDS = %w[driver_license national_id].freeze
  STATUSES = %w[pending approved rejected].freeze
  IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_BYTES = 5.megabytes

  belongs_to :user
  belongs_to :reviewed_by, class_name: 'User', optional: true

  validates :kind, inclusion: { in: KINDS }, uniqueness: { scope: :user_id }
  validates :status, inclusion: { in: STATUSES }
  validates :number, presence: true, length: { maximum: 40 }
  validates :content_type, inclusion: { in: IMAGE_TYPES, message: :not_an_image }
  validates :image, presence: true
  validate :image_is_small_enough
  validates :rejection_reason, length: { maximum: 200 }

  scope :pending, -> { where(status: 'pending') }
  # Lists never need the picture itself.
  scope :without_image, -> { select(column_names - ['image']) }

  STATUSES.each { |name| define_method(:"#{name}?") { status == name } }

  # Sends in (or replaces) one document. A new picture always goes back to "pending".
  def self.submit!(user:, kind:, number:, upload:)
    document = find_or_initialize_by(user:, kind:)
    document.assign_attributes(number: number.to_s.strip, image: upload.read, content_type: upload.content_type.to_s,
                               status: 'pending', rejection_reason: nil, reviewed_by: nil, reviewed_at: nil)
    document.save!
    sync_verification(user)
    document
  end

  def approve!(by:)
    update!(status: 'approved', rejection_reason: nil, reviewed_by: by, reviewed_at: Time.current)
    self.class.sync_verification(user, by:)
    Notification.notify(user, 'identity_approved', document: kind)
  end

  def reject!(by:, reason:)
    update!(status: 'rejected', rejection_reason: reason.to_s.strip.presence, reviewed_by: by, reviewed_at: Time.current)
    self.class.sync_verification(user, by:)
    Notification.notify(user, 'identity_rejected', document: kind, reason: rejection_reason)
  end

  # The verified badge follows the documents: on when both are approved, off as soon as one is not.
  def self.sync_verification(user, by: nil)
    approved = where(user:, status: 'approved').pluck(:kind)
    complete = (KINDS - approved).empty?
    if complete && !user.verified?
      user.update_columns(verified_at: Time.current, verified_by_id: by&.id)
    elsif !complete && user.verified? && exists?(user:)
      user.update_columns(verified_at: nil, verified_by_id: nil)
    end
  end

  private

  def image_is_small_enough
    errors.add(:image, :too_large) if image.present? && image.bytesize > MAX_BYTES
  end
end
