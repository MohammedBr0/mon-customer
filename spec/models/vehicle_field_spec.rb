# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VehicleField do
  it 'normalises and validates the key' do
    field = build(:vehicle_field, key: ' Fuel Type ')
    field.valid?
    expect(field.key).to eq 'fuel_type'
    expect(build(:vehicle_field, key: '1abc')).not_to be_valid
    create(:vehicle_field, key: 'plate')
    expect(build(:vehicle_field, key: 'plate')).not_to be_valid
  end

  it 'needs options for a select and an ordered number range' do
    expect(build(:vehicle_field, field_type: 'select', options: [])).not_to be_valid
    expect(build(:vehicle_field, field_type: 'select', options: %w[A B])).to be_valid
    expect(build(:vehicle_field, field_type: 'number', min_value: 5, max_value: 2)).not_to be_valid
  end

  it 'parses one option per line' do
    field = build(:vehicle_field, field_type: 'select')
    field.options_text = "White\n Black \n\nWhite\nRed"

    expect(field.options).to eq %w[White Black Red]
    expect(field.options_text).to eq "White\nBlack\nRed"
  end

  it 'casts and checks values by type' do
    number = build(:vehicle_field, field_type: 'number', min_value: 1, max_value: 10)
    expect(number.cast('4')).to eq 4
    expect(number.error_for(0)).to eq :greater_than_or_equal_to
    expect(number.error_for(11)).to eq :less_than_or_equal_to
    expect(number.error_for(number.cast('abc'))).to eq :not_a_number

    select = build(:vehicle_field, field_type: 'select', options: %w[Red Blue])
    expect(select.error_for('Green')).to eq :inclusion
    expect(select.error_for('Red')).to be_nil

    expect(build(:vehicle_field, required: true).error_for(nil)).to eq :blank
    expect(build(:vehicle_field, field_type: 'boolean').cast('1')).to be true
    expect(build(:vehicle_field, field_type: 'boolean').cast('0')).to be_nil
  end

  it 'shows the label in the viewer language with an English fallback' do
    field = build(:vehicle_field, label: 'Color', am: 'ቀለም')

    expect(field.label_for('am-ET')).to eq 'ቀለም'
    expect(field.label_for('it-IT')).to eq 'Color'
  end

  it 'seeds the Ethiopian defaults once' do
    described_class.seed_defaults!
    described_class.seed_defaults!

    expect(described_class.pluck(:key)).to include('vehicle_type', 'make', 'plate', 'seats')
    expect(described_class.count).to eq described_class::DEFAULTS.size
    expect(described_class.find_by(key: 'plate').visibility).to eq 'confirmed'
  end

  it 'only lists active fields in order' do
    second = create(:vehicle_field, position: 2)
    first = create(:vehicle_field, position: 1)
    create(:vehicle_field, active: false)

    expect(described_class.active).to eq [first, second]
  end
end
