# frozen_string_literal: true

# Splits a booking into what the driver asked for, the platform fee and what each side pays or gets.
# The fee is a percentage of the fare. It is added to the passenger's bill or taken from the
# driver's payout, depending on who the platform setting says is charged.
PriceBreakdown = Struct.new(:price_per_seat, :seats, :fee_percent, :charged_to, :rides) do
  def self.for(price_per_seat:, seats: 1, rides: 1, setting: PlatformSetting.current)
    new(price_per_seat.to_d, seats.to_i, setting.fee_percent.to_d, setting.fee_charged_to, rides.to_i)
  end

  # Number of days (rides) the booking covers; a one-off trip is one ride.
  def ride_count
    [rides.to_i, 1].max
  end

  def fare_total
    price_per_seat * seats * ride_count
  end

  def fee_amount
    (fare_total * fee_percent / 100).round(2)
  end

  def passenger_total
    charged_to == 'passenger' ? fare_total + fee_amount : fare_total
  end

  def driver_payout
    charged_to == 'driver' ? fare_total - fee_amount : fare_total
  end

  def passenger_price_per_seat
    seats.positive? ? (passenger_total / (seats * ride_count)).round(2) : 0.to_d
  end
end
