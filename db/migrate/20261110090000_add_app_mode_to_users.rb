# frozen_string_literal: true

class AddAppModeToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :app_mode, :string, null: false, default: 'passenger'
  end
end
