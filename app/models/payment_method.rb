# frozen_string_literal: true

# A way passengers can pay drivers (cash, Telebirr, a bank...). Super admins keep the list; each driver picks
# the ones they accept.
class PaymentMethod < ApplicationRecord
  has_many :driver_payment_methods, dependent: :destroy

  validates :name, presence: true, length: { maximum: 40 }, uniqueness: { case_sensitive: false }
  validates :name_am, :account_label, length: { maximum: 60 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  before_create { self.position = (PaymentMethod.maximum(:position) || -1) + 1 if position.zero? && PaymentMethod.exists? }

  def label(locale = I18n.locale)
    locale.to_s.start_with?('am') && name_am.present? ? name_am : name
  end

  # Cash and similar need no account details from the driver.
  def needs_account?
    account_label.present?
  end
end
