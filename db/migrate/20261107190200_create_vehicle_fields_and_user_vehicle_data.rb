# frozen_string_literal: true

class CreateVehicleFieldsAndUserVehicleData < ActiveRecord::Migration[7.1]
  DEFAULT_FIELDS = [
    { key: 'vehicle_type', label: 'Vehicle type', labels: { 'am' => 'የተሽከርካሪ ዓይነት' }, field_type: 'select', required: true, visibility: 'public',
      options: ['Sedan', 'Hatchback', 'SUV', 'Minibus (Hiace)', 'Pickup', 'Other'] },
    { key: 'make', label: 'Make', labels: { 'am' => 'ሰሪ' }, field_type: 'text', required: true, visibility: 'public', help_text: 'e.g. Toyota, Suzuki, Hyundai' },
    { key: 'model', label: 'Model', labels: { 'am' => 'ሞዴል' }, field_type: 'text', required: false, visibility: 'public', help_text: 'e.g. Corolla, Dzire, Hiace' },
    { key: 'color', label: 'Color', labels: { 'am' => 'ቀለም' }, field_type: 'select', required: true, visibility: 'public',
      options: %w[White Silver Black Grey Blue Red Green Yellow Brown Other] },
    { key: 'plate', label: 'Plate number', labels: { 'am' => 'የሰሌዳ ቁጥር' }, field_type: 'text', required: true, visibility: 'confirmed',
      help_text: 'Shown only to confirmed passengers.' },
    { key: 'seats', label: 'Passenger seats', labels: { 'am' => 'የተሳፋሪ መቀመጫዎች' }, field_type: 'number', required: false, visibility: 'public',
      min_value: 1, max_value: 20 },
    { key: 'air_conditioning', label: 'Air conditioning', labels: { 'am' => 'አየር ማቀዝቀዣ' }, field_type: 'boolean', required: false, visibility: 'public' }
  ].freeze

  def up
    create_table :vehicle_fields do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.jsonb :labels, null: false, default: {}
      t.string :field_type, null: false, default: 'text'
      t.jsonb :options, null: false, default: []
      t.boolean :required, null: false, default: false
      t.string :visibility, null: false, default: 'public'
      t.string :help_text
      t.integer :min_value
      t.integer :max_value
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :vehicle_fields, :key, unique: true

    add_column :users, :vehicle_data, :jsonb, null: false, default: {}
    add_column :users, :phone, :string

    DEFAULT_FIELDS.each_with_index do |field, index|
      execute <<~SQL.squish
        INSERT INTO vehicle_fields (key, label, labels, field_type, options, required, visibility, help_text, min_value, max_value, position, created_at, updated_at)
        VALUES (#{quote(field[:key])}, #{quote(field[:label])}, #{quote(field[:labels].to_json)}::jsonb, #{quote(field[:field_type])},
                #{quote((field[:options] || []).to_json)}::jsonb, #{field[:required]}, #{quote(field[:visibility])}, #{quote(field[:help_text])},
                #{field[:min_value] || 'NULL'}, #{field[:max_value] || 'NULL'}, #{index}, NOW(), NOW())
      SQL
    end

    # Carry the old fixed vehicle columns over into the configurable fields.
    execute <<~SQL.squish
      UPDATE users SET vehicle_data = jsonb_strip_nulls(jsonb_build_object(
        'make', NULLIF(car_make, ''),
        'model', NULLIF(car_model, ''),
        'color', NULLIF(INITCAP(car_color), ''),
        'plate', NULLIF(car_plate, '')))
      WHERE car_make IS NOT NULL OR car_model IS NOT NULL OR car_color IS NOT NULL OR car_plate IS NOT NULL
    SQL

    # Ethiopia runs on East Africa Time (Rails calls this zone "Nairobi").
    change_column_default :users, :time_zone, from: 'UTC', to: 'Nairobi'
    execute "UPDATE users SET time_zone = 'Nairobi' WHERE time_zone = 'UTC'"
  end

  def down
    change_column_default :users, :time_zone, from: 'Nairobi', to: 'UTC'
    remove_column :users, :phone
    remove_column :users, :vehicle_data
    drop_table :vehicle_fields
  end

  private

  def quote(value)
    value.nil? ? 'NULL' : ActiveRecord::Base.connection.quote(value)
  end
end
