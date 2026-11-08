# frozen_string_literal: true

module ApiHelpers
  def api_headers(user, extra = {})
    _record, raw = ApiToken.issue_for(user, device_name: 'rspec')
    { 'Authorization' => "Bearer #{raw}", 'Accept' => 'application/json' }.merge(extra)
  end

  def json
    response.parsed_body
  end
end

RSpec.configure { |config| config.include ApiHelpers, type: :request }
