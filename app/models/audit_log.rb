# frozen_string_literal: true

# A record of what staff changed, who did it and to what. Never edited or deleted from the app.
class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: 'User'

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  validates :action, presence: true

  def self.record(actor, action, subject = nil, details = {})
    create!(actor:, action:, subject_type: subject&.class&.name, subject_id: subject&.id,
            subject_label: subject.respond_to?(:title) ? subject.title : subject&.to_s, details:)
  end

  def readonly?
    persisted? || super
  end
end
