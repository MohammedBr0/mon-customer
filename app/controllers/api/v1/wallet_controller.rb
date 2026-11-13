# frozen_string_literal: true

module Api
  module V1
    # A person's wallet: balance, history, adding money by phone prompt, and asking for money out.
    class WalletController < BaseController
      before_action :require_wallet, only: %i[topup withdraw]

      def show
        BookingPayment.settle_due!(Booking.where(passenger: current_user).or(Booking.where(itinerary_id: current_user.itineraries.select(:id))))
        wallet = Wallet.for(current_user)
        entries, meta = paginate(wallet.entries.recent)
        render json: {
          wallet: serializer.wallet(wallet), meta:,
          entries: entries.map { |entry| serializer.wallet_entry(entry) },
          withdrawals: current_user.wallet_withdrawals.order(created_at: :desc).limit(10).map { |withdrawal| serializer.withdrawal(withdrawal) }
        }
      end

      # Starts a top-up: Afro Pay sends a PIN prompt to the phone. The app then watches the top-up until it settles.
      def topup
        phone = PhoneLogin.normalize(params.require(:phone))
        return render_error('invalid_phone', I18n.t('api.invalid_phone'), :unprocessable_entity) if phone.nil?

        topup = WalletTopup.start!(user: current_user, amount: params.require(:amount), provider: params.require(:provider).to_s, phone:)
        render json: { topup: serializer.topup(topup) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid e.record
      rescue AfroPayClient::Error => e
        render_error 'payment_unavailable', I18n.t('wallet.errors.gateway', reason: e.message), :bad_gateway
      end

      def topup_status
        render json: { topup: serializer.topup(current_user.wallet_topups.find(params[:id])), wallet: serializer.wallet(Wallet.for(current_user)) }
      end

      def withdraw
        withdrawal = WalletWithdrawal.request!(user: current_user, amount: params.require(:amount), method_name: params.require(:method_name).to_s,
                                               account_number: params.require(:account_number).to_s, account_name: params[:account_name].to_s.presence)
        render json: { withdrawal: serializer.withdrawal(withdrawal), wallet: serializer.wallet(Wallet.for(current_user)) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid e.record
      rescue Wallet::InsufficientFunds
        render_error 'insufficient_funds', I18n.t('wallet.errors.insufficient'), :unprocessable_entity
      end

      private

      def require_wallet
        render_error('wallet_disabled', I18n.t('wallet.errors.disabled'), :service_unavailable) unless AfroPayClient.enabled?
      end
    end
  end
end
