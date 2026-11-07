# frozen_string_literal: true

require 'net/http'
require 'json'

namespace :neon_auth do
  desc 'Create a test user in Neon Auth from SEED_USER_EMAIL / SEED_USER_PASSWORD (no-op if unset)'
  task seed_test_user: :environment do
    email    = ENV.fetch('SEED_USER_EMAIL', '').strip
    password = ENV.fetch('SEED_USER_PASSWORD', '')

    if email.empty? || password.empty?
      puts 'neon_auth:seed_test_user skipped (SEED_USER_EMAIL / SEED_USER_PASSWORD not set)'
      next
    end

    origin = ENV.fetch('APP_BASE_URL', '')
    origin = "https://#{origin}" unless origin.start_with?('http')

    uri = URI("#{APP_CONFIG.neon_auth.issuer}/sign-up/email")
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'Origin' => origin)
    request.body = { name: ENV.fetch('SEED_USER_NAME', 'Test User'), email: email, password: password }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 20) { |http| http.request(request) }

    case response.code.to_i
    when 200..299
      puts "neon_auth:seed_test_user created #{email}"
    when 400..422
      # Most likely the user already exists; a failed seed must never block boot.
      puts "neon_auth:seed_test_user did not create #{email} (HTTP #{response.code}: #{response.body.to_s[0, 200]})"
    else
      warn "neon_auth:seed_test_user failed (HTTP #{response.code})"
    end
  rescue StandardError => e
    warn "neon_auth:seed_test_user error: #{e.class}: #{e.message}"
  end
end
