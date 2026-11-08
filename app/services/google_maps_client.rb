# frozen_string_literal: true

require 'net/http'

# Talks to Google's current Places and Routes APIs from the server. The browser only loads the map itself,
# so no legacy Directions, Geocoding or Static Maps access is needed on the key.
class GoogleMapsClient
  class Error < StandardError; end

  PLACES_URL = URI('https://places.googleapis.com/v1/places:searchText')
  ROUTES_URL = URI('https://routes.googleapis.com/directions/v2:computeRoutes')
  # Rough box around Ethiopia, so "Bole" means Addis Ababa and not somewhere else.
  ETHIOPIA = { rectangle: { low: { latitude: 3.4, longitude: 32.9 }, high: { latitude: 14.9, longitude: 48.0 } } }.freeze

  def self.key
    APP_CONFIG.google_maps_server_key.presence || APP_CONFIG.google_maps_api_key.presence
  end

  def self.enabled?
    key.present?
  end

  # A free-text place to { address:, lat:, lng: }, or nil when nothing matches.
  def geocode(text)
    return coordinates_from(text) if coordinates?(text)

    body = { textQuery: text.to_s, regionCode: 'ET', locationBias: ETHIOPIA, pageSize: 1, languageCode: I18n.locale.to_s.start_with?('am') ? 'am' : 'en' }
    place = post(PLACES_URL, body, 'places.formattedAddress,places.location').fetch('places', []).first
    return unless place

    { address: place['formattedAddress'], lat: place.dig('location', 'latitude'), lng: place.dig('location', 'longitude') }
  end

  # A driving route between two places (text or "lat,lng"), in the shape the trip form stores.
  def route(origin:, destination:, avoid_highways: false, avoid_tolls: false)
    from = geocode(origin) || raise(Error, 'not_found')
    to = geocode(destination) || raise(Error, 'not_found')
    body = {
      origin: waypoint(from), destination: waypoint(to), travelMode: 'DRIVE', units: 'METRIC',
      routeModifiers: { avoidHighways: avoid_highways, avoidTolls: avoid_tolls }
    }
    mask = 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline'
    found = post(ROUTES_URL, body, mask).fetch('routes', []).first || raise(Error, 'zero_results')
    polyline = found.dig('polyline', 'encodedPolyline')
    meters = found['distanceMeters'].to_i
    seconds = found['duration'].to_s.to_i
    {
      start_address: from[:address], end_address: to[:address],
      distance_text: format('%.1f km', meters / 1000.0), distance_value: meters,
      duration_text: duration_text(seconds), duration_value: seconds,
      start_location: [from[:lng], from[:lat]], end_location: [to[:lng], to[:lat]],
      via_waypoints: [], overview_polyline: polyline, overview_path: self.class.decode(polyline).map { |lat, lng| [lng, lat] }
    }
  end

  # Google's encoded polyline format (precision 5) to [[lat, lng], ...].
  def self.decode(encoded)
    points = []
    index = lat = lng = 0
    while index < encoded.to_s.length
      lat += next_value(encoded, index) { |i| index = i }
      lng += next_value(encoded, index) { |i| index = i }
      points << [lat / 1e5, lng / 1e5]
    end
    points
  end

  def self.next_value(encoded, index)
    result = shift = 0
    loop do
      byte = encoded[index].ord - 63
      index += 1
      result |= (byte & 0x1f) << shift
      shift += 5
      break if byte < 0x20
    end
    yield index
    result.odd? ? ~(result >> 1) : result >> 1
  end

  private

  def waypoint(place)
    { location: { latLng: { latitude: place[:lat], longitude: place[:lng] } } }
  end

  def coordinates?(text)
    text.to_s.match?(/\A\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*\z/)
  end

  def coordinates_from(text)
    lat, lng = text.split(',').map(&:to_f)
    { address: format('%.5f, %.5f', lat, lng), lat:, lng: }
  end

  def duration_text(seconds)
    minutes = (seconds / 60.0).ceil
    return "#{minutes} min" if minutes < 60

    hours, rest = minutes.divmod(60)
    rest.zero? ? "#{hours} h" : "#{hours} h #{rest} min"
  end

  def post(uri, body, field_mask)
    raise Error, 'not_configured' unless self.class.enabled?

    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'X-Goog-Api-Key' => self.class.key, 'X-Goog-FieldMask' => field_mask)
    request.body = body.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
    raise Error, "google_#{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, JSON::ParserError => e
    raise Error, e.class.name
  end
end
