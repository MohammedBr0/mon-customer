# frozen_string_literal: true

# A driver's vehicle and contact details. The vehicle questions are configured by super admins
# (VehicleField); the answers are stored in `vehicle_data`.
module VehicleDetails
  extend ActiveSupport::Concern

  ETHIOPIAN_PHONE = /\A\+251[79]\d{8}\z/
  DESCRIPTION_KEYS = %w[color make model].freeze

  included do
    self.ignored_columns += %w[car_make car_model car_color car_plate]

    before_validation :sanitize_vehicle_data
    before_validation :normalize_phone
    validate :vehicle_data_matches_fields
    # The condition keeps this server-side only: the browser would test the raw text ("0911 22 33 44")
    # before normalize_phone turns it into +251911223344, and wrongly block valid numbers.
    validates :phone, format: { with: ETHIOPIAN_PHONE, message: :invalid_ethiopian_phone }, if: -> { phone.present? }
  end

  def vehicle_value(key)
    vehicle_data[key.to_s]
  end

  # Fields the viewer may see: public ones, plus "confirmed" ones when they share a confirmed booking.
  def visible_vehicle_details(confirmed: false)
    VehicleField.active.filter_map do |field|
      next if field.visibility == 'private' || (field.visibility == 'confirmed' && !confirmed)

      value = field.display_value(vehicle_value(field.key))
      [field, value] if value.present?
    end
  end

  # Short text such as "Red Toyota Corolla".
  def vehicle_description
    values = DESCRIPTION_KEYS.filter_map { |key| vehicle_value(key).presence }
    values.join(' ').presence
  end

  def missing_vehicle_fields
    VehicleField.active.select { |field| field.required? && vehicle_value(field.key).blank? }
  end

  def vehicle_complete?
    missing_vehicle_fields.empty?
  end

  private

  # Keeps only answers for fields that still exist, cast to their type.
  def sanitize_vehicle_data
    raw = (self[:vehicle_data] || {}).to_h.stringify_keys
    self.vehicle_data = VehicleField.active.each_with_object({}) do |field, data|
      value = field.cast(raw[field.key])
      data[field.key] = value unless value.nil?
    end
  end

  def vehicle_data_matches_fields
    VehicleField.active.each do |field|
      value = vehicle_value(field.key)
      # Required answers are enforced when posting a trip, not when saving a profile.
      reason = field.error_for(value)
      errors.add(:base, :vehicle_field_invalid, field: field.label_for, reason: I18n.t("vehicle.errors.#{reason}")) if reason && reason != :blank
    end
  end

  def normalize_phone
    return if phone.blank?

    digits = phone.gsub(/[\s\-().]/, '')
    digits = digits.sub(/\A00251/, '+251').sub(/\A251/, '+251').sub(/\A0/, '+251')
    self.phone = digits
  end
end
