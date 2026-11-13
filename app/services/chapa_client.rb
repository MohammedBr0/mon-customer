# frozen_string_literal: true

require 'net/http'

# Chapa (https://developer.chapa.co): takes payments on a hosted checkout page, confirms them, and sends
# payouts to Ethiopian banks and mobile wallets. Uses Chapa's v1 API.
class ChapaClient
  class Error < StandardError; end

  def self.key
    APP_CONFIG.chapa.secret_key.presence
  end

  def self.enabled?
    key.present?
  end

  # Set in Chapa's dashboard under webhooks; when present, unsigned webhooks are refused.
  def self.webhook_secret
    APP_CONFIG.chapa.webhook_secret.presence
  end

  # Opens a payment and returns the address of Chapa's checkout page for it.
  def initialize_payment(tx_ref:, amount:, first_name:, last_name:, phone: nil, email: nil, callback_url:, return_url:, title:, description:)
    body = { amount: format('%.2f', amount), currency: 'ETB', tx_ref:, first_name:, last_name:, phone_number: phone, email:, callback_url:, return_url:,
             customization: { title:, description: } }.compact
    post('/v1/transaction/initialize', body).dig('data', 'checkout_url') || raise(Error, 'no_checkout_url')
  end

  # What Chapa itself says about a payment: { status: 'success' | 'pending' | 'failed', amount:, currency:, method:, reference: }.
  def verify_payment(tx_ref)
    data = get("/v1/transaction/verify/#{ERB::Util.url_encode(tx_ref)}")['data'] || {}
    { status: data['status'].to_s.downcase, amount: data['amount'].to_d, currency: data['currency'], method: data['method'], reference: data['reference'] }
  end

  # Banks and mobile wallets a payout can go to: [{ id:, name:, account_length:, mobile: }].
  def banks
    get('/v1/banks').fetch('data', []).select { |bank| bank['can_process_payouts'].to_i == 1 && bank['is_active'].to_i == 1 }.map do |bank|
      { id: bank['id'], name: bank['name'], account_length: bank['acct_length'], mobile: bank['is_mobilemoney'].to_i == 1 }
    end
  end

  # Sends money out of the merchant balance. Returns when Chapa has queued it; the result arrives later.
  def transfer(reference:, amount:, account_name:, account_number:, bank_code:)
    post('/v1/transfers', { account_name:, account_number:, amount: format('%.2f', amount), currency: 'ETB', reference:, bank_code: })
    true
  end

  # 'success', 'failed', or 'pending' when Chapa has not finished (or cannot say, as in test mode).
  def verify_transfer(reference)
    data = get("/v1/transfers/verify/#{ERB::Util.url_encode(reference)}")['data']
    data = data.first if data.is_a?(Array)
    status = data.is_a?(Hash) ? data['status'].to_s.downcase : ''
    %w[success failed].find { |known| status.start_with?(known) } || 'pending'
  rescue Error
    'pending'
  end

  # True when a webhook really came from Chapa: its signature is the HMAC-SHA256 of the exact body with our secret.
  def self.valid_signature?(raw_body, signature)
    secret = webhook_secret
    return false if secret.blank? || signature.blank?

    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body.to_s)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
  end

  private

  def post(path, body)
    request(Net::HTTP::Post, path) { |req| req.body = body.to_json }
  end

  def get(path)
    request(Net::HTTP::Get, path)
  end

  def request(verb, path)
    raise Error, 'not_configured' unless self.class.enabled?

    uri = URI("#{APP_CONFIG.chapa.base_url}#{path}")
    req = verb.new(uri, 'Authorization' => "Bearer #{self.class.key}", 'Content-Type' => 'application/json')
    yield req if block_given?
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 25) { |http| http.request(req) }
    parsed = JSON.parse(response.body.to_s)
    raise Error, message_from(parsed) || "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess) && parsed['status'].to_s == 'success'

    parsed
  rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError
    raise Error, 'network'
  rescue JSON::ParserError
    raise Error, 'bad_response'
  end

  # Chapa's "message" is a sentence, or a hash of field => [problems].
  def message_from(parsed)
    message = parsed['message']
    message.is_a?(Hash) ? message.values.flatten.join(', ') : message.presence
  end
end
