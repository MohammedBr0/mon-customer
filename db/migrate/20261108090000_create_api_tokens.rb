# frozen_string_literal: true

class CreateApiTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :device_name
      t.datetime :last_used_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :api_tokens, :token_digest, unique: true
  end
end
