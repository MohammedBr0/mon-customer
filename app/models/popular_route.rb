# frozen_string_literal: true

# Routes super admins highlight on the landing page.
class PopularRoute < ApplicationRecord
  scope :active, -> { where(active: true).order(:position, :id) }
  scope :ordered, -> { order(:position, :id) }

  validates :from_label, :to_label, presence: true, length: { maximum: 60 }

  before_create { self.position = (self.class.maximum(:position) || -1) + 1 }

  def to_s
    "#{from_label} → #{to_label}"
  end
end
