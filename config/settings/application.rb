# frozen_string_literal: true

# DO NOT SET SENSITIVE DATA HERE!
# USE ENVIRONMENT VARIABLES OR 'local.rb' INSTEAD

# OVERRIDE THESE DEFAULTS IN A PROPER ENVIRONMENT CONFIGURATION FILE
# SET SENSITIVE DATA ONLY IN 'local.rb'

SimpleConfig.for :application do
  set :app_name, 'Arifway'

  set :base_url, 'localhost:3000'
  set :single_process_mode, true

  # Ethiopian Birr. Amounts are shown as "150 Br"; PlatformSetting lets a super admin change the symbol.
  set :currency, ' Br'
  set :fuel_consumption, 8.0
  set :fuel_currency, 'Br'

  set :google_analytics_id, nil
  set :google_maps_api_key, nil
  set :google_maps_server_key, nil

  # SMS codes for phone registration (AfroMessage). Without a token, phone sign-up works without a code.
  group :afromessage do
    set :token, nil
    set :identifier, nil
    set :sender, nil
  end

  set :google_static_maps, false

  # Neon Auth (managed Better Auth) acting as an OpenID Connect provider
  group :neon_auth do
    set :issuer, 'NEON_AUTH_URL'
    set :client_id, 'NEON_AUTH_CLIENT_ID'
    set :client_secret, 'NEON_AUTH_CLIENT_SECRET'
    set :scope, %i[openid profile email]
  end

  group :airbrake do
    set :project_id, nil
    set :project_key, nil
    set :host, nil
  end

  group :map do
    # Addis Ababa
    set :center, [9.0192, 38.7525]
    set :zoom, 7
  end

  group :itineraries do
    # Trips must start and end inside Ethiopia. Set GEO_RESTRICTED=false to allow anywhere.
    set :geo_restricted, ENV.fetch('GEO_RESTRICTED', 'true') != 'false'

    # Approximate outline of Ethiopia as a closed ring, in [lng, lat] format
    set :bounds, [
      [36.55, 14.27], [37.9, 14.88], [39.4, 14.55], [40.8, 14.1], [41.8, 12.7], [42.4, 12.4], [43.1, 10.9],
      [44.0, 9.9], [47.97, 8.0], [44.2, 5.0], [42.9, 4.9], [41.9, 3.95], [39.1, 3.5], [36.05, 4.45],
      [34.0, 4.2], [33.0, 7.8], [34.1, 9.5], [34.3, 10.7], [35.3, 11.8], [36.0, 12.7]
    ]
  end

  group :mailer do
    set :from, '"Icare" <no-reply@i.care>'
    set :host, 'localhost'

    group :smtp_settings do
      set :address, 'localhost'
      set :port, 587
      set :authentication, :plain
      set :domain, 'localhost'

      set :user_name, 'test'
      set :password, 'test'
    end
  end

  group :redis do
    set :url, 'redis://127.0.0.1:6379'
  end
end
