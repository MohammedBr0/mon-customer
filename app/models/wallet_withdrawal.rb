# frozen_string_literal: true

# A driver (or anyone with a balance) asks for money out of their wallet. The amount is set aside straight away;
# an admin sends it by Telebirr or bank and marks it paid, or rejects it and the money goes back.
class WalletWithdrawal < ApplicationRecord
  STATUSES = %w[requested paid rejected].freeze

  belongs_to :user
  belongs_to :handled_by, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :method_name, :account_number, presence: true, length: { maximum: 80 }
  validates :account_name, :note, length: { maximum: 200 }
  validate :amount_is_allowed, on: :create

  scope :requested, -> { where(status: 'requested') }

  STATUSES.each { |name| define_method(:"#{name}?") { status == name } }

  def self.request!(user:, amount:, method_name:, account_number:, account_name: nil)
    transaction do
      withdrawal = create!(user:, amount:, method_name:, account_number:, account_name:)
      Wallet.for(user).move!('withdrawal_request', available: -withdrawal.amount, held: withdrawal.amount, subject: withdrawal, memo: method_name)
      withdrawal
    end
  end

  def mark_paid!(by:, note: nil)
    transaction do
      lock!
      raise ActiveRecord::RecordInvalid, self unless requested?

      update!(status: 'paid', handled_by: by, handled_at: Time.current, note:)
      Wallet.for(user).move!('withdrawal_paid', held: -amount, subject: self, memo: note)
    end
    Notification.notify(user, 'withdrawal_paid', amount: ApiSerializer.money(amount).to_s)
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
