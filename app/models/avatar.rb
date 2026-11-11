# frozen_string_literal: true

# A person's profile photo, uploaded from the app. Everyone who can see the person can see it, like on any
# ride app, so it is served at a plain public address.
class Avatar < ApplicationRecord
  TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_BYTES = 2.megabytes

  belongs_to :user

  validates :content_type, inclusion: { in: TYPES, message: :not_an_image }
  validates :image, presence: true
  validate { errors.add(:image, :too_large) if image.present? && image.bytesize > MAX_BYTES }

  # Saves the photo and points the person's picture at it. The version in the address makes phones fetch the new one.
  def self.upload!(user:, upload:)
    avatar = find_or_initialize_by(user:)
    avatar.update!(image: upload.read, content_type: upload.content_type.to_s)
    user.update_columns(image: Rails.application.routes.url_helpers.avatar_path(user.id, v: avatar.updated_at.to_i))
    avatar
  end

  def self.remove!(user)
    where(user:).delete_all
    user.update_columns(image: nil) if user.image.to_s.start_with?('/avatars/')
  end
end
