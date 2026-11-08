# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, %i[user_id id]
    add_index :notifications, %i[user_id read_at]
  end
end
