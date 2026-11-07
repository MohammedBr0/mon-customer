# frozen_string_literal: true

# One question about a driver's vehicle (type, plate, seats, ...). Super admins add, change
# and remove these without a deploy; the answers live in users.vehicle_data keyed by `key`.
class VehicleField < ApplicationRecord
  TYPES = %w[text select number boolean].freeze
  VISIBILITIES = %w[public confirmed private].freeze
  MAX_TEXT_LENGTH = 60

  DEFAULTS = [
    { key: 'vehicle_type', label: 'Vehicle type', labels: { 'am' => 'የተሽከርካሪ ዓይነት' }, field_type: 'select', required: true, visibility: 'public',
      options: ['Sedan', 'Hatchback', 'SUV', 'Minibus (Hiace)', 'Pickup', 'Other'] },
    { key: 'make', label: 'Make', labels: { 'am' => 'ሰሪ' }, field_type: 'text', required: true, visibility: 'public', help_text: 'e.g. Toyota, Suzuki, Hyundai' },
    { key: 'model', label: 'Model', labels: { 'am' => 'ሞዴል' }, field_type: 'text', required: false, visibility: 'public', help_text: 'e.g. Corolla, Dzire, Hiace' },
    { key: 'color', label: 'Color', labels: { 'am' => 'ቀለም' }, field_type: 'select', required: true, visibility: 'public',
      options: %w[White Silver Black Grey Blue Red Green Yellow Brown Other] },
    { key: 'plate', label: 'Plate number', labels: { 'am' => 'የሰሌዳ ቁጥር' }, field_type: 'text', required: true, visibility: 'confirmed',
      help_text: 'Shown only to confirmed passengers.' },
    { key: 'seats', label: 'Passenger seats', labels: { 'am' => 'የተሳፋሪ መቀመጫዎች' }, field_type: 'number', required: false, visibility: 'public', min_value: 1, max_value: 20 },
    { key: 'air_conditioning', label: 'Air conditioning', labels: { 'am' => 'አየር ማቀዝቀዣ' }, field_type: 'boolean', required: false, visibility: 'public' }
  ].freeze

  store_accessor :labels, :am, :it

  scope :active, -> { where(active: true).order(:position, :id) }
  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_key
  before_create { self.position = (self.class.maximum(:position) || -1) + 1 if position.to_i.zero? && self.class.exists? }

  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z][a-z0-9_]{1,29}\z/, allow_blank: true }
  validates :label, presence: true, length: { maximum: 60 }
  validates :field_type, inclusion: { in: TYPES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :help_text, length: { maximum: 120 }
  validates :min_value, :max_value, numericality: { only_integer: true }, allow_nil: true
  validate :select_needs_options
  validate :range_is_ordered

  def self.seed_defaults!
    return if exists?

    DEFAULTS.each_with_index { |attributes, index| create!(attributes.merge(position: index)) }
  end

  # Label in the viewer's language, falling back to the English label.
  def label_for(locale = I18n.locale)
    labels[locale.to_s.split('-').first].presence || label
  end

  def options_list
    Array(options)
  end

  # One option per line, as typed in the admin form.
  def options_text
    options_list.join("\n")
  end

  def options_text=(text)
    self.options = text.to_s.lines.map(&:strip).compact_blank.uniq
  end

  def select?
    field_type == 'select'
  end

  def number?
    field_type == 'number'
  end

  def boolean?
    field_type == 'boolean'
  end

  # Turns what a user typed into the stored value (nil when blank).
  def cast(raw)
    return (ActiveModel::Type::Boolean.new.cast(raw) ? true : nil) if boolean? && raw.present?
    return nil if raw.blank? || boolean?
    return Integer(raw.to_s.strip, exception: false) || raw.to_s.strip if number?

    raw.to_s.strip
  end

  # Error key for a cast value, or nil when it is acceptable.
  def error_for(value)
    return (required? ? :blank : nil) if value.nil?

    case field_type
    when 'select' then :inclusion unless options_list.include?(value)
    when 'number' then number_error(value)
    when 'text' then :too_long if value.to_s.length > MAX_TEXT_LENGTH
    end
  end

  def display_value(value)
    return if value.nil?

    boolean? ? I18n.t('vehicle.yes') : value.to_s
  end

  private

  def number_error(value)
    return :not_a_number unless value.is_a?(Integer)
    return :greater_than_or_equal_to if min_value && value < min_value

    :less_than_or_equal_to if max_value && value > max_value
  end

  def normalize_key
    self.key = key.to_s.strip.downcase.gsub(/[^a-z0-9_]+/, '_') if key.present?
  end

  def select_needs_options
    errors.add(:options, :blank) if select? && options_list.empty?
  end

  def range_is_ordered
    errors.add(:max_value, :greater_than_or_equal_to, count: min_value) if min_value && max_value && max_value < min_value
  end
end
