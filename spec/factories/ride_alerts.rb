# frozen_string_literal: true

FactoryBot.define do
  factory :ride_alert do
    user
    start_label { 'Addis Ababa' }
    end_label { 'Adama' }
    start_location { [38.7525, 9.0192] }
    end_location { [39.2695, 8.54] }
  end
end
