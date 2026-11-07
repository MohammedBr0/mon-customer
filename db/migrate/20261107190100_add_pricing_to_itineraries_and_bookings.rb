# frozen_string_literal: true

class AddPricingToItinerariesAndBookings < ActiveRecord::Migration[7.1]
  def up
    add_column :itineraries, :price_per_seat, :decimal, precision: 10, scale: 2, null: false, default: 0

    # Existing trips used a shared-cost model: turn it into a price the driver would have asked.
    execute <<~SQL.squish
      UPDATE itineraries
      SET price_per_seat = ROUND((COALESCE(fuel_cost, 0) + COALESCE(tolls, 0))::numeric / (COALESCE(num_people, 0) + 1), 2)
    SQL

    change_table :bookings, bulk: true do |t|
      t.decimal :price_per_seat, precision: 10, scale: 2, null: false, default: 0
      t.decimal :fee_percent, precision: 5, scale: 2, null: false, default: 0
      t.string :fee_charged_to, null: false, default: 'passenger'
      t.decimal :fare_total, precision: 10, scale: 2, null: false, default: 0
      t.decimal :fee_amount, precision: 10, scale: 2, null: false, default: 0
      t.decimal :passenger_total, precision: 10, scale: 2, null: false, default: 0
      t.decimal :driver_payout, precision: 10, scale: 2, null: false, default: 0
    end

    # Bookings made before pricing existed carry the trip price and no fee.
    execute <<~SQL.squish
      UPDATE bookings
      SET price_per_seat = itineraries.price_per_seat,
          fare_total = itineraries.price_per_seat * bookings.seats,
          passenger_total = itineraries.price_per_seat * bookings.seats,
          driver_payout = itineraries.price_per_seat * bookings.seats
      FROM itineraries
      WHERE itineraries.id = bookings.itinerary_id
    SQL
  end

  def down
    change_table :bookings, bulk: true do |t|
      t.remove :price_per_seat, :fee_percent, :fee_charged_to, :fare_total, :fee_amount, :passenger_total, :driver_payout
    end
    remove_column :itineraries, :price_per_seat
  end
end
