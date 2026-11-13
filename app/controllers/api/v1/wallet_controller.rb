# frozen_string_literal: true

module Api
  module V1
    # A person's wallet: balance, history, adding money by phone prompt, and asking for money out.
    class WalletController < BaseController
      before_action :require_wallet, only: %i[topup withdraw banks]

      def show
        BookingPayment.settle_due!(Booking.where(passenger: current_user).or(Booking.where(itinerary_id: current_user.itineraries.select(:id))))
        current_user.wallet_topups.where(status: 'pending', created_at: 1.day.ago..).find_each(&:refresh!)
        current_user.wallet_withdrawals.where(status: 'sending').find_each(&:refresh!)
        wallet = Wallet.for(current_user)
        entries, meta = paginate(wallet.entries.recent)
        render json: {
          wallet: serializer.wallet(wallet), meta:,
          entries: entries.map { |entry| serializer.wallet_entry(entry) },
          withdrawals: current_user.wallet_withdrawals.order(created_at: :desc).limit(10).map { |withdrawal| serializer.withdrawal(withdrawal) }
        }
      end

      # Starts a top-up and returns the address of Chapa's checkout page. The app opens it and then watches the top-up.
      def topup
        topup = WalletTopup.start!(user: current_user, amount: params.require(:amount))
        render json: { topup: serializer.topup(topup) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid e.record
      rescue ChapaClient::Error => e
        render_error 'payment_unavailable', I18n.t('wallet.errors.gateway', reason: e.message), :bad_gateway
      end

      # Asks Chapa whether the payment went through (so the wallet is right even if Chapa's webhook never arrives).
      def topup_status
        topup = current_user.wallet_topups.find(params[:id]).refresh!
        render json: { topup: serializer.topup(topup), wallet: serializer.wallet(Wallet.for(current_user)) }
      end

      # Banks and mobile wallets a withdrawal can be sent to.
      def banks
        banks = Rails.cache.fetch('chapa-banks', expires_in: 6.hours) { ChapaClient.new.banks }
        render json: { banks: }
      rescue ChapaClient::Error => e
        render_error 'payment_unavailable', I18n.t('wallet.errors.gateway', reason: e.message), :bad_gateway
      end

      def withdraw
        withdrawal = WalletWithdrawal.request!(user: current_user, amount: params.require(:amount), method_name: params.require(:method_name).to_s,
                                               account_number: params.require(:account_number).to_s, account_name: params[:account_name].to_s.presence,
                                               bank_code: params[:bank_code].presence&.to_i)
        render json: { withdrawal: serializer.withdrawal(withdrawal), wallet: serializer.wallet(Wallet.for(current_user)) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid e.record
      rescue Wallet::InsufficientFunds
        render_error 'insufficient_funds', I18n.t('wallet.errors.insufficient'), :unprocessable_entity
      end

      private

      def require_wallet
        render_error('wallet_disabled', I18n.t('wallet.errors.disabled'), :service_unavailable) unless ChapaClient.enabled?
      end
    end
  end
end
