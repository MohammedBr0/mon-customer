# frozen_string_literal: true

module Api
  module V1
    class BookingsController < BaseController
      before_action :set_booking, only: %i[confirm decline cancel skip_date complete]
      before_action :require_driver, only: %i[confirm decline]
      before_action :require_participant, only: %i[cancel skip_date]
      before_action :settle_due, only: :index

      # Both directions: seats I asked for, and requests for my trips.
      def index
        made = current_user.bookings.includes(itinerary: :user).order(created_at: :desc)
        received = Booking.joins(:itinerary).where(itineraries: { user_id: current_user.id }).includes(:passenger, itinerary: :user).order(created_at: :desc)
        render json: { made:     made.limit(100).map { |booking| serializer.booking(booking, viewer: current_user) },
                       received: received.limit(100).map { |booking| serializer.booking(booking, viewer: current_user) } }
      end

      def create
        itinerary = Itinerary.friendly.find(params[:itinerary_id])
        return render_error('not_bookable', I18n.t('flash.errors.not_allowed'), :forbidden) unless itinerary.bookable_by?(current_user)

        booking = itinerary.bookings.new(booking_params.merge(passenger: current_user).merge(pickup_params))
        booking.payment_method = params.dig(:booking, :payment_method) == 'wallet' ? 'wallet' : 'cash'
        if booking.save
          BookingMailer.with(booking:).requested.deliver_later
          render json: { booking: serializer.booking(booking, viewer: current_user) }, status: :created
        else
          render_invalid booking
        end
      rescue Wallet::InsufficientFunds
        render_error 'insufficient_funds', I18n.t('wallet.errors.insufficient'), :unprocessable_entity
      end

      # The passenger says the ride went well: the driver is paid straight away.
      def complete
        return render_error('forbidden', I18n.t('flash.errors.not_allowed'), :forbidden) unless @booking.passenger_id == current_user.id

        @booking.confirm_completed!
        render json: { booking: serializer.booking(@booking.reload, viewer: current_user) }
      rescue Booking::InvalidTransition
        render_error 'invalid_transition', I18n.t('flash.bookings.invalid'), :unprocessable_entity
      end

      def confirm
        transition(:confirm!, :confirmed)
      end

      def decline
        transition(:decline!, :declined)
      end

      def cancel
        @booking.cancel!(by: current_user)
        BookingMailer.with(booking: @booking).cancelled.deliver_later
        render json: { booking: serializer.booking(@booking, viewer: current_user) }
      rescue Booking::InvalidTransition
        render_error 'invalid_transition', I18n.t('flash.bookings.invalid'), :unprocessable_entity
      end

      def skip_date
        date = Date.iso8601(params.require(:date).to_s)
        @booking.skip_date!(date, by: current_user)
        BookingMailer.with(booking: @booking, date:, by: current_user).date_skipped.deliver_later
        render json: { booking: serializer.booking(@booking, viewer: current_user) }
      rescue ArgumentError, Booking::InvalidTransition
        render_error 'invalid_transition', I18n.t('flash.bookings.invalid'), :unprocessable_entity
      end

      private

      # There is no background worker, so payments that have come due are released when someone opens their bookings.
      def settle_due
        BookingPayment.settle_due!(Booking.where(passenger: current_user).or(Booking.where(itinerary_id: current_user.itineraries.select(:id))))
      end

      def set_booking
        @booking = Booking.includes(:itinerary, :passenger).find(params[:id])
      end

      def require_driver
        render_error('forbidden', I18n.t('flash.errors.not_allowed'), :forbidden) unless @booking.driver == current_user
      end

      def require_participant
        render_error('forbidden', I18n.t('flash.errors.not_allowed'), :forbidden) unless @booking.participant?(current_user)
      end

      def transition(action, mail)
        @booking.public_send(action)
        BookingMailer.with(booking: @booking).public_send(mail).deliver_later
        render json: { booking: serializer.booking(@booking, viewer: current_user) }
      rescue Booking::InvalidTransition => e
        key = e.message == 'not_enough_seats' ? 'flash.bookings.not_enough_seats' : 'flash.bookings.invalid'
        render_error e.message, I18n.t(key), :unprocessable_entity
      end

      # Where the passenger would like to be picked up (optional): shown to the driver with the request.
      def pickup_params
        pickup = params.dig(:booking, :pickup)
        return {} unless pickup.respond_to?(:permit) && pickup[:lat].present? && pickup[:lng].present?

        { pickup_lat: pickup[:lat], pickup_lng: pickup[:lng], pickup_label: pickup[:label].to_s.strip.presence }
      end

      def booking_params
        params.fetch(:booking, {}).permit(:seats, :note, ride_dates: [])
      end
    end
  end
end
