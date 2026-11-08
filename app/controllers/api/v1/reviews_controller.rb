# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < BaseController
      def create
        booking = Booking.includes(:itinerary, :passenger).find(params[:booking_id])
        return render_error('forbidden', I18n.t('flash.errors.not_allowed'), :forbidden) unless booking.participant?(current_user)
        return render_error('not_completed', I18n.t('flash.reviews.not_completed'), :unprocessable_entity) unless booking.completed?
        return render_error('already_reviewed', I18n.t('flash.reviews.already_reviewed'), :unprocessable_entity) if booking.reviewed_by?(current_user)

        review = Review.new(params.require(:review).permit(:rating, :comment).merge(booking:, reviewer: current_user, reviewee: booking.counterpart_of(current_user)))
        if review.save
          render json: { review: { id: review.id, rating: review.rating, comment: review.comment } }, status: :created
        else
          render_invalid review
        end
      end
    end
  end
end
