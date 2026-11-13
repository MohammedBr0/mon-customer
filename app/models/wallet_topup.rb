# frozen_string_literal: true

# Money someone adds to their wallet through Chapa. They pay on Chapa's checkout page (Telebirr, CBE Birr,
# M-Pesa, cards). The wallet is credited only after Chapa itself confirms the payment and its amount, never on
# the word of a callback alone.
class WalletTopup < ApplicationRecord
  STATUSES = %w[pending success failed].freeze

  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validate :amount_within_limits, on: :create

  before_validation(on: :create) { self.merchant_order_id ||= "ARIF#{Time.current.strftime('%y%m%d%H%M%S')}#{SecureRandom.hex(3).upcase}" }

  def final?
    status != 'pending'
  end

  # Opens the payment at Chapa and keeps the address of its checkout page.
  def self.start!(user:, amount:)
    topup = create!(user:, amount:, provider: 'chapa', phone: user.phone.to_s.delete('+').presence)
    first, last = user.to_s.split(' ', 2)
    url = ChapaClient.new.initialize_payment(
      tx_ref: topup.merchant_order_id, amount: topup.amount, first_name: first.presence || 'Arifway', last_name: last.presence || 'User',
      phone: user.phone.to_s.sub('+251', '0').presence, email: (user.email unless user.phone_account?),
      callback_url: "#{NeonAuthClient.origin}/api/v1/payments/chapa/callback", return_url: "#{NeonAuthClient.origin}/payments/done",
      title: APP_CONFIG.app_name, description: I18n.t('wallet.topup_description', app: APP_CONFIG.app_name)
    )
    topup.update!(checkout_url: url)
    topup
  rescue ChapaClient::Error
    topup&.update(status: 'failed')
    raise
  end

  # Asks Chapa what happened to this payment and settles it. Safe to call any number of times.
  def refresh!
    return self if final?

    result = ChapaClient.new.verify_payment(merchant_order_id)
    with_lock do
      return self if final?

      if result[:status] == 'success' && result[:currency] == 'ETB' && result[:amount] == amount
        update!(status: 'success', reference: result[:reference], provider_reference: result[:method], credited_at: Time.current)
        Wallet.for(user).move!('topup', available: amount, subject: self, memo: result[:method].presence || 'Chapa')
        Notification.notify(user, 'wallet_topup', amount: ApiSerializer.money(amount).to_s)
      elsif result[:status].start_with?('fail')
        update!(status: 'failed')
      end
    end
    self
  rescue ChapaClient::Error
    self # Chapa could not be reached: the top-up stays pending and is checked again later
  end

  private

  def amount_within_limits
    setting = PlatformSetting.current
    errors.add(:amount, :out_of_range, min: setting.min_topup.to_i, max: setting.max_topup.to_i) unless amount.to_d.between?(setting.min_topup, setting.max_topup)
  end
end
