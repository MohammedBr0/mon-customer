# frozen_string_literal: true

class ReportsController < ApplicationController
  before_action :set_reportable

  def new
    @report = Report.new(reportable: @reportable)
  end

  def create
    @report = Report.new(report_params.merge(reporter: current_user, reportable: @reportable))
    if @report.save
      redirect_to root_path, flash: { success: t('flash.reports.created') }
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_reportable
    type = params.dig(:report, :reportable_type) || params[:type]
    id = params.dig(:report, :reportable_id) || params[:id]
    return redirect_to(root_path, flash: { error: t('flash.errors.not_allowed') }) unless Report::TYPES.include?(type)

    @reportable = type.constantize.find(id)
  end

  def report_params
    params.require(:report).permit(:reason, :details)
  end
end
