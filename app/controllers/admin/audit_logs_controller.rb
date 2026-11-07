# frozen_string_literal: true

module Admin
  class AuditLogsController < SuperController
    def index
      @logs = AuditLog.includes(:actor).recent
      @logs = @logs.where('audit_logs.action LIKE ?', "#{AuditLog.sanitize_sql_like(params[:prefix])}%") if params[:prefix].present?
      @logs = @logs.where(actor_id: params[:actor_id]) if params[:actor_id].present?
      @logs = @logs.page params[:page]
    end
  end
end
