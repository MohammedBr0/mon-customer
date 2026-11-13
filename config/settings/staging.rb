# frozen_string_literal: true

# DO NOT SET SENSITIVE DATA HERE!
# USE ENVIRONMENT VARIABLES OR 'local.rb' INSTEAD

SimpleConfig.for :application do
  set :base_url, ENV['APP_BASE_URL']
  set :single_process_mode, false

  set :google_analytics_id, ENV['GOOGLE_ANALYTICS_ID']
  set :google_maps_api_key, ENV['GOOGLE_MAPS_API_KEY']
  # Optional second key for server calls; use it when the browser key is limited to website referrers.
  set :google_maps_server_key, ENV['GOOGLE_MAPS_SERVER_KEY']
  set :google_static_maps, ENV['GOOGLE_STATIC_MAPS'] == 'true'

  group :afropay do
    set :api_key, ENV['AFROPAY_API_KEY']
    set :base_url, ENV['AFROPAY_BASE_URL'].presence || 'https://paybridge.sandbox.afropays.co'
  end

  group :afromessage do
    set :token, ENV['AFROMESSAGE_TOKEN']
    set :identifier, ENV['AFROMESSAGE_IDENTIFIER']
    set :sender, ENV['AFROMESSAGE_SENDER']
  end

  group :neon_auth do
    set :issuer, ENV['NEON_AUTH_URL']
    set :client_id, ENV['NEON_AUTH_CLIENT_ID']
    set :client_secret, ENV['NEON_AUTH_CLIENT_SECRET']
  end

  group :airbrake do
    set :project_id, ENV['AIRBRAKE_PROJECT_ID']
    set :project_key, ENV['AIRBRAKE_PROJECT_KEY']
    set :host, ENV['AIRBRAKE_HOST']
  end

  group :mailer do
    set :from, ENV.fetch('MAILER_FROM', '"Icare" <no-reply@i.care>')
    set :host, ENV.fetch('APP_BASE_URL', 'localhost').sub(%r{\Ahttps?://}, '').chomp('/')

    group :smtp_settings do
      set :address, ENV['SMTP_ADDRESS']
      set :port, ENV.fetch('SMTP_PORT', 587).to_i
      set :authentication, :plain
      set :domain, ENV.fetch('SMTP_DOMAIN') { ENV.fetch('APP_BASE_URL', 'localhost').sub(%r{\Ahttps?://}, '').chomp('/') }

      set :user_name, ENV['SMTP_USERNAME']
      set :password, ENV['SMTP_PASSWORD']
    end
  end

  group :redis do
    set :url, ENV['REDIS_URL']
  end
end
