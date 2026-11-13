# frozen_string_literal: true

# Money someone adds to their wallet through Afro Pay: a PIN prompt appears on their phone, and Afro Pay tells
# us the result on a callback address that is secret to this one top-up.
class WalletTopup < ApplicationRecord
  PROVIDERS = AfroPayClient::PROVIDERS.keys.freeze
  STATUSES = %w[pending processing success failed canceled expired unauthorized].freeze
  FINAL = %w[success canceled expired unauthorized].freeze

  belongs_to :user

  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
  validates :phone, format: { with: /\A251[79]\d{8}\z/ }
  validate :amount_within_limits, on: :create

  before_validation :assign_identifiers, on: :create

  def final?
    FINAL.include?(status)
  end

  # Starts the payment: asks Afro Pay to send the PIN prompt to the phone.
  def self.start!(user:, amount:, provider:, phone:)
    topup = create!(user:, amount:, provider:, phone: PhoneLogin.normalize(phone).to_s.delete('+'))
    result = AfroPayClient.new.initiate(provider:, amount: topup.amount, phone: topup.phone, order_id: topup.merchant_order_id,
                                        callback_url: topup.callback_url, description: I18n.t('wallet.topup_description', app: APP_CONFIG.app_name))
    topup.update!(reference: result[:reference])
    topup
  rescue AfroPayClient::Error
    topup&.update(status: 'failed')
    raise
  end

  def callback_url
    "#{NeonAuthClient.origin}/api/v1/payments/afropay/#{callback_token}"
  end

  # Applies what Afro Pay reported. The wallet is credited once, and only when everything matches what we asked for.
  def apply_callback!(status:, amount:, order_id:, provider_reference: nil)
    with_lock do
      return self if final? # a finished top-up never changes again, however many callbacks arrive

      reported = status.to_s.downcase
      return self unless STATUSES.include?(reported)
      return self if order_id.to_s != merchant_order_id

      if reported == 'success'
        return self unless amount.to_d == self.amount # a different amount is not this top-up

        update!(status: 'success', provider_reference:, credited_at: Time.current)
        Wallet.for(user).move!('topup', available: self.amount, subject: self, memo: provider)
        Notification.notify(user, 'wallet_topup', amount: ApiSerializer.money(self.amount).to_s)
      else
        update!(status: reported, provider_reference:)
      end
    end
    self
  end

  private

  def assign_identifiers
    self.merchant_order_id ||= "ARIF-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4).upcase}"
    self.callback_token ||= SecureRandom.urlsafe_base64(32)
  end

  def amount_within_limits
    setting = PlatformSetting.current
    errors.add(:amount, :out_of_range, min: setting.min_topup.to_i, max: setting.max_topup.to_i) unless amount.to_d.between?(setting.min_topup, setting.max_topup)
  end
end
