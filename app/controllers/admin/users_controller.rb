# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show login_as ban unban verify unverify set_role]
    before_action :prevent_autoban, only: %i[ban unban]
    before_action :require_super_admin, only: %i[login_as set_role]

    def index
      @users = User.order(:name)
      @users = @users.where('users.name ILIKE :q OR users.email ILIKE :q OR users.phone ILIKE :q', q: "%#{User.sanitize_sql_like(params[:q].strip)}%") if params[:q].present?
      @users = @users.where(banned: true) if params[:filter] == 'banned'
      @users = @users.where.not(verified_at: nil) if params[:filter] == 'verified'
      @users = @users.where(verified_at: nil) if params[:filter] == 'unverified'
      @users = @users.where('users.admin OR users.moderator') if params[:filter] == 'staff'
      @users = @users.page params[:page]
    end

    def show
      @itineraries = @user.itineraries.order(created_at: :desc).limit(10)
      @bookings = @user.bookings.includes(:itinerary).order(created_at: :desc).limit(10)
      @reports_against = Report.where(reportable: @user).recent.limit(5)
    end

    def login_as
      audit!('user.login_as', @user)
      sign_in_and_redirect :user, @user
    end

    def ban
      if @user.update(banned: true)
        audit!('user.ban', @user)
        redirect_back_or_to admin_users_path, flash: { success: t('flash.admin.users.success.ban') }
      else
        redirect_back_or_to admin_users_path, flash: { error: t('flash.admin.users.error.ban') }
      end
    end

    def unban
      if @user.update(banned: false)
        audit!('user.unban', @user)
        redirect_back_or_to admin_users_path, flash: { success: t('flash.admin.users.success.unban') }
      else
        redirect_back_or_to admin_users_path, flash: { error: t('flash.admin.users.error.unban') }
      end
    end

    # Staff check a driver's licence and identity off-platform, then mark them verified.
    def verify
      @user.update!(verified_at: Time.current, verified_by: current_user)
      audit!('user.verify', @user)
      redirect_back_or_to admin_user_path(@user), flash: { success: t('flash.admin.users.verified') }
    end

    def unverify
      @user.update!(verified_at: nil, verified_by: nil)
      audit!('user.unverify', @user)
      redirect_back_or_to admin_user_path(@user), flash: { success: t('flash.admin.users.unverified') }
    end

    # Only a super admin changes roles, and never their own.
    def set_role
      return redirect_to(admin_user_path(@user), flash: { error: t('flash.admin.users.own_role') }) if @user == current_user

      role = params[:role].to_s
      return redirect_to(admin_user_path(@user), flash: { error: t('flash.errors.not_allowed') }) unless %w[user moderator admin].include?(role)

      from = @user.role_name
      @user.update!(admin: role == 'admin', moderator: role == 'moderator')
      audit!('user.role', @user, from:, to: @user.role_name)
      redirect_to admin_user_path(@user), flash: { success: t('flash.admin.users.role_changed') }
    end

    private

    def set_user
      @user = User.find params[:id]
    end

    def require_super_admin
      redirect_to admin_root_path, flash: { error: t('flash.errors.not_allowed') } unless current_user.super_admin?
    end

    def prevent_autoban
      redirect_to admin_users_path, flash: { error: t('flash.admin.users.error.ban') } if @user == current_user
    end
  end
end
