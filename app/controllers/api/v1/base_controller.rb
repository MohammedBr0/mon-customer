# frozen_string_literal: true

module Api
  module V1
    # Shared behaviour for the mobile API: bearer-token sign-in, JSON errors and the caller's language.
    class BaseController < ActionController::API
      include ActionController::MimeResponds

      attr_reader :current_user

      before_action :authenticate!
      around_action :with_locale

      rescue_from ActiveRecord::RecordNotFound do
        I18n.with_locale(request_locale) { render_error 'not_found', I18n.t('api.not_found'), :not_found }
      end
      rescue_from ActionController::ParameterMissing do |error|
        render_error 'invalid_request', error.message, :unprocessable_entity
      end

      private

      def authenticate!
        raw = request.authorization.to_s[/\ABearer (.+)\z/, 1]
        token = ApiToken.authenticate(raw)
        return render_error('unauthorized', I18n.t('api.unauthorized'), :unauthorized) unless token
        return render_error('banned', I18n.t('api.banned'), :forbidden) if token.user.banned?

        @current_token = token
        @current_user = token.user
      end

      def with_locale(&block)
        I18n.with_locale(request_locale, &block)
      end

      # The person's saved language, else the app's Accept-Language header, else English.
      def request_locale
        wanted = current_user&.locale.presence || request.headers['Accept-Language'].to_s[/\A[a-z]{2}/]
        return I18n.default_locale if wanted.blank?

        I18n.available_locales.find { |candidate| candidate.to_s.start_with?(wanted.to_s) } || I18n.default_locale
      end

      def render_error(code, message, status, details = nil)
        render json: { error: { code:, message:, details: }.compact }, status:
      end

      def render_invalid(record)
        render_error 'invalid_record', record.errors.full_messages.to_sentence, :unprocessable_entity, record.errors.to_hash
      end

      def page_params
        requested = params[:per].to_i
        { page: [params[:page].to_i, 1].max, per: requested.positive? ? [requested, 50].min : 20 }
      end

      def paginate(scope)
        paging = page_params
        records = scope.page(paging[:page]).per(paging[:per])
        [records, { page: records.current_page, per: paging[:per], total: records.total_count, last: records.last_page? }]
      end

      def serializer
        ApiSerializer
      end
    end
  end
end
