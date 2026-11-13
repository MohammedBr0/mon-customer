# frozen_string_literal: true

# Someone asks for money out of their wallet. The amount is set aside straight away. It is then sent through
# Chapa to their bank or mobile wallet: automatically when it is within the admins' limit, otherwise when an
# admin approves it. If the transfer fails the request goes back to waiting; if it is rejected the money returns.
class WalletWithdrawal < ApplicationRecord
  STATUSES = %w[requested sending paid rejected].freeze

  belongs_to :user
  belongs_to :handled_by, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :method_name, :account_number, presence: true, length: { maximum: 80 }
  validates :account_name, :note, length: { maximum: 200 }
  validate :amount_is_allowed, on: :create

  scope :open, -> { where(status: %w[requested sending]) }

  STATUSES.each { |name| define_method(:"#{name}?") { status == name } }

  def self.request!(user:, amount:, method_name:, account_number:, account_name: nil, bank_code: nil)
    withdrawal = transaction do
      record = create!(user:, amount:, method_name:, account_number:, account_name: account_name.presence || user.to_s, bank_code:)
      Wallet.for(user).move!('withdrawal_request', available: -record.amount, held: record.amount, subject: record, memo: method_name)
      record
    end
    withdrawal.send_with_chapa! if withdrawal.bank_code && withdrawal.amount <= PlatformSetting.current.auto_payout_limit
    withdrawal
  end

  # Hands the payout to Chapa. The money stays set aside until Chapa says it arrived.
  def send_with_chapa!(by: nil)
    raise ActiveRecord::RecordInvalid, self unless requested? && bank_code.present?

    reference = "ARIFWD#{id}T#{Time.current.to_i}"
    update!(status: 'sending', transfer_reference: reference, handled_by: by, handled_at: Time.current)
    ChapaClient.new.transfer(reference:, amount:, account_name:, account_number:, bank_code:)
    self
  rescue ChapaClient::Error => e
    update!(status: 'requested', transfer_reference: nil, note: e.message.truncate(190))
    self
  end

  # Asks Chapa how the transfer went and settles it.
  def refresh!
    return self unless sending?

    case ChapaClient.new.verify_transfer(transfer_reference)
    when 'success' then mark_paid!(by: handled_by, note: "Chapa #{transfer_reference}")
    when 'failed' then update!(status: 'requested', note: I18n.t('wallet.transfer_failed'))
    end
    self
  end

  def mark_paid!(by:, note: nil)
    transaction do
      lock!
      raise ActiveRecord::RecordInvalid, self unless requested? || sending?

      update!(status: 'paid', handled_by: by, handled_at: Time.current, note:)
      Wallet.for(user).move!('withdrawal_paid', held: -amount, subject: self, memo: note)
    end
    Notification.notify(user, 'withdrawal_paid', amount: ApiSerializer.money(amount).to_s)
    PaymentSms.withdrawal(self)
  end

  def reject!(by:, note:)
    transaction do
      lock!
      raise ActiveRecord::RecordInvalid, self unless requested?

      update!(status: 'rejected', handled_by: by, handled_at: Time.current, note:)
      Wallet.for(user).move!('withdrawal_rejected', available: amount, held: -amount, subject: self, memo: note)
    end
    Notification.notify(user, 'withdrawal_rejected', amount: ApiSerializer.money(amount).to_s, reason: note.to_s)
  end

  private

  def amount_is_allowed
    minimum = PlatformSetting.current.min_withdrawal
    errors.add(:amount, :below_minimum, min: minimum.to_i) if amount.to_d < minimum
    errors.add(:amount, :more_than_balance) if user && amount.to_d > Wallet.for(user).available
  end
end
