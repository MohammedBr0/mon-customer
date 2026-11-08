# frozen_string_literal: true

module Api
  module V1
    # The person's inbox. `after` returns only notifications newer than that id, which the app uses to poll.
    class NotificationsController < BaseController
      def index
        scope = current_user.notifications.recent
        scope = scope.where('id > ?', params[:after].to_i) if params[:after].present?
        records, meta = paginate(scope)
        render json: { notifications: records.map { |notification| ApiSerializer.notification(notification) }, meta:,
                       unread: current_user.notifications.unread.count }
      end

      def read
        current_user.notifications.find(params[:id]).then { |notification| notification.update!(read_at: Time.current) unless notification.read? }
        render json: { unread: current_user.notifications.unread.count }
      end

      def read_all
        current_user.notifications.unread.update_all(read_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        render json: { unread: 0 }
      end
    end
  end
end
