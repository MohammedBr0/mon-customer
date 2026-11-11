# frozen_string_literal: true

module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate!, only: %i[sign_in sign_up send_code]
      before_action :throttle!, only: %i[sign_in sign_up]

      LIMIT = 10
      WINDOW = 10.minutes

      # `login` is an Ethiopian mobile number or an email address (older apps send `email`).
      def sign_in
        email = PhoneLogin.login_email(login_param)
        return render_error('invalid_login', I18n.t('api.invalid_login'), :unprocessable_entity) if email.blank?

        user = NeonAuthClient.new.sign_in(email:, password: params.require(:password).to_s)
        respond_with_session(user)
      rescue NeonAuthClient::Error => e
        auth_failed(e)
      end

      # Texts a code to the number someone wants to register with.
      def send_code
        return render_error('sms_unavailable', I18n.t('api.sms_unavailable'), :service_unavailable) unless AfroMessageClient.enabled?

        phone = PhoneLogin.normalize(params.require(:phone))
        return render_error('invalid_phone', I18n.t('api.invalid_phone'), :unprocessable_entity) if phone.nil?
        return render_error('phone_taken', I18n.t('api.phone_taken'), :unprocessable_entity) if User.exists?(email: PhoneLogin.email_for(phone))

        verification = PhoneVerification.start!(phone:, ip: request.remote_ip)
        render json: { verification_id: verification.verification_id, expires_in: AfroMessageClient::TTL_SECONDS, code_length: AfroMessageClient::CODE_LENGTH }, status: :created
      rescue PhoneVerification::TooMany
        render_error 'rate_limited', I18n.t('api.rate_limited'), :too_many_requests
      rescue AfroMessageClient::Error
        render_error 'sms_unavailable', I18n.t('api.sms_unavailable'), :bad_gateway
      end

      # Registers with a phone number (the usual way in the app) or with an email address.
      def sign_up
        phone = PhoneLogin.normalize(params[:phone]) if params[:phone].present?
        return render_error('invalid_phone', I18n.t('api.invalid_phone'), :unprocessable_entity) if params[:phone].present? && phone.nil?

        verified = phone.present? && AfroMessageClient.enabled?
        return render_error('invalid_code', I18n.t('api.invalid_code'), :unprocessable_entity) if verified && !PhoneVerification.confirm(phone:, verification_id: params[:verification_id], code: params[:code])

        email = phone ? PhoneLogin.email_for(phone) : params.require(:email).to_s.strip.downcase
        mode = User::APP_MODES.include?(params[:app_mode]) ? params[:app_mode] : nil
        user = NeonAuthClient.new.sign_up(name: params.require(:name).to_s.strip, email:, password: params.require(:password).to_s)
        respond_with_session(user, status: :created, phone:, mode:, verified:)
      rescue AfroMessageClient::Error
        render_error 'sms_unavailable', I18n.t('api.sms_unavailable'), :bad_gateway
      rescue NeonAuthClient::Error => e
        return render_error('phone_taken', I18n.t('api.phone_taken'), :unprocessable_entity) if phone && e.status == 422

        auth_failed(e)
      end

      def sign_out
        @current_token.destroy
        head :no_content
      end

      private

      def login_param
        params[:login].presence || params.require(:email)
      end

      def respond_with_session(neon_user, status: :ok, phone: nil, mode: nil, verified: false)
        user = User.where(provider: 'neon', uid: neon_user.id).first_or_initialize
        user.assign_attributes(email: neon_user.email, name: neon_user.name.presence || user.name || neon_user.email.to_s.split('@').first, image: (user.image if user.image.to_s.start_with?('/avatars/')) || neon_user.image.presence || user.image)
        # A phone account always carries its sign-in number, so drivers and passengers can call each other.
        user.phone = phone || PhoneLogin.phone_from(neon_user.email) || user.phone
        user.app_mode = mode if mode
        user.phone_verified_at = Time.current if verified
        user.save!
        return render_error('banned', I18n.t('api.banned'), :forbidden) if user.banned?

        _record, raw = ApiToken.issue_for(user, device_name: params[:device_name])
        render json: { token: raw, user: serializer.me(user) }, status:
      end

      def auth_failed(error)
        status = if error.status == 503
                   :service_unavailable
                 else
                   (error.status >= 500 ? :bad_gateway : :unauthorized)
                 end
        status = :unprocessable_entity if error.status == 422
        render_error('auth_failed', error.message, status)
      end

      # Sign-in attempts per address and email are limited so the endpoint cannot be used to guess passwords.
      def throttle!
        key = "api-auth:#{request.remote_ip}:#{(params[:login] || params[:phone] || params[:email]).to_s.downcase.gsub(/\s/, '')}"
        count = Rails.cache.increment(key, 1, expires_in: WINDOW) || (Rails.cache.write(key, 1, expires_in: WINDOW) && 1)
        render_error('rate_limited', I18n.t('api.rate_limited'), :too_many_requests) if count.to_i > LIMIT
      end
    end
  end
end
