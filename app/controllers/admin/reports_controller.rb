# frozen_string_literal: true

module Admin
  class ReportsController < BaseController
    before_action :set_report, only: %i[show resolve]

    def index
      @status = Report::STATUSES.include?(params[:status]) ? params[:status] : 'open'
      @reports = Report.where(status: @status).includes(:reporter, :reportable).recent.page params[:page]
    end

    def show; end

    # Optionally acts on the reported item at the same time.
    def resolve
      status = params[:outcome] == 'dismiss' ? 'dismissed' : 'resolved'
      take_action(params[:action_taken].to_s)
      @report.resolve!(by: current_user, status:, note: params[:note])
      audit!("report.#{status}", @report, action_taken: params[:action_taken].presence, note: params[:note].presence)
      redirect_to admin_reports_path, flash: { success: t('flash.admin.reports.resolved') }
    end

    private

    def set_report
      @report = Report.find(params[:id])
    end

    def take_action(action)
      item = @report.reportable
      case action
      when 'cancel_trip' then item.cancel! if item.is_a?(Itinerary) && !item.cancelled?
      when 'ban_user' then reported_user&.update!(banned: true) unless reported_user == current_user
      when 'hide_review' then item.update!(hidden_at: Time.current) if item.is_a?(Review)
      end
    end

    def reported_user
      item = @report.reportable
      case item
      when User then item
      when Itinerary then item.user
      when Review then item.reviewer
      end
    end
  end
end
