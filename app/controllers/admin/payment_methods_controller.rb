# frozen_string_literal: true

module Admin
  # Super admins decide which payment methods drivers can offer.
  class PaymentMethodsController < SuperController
    before_action :set_method, only: %i[edit update destroy]

    def index
      @methods = PaymentMethod.ordered
    end

    def new
      @method = PaymentMethod.new(active: true)
    end

    def edit; end

    def create
      @method = PaymentMethod.new(method_params)
      if @method.save
        audit!('payment_method.create', @method, name: @method.name)
        redirect_to admin_payment_methods_path, flash: { success: t('payments.flash.saved') }
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @method.update(method_params)
        audit!('payment_method.update', @method, name: @method.name)
        redirect_to admin_payment_methods_path, flash: { success: t('payments.flash.saved') }
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Deleting a method also removes it from every driver who accepted it. Switching it off keeps their details.
    def destroy
      @method.destroy
      audit!('payment_method.destroy', @method, name: @method.name)
      redirect_to admin_payment_methods_path, flash: { success: t('payments.flash.deleted') }
    end

    private

    def set_method
      @method = PaymentMethod.find(params[:id])
    end

    def method_params
      params.require(:payment_method).permit(:name, :name_am, :account_label, :active, :position)
    end
  end
end
