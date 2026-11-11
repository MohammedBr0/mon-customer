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

      # Replaces the payment methods this driver accepts.
      def payment_methods
        entries = params.fetch(:methods, []).map { |entry| entry.permit(:id, :account_name, :account_number).to_h.symbolize_keys }
        DriverPaymentMethod.replace_for(current_user, entries)
        render json: { user: serializer.me(current_user.reload) }
      rescue ActiveRecord::RecordInvalid => e
        render_invalid e.record
      end

      # A new profile photo, for passengers and drivers alike.
      def avatar
        upload = params.require(:image)
        return render_error('invalid_request', I18n.t('api.identity_image'), :unprocessable_entity) unless upload.respond_to?(:read)

        Avatar.upload!(user: current_user, upload:)
        render json: { user: serializer.me(current_user.reload) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid e.record
      end

      def remove_avatar
        Avatar.remove!(current_user)
        render json: { user: serializer.me(current_user.reload) }
      end

      # Sends in a photo of a driving licence or national ID for staff to check.
      def identity
        upload = params.require(:image)
        return render_error('invalid_request', I18n.t('api.identity_image'), :unprocessable_entity) unless upload.respond_to?(:read)

        IdentityDocument.submit!(user: current_user, kind: params.require(:kind), number: params.require(:number), upload:)
        render json: { user: serializer.me(current_user.reload) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid e.record
      end

      private

      def profile_params
        params.require(:user).permit(:app_mode, :reminder_minutes, :time_zone, :locale, :vehicle_avg_consumption, :send_email_messages, :phone, vehicle_data: {})
      end
    end
  end
end
