# frozen_string_literal: true

FactoryBot.define do
  factory :review do
    booking { association :booking, :completed }
    reviewer { booking.passenger }
    reviewee { booking.driver }
    rating { 5 }
    comment { 'Great ride, on time and friendly.' }
  end
end
