# frozen_string_literal: true

# Finds trips that stay inside one city. Riders pick neighbourhoods (or just the city); a trip matches when it
# starts and ends within a short walk of the chosen neighbourhoods, in the direction of travel.
class CityCommuteSearch
  RADIUS_METERS = 2500
  NEAR = 'ST_DWithin(itineraries.%<column>s, Geography(ST_MakePoint(:%<prefix>s_lng, :%<prefix>s_lat)), :meters)'
  TIME_OF_DAY = "((itineraries.leave_date AT TIME ZONE 'Africa/Addis_Ababa')::time)"

  def self.call(city:, from: nil, to: nil, seats: 1, sort: nil, user: nil)
    new(city:, from:, to:, seats:, sort:, user:).call
  end

  def initialize(city:, from:, to:, seats:, sort:, user:)
    @city = city.to_s
    @from = EthiopianPlace.find(from) if from.present?
    @to = EthiopianPlace.find(to) if to.present?
    @seats = seats.to_i.clamp(1, Booking::MAX_SEATS)
    @sort = sort.to_s
    @user = user
  end

  def call
    scope = Itinerary.not_cancelled.upcoming_or_commute.where(city: @city).includes(:user)
    scope = scope.where(ItinerarySearch::SEATS_CONDITION, seats: @seats)
    scope = scope.where(pink: false) unless @user&.female?
    scope = near(scope, @from, :start_location, :start) if @from
    scope = near(scope, @to, :end_location, :end) if @to
    @sort == 'price' ? scope.order(:price_per_seat, Arel.sql(TIME_OF_DAY)) : scope.order(Arel.sql(TIME_OF_DAY), :price_per_seat)
  end

  private

  def near(scope, place, column, prefix)
    scope.where(format(NEAR, column:, prefix:), "#{prefix}_lat": place.lat, "#{prefix}_lng": place.lng, meters: RADIUS_METERS)
  end
end
