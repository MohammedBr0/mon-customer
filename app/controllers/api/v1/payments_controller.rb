# frozen_string_literal: true

module Api
  module V1
    # Where Afro Pay reports the result of a payment. Afro Pay does not sign its callbacks, so each top-up has its
    # own secret address, and the report must match the order id and amount we asked for before any money is credited.
    class PaymentsController < ActionController::API
      def afropay
        topup = WalletTopup.find_by(callback_token: params[:token].to_s)
        return head :not_found unless topup

        body = params.to_unsafe_h
        topup.apply_callback!(status: body['Status'], amount: body['Amount'], order_id: body['MerchantOrderId'], provider_reference: body['ProviderReference'].to_s.presence)
        head :ok
      end
    end
  end
end
