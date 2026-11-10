# frozen_string_literal: true

# Accounts registered with a phone number have a stand-in address that cannot receive mail: never try to send to it.
class PhoneLoginMailInterceptor
  def self.delivering_email(message)
    message.perform_deliveries = false if Array(message.to).all? { |address| address.to_s.end_with?('@phone.icare.invalid') }
  end
end

ActionMailer::Base.register_interceptor(PhoneLoginMailInterceptor)
