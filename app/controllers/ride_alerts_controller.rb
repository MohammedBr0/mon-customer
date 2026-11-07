# frozen_string_literal: true

class RideAlertsController < ApplicationController
  def index
    @alerts = current_user.ride_alerts.order(created_at: :desc)
  end

  # Called from the search page (JSON) with the route the person just searched for.
  def create
    alert = RideAlert.from_search(current_user, params.require(:ride_alert).permit(:from, :to, :start_location_lng, :start_location_lat, :end_location_lng, :end_location_lat))
    if alert.save
      respond_to do |format|
        format.json { render json: { message: t('flash.alerts.created') }, status: :created }
        format.html { redirect_to ride_alerts_path, flash: { success: t('flash.alerts.created') } }
      end
    else
      respond_to do |format|
        format.json { render json: { message: alert.errors.full_messages.to_sentence }, status: :unprocessable_entity }
        format.html { redirect_to ride_alerts_path, flash: { error: alert.errors.full_messages.to_sentence } }
      end
    end
  end

  def destroy
    current_user.ride_alerts.find(params[:id]).destroy
    redirect_to ride_alerts_path, flash: { success: t('flash.alerts.destroyed') }
  end
end
