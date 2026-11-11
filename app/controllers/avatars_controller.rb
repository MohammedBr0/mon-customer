# frozen_string_literal: true

# Serves profile photos. Public on purpose: they appear next to people's names throughout the service.
class AvatarsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    avatar = Avatar.find_by!(user_id: params[:id])
    expires_in 1.day, public: true
    send_data avatar.image, type: avatar.content_type, disposition: 'inline' if stale?(avatar, public: true)
  end
end
