# frozen_string_literal: true

class AddPickupsRemindersLiveTracking < ActiveRecord::Migration[7.1]
  def change
    # Where a passenger wants to be picked up, shown to the driver with the seat request.
    add_column :bookings, :pickup_lat, :decimal, precision: 9, scale: 6
    add_column :bookings, :pickup_lng, :decimal, precision: 9, scale: 6
    add_column :bookings, :pickup_label, :string

    # Minutes before a ride that the person wants a reminder (0 = none).
    add_column :users, :reminder_minutes, :integer, null: false, default: 15

    # A starting point for drivers' prices: suggested fare per km for the whole car (0 = no suggestion).
    add_column :platform_settings, :suggested_price_per_km, :decimal, precision: 8, scale: 2, null: false, default: 6

    # The driver's position while a ride is under way.
    add_column :itineraries, :live_started_at, :datetime
    add_column :itineraries, :live_ended_at, :datetime
    add_column :itineraries, :live_lat, :decimal, precision: 9, scale: 6
    add_column :itineraries, :live_lng, :decimal, precision: 9, scale: 6
    add_column :itineraries, :live_heading, :decimal, precision: 5, scale: 1
    add_column :itineraries, :live_updated_at, :datetime
  end
end
