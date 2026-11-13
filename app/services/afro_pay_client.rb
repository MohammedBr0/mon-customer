# frozen_string_literal: true

require 'net/http'

# Asks Afro Pay to send a payment prompt (USSD pop-up) to someone's phone.
# Docs: https://api-doc.dev.afropays.co/api-reference/getting-started
class AfroPayClient
  class Error < StandardError; end

  # What we call each provider, and the path of its "direct" endpoint.
  PROVIDERS = {
    'telebirr'   => 'TelebirrUssd',
    'cbe_birr'   => 'CBEBirrUssd',
    'mpesa'      => 'MpesaUssd',
    'awash_birr' => 'AwashBirr'
  }.freeze

  def self.key
    APP_CONFIG.afropay.api_key.presence
  end

  def self.enabled?
    key.present?
  end

  # Returns { reference:, payment_url: }.
  def initiate(provider:, amount:, phone:, order_id:, callback_url:, description:)
    raise Error, 'not_configured' unless self.class.enabled?

    path = PROVIDERS.fetch(provider) { raise Error, 'unknown_provider' }
    body = {
      description:, amount: amount.to_f, currency: 'ETB', phone:, MerchantOrderId: order_id, callbackUrl: callback_url,
      order: { items: [{ itemName: description, price: amount.to_f, quantity: 1 }] }
    }
    uri = URI("#{APP_CONFIG.afropay.base_url}/api/v1/#{path}/direct/transaction-initiate")
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'X-Api-Key' => self.class.key)
    request.body = body.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 25) { |http| http.request(request) }
    parsed = JSON.parse(response.body.to_s)
    raise Error, parsed['message'].presence || "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess) && parsed['isSuccess']

    { reference: parsed.dig('data', 'refrence'), payment_url: parsed.dig('data', 'paymentUrl') }
  rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError
    raise Error, 'network'
  rescue JSON::ParserError
    raise Error, 'bad_response'
  end
end
