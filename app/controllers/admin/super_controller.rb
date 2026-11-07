# frozen_string_literal: true

module Admin
  # Areas only a super admin may use: money, configuration, roles and the audit log.
  class SuperController < BaseController
    before_action :require_super_admin

    private

    def require_super_admin
      redirect_to admin_root_path, flash: { error: t('flash.errors.not_allowed') } unless current_user.super_admin?
    end
  end
end
