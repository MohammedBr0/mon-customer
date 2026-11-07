# frozen_string_literal: true

# rubocop:disable Layout/FirstHashElementIndentation, Rails/RelativeDateConstant
OMNIAUTH_MOCKED_AUTHHASH = OmniAuth::AuthHash.new({
  'provider'    => 'neon',
  'uid'         => '123456',
  'info'        => {
    'email' => 'test@example.com',
    'name'  => 'John Doe',
    'image' => 'https://s.gravatar.com/avatar/123456?s=480&r=pg&d=https%3A%2F%2Fexample.com%2Favatar.png'
  },
  'credentials' => {
    'token'      => 'token',
    'expires_at' => 2.days.from_now.to_i,
    'expires'    => true
  },
  'extra'       => {
    'raw_info' => {
      'name'  => 'test@example.com',
      'email' => 'John Doe',
      'id'    => '123456'
    }
  }
})
# rubocop:enable Layout/FirstHashElementIndentation, Rails/RelativeDateConstant

OmniAuth.config.test_mode = true
OmniAuth.config.mock_auth[:neon] = OMNIAUTH_MOCKED_AUTHHASH

module OmniauthMacros
  def login_via_neon
    visit root_path
    first("form[action=\"#{user_neon_omniauth_authorize_path}\"] button").click
  end
end

RSpec.configure do |config|
  config.include OmniauthMacros
end
