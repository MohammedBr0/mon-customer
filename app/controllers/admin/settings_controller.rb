# frozen_string_literal: true

module Admin
  # Platform fee and payment settings, editable by super admins.
  class SettingsController < BaseController
    before_action :set_setting

    def show; end

    def update
      if @setting.update(setting_params)
        redirect_to admin_settings_path, flash: { success: t('flash.admin.settings.updated') }
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_setting
      @setting = PlatformSetting.current
    end

    def setting_params
      params.require(:platform_setting).permit(:fee_percent, :fee_charged_to, :currency_code, :currency_symbol, :max_price_per_seat, :payment_instructions)
    end
  end
end
