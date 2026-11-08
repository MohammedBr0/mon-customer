# frozen_string_literal: true

module Api
  module V1
    class RideAlertsController < BaseController
      def index
        render json: { ride_alerts: current_user.ride_alerts.order(created_at: :desc).map { |alert| serializer.ride_alert(alert) } }
      end

      def create
        start = place(:start)
        finish = place(:end)
        alert = current_user.ride_alerts.new(start_label: start[:label], end_label: finish[:label], start_location: [start[:lng], start[:lat]], end_location: [finish[:lng], finish[:lat]])
        if alert.save
          render json: { ride_alert: serializer.ride_alert(alert) }, status: :created
        else
          render_invalid alert
        end
      end

      def destroy
        current_user.ride_alerts.find(params[:id]).destroy
        head :no_content
      end

      private

      def place(side)
        raw = params.require(:ride_alert).fetch(side, {}).permit(:key, :name, :lat, :lng)
        known = EthiopianPlace.find(raw[:key]) if raw[:key].present?
        return { label: known.name, lat: known.lat, lng: known.lng } if known
        raise ActionController::ParameterMissing, "ride_alert.#{side}" if raw[:lat].blank? || raw[:lng].blank?

        { label: raw[:name].presence || EthiopianPlace.nearest(raw[:lat], raw[:lng]).name, lat: raw[:lat].to_f, lng: raw[:lng].to_f }
      end
    end
  end
end
