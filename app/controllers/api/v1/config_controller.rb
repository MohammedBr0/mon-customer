# frozen_string_literal: true

module Api
  module V1
    # Public settings the app needs before sign-in: currency, fees, vehicle questions, places.
    class ConfigController < BaseController
      skip_before_action :authenticate!

      def show
        setting = PlatformSetting.current
        render json: {
          currency: { code: setting.currency_code, symbol: setting.currency_symbol },
          fee: { percent: serializer.money(setting.fee_percent), charged_to: setting.fee_charged_to },
          max_price_per_seat: serializer.money(setting.max_price_per_seat),
          payment_instructions: setting.payment_instructions,
          phone_verification: AfroMessageClient.enabled?,
          commutes_enabled: setting.commutes_enabled, commute_horizon_days: setting.commute_horizon_days,
          announcement: (setting.announcement if setting.announcement_active?),
          payment_methods: PaymentMethod.active.ordered.map { |method| serializer.payment_method(method) },
          vehicle_fields: VehicleField.active.map { |field| serializer.vehicle_field(field) },
          popular_routes: PopularRoute.active.map { |route| { from: route.from_label, to: route.to_label } },
          places: EthiopianPlace.all.map(&:as_json),
          cities: EthiopianPlace.cities_with_areas.map { |city| city.as_json.merge(areas: EthiopianPlace.areas(city.key).map(&:as_json)) },
          languages: I18n.available_locales.map(&:to_s), api_version: 1
        }
      end
    end
  end
end
