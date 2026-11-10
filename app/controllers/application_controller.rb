# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include RouteLocalizer

  protect_from_forgery with: :exception

  before_action :authenticate_user!
  before_action :check_banned, except: [:banned], if: :user_signed_in?

  around_action :localize_route
  around_action :time_zone_from_user, if: -> { user_signed_in? && current_user.time_zone? }

  def banned; end

  private

  def after_sign_in_path_for(_resource_or_scope)
    session.delete(:redirect_to) || home_path_for(current_user)
  end

  # Where someone lands by default: super admins on the admin dashboard, everyone else on their own.
  def home_path_for(user)
    user&.super_admin? ? admin_root_path : dashboard_path
  end

  def check_banned
    redirect_to :banned if current_user.banned?
  end

  def time_zone_from_user(&block)
    Time.use_zone current_user.time_zone, &block
  end
end
