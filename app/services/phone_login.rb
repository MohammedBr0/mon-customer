# frozen_string_literal: true

# Lets people register and sign in with an Ethiopian mobile number. The sign-in service only knows email
# addresses, so each number gets a fixed stand-in address on a domain that can never receive mail.
module PhoneLogin
  DOMAIN = 'phone.icare.invalid'
  NUMBER = /\A\+251[79]\d{8}\z/

  module_function

  # "0911 22 33 44", "911223344", "251911223344" or "+251911223344" to "+251911223344"; nil when not a mobile number.
  def normalize(raw)
    digits = raw.to_s.gsub(/[\s\-().]/, '')
    digits = "+251#{digits[1..]}" if digits.match?(/\A0[79]\d{8}\z/)
    digits = "+251#{digits}" if digits.match?(/\A[79]\d{8}\z/)
    digits = "+#{digits}" if digits.match?(/\A251[79]\d{8}\z/)
    digits if digits.match?(NUMBER)
  end

  def email_for(phone)
    "p#{phone.delete('+')}@#{DOMAIN}"
  end

  def stand_in?(email)
    email.to_s.end_with?("@#{DOMAIN}")
  end

  def phone_from(email)
    "+#{email[/\Ap(\d+)@/, 1]}" if stand_in?(email)
  end

  # What a person typed in the sign-in box: an email address stays as it is, a phone number becomes its stand-in.
  def login_email(identifier)
    text = identifier.to_s.strip
    return text.downcase if text.include?('@')

    phone = normalize(text)
    phone && email_for(phone)
  end
end
