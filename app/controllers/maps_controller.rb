# frozen_string_literal: true

# Lets the trip form and the search box use Google's Places and Routes through the server.
class MapsController < ApplicationController
  before_action :require_maps

  def geocode
    place = GoogleMapsClient.new.geocode(params.require(:q))
    place ? render(json: place) : render(json: { error: 'not_found' }, status: :not_found)
  rescue GoogleMapsClient::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def route
    result = GoogleMapsClient.new.route(origin: params.require(:origin), destination: params.require(:destination),
                                        avoid_highways: params[:avoid_highways] == 'true', avoid_tolls: params[:avoid_tolls] == 'true')
    render json: result
  rescue GoogleMapsClient::Error => e
    render json: { error: e.message }, status: (%w[not_found zero_results].include?(e.message) ? :not_found : :bad_gateway)
  end

  private

  def require_maps
    render json: { error: 'not_configured' }, status: :service_unavailable unless GoogleMapsClient.enabled?
  end
end
