# frozen_string_literal: true

# DO NOT SET SENSITIVE DATA HERE!
# USE ENVIRONMENT VARIABLES OR 'local.rb' INSTEAD

SimpleConfig.for :application do
  group :neon_auth do
    set :issuer, 'https://neon-auth.test/icare/auth'
  end

  group :itineraries do
    set :geo_restricted, false
    set :bounds, [
      [5, 4],
      [7, 4],
      [2, 7],
      [2, 5]
    ]
  end
end
