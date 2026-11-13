# frozen_string_literal: true

class CreateWallets < ActiveRecord::Migration[7.1]
  def change
    # One per person, plus one "platform" wallet (no user) that collects fees.
    create_table :wallets do |t|
      t.references :user, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :kind, null: false, default: 'user'
      t.decimal :available, precision: 12, scale: 2, null: false, default: 0
      t.decimal :held, precision: 12, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :wallets, 'available >= 0 AND held >= 0', name: 'wallets_never_negative'

    # Every movement of money. Balances can always be rebuilt from these rows.
    create_table :wallet_entries do |t|
      t.references :wallet, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.decimal :available_change, precision: 12, scale: 2, null: false, default: 0
      t.decimal :held_change, precision: 12, scale: 2, null: false, default: 0
      t.decimal :available_after, precision: 12, scale: 2, null: false
      t.decimal :held_after, precision: 12, scale: 2, null: false
      t.references :subject, polymorphic: true
      t.string :memo
      t.datetime :created_at, null: false
    end
    add_index :wallet_entries, %i[wallet_id id]

    create_table :wallet_topups do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :provider, null: false
      t.string :phone, null: false
      t.string :merchant_order_id, null: false
      t.string :callback_token, null: false
      t.string :reference
      t.string :provider_reference
      t.string :status, null: false, default: 'pending'
      t.datetime :credited_at
      t.timestamps
    end
    add_index :wallet_topups, :merchant_order_id, unique: true
    add_index :wallet_topups, :callback_token, unique: true

    create_table :wallet_withdrawals do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :method_name, null: false
      t.string :account_number, null: false
      t.string :account_name
      t.string :status, null: false, default: 'requested'
      t.string :note
      t.references :handled_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :handled_at
      t.timestamps
    end
    add_index :wallet_withdrawals, :status

    # How a seat is paid for, and where its money is.
    add_column :bookings, :payment_method, :string, null: false, default: 'cash'
    add_column :bookings, :payment_state, :string, null: false, default: 'none'
    add_column :bookings, :held_amount, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_column :bookings, :passenger_confirmed_at, :datetime
    add_column :bookings, :settled_at, :datetime

    add_column :platform_settings, :min_topup, :decimal, precision: 10, scale: 2, null: false, default: 10
    add_column :platform_settings, :max_topup, :decimal, precision: 10, scale: 2, null: false, default: 20_000
    add_column :platform_settings, :min_withdrawal, :decimal, precision: 10, scale: 2, null: false, default: 100
  end
end
