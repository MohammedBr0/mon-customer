# frozen_string_literal: true

class CreateBookings < ActiveRecord::Migration[7.1]
  def change
    create_table :bookings do |t|
      t.references :itinerary, null: false, foreign_key: true
      t.references :passenger, null: false, foreign_key: { to_table: :users }
      t.integer :seats, null: false, default: 1
      t.string :status, null: false, default: 'pending'
      t.text :note
      t.datetime :decided_at
      t.datetime :cancelled_at
      t.references :cancelled_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :bookings, :status
    # A passenger can hold only one live (pending or confirmed) booking per itinerary.
    add_index :bookings, %i[itinerary_id passenger_id], unique: true,
                                                         where: "status IN ('pending', 'confirmed')",
                                                         name: 'index_bookings_one_active_per_passenger'
  end
end
