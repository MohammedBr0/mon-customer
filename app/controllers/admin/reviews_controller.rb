# frozen_string_literal: true

module Admin
  class ReviewsController < BaseController
    def index
      @reviews = Review.includes(:reviewer, :reviewee).order(created_at: :desc)
      @reviews = @reviews.where.not(hidden_at: nil) if params[:filter] == 'hidden'
      @reviews = @reviews.where(rating: ..2) if params[:filter] == 'low'
      @reviews = @reviews.page params[:page]
    end

    def hide
      review = Review.find(params[:id])
      review.update!(hidden_at: Time.current)
      audit!('review.hide', review, rating: review.rating)
      redirect_back_or_to admin_reviews_path, flash: { success: t('flash.admin.reviews.hidden') }
    end

    def unhide
      review = Review.find(params[:id])
      review.update!(hidden_at: nil)
      audit!('review.unhide', review)
      redirect_back_or_to admin_reviews_path, flash: { success: t('flash.admin.reviews.unhidden') }
    end
  end
end
