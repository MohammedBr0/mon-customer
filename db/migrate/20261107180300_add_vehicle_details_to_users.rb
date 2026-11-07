# frozen_string_literal: true

class AddVehicleDetailsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :car_make, :string
    add_column :users, :car_model, :string
    add_column :users, :car_color, :string
    add_column :users, :car_plate, :string
  end
end
