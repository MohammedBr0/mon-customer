# frozen_string_literal: true

module Admin
  # Money held in the service: totals, withdrawals to send, and recent top-ups. Super admins only.
  class WalletsController < SuperController
    def show
      users = Wallet.where(kind: 'user')
      @totals = { available: users.sum(:available), held: users.sum(:held), fees: Wallet.platform.available }
      @withdrawals = WalletWithdrawal.open.includes(:user).order(:created_at)
      @topups = WalletTopup.includes(:user).order(created_at: :desc).limit(15)
      @due = Booking.where(payment_method: 'wallet', payment_state: 'held', status: 'confirmed').count
    end

    def settle
      count = BookingPayment.settle_due!
      audit!('wallet.settle', nil, released: count)
      redirect_to admin_wallets_path, flash: { success: t('wallet.admin.settled', count:) }
    end
  end
end
