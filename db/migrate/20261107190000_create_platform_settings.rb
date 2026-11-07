# frozen_string_literal: true

class CreatePlatformSettings < ActiveRecord::Migration[7.1]
  def up
    create_table :platform_settings do |t|
      t.decimal :fee_percent, precision: 5, scale: 2, null: false, default: 10.0
      t.string :fee_charged_to, null: false, default: 'passenger'
      t.string :currency_code, null: false, default: 'ETB'
      t.string :currency_symbol, null: false, default: 'Br'
      t.decimal :max_price_per_seat, precision: 10, scale: 2, null: false, default: 10_000
      t.text :payment_instructions
      t.timestamps
    end

    execute <<~SQL.squish
      INSERT INTO platform_settings (payment_instructions, created_at, updated_at)
      VALUES ('Pay the driver directly when you meet, in cash or with Telebirr or CBE Birr.', NOW(), NOW())
    SQL
  end

  def down
    drop_table :platform_settings
  end
end
