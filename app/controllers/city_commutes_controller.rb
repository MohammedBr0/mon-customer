# frozen_string_literal: true

# Daily rides inside one city. Works from a list of neighbourhoods, so it needs no map.
class CityCommutesController < ApplicationController
  def index
    @cities = EthiopianPlace.cities_with_areas
    @city = @cities.find { |city| city.key == params[:city] } || @cities.first
    @areas = EthiopianPlace.areas(@city.key)
    @itineraries = CityCommuteSearch.call(city: @city.key, from: params[:from], to: params[:to], seats: params[:seats], sort: params[:sort], user: current_user)
                                    .page(params[:page]).per(20)
  end

  def new
    @cities = EthiopianPlace.cities_with_areas
    @city = @cities.find { |city| city.key == params[:city] } || @cities.first
    @itinerary = Itinerary.new(city: @city.key, num_people: 3)
  end

  def create
    @cities = EthiopianPlace.cities_with_areas
    @itinerary = current_user.itineraries.new(commute_params)
    @itinerary.use_city_areas(city: params[:city], from: params[:from_area], to: params[:to_area])
    @itinerary.leave_date = first_departure
    @city = @cities.find { |city| city.key == @itinerary.city } || @cities.first
    if @itinerary.save
      RideAlertMatchJob.perform_later(@itinerary)
      redirect_to itinerary_path(@itinerary), flash: { success: t('city.created') }
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def commute_params
    permitted = params.require(:itinerary).permit(:price_per_seat, :num_people, :pickup_point, :dropoff_point, :description, :smoking_allowed, :pets_allowed, :commute_until, commute_days: [])
    permitted[:pink] = params[:itinerary][:pink] if current_user.female?
    permitted
  end

  # The first ride: the chosen date (or today) at the chosen time, in Ethiopian time.
  def first_departure
    date = Date.iso8601(params[:start_date].to_s)
    hour, minute = params[:time].to_s.split(':').map(&:to_i)
    Itinerary::RIDE_ZONE.local(date.year, date.month, date.day, hour || 7, minute || 0)
  rescue ArgumentError
    nil
  end
end
