# frozen_string_literal: true

# Platform-wide settings a super admin can change. There is exactly one row.
class PlatformSetting < ApplicationRecord
  FEE_CHARGED_TO = %w[passenger driver].freeze
  MAX_FEE_PERCENT = 50

  validates :fee_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_FEE_PERCENT }
  validates :fee_charged_to, inclusion: { in: FEE_CHARGED_TO }
  validates :currency_code, presence: true, length: { maximum: 5 }
  validates :currency_symbol, presence: true, length: { maximum: 6 }
  validates :max_price_per_seat, numericality: { greater_than: 0, less_than_or_equal_to: 1_000_000 }
  validates :payment_instructions, length: { maximum: 500 }

  def self.current
    first || create!(payment_instructions: 'Pay the driver directly when you meet, in cash or with Telebirr or CBE Birr.')
  end

  def fee_charged_to_passenger?
    fee_charged_to == 'passenger'
  end
end
