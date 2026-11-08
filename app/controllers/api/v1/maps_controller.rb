# frozen_string_literal: true

module Api
  module V1
    # Place search, "what is here?" and route previews for the app's map screens (Google Places and Routes).
    class MapsController < BaseController
      LIMIT = 90
      WINDOW = 1.minute

      before_action :require_maps
      before_action :throttle!

      def search
        near = [params[:lat], params[:lng]].map { |value| Float(value, exception: false) }
        places = client.search(params.require(:q), near: near.all? ? near : nil)
        render json: { places: }
      end

      def reverse
        render json: { place: client.reverse(params.require(:lat), params.require(:lng)) }
      end

      def route
        route = client.route(origin: params.require(:from), destination: params.require(:to))
        render json: { route: route.slice(:distance_text, :distance_value, :duration_text, :duration_value, :overview_polyline) }
      rescue GoogleMapsClient::Error => e
        raise unless %w[not_found zero_results].include?(e.message)

        render_error 'no_route', I18n.t('api.no_route'), :unprocessable_entity
      end

      rescue_from GoogleMapsClient::Error do |error|
        render_error 'maps_unavailable', I18n.t('api.maps_unavailable'), :bad_gateway if error.message != 'not_configured'
      end

      private

      def client
        @client ||= GoogleMapsClient.new
      end

      def require_maps
        render_error 'maps_unavailable', I18n.t('api.maps_unavailable'), :service_unavailable unless GoogleMapsClient.enabled?
      end

      # Each lookup costs money, so one person gets a generous but finite number a minute.
      def throttle!
        key = "maps:#{current_user.id}"
        count = Rails.cache.increment(key, 1, expires_in: WINDOW) || (Rails.cache.write(key, 1, expires_in: WINDOW) && 1)
        render_error 'rate_limited', I18n.t('api.rate_limited'), :too_many_requests if count.to_i > LIMIT
      end
    end
  end
end
