# frozen_string_literal: true

module Api
  module V1
    class ReportsController < BaseController
      def create
        type = params.require(:type)
        return render_error('invalid_request', I18n.t('flash.errors.not_allowed'), :unprocessable_entity) unless Report::TYPES.include?(type)

        report = Report.new(reporter: current_user, reportable: type.constantize.find(params.require(:id)), reason: params[:reason], details: params[:details])
        if report.save
          render json: { report: { id: report.id, status: report.status } }, status: :created
        else
          render_invalid report
        end
      end
    end
  end
end
