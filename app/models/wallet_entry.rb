# frozen_string_literal: true

# One line of a wallet's history. Never edited or deleted.
class WalletEntry < ApplicationRecord
  KINDS = %w[topup hold hold_release payment earning fee refund withdrawal_request withdrawal_paid withdrawal_rejected adjustment].freeze

  belongs_to :wallet
  belongs_to :subject, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }

  before_update { raise ActiveRecord::ReadOnlyRecord }
  before_destroy { raise ActiveRecord::ReadOnlyRecord unless destroyed_by_association }

  scope :recent, -> { order(id: :desc) }
end
