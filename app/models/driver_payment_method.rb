# frozen_string_literal: true

# One payment method a driver accepts, with the account passengers should pay into (when the method has one).
class DriverPaymentMethod < ApplicationRecord
  belongs_to :user
  belongs_to :payment_method

  validates :payment_method_id, uniqueness: { scope: :user_id }
  validates :account_name, length: { maximum: 80 }
  validates :account_number, length: { maximum: 60 }
  validates :account_number, presence: true, if: -> { payment_method&.needs_account? }

  # Replaces everything the driver accepts with the given list of { id:, account_name:, account_number: }.
  def self.replace_for(user, entries)
    allowed = PaymentMethod.active.index_by(&:id)
    transaction do
      user.driver_payment_methods.destroy_all
      Array(entries).uniq { |entry| entry[:id].to_i }.filter_map do |entry|
        method = allowed[entry[:id].to_i]
        next unless method

        user.driver_payment_methods.create!(payment_method: method, account_name: entry[:account_name].to_s.strip.presence,
                                            account_number: (entry[:account_number].to_s.strip.presence if method.needs_account?))
      end
    end
  end
end
