# frozen_string_literal: true

module Api
  module V1
    class MeController < BaseController
      def show
        render json: { user: serializer.me(current_user) }
      end

      def update
        if current_user.update(profile_params)
          render json: { user: serializer.me(current_user) }
        else
          render_invalid current_user
        end
      end

      def destroy
        current_user.destroy
        head :no_content
      end

      private

      def profile_params
        params.require(:user).permit(:time_zone, :locale, :vehicle_avg_consumption, :send_email_messages, :phone, vehicle_data: {})
      end
    end
  end
end
