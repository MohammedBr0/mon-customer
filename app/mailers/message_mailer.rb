# frozen_string_literal: true

class MessageMailer < ApplicationMailer
  def new_message
    @message = params[:message]
    @conversation = @message.conversation
    @recipient = @conversation.with(@message.sender)
    mail_to @recipient, 'mailers.message.new_message.subject', sender: @message.sender.to_s
  end
end
