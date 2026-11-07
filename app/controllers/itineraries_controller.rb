# frozen_string_literal: true

class ItinerariesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]

  before_action :set_itinerary, only: [:show]
  before_action :check_female, only: [:show]

  before_action :check_permissions

  def index
    # @itineraries = Itinerary.includes(:user).all
  end

  def show
    if current_user
      @conversation = @itinerary.conversations.find_or_initialize_by(sender: current_user, receiver: @itinerary.user)
      @my_booking = @itinerary.bookings.where(passenger: current_user).order(created_at: :desc).first
      @driver_bookings = @itinerary.bookings.includes(:passenger).order(:created_at) if current_user == @itinerary.user
    end
    session[:redirect_to] = itinerary_path(@itinerary) unless user_signed_in?
  end

  def new
    @itinerary = Itinerary.new
  end

  def edit
    @itinerary = current_user.itineraries.friendly.find params[:id]
  end

  def create
    @itinerary = current_user.itineraries.new(itinerary_params)
    if @itinerary.save
      redirect_to itinerary_path(@itinerary), flash: { success: t('flash.itineraries.success.create') }
    else
      render :new
    end
  end

  def update
    @itinerary = current_user.itineraries.friendly.find params[:id]
    if @itinerary.update itinerary_params
      redirect_to itinerary_path(@itinerary), flash: { success: t('flash.itineraries.success.update') }
    else
      render :edit
    end
  end

  def destroy
    @itinerary = current_user.itineraries.friendly.find params[:id]
    @itinerary.destroy
    redirect_to itineraries_user_path(current_user), flash: { success: t('flash.itineraries.success.destroy') }
  end

  def cancel
    @itinerary = current_user.itineraries.friendly.find params[:id]
    bookings = @itinerary.bookings.active.includes(:passenger).to_a
    @itinerary.cancel!
    bookings.each { |booking| ItineraryMailer.with(booking:).cancelled.deliver_later }
    redirect_to itinerary_path(@itinerary), flash: { success: t('flash.itineraries.success.cancel') }
  end

  def search
    @itineraries = ItinerarySearch.call(params[:itineraries_search], current_user).itineraries
  end

  protected

  def check_permissions; end

  def set_itinerary
    @itinerary = Itinerary.friendly.find params[:id]
  end

  def itinerary_params
    params.require(:itinerary).permit(*itinerary_attributes)
  end

  def itinerary_attributes
    allowlist = %i[start_address end_address description num_people smoking_allowed pets_allowed price_per_seat
                   avoid_highways avoid_tolls
                   round_trip leave_date return_date daily
                   route]
    allowlist << :pink if current_user&.female?
    allowlist
  end

  def check_female
    return unless @itinerary.pink?

    if !user_signed_in?
      redirect_to root_path
    elsif !current_user.female?
      redirect_to :dashboard, flash: { error: t('flash.itineraries.error.pink') }
    end
  end
end
