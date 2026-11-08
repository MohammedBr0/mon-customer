# frozen_string_literal: true

class AddCityToItineraries < ActiveRecord::Migration[7.1]
  def change
    add_column :itineraries, :city, :string
    add_index :itineraries, %i[city leave_date], where: 'city IS NOT NULL'
  end
end
