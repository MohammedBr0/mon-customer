# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: 'User'

  validates :body, presence: true, length: { maximum: 1000 }

  scope :unread, -> { where(read_at: nil) }

  after_create_commit :notify_recipient

  def unread?
    read_at.nil?
  end

  private

  # Honours the "email me when I receive a message" setting.
  def notify_recipient
    Notification.notify(conversation.with(sender), 'new_message', conversation_id: conversation_id, person: sender.to_s, preview: body.truncate(80))
    return unless conversation.with(sender).send_email_messages?

    MessageMailer.with(message: self).new_message.deliver_later
  end
end
