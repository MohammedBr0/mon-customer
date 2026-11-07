# frozen_string_literal: true

module Admin
  # Routes shown as shortcuts on the landing page.
  class PopularRoutesController < SuperController
    before_action :set_route, only: %i[edit update destroy move]

    def index
      @routes = PopularRoute.ordered
    end

    def new
      @route = PopularRoute.new
    end

    def edit; end

    def create
      @route = PopularRoute.new(route_params)
      if @route.save
        audit!('popular_route.create', @route)
        redirect_to admin_popular_routes_path, flash: { success: t('flash.admin.popular_routes.saved') }
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @route.update(route_params)
        audit!('popular_route.update', @route)
        redirect_to admin_popular_routes_path, flash: { success: t('flash.admin.popular_routes.saved') }
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @route.destroy
      audit!('popular_route.destroy', @route)
      redirect_to admin_popular_routes_path, flash: { success: t('flash.admin.popular_routes.deleted') }
    end

    def move
      ordered = PopularRoute.ordered.to_a
      index = ordered.index(@route)
      swap_with = params[:direction] == 'up' ? index - 1 : index + 1
      if swap_with.between?(0, ordered.size - 1)
        ordered[index], ordered[swap_with] = ordered[swap_with], ordered[index]
        ordered.each_with_index { |route, position| route.update_columns(position:) }
      end
      redirect_to admin_popular_routes_path
    end

    private

    def set_route
      @route = PopularRoute.find(params[:id])
    end

    def route_params
      params.require(:popular_route).permit(:from_label, :to_label, :active)
    end
  end
end
