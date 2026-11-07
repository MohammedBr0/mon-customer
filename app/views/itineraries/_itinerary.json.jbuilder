# frozen_string_literal: true

json.call(itinerary, :description, :leave_date, :num_people, :overview_polyline,
          :pets_allowed, :daily, :return_date, :round_trip, :smoking_allowed, :pink,
          :title, :via_waypoints)

json.id itinerary.id.to_s
json.seats_available itinerary.seats_available
json.price_per_seat itinerary.price_per_seat
json.passenger_price_per_seat itinerary.passenger_price_per_seat
json.start_location lat: itinerary.start_location.lat, lng: itinerary.start_location.lon
json.end_location lat: itinerary.end_location.lat, lng: itinerary.end_location.lon

json.url itinerary_url(itinerary)

json.user do
  json.call(itinerary.user, :name, :uid, :to_param)

  # TODO: move to front-end
  json.image itinerary.user.image? ? itinerary.user.image : asset_pack_path('static/images/user.jpg')
end
