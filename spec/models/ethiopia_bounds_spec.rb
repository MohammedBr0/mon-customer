# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ethiopian service area' do
  # [lng, lat]
  let(:ethiopian_cities) do
    { 'Addis Ababa' => [38.74, 9.03], 'Adama' => [39.27, 8.54], 'Hawassa' => [38.48, 7.06], 'Bahir Dar' => [37.39, 11.59],
      'Mekelle' => [39.47, 13.5], 'Dire Dawa' => [41.87, 9.59], 'Jimma' => [36.83, 7.67], 'Gondar' => [37.47, 12.6],
      'Harar' => [42.12, 9.31], 'Arba Minch' => [37.55, 6.03], 'Gambella' => [34.59, 8.25], 'Jijiga' => [42.8, 9.35] }
  end
  let(:foreign_cities) do
    { 'Nairobi' => [36.82, -1.29], 'Milan' => [9.19, 45.46], 'Khartoum' => [32.5, 15.5], 'Djibouti' => [43.15, 11.59],
      'Asmara' => [38.93, 15.33], 'Mogadishu' => [45.34, 2.05] }
  end

  def inside?(area, lng_lat)
    area.contains?(RGeo::Geographic.spherical_factory.point(*lng_lat))
  end

  describe 'trip validation with the Ethiopian outline' do
    let(:outline) do
      eval(Rails.root.join('config/settings/application.rb').read[/set :bounds, (\[.*?\n    \])/m, 1]) # rubocop:disable Security/Eval
    end
    let(:area) do
      ring = GeoItinerary::RGEO_FACTORY.linear_ring(outline.map { |p| RGeo::Geographic.spherical_factory.point(*p) })
      GeoItinerary::RGEO_FACTORY.polygon(ring)
    end

    it 'covers major cities across the country' do
      ethiopian_cities.each { |name, point| expect(inside?(area, point)).to be(true), "#{name} should be inside" }
    end

    it 'excludes neighbouring capitals and other continents' do
      foreign_cities.each { |name, point| expect(inside?(area, point)).to be(false), "#{name} should be outside" }
    end
  end

  describe 'Itinerary#inside_bounds uses the area, not just its outline' do
    around do |example|
      APP_CONFIG.itineraries.set :geo_restricted, true
      example.run
    ensure
      APP_CONFIG.itineraries.set :geo_restricted, false
    end

    # Test bounds: a small area between lng 2..7 and lat 4..7. [4, 5.5] is deep inside it, not on its outline.
    it 'accepts a trip whose points are inside the area but not on its edge' do
      expect(build(:itinerary, start_location: [4, 5.5], end_location: [3.5, 5.5])).to be_valid
    end

    it 'rejects a trip with a point outside' do
      expect(build(:itinerary, start_location: [4, 5.5], end_location: [30, 30])).not_to be_valid
    end
  end
end
