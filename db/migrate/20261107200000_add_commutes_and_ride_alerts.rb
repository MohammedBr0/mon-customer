# frozen_string_literal: true

class AddCommutesAndRideAlerts < ActiveRecord::Migration[7.1]
  def up
    change_table :itineraries, bulk: true do |t|
      t.integer :commute_days, array: true, null: false, default: [] # 0 = Sunday ... 6 = Saturday
      t.date :commute_until
      t.string :pickup_point
      t.string :dropoff_point
    end

    # A booking now lists the days it covers, so a commuter can book several days at once.
    add_column :bookings, :ride_dates, :date, array: true, null: false, default: []
    execute <<~SQL.squish
      UPDATE bookings
      SET ride_dates = ARRAY[(itineraries.leave_date AT TIME ZONE 'UTC' AT TIME ZONE 'Africa/Addis_Ababa')::date]
      FROM itineraries
      WHERE itineraries.id = bookings.itinerary_id
    SQL
    execute "UPDATE itineraries SET daily = FALSE"

    create_table :ride_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :start_label, null: false
      t.string :end_label, null: false
      t.geography :start_location, limit: { srid: 4326, type: 'st_point', geographic: true }, null: false
      t.geography :end_location, limit: { srid: 4326, type: 'st_point', geographic: true }, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_notified_at
      t.timestamps
    end
  end

  def down
    drop_table :ride_alerts
    remove_column :bookings, :ride_dates
    change_table :itineraries, bulk: true do |t|
      t.remove :commute_days, :commute_until, :pickup_point, :dropoff_point
    end
  end
end
