# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pricing' do
  describe PriceBreakdown do
    it 'adds the fee to the passenger bill when passengers are charged' do
      breakdown = described_class.new(150.to_d, 2, 10.to_d, 'passenger')

      expect(breakdown.fare_total).to eq 300
      expect(breakdown.fee_amount).to eq 30
      expect(breakdown.passenger_total).to eq 330
      expect(breakdown.driver_payout).to eq 300
      expect(breakdown.passenger_price_per_seat).to eq 165
    end

    it 'takes the fee from the driver when drivers are charged' do
      breakdown = described_class.new(150.to_d, 2, 10.to_d, 'driver')

      expect(breakdown.passenger_total).to eq 300
      expect(breakdown.driver_payout).to eq 270
    end

    it 'rounds the fee to cents and handles a zero fee' do
      expect(described_class.new(33.to_d, 1, BigDecimal('12.5'), 'passenger').fee_amount).to eq 4.13
      expect(described_class.new(100.to_d, 3, 0.to_d, 'passenger').passenger_total).to eq 300
    end
  end

  describe PlatformSetting do
    it 'creates a single default row on first use' do
      described_class.delete_all

      expect { described_class.current }.to change(described_class, :count).by(1)
      expect(described_class.current).to have_attributes(fee_percent: 10, fee_charged_to: 'passenger', currency_code: 'ETB', currency_symbol: 'Br')
      expect(described_class.count).to eq 1
    end

    it 'validates the fee range, payer and price limit' do
      setting = described_class.current

      expect(setting.update(fee_percent: -1)).to be false
      expect(setting.update(fee_percent: 51)).to be false
      expect(setting.update(fee_charged_to: 'nobody')).to be false
      expect(setting.update(max_price_per_seat: 0)).to be false
      expect(setting.reload.update(fee_percent: 15.5, fee_charged_to: 'driver')).to be true
    end
  end

  describe Booking do
    it 'freezes the price and fee when the booking is made' do
      PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
      itinerary = create(:itinerary, num_people: 3, price_per_seat: 200)
      booking = create(:booking, itinerary:, seats: 2)

      expect(booking).to have_attributes(price_per_seat: 200, fee_percent: 10, fee_charged_to: 'passenger',
                                         fare_total: 400, fee_amount: 40, passenger_total: 440, driver_payout: 400)

      PlatformSetting.current.update!(fee_percent: 25)
      itinerary.update!(price_per_seat: 999)

      expect(booking.reload).to have_attributes(fee_percent: 10, passenger_total: 440)
      expect(booking.price_breakdown.passenger_total).to eq 440
    end

    it 'records the driver fee model too' do
      PlatformSetting.current.update!(fee_percent: 20, fee_charged_to: 'driver')
      booking = create(:booking, itinerary: create(:itinerary, num_people: 3, price_per_seat: 100), seats: 1)

      expect(booking).to have_attributes(passenger_total: 100, fee_amount: 20, driver_payout: 80)
    end
  end
end
