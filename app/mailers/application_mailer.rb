# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  layout 'mailer'

  private

  # Sends the mail in the recipient's language when it is one the app supports.
  def mail_to(user, subject_key, **subject_options)
    locale = [user.locale&.to_sym, I18n.default_locale].find { |l| I18n.available_locales.include?(l) }
    I18n.with_locale(locale) do
      mail to: user.email, subject: t(subject_key, **subject_options)
    end
  end
end
