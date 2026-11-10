# frozen_string_literal: true

# One SMS code sent to prove someone holds a phone number. Only AfroMessage knows the code; this row keeps
# who it was sent to, how many guesses were made and whether it has been used.
class PhoneVerification < ApplicationRecord
  MAX_ATTEMPTS = 5
  PER_PHONE = 3      # codes per number...
  PHONE_WINDOW = 10.minutes
  PER_IP = 10        # ...and per address
  IP_WINDOW = 1.hour

  class TooMany < StandardError; end

  scope :usable, -> { where(consumed_at: nil).where('expires_at > ?', Time.current) }

  # Sends a code, unless this number or address has asked for too many.
  def self.start!(phone:, ip:)
    raise TooMany if where(phone:).where('created_at > ?', PHONE_WINDOW.ago).count >= PER_PHONE
    raise TooMany if ip.present? && where(ip:).where('created_at > ?', IP_WINDOW.ago).count >= PER_IP

    verification_id = AfroMessageClient.new.challenge(phone)
    create!(phone:, ip:, verification_id:, expires_at: AfroMessageClient::TTL_SECONDS.seconds.from_now)
  end

  # Checks a code once and uses the verification up when it is right. Wrong guesses are counted and capped.
  def self.confirm(phone:, verification_id:, code:)
    record = usable.find_by(phone:, verification_id: verification_id.to_s)
    return false if record.nil? || record.attempts >= MAX_ATTEMPTS

    record.increment!(:attempts)
    return false unless AfroMessageClient.new.verify(phone:, verification_id: record.verification_id, code: code.to_s.strip)

    record.update!(consumed_at: Time.current)
    true
  end
end
