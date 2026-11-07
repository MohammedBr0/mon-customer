# frozen_string_literal: true

module Admin
  # Staff area: super admins and moderators.
  class BaseController < ::ApplicationController
    before_action :check_staff

    private

    def check_staff
      redirect_to root_path, flash: { error: t('flash.errors.not_allowed') } unless current_user.staff?
    end

    # Records what staff did, for the audit log.
    def audit!(action, subject = nil, details = {})
      AuditLog.record(current_user, action, subject, details)
    end
  end
end
