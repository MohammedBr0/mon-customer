# frozen_string_literal: true

module Api
  module V1
    class ItinerariesController < BaseController
      before_action :set_itinerary, only: %i[show cancel update]
      before_action :require_owner, only: %i[cancel update]

      # Search by route (coordinates) or list the latest trips.
      def index
        records, meta = paginate(searching? ? search_scope : latest_scope)
        render json: { itineraries: records.map { |itinerary| serializer.itinerary(itinerary, viewer: current_user) }, meta: }
      end

      def mine
        records, meta = paginate(current_user.itineraries.includes(:user).order(created_at: :desc))
        render json: { itineraries: records.map { |itinerary| serializer.itinerary(itinerary, viewer: current_user) }, meta: }
      end

      def show
        return render_error('forbidden', I18n.t('flash.errors.not_allowed'), :forbidden) if @itinerary.pink? && !current_user.female? && @itinerary.user != current_user

        render json: { itinerary: serializer.itinerary(@itinerary, viewer: current_user, detail: true) }
      end

      def create
        itinerary = current_user.itineraries.new(trip_attributes)
        itinerary.route = RouteBuilder.call(from: coordinates(:start), to: coordinates(:end))
        if itinerary.save
          RideAlertMatchJob.perform_later(itinerary)
          render json: { itinerary: serializer.itinerary(itinerary, viewer: current_user, detail: true) }, status: :created
        else
          render_invalid itinerary
        end
      end

      def update
        if @itinerary.update(params.require(:itinerary).permit(:description, :price_per_seat, :pickup_point, :dropoff_point, :smoking_allowed, :pets_allowed))
          render json: { itinerary: serializer.itinerary(@itinerary, viewer: current_user, detail: true) }
        else
          render_invalid @itinerary
        end
      end

      def cancel
        bookings = @itinerary.bookings.active.includes(:passenger).to_a
        @itinerary.cancel!
        bookings.each { |booking| ItineraryMailer.with(booking:).cancelled.deliver_later }
        render json: { itinerary: serializer.itinerary(@itinerary, viewer: current_user, detail: true) }
      end

      private

      def set_itinerary
        @itinerary = Itinerary.friendly.find(params[:id])
      end

      def require_owner
        render_error('forbidden', I18n.t('flash.errors.not_allowed'), :forbidden) unless @itinerary.user == current_user
      end

      def searching?
        %i[start_lat start_lng end_lat end_lng].all? { |key| params[key].present? }
      end

      def search_scope
        criteria = {
          start_location_lat: params[:start_lat], start_location_lng: params[:start_lng], end_location_lat: params[:end_lat], end_location_lng: params[:end_lng],
          seats: params[:seats], sort: params[:sort], filter_round_trip: (params[:round_trip] == 'true' ? '1' : nil), filter_pink: (params[:pink] == 'true' ? '1' : nil),
          filter_smoking_allowed: params[:smoking_allowed].presence, filter_pets_allowed: params[:pets_allowed].presence, filter_driver_gender: params[:driver_gender].presence
        }.compact_blank.with_indifferent_access
        ItinerarySearch.call(criteria, current_user).itineraries.includes(:user)
      end

      def latest_scope
        scope = Itinerary.not_cancelled.upcoming_or_commute.includes(:user).order(created_at: :desc)
        current_user.female? ? scope : scope.where(pink: false)
      end

      def trip_attributes
        permitted = params.require(:itinerary).permit(:start_address, :end_address, :description, :leave_date, :return_date, :round_trip, :price_per_seat, :num_people,
                                                      :commute_until, :pickup_point, :dropoff_point, :smoking_allowed, :pets_allowed, :pink, commute_days: [])
        permitted[:start_address] ||= place_name(:start)
        permitted[:end_address] ||= place_name(:end)
        permitted.delete(:pink) unless current_user.female?
        permitted
      end

      # A place is either a known place key, or explicit coordinates.
      def place_param(side)
        params.require(:itinerary).fetch(side, {}).permit(:key, :name, :lat, :lng)
      end

      def coordinates(side)
        place = place_param(side)
        known = EthiopianPlace.find(place[:key]) if place[:key].present?
        return [known.lat, known.lng] if known

        raise ActionController::ParameterMissing, "itinerary.#{side}" if place[:lat].blank? || place[:lng].blank?

        [place[:lat].to_f, place[:lng].to_f]
      end

      def place_name(side)
        place = place_param(side)
        place[:name].presence || EthiopianPlace.find(place[:key])&.name
      end
    end
  end
end
