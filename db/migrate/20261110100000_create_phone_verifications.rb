# frozen_string_literal: true

class CreatePhoneVerifications < ActiveRecord::Migration[7.1]
  def change
    create_table :phone_verifications do |t|
      t.string :phone, null: false
      t.string :verification_id, null: false
      t.string :ip
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :phone_verifications, :verification_id, unique: true
    add_index :phone_verifications, %i[phone created_at]
    add_column :users, :phone_verified_at, :datetime
  end
end
