# frozen_string_literal: true

# Text messages that confirm money movements, so people have a record outside the app.
module PaymentSms
  module_function

  # Chapa's own receipt page for a payment.
  def receipt_url(reference)
    "https://chapa.link/payment-receipt/#{reference}" if reference.present?
  end

  # "500 Br added to your Arifway wallet. Ref APabc123. Receipt: https://chapa.link/payment-receipt/APabc123"
  def topup(topup)
    deliver(topup.user, I18n.t('wallet.sms.topup', amount: amount(topup.amount), app: APP_CONFIG.app_name, reference: topup.reference.presence || topup.merchant_order_id,
                                                   receipt: receipt_url(topup.reference)).squish)
  end

  def withdrawal(withdrawal)
    deliver(withdrawal.user, I18n.t('wallet.sms.withdrawal', amount: amount(withdrawal.amount), app: APP_CONFIG.app_name, account: "#{withdrawal.method_name} #{withdrawal.account_number}",
                                                              reference: withdrawal.transfer_reference))
  end

  def amount(value)
    ActiveSupport::NumberHelper.number_to_rounded(value, precision: 2, strip_insignificant_zeros: true)
  end

  # Never lets a failed text message undo or block a payment.
  def deliver(user, message)
    return false unless AfroMessageClient.enabled? && user.phone.present?

    locale = I18n.available_locales.find { |candidate| candidate.to_s == user.locale.to_s } || I18n.default_locale
    AfroMessageClient.new.send_sms(user.phone, I18n.with_locale(locale) { message })
  rescue StandardError => e
    Rails.logger.warn("Payment SMS failed: #{e.message}")
    false
  end
end
