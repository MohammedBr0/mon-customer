# frozen_string_literal: true

require 'net/http'

# Sends and checks SMS security codes through AfroMessage (https://www.afromessage.com/developers).
# AfroMessage generates the code and checks it; the code itself is never stored or logged here.
class AfroMessageClient
  class Error < StandardError; end

  BASE = 'https://api.afromessage.com/api'
  CODE_LENGTH = 6
  TTL_SECONDS = 600

  def self.token
    APP_CONFIG.afromessage.token.presence
  end

  def self.enabled?
    token.present?
  end

  # Texts a code to the number and returns AfroMessage's verification id.
  def challenge(phone)
    params = {
      to: phone, len: CODE_LENGTH, t: 0, ttl: TTL_SECONDS, sb: 1,
      pr: I18n.t('api.otp_sms', app: APP_CONFIG.app_name),
      from: APP_CONFIG.afromessage.identifier.presence, sender: APP_CONFIG.afromessage.sender.presence
    }.compact
    response = get('/challenge', params)
    response['verificationId'].presence || raise(Error, 'no_verification_id')
  end

  # Sends a plain text message. Returns true when AfroMessage accepted it.
  def send_sms(phone, message)
    get('/send', { to: phone, message:, from: APP_CONFIG.afromessage.identifier.presence, sender: APP_CONFIG.afromessage.sender.presence }.compact)
    true
  rescue Error
    false
  end

  # True when the code is the one sent for this verification.
  def verify(phone:, verification_id:, code:)
    get('/verify', { to: phone, vc: verification_id, code: })
    true
  rescue Error => e
    raise if e.message.start_with?('network', 'http_5')

    false
  end

  private

  def get(path, params)
    raise Error, 'not_configured' unless self.class.enabled?

    uri = URI("#{BASE}#{path}")
    uri.query = URI.encode_www_form(params)
    request = Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{self.class.token}", 'Content-Type' => 'application/json')
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 15) { |http| http.request(request) }
    raise Error, "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    raise Error, 'rejected' unless body['acknowledge'] == 'success'

    body['response'].is_a?(Hash) ? body['response'] : {}
  rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError
    raise Error, 'network'
  rescue JSON::ParserError
    raise Error, 'http_502'
  end
end
