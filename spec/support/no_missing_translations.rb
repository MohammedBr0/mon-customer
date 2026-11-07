# frozen_string_literal: true

# Any page that renders a "translation missing" marker fails the example that rendered it.
RSpec.configure do |config|
  config.after(:each, type: :request) do
    body = response&.body.to_s
    expect(body).not_to match(/translation[ _]missing/i), 'a page rendered a missing translation'
  end
end
