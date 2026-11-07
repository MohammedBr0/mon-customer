# frozen_string_literal: true

class BookingsController < ApplicationController
  before_action :set_booking, only: %i[confirm decline cancel skip_date]
  before_action :require_driver, only: %i[confirm decline]
  before_action :require_participant, only: %i[cancel skip_date]

  def index
    @bookings = current_user.bookings.includes(itinerary: :user).order(created_at: :desc)
    @requests = Booking.joins(:itinerary).where(itineraries: { user_id: current_user.id })
                       .includes(:passenger, :itinerary).order(created_at: :desc)
  end

  def create
    @itinerary = Itinerary.friendly.find(params[:itinerary_id])
    return deny unless @itinerary.bookable_by?(current_user)

    booking = @itinerary.bookings.new(booking_params.merge(passenger: current_user))
    if booking.save
      BookingMailer.with(booking:).requested.deliver_later
      redirect_to itinerary_path(@itinerary), flash: { success: t('flash.bookings.created') }
    else
      redirect_to itinerary_path(@itinerary), flash: { error: booking.errors.full_messages.to_sentence }
    end
  end

  def confirm
    transition(:confirm!, :confirmed, 'flash.bookings.confirmed')
  end

  def decline
    transition(:decline!, :declined, 'flash.bookings.declined')
  end

  def cancel
    @booking.cancel!(by: current_user)
    BookingMailer.with(booking: @booking).cancelled.deliver_later
    redirect_back_or_to bookings_path, flash: { success: t('flash.bookings.cancelled') }
  rescue Booking::InvalidTransition
    redirect_back_or_to bookings_path, flash: { error: t('flash.bookings.invalid') }
  end

  # A commuter (or the driver) drops a single day from a multi-day booking.
  def skip_date
    date = Date.iso8601(params[:date].to_s)
    @booking.skip_date!(date, by: current_user)
    BookingMailer.with(booking: @booking, date:, by: current_user).date_skipped.deliver_later
    redirect_back_or_to bookings_path, flash: { success: t('flash.bookings.date_skipped') }
  rescue ArgumentError, Booking::InvalidTransition
    redirect_back_or_to bookings_path, flash: { error: t('flash.bookings.invalid') }
  end

  private

  def set_booking
    @booking = Booking.includes(:itinerary, :passenger).find(params[:id])
  end

  def require_driver
    deny unless @booking.driver == current_user
  end

  def require_participant
    deny unless @booking.participant?(current_user)
  end

  def deny
    redirect_to root_path, flash: { error: t('flash.errors.not_allowed') }
  end

  def transition(action, mail, success_key)
    @booking.public_send(action)
    BookingMailer.with(booking: @booking).public_send(mail).deliver_later
    redirect_back_or_to bookings_path, flash: { success: t(success_key) }
  rescue Booking::InvalidTransition => e
    key = e.message == 'not_enough_seats' ? 'flash.bookings.not_enough_seats' : 'flash.bookings.invalid'
    redirect_back_or_to bookings_path, flash: { error: t(key) }
  end

  def booking_params
    params.fetch(:booking, {}).permit(:seats, :note, ride_dates: [])
  end
end
