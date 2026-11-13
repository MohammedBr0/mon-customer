# frozen_string_literal: true

class SwitchWalletToChapa < ActiveRecord::Migration[7.1]
  def change
    # Top-ups now go through Chapa's checkout page; the phone prompt and its secret callback address are gone.
    add_column :wallet_topups, :checkout_url, :string
    change_column_null :wallet_topups, :phone, true
    change_column_null :wallet_topups, :callback_token, true
    change_column_default :wallet_topups, :provider, from: nil, to: 'chapa'

    # Withdrawals are sent through Chapa's transfer API to a bank or mobile wallet.
    add_column :wallet_withdrawals, :bank_code, :integer
    add_column :wallet_withdrawals, :transfer_reference, :string
    add_index :wallet_withdrawals, :transfer_reference, unique: true

    # Withdrawals up to this amount are sent without waiting for an admin (0 = an admin approves every one).
    add_column :platform_settings, :auto_payout_limit, :decimal, precision: 10, scale: 2, null: false, default: 0
  end
end
