# frozen_string_literal: true

class PagesController < ApplicationController
  skip_before_action :authenticate_user!

  def home
    redirect_to home_path_for(current_user) if user_signed_in?
  end
end
