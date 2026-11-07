# frozen_string_literal: true

module Admin
  # Super admins decide which vehicle details drivers are asked for.
  class VehicleFieldsController < BaseController
    before_action :set_field, only: %i[edit update destroy move]

    def index
      @fields = VehicleField.ordered
    end

    def new
      @field = VehicleField.new(field_type: 'text', visibility: 'public')
    end

    def edit; end

    def create
      @field = VehicleField.new(field_params)
      if @field.save
        redirect_to admin_vehicle_fields_path, flash: { success: t('flash.admin.vehicle_fields.created') }
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @field.update(field_params.except(:key))
        redirect_to admin_vehicle_fields_path, flash: { success: t('flash.admin.vehicle_fields.updated') }
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Removing a field also removes the answers drivers gave for it the next time they save.
    def destroy
      @field.destroy
      redirect_to admin_vehicle_fields_path, flash: { success: t('flash.admin.vehicle_fields.destroyed') }
    end

    def move
      ordered = VehicleField.ordered.to_a
      index = ordered.index(@field)
      swap_with = params[:direction] == 'up' ? index - 1 : index + 1
      if swap_with.between?(0, ordered.size - 1)
        ordered[index], ordered[swap_with] = ordered[swap_with], ordered[index]
        ordered.each_with_index { |field, position| field.update_columns(position:) }
      end
      redirect_to admin_vehicle_fields_path
    end

    private

    def set_field
      @field = VehicleField.find(params[:id])
    end

    def field_params
      params.require(:vehicle_field).permit(:key, :label, :am, :it, :field_type, :options_text, :required, :visibility, :help_text, :min_value, :max_value, :active)
    end
  end
end
