# frozen_string_literal: true

require 'csv'

module Admin
  # Every booking on the platform. Staff can step in; the CSV export carries money, so it is for super admins.
  class BookingsController < BaseController
    before_action :require_super_admin_for_export, only: :index

    def index
      @bookings = filtered_bookings.includes(:passenger, itinerary: :user).order(created_at: :desc)
      respond_to do |format|
        format.html { @bookings = @bookings.page params[:page] }
        format.csv do
          audit!('bookings.export', nil, filter: params.permit(:status, :from, :to, :q).to_h)
          send_data bookings_csv(@bookings), filename: "bookings-#{Date.current}.csv", type: 'text/csv'
        end
      end
    end

    def cancel
      booking = Booking.find(params[:id])
      booking.cancel!(by: current_user)
      audit!('booking.cancel', booking, trip: booking.itinerary.title)
      BookingMailer.with(booking:).cancelled.deliver_later
      redirect_back_or_to admin_bookings_path, flash: { success: t('flash.bookings.cancelled') }
    rescue Booking::InvalidTransition
      redirect_back_or_to admin_bookings_path, flash: { error: t('flash.bookings.invalid') }
    end

    private

    # The export carries money and phone numbers, so only super admins may download it.
    def require_super_admin_for_export
      return unless request.format.csv? && !current_user.super_admin?

      redirect_to admin_bookings_path(format: :html), flash: { error: t('flash.errors.not_allowed') }
    end

    def filtered_bookings
      scope = Booking.all
      scope = scope.where(status: params[:status]) if Booking::STATUSES.include?(params[:status])
      scope = scope.where(created_at: Date.parse(params[:from]).beginning_of_day..) if params[:from].present?
      scope = scope.where(created_at: ..Date.parse(params[:to]).end_of_day) if params[:to].present?
      if params[:q].present?
        like = "%#{Booking.sanitize_sql_like(params[:q].strip)}%"
        scope = scope.joins(:passenger, :itinerary).where('users.name ILIKE :q OR users.email ILIKE :q OR itineraries.start_address ILIKE :q OR itineraries.end_address ILIKE :q', q: like)
      end
      scope
    rescue ArgumentError
      Booking.none
    end

    def bookings_csv(bookings)
      CSV.generate do |csv|
        csv << %w[id created_at status trip driver driver_phone passenger passenger_phone seats days fare fee_percent fee_charged_to fee passenger_total driver_payout]
        bookings.find_each do |booking|
          csv << [booking.id, booking.created_at.iso8601, booking.status, booking.itinerary.title, booking.driver.to_s, booking.driver.phone,
                  booking.passenger.to_s, booking.passenger.phone, booking.seats, booking.ride_dates.size, booking.fare_total, booking.fee_percent,
                  booking.fee_charged_to, booking.fee_amount, booking.passenger_total, booking.driver_payout]
        end
      end
    end
  end
end
