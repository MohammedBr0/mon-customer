# frozen_string_literal: true

FactoryBot.define do
  factory :vehicle_field do
    sequence(:key) { |n| "field_#{n}" }
    label { key.humanize }
    field_type { 'text' }
    visibility { 'public' }
    required { false }
    active { true }
  end
end
