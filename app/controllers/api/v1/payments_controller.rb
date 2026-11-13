# frozen_string_literal: true

module Api
  module V1
    # Where Chapa reports on payments and payouts. Nothing here is trusted on its own: every report only makes
    # the server ask Chapa (with our secret key) what really happened, and act on that answer.
    class PaymentsController < ActionController::API
      # Chapa's webhook (POST, signed) for payments and payouts.
      def chapa
        signature = request.headers['x-chapa-signature'].presence || request.headers['Chapa-Signature']
        return head :unauthorized if ChapaClient.webhook_secret && !ChapaClient.valid_signature?(request.raw_post, signature)

        settle(params[:tx_ref].presence || params[:trx_ref].presence || params[:reference].presence || params[:merchant_reference])
        head :ok
      end

      # The callback_url Chapa calls when a checkout finishes.
      def chapa_callback
        settle(params[:trx_ref].presence || params[:tx_ref].presence || params[:ref_id])
        head :ok
      end

      private

      def settle(reference)
        return if reference.blank?

        WalletTopup.find_by(merchant_order_id: reference.to_s)&.refresh!
        WalletWithdrawal.find_by(transfer_reference: reference.to_s)&.refresh!
      end
    end
  end
end
