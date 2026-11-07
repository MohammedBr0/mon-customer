# frozen_string_literal: true

class ReviewsController < ApplicationController
  before_action :set_booking
  before_action :require_reviewable

  def new
    @review = Review.new(booking: @booking)
  end

  def create
    @review = Review.new(review_params.merge(booking: @booking, reviewer: current_user, reviewee: @booking.counterpart_of(current_user)))
    if @review.save
      redirect_to user_path(@review.reviewee), flash: { success: t('flash.reviews.created') }
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_booking
    @booking = Booking.includes(:itinerary, :passenger).find(params[:booking_id])
    redirect_to root_path, flash: { error: t('flash.errors.not_allowed') } unless @booking.participant?(current_user)
  end

  def require_reviewable
    return if performed?

    if !@booking.completed?
      redirect_to bookings_path, flash: { error: t('flash.reviews.not_completed') }
    elsif @booking.reviewed_by?(current_user)
      redirect_to bookings_path, flash: { error: t('flash.reviews.already_reviewed') }
    end
  end

  def review_params
    params.require(:review).permit(:rating, :comment)
  end
end
