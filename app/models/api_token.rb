# frozen_string_literal: true

# Bearer token the mobile app keeps after signing in. Only a SHA-256 digest is stored, so a
# database leak does not expose usable tokens.
class ApiToken < ApplicationRecord
  LIFETIME = 180.days

  belongs_to :user

  scope :active, -> { where('expires_at > ?', Time.current) }

  validates :token_digest, presence: true, uniqueness: true

  # Creates a token and returns [record, raw_token]. The raw value is shown once and never stored.
  def self.issue_for(user, device_name: nil)
    raw = SecureRandom.urlsafe_base64(32)
    record = create!(user:, token_digest: digest(raw), device_name: device_name.to_s.first(80).presence, expires_at: LIFETIME.from_now)
    [record, raw]
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  def self.authenticate(raw)
    return if raw.blank?

    token = active.includes(:user).find_by(token_digest: digest(raw))
    token&.touch(:last_used_at) if token && (token.last_used_at.nil? || token.last_used_at < 5.minutes.ago)
    token
  end
end
