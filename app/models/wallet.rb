# frozen_string_literal: true

# Someone's money inside the service: what they can spend or withdraw ("available") and what is set aside for a
# seat they have asked for ("held"). Balances only ever change through #move!, which writes a WalletEntry for
# every change, so the history always adds up to the balance.
class Wallet < ApplicationRecord
  class InsufficientFunds < StandardError; end

  belongs_to :user, optional: true
  has_many :entries, class_name: 'WalletEntry', dependent: :destroy

  validates :kind, inclusion: { in: %w[user platform] }

  def self.for(user)
    find_or_create_by!(user:)
  rescue ActiveRecord::RecordNotUnique
    find_by!(user:)
  end

  # The service's own wallet, where fees collect.
  def self.platform
    find_or_create_by!(kind: 'platform', user: nil)
  end

  # Changes this wallet's balances and records why. Locks the row so two requests can never spend the same money.
  def move!(kind, available: 0, held: 0, subject: nil, memo: nil)
    with_lock do
      new_available = self.available + available.to_d
      new_held = self.held + held.to_d
      raise InsufficientFunds if new_available.negative? || new_held.negative?

      update!(available: new_available, held: new_held)
      entries.create!(kind:, available_change: available.to_d, held_change: held.to_d, available_after: new_available, held_after: new_held, subject:, memo:)
    end
  end
end
