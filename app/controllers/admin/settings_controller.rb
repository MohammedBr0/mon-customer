# frozen_string_literal: true

module Admin
  # Platform fee and payment settings, editable by super admins.
  class SettingsController < SuperController
    before_action :set_setting

    def show; end

    def update
      @setting.assign_attributes(setting_params)
      changes = @setting.changes.transform_values { |(from, to)| { from:, to: } }
      if @setting.save
        audit!('settings.update', nil, changes)
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
      params.require(:platform_setting).permit(:fee_percent, :fee_charged_to, :currency_code, :currency_symbol, :max_price_per_seat, :payment_instructions,
                                               :announcement, :announcement_active, :commutes_enabled, :commute_horizon_days)
    end
  end
end
