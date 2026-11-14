# frozen_string_literal: true

class CreateBoardings < ActiveRecord::Migration[7.1]
  def change
    # What happened to a passenger on one day of a ride: picked up, didn't show, dropped off.
    create_table :boardings do |t|
      t.references :booking, null: false, foreign_key: { on_delete: :cascade }
      t.date :ride_date, null: false
      t.datetime :boarded_at
      t.datetime :no_show_at
      t.datetime :dropped_off_at
      t.timestamps
    end
    add_index :boardings, %i[booking_id ride_date], unique: true

    # Which day's ride is under way, and when the car reached its destination.
    add_column :itineraries, :live_ride_date, :date
    add_column :itineraries, :arrived_at, :datetime
  end
end
