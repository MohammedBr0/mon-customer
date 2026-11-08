# frozen_string_literal: true

require 'net/http'
require 'json'

# Server-side email and password sign-in against Neon Auth, for the mobile app. The app sends the
# credentials to this API over HTTPS; they are forwarded to Neon Auth and never stored here.
class NeonAuthClient
  class Error < StandardError
    attr_reader :status

    def initialize(message, status)
      super(message)
      @status = status
    end
  end

  User = Struct.new(:id, :email, :name, :image, keyword_init: true)

  # The origin Neon Auth has been told to trust (the site's public address).
  def self.origin
    host = APP_CONFIG.base_url.to_s
    return host if host.start_with?('http')

    "#{host.start_with?('localhost') ? 'http' : 'https'}://#{host}"
  end

  def sign_in(email:, password:)
    user_from post('/sign-in/email', { email:, password: })
  end

  # Creates the account, then signs in so the caller gets a verified user record.
  def sign_up(name:, email:, password:)
    post('/sign-up/email', { name:, email:, password: })
    sign_in(email:, password:)
  end

  private

  def post(path, body)
    uri = URI("#{APP_CONFIG.neon_auth.issuer}#{path}")
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'Origin' => self.class.origin)
    request.body = body.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 15) { |http| http.request(request) }
    parsed = begin
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end
    raise Error.new(parsed['message'].presence || 'Sign-in failed', response.code.to_i) unless response.is_a?(Net::HTTPSuccess)

    parsed
  rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError
    raise Error.new('Sign-in service is unavailable', 503)
  end

  def user_from(payload)
    data = payload['user']
    raise Error.new('Sign-in failed', 502) if data.blank? || data['id'].blank?

    User.new(id: data['id'], email: data['email'], name: data['name'], image: data['image'])
  end
end
