# frozen_string_literal: true

FactoryBot.define do
  factory :booking do
    itinerary { association :itinerary, num_people: 3 }
    passenger { association :user }
    seats { 1 }
    status { 'pending' }

    trait :confirmed do
      status { 'confirmed' }
      decided_at { Time.current }
    end

    # A confirmed booking on a trip that has already left.
    trait :completed do
      confirmed
      after(:create) { |booking| booking.itinerary.update_columns(leave_date: 2.days.ago) }
    end
  end
end
