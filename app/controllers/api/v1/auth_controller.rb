# frozen_string_literal: true

module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate!, only: %i[sign_in sign_up]
      before_action :throttle!, only: %i[sign_in sign_up]

      LIMIT = 10
      WINDOW = 10.minutes

      def sign_in
        user = NeonAuthClient.new.sign_in(email: params.require(:email).to_s.strip.downcase, password: params.require(:password).to_s)
        respond_with_session(user)
      rescue NeonAuthClient::Error => e
        auth_failed(e)
      end

      def sign_up
        user = NeonAuthClient.new.sign_up(name: params.require(:name).to_s.strip, email: params.require(:email).to_s.strip.downcase,
                                          password: params.require(:password).to_s)
        respond_with_session(user, status: :created)
      rescue NeonAuthClient::Error => e
        auth_failed(e)
      end

      def sign_out
        @current_token.destroy
        head :no_content
      end

      private

      def respond_with_session(neon_user, status: :ok)
        user = User.where(provider: 'neon', uid: neon_user.id).first_or_initialize
        user.assign_attributes(email: neon_user.email, name: neon_user.name.presence || user.name || neon_user.email.to_s.split('@').first, image: neon_user.image.presence || user.image)
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
        key = "api-auth:#{request.remote_ip}:#{params[:email].to_s.downcase}"
        count = Rails.cache.increment(key, 1, expires_in: WINDOW) || (Rails.cache.write(key, 1, expires_in: WINDOW) && 1)
        render_error('rate_limited', I18n.t('api.rate_limited'), :too_many_requests) if count.to_i > LIMIT
      end
    end
  end
end
