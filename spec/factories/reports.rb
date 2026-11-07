# frozen_string_literal: true

FactoryBot.define do
  factory :report do
    reporter { association :user }
    reportable { association :itinerary }
    reason { 'other' }
    status { 'open' }
  end
end
