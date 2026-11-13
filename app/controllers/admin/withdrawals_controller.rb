# frozen_string_literal: true

module Admin
  # A super admin sends the money outside the app (Telebirr, bank) and records it here.
  class WithdrawalsController < SuperController
    before_action { @withdrawal = WalletWithdrawal.find(params[:id]) }

    def pay
      @withdrawal.mark_paid!(by: current_user, note: params[:note].to_s.presence)
      audit!('withdrawal.pay', @withdrawal, amount: @withdrawal.amount.to_f, user_id: @withdrawal.user_id)
      redirect_to admin_wallets_path, flash: { success: t('wallet.admin.paid') }
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_wallets_path, flash: { error: t('flash.errors.not_allowed') }
    end

    def reject
      @withdrawal.reject!(by: current_user, note: params[:note].to_s.presence || '-')
      audit!('withdrawal.reject', @withdrawal, amount: @withdrawal.amount.to_f, user_id: @withdrawal.user_id)
      redirect_to admin_wallets_path, flash: { success: t('wallet.admin.rejected') }
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_wallets_path, flash: { error: t('flash.errors.not_allowed') }
    end
  end
end
