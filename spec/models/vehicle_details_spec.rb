# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, 'vehicle details and phone' do
  let!(:make) { create(:vehicle_field, key: 'make', label: 'Make', position: 1) }
  let!(:color) { create(:vehicle_field, key: 'color', label: 'Color', field_type: 'select', options: %w[Red Blue], position: 2) }
  let!(:plate) { create(:vehicle_field, key: 'plate', label: 'Plate', visibility: 'confirmed', required: true, position: 3) }
  let!(:secret) { create(:vehicle_field, key: 'vin', label: 'VIN', visibility: 'private', position: 4) }
  let(:user) { create(:user) }

  it 'keeps only answers for active fields, cast to their type' do
    user.update!(vehicle_data: { 'make' => ' Toyota ', 'color' => 'Red', 'ghost' => 'x', 'plate' => '' })

    expect(user.vehicle_data).to eq('make' => 'Toyota', 'color' => 'Red')
  end

  it 'rejects values the admin did not allow' do
    expect(user.update(vehicle_data: { 'color' => 'Pink' })).to be false
    expect(user.errors[:base].join).to include('Color')
  end

  it 'does not require vehicle answers just to save a profile' do
    expect(user.update(name: 'New Name')).to be true
    expect(user.vehicle_complete?).to be false
    expect(user.missing_vehicle_fields).to eq [plate]
  end

  it 'builds a short description and hides restricted fields' do
    user.update!(vehicle_data: { 'make' => 'Toyota', 'color' => 'Red', 'plate' => 'AA 12345', 'vin' => 'X1' })

    expect(user.vehicle_description).to eq 'Red Toyota'
    expect(user.visible_vehicle_details.map { |field, _| field.key }).to eq %w[make color]
    expect(user.visible_vehicle_details(confirmed: true).map { |field, _| field.key }).to eq %w[make color plate]
  end

  it 'follows admin changes: a new required field makes the vehicle incomplete again' do
    user.update!(vehicle_data: { 'plate' => 'AA 12345' })
    expect(user.vehicle_complete?).to be true

    create(:vehicle_field, key: 'insurance', label: 'Insurance', required: true)

    expect(user.reload.vehicle_complete?).to be false
  end

  describe 'phone' do
    it 'normalises Ethiopian numbers' do
      { '0911223344' => '+251911223344', '+251 91 122 3344' => '+251911223344', '251711223344' => '+251711223344',
        '00251911223344' => '+251911223344' }.each do |input, expected|
        user.update!(phone: input)
        expect(user.phone).to eq expected
      end
    end

    it 'rejects other numbers and allows blank' do
      expect(user.update(phone: '12345')).to be false
      expect(user.update(phone: '+393331234567')).to be false
      expect(user.update(phone: '')).to be true
    end
  end
end
