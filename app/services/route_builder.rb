# frozen_string_literal: true

# Builds the route data a trip needs from two points, without a maps service: a straight line between
# the points, sampled into a few steps, plus the Google-format encoded polyline. When the web app has
# a Google Maps key the website draws real roads; trips made in the mobile app show this simple line.
class RouteBuilder
  STEPS = 12

  def self.call(from:, to:)
    new(from, to).call
  end

  def initialize(from, to)
    @from = from # [lat, lng]
    @to = to
  end

  def call
    points = (0..STEPS).map do |step|
      ratio = step.to_f / STEPS
      [@from[0] + ((@to[0] - @from[0]) * ratio), @from[1] + ((@to[1] - @from[1]) * ratio)]
    end

    {
      start_location:    [@from[1], @from[0]],
      end_location:      [@to[1], @to[0]],
      via_waypoints:     [],
      overview_path:     points.map { |lat, lng| [lng, lat] },
      overview_polyline: encode(points)
    }.to_json
  end

  private

  # https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  def encode(points)
    last_lat = 0
    last_lng = 0
    points.map do |lat, lng|
      rounded_lat = (lat * 1e5).round
      rounded_lng = (lng * 1e5).round
      chunk = encode_number(rounded_lat - last_lat) + encode_number(rounded_lng - last_lng)
      last_lat = rounded_lat
      last_lng = rounded_lng
      chunk
    end.join
  end

  def encode_number(number)
    value = number.negative? ? ~(number << 1) : (number << 1)
    out = +''
    while value >= 0x20
      out << ((0x20 | (value & 0x1f)) + 63).chr
      value >>= 5
    end
    out << (value + 63).chr
  end
end
