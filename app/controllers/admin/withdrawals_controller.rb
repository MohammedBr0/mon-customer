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

    # Sends the money through Chapa. It stays set aside until Chapa confirms it arrived.
    def send_out
      @withdrawal.send_with_chapa!(by: current_user)
      audit!('withdrawal.send', @withdrawal, amount: @withdrawal.amount.to_f, user_id: @withdrawal.user_id)
      flash = @withdrawal.sending? ? { success: t('wallet.admin.sent') } : { error: t('wallet.admin.send_failed', reason: @withdrawal.note) }
      redirect_to(admin_wallets_path, flash:)
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_wallets_path, flash: { error: t('flash.errors.not_allowed') }
    end

    # Asks Chapa whether a transfer that was sent has arrived.
    def check
      @withdrawal.refresh!
      redirect_to admin_wallets_path, flash: { success: t("wallet.admin.check_#{@withdrawal.status}") }
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
