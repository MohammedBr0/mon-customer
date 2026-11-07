# frozen_string_literal: true

class AddCancelledAtToItineraries < ActiveRecord::Migration[7.1]
  def change
    add_column :itineraries, :cancelled_at, :datetime
    add_index :itineraries, :cancelled_at
  end
end
