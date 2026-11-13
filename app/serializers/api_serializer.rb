# frozen_string_literal: true

# JSON shapes for the mobile API. Money is sent as numbers, dates as ISO 8601, and contact details
# only to people who share a confirmed booking.
module ApiSerializer
  module_function

  def money(value)
    value.to_d.to_f
  end

  def point(location)
    return unless location

    { lat: location.lat, lng: location.lon }
  end

  def user(user, confirmed: false, vehicle: false)
    data = {
      id: user.id, name: user.to_s, first_name: user.first_name, image: absolute_image(user.image),
      verified: user.verified?, licence_verified: user.licence_verified?, rating: user.average_rating, reviews_count: user.reviews_count
    }
    data[:phone] = user.phone if confirmed && user.phone.present?
    data[:vehicle] = user.visible_vehicle_details(confirmed:).map { |field, value| { key: field.key, label: field.label_for, value: } } if vehicle
    data
  end

  def me(user)
    user(user).merge(
      email: (user.email unless user.phone_account?), phone_account: user.phone_account?, app_mode: user.app_mode, reminder_minutes: user.reminder_minutes, identity: identity(user), payment_methods: driver_payment_methods(user, confirmed: true), phone_verified: user.phone_verified_at.present?, phone: user.phone, locale: user.locale, time_zone: user.time_zone, send_email_messages: user.send_email_messages,
      vehicle_avg_consumption: user.vehicle_avg_consumption.to_f, vehicle_data: user.vehicle_data, vehicle_complete: user.vehicle_complete?,
      missing_vehicle_fields: user.missing_vehicle_fields.map(&:key), gender: user.gender, role: user.role_name, staff: user.staff?
    )
  end

  def itinerary(itinerary, viewer: nil, detail: false)
    driver = itinerary.user
    booking = viewer ? itinerary.bookings.where(passenger: viewer).order(created_at: :desc).first : nil
    confirmed = viewer.present? && (viewer == driver || booking&.confirmed?)
    data = {
      id: itinerary.id, slug: itinerary.slug, title: itinerary.title,
      start_address: itinerary.start_address, end_address: itinerary.end_address,
      start_name: short_name(itinerary.start_location, itinerary.start_address), end_name: short_name(itinerary.end_location, itinerary.end_address),
      live: itinerary.live?,
      start_location: point(itinerary.start_location), end_location: point(itinerary.end_location), overview_polyline: itinerary.overview_polyline,
      leave_date: itinerary.leave_date&.iso8601, return_date: itinerary.return_date&.iso8601,
      city: itinerary.city, city_commute: itinerary.city_commute?,
      commute: itinerary.commute?, commute_days: itinerary.commute_days, commute_until: itinerary.commute_until&.iso8601,
      schedule_summary: itinerary.schedule_summary, pickup_point: itinerary.pickup_point, dropoff_point: itinerary.dropoff_point,
      price_per_seat: money(itinerary.price_per_seat), passenger_price_per_seat: money(itinerary.passenger_price_per_seat),
      seats_total: itinerary.num_people, seats_available: itinerary.seats_available, full: itinerary.full?,
      cancelled: itinerary.cancelled?, past: itinerary.past?, pink: itinerary.pink?, smoking_allowed: itinerary.smoking_allowed?,
      pets_allowed: itinerary.pets_allowed?, round_trip: itinerary.round_trip?, description: itinerary.description,
      driver: user(driver, confirmed:, vehicle: detail)
    }
    return data unless detail

    data.merge(
      distance_km: distance_km(itinerary), passengers: passengers(itinerary), payment_methods: driver_payment_methods(driver, confirmed:),
      occurrence_dates: itinerary.occurrence_dates.map { |date| { date: date.iso8601, seats_available: itinerary.seats_available(date) } },
      bookable:         viewer.present? && itinerary.bookable_by?(viewer),
      my_booking:       booking && booking(booking, viewer:),
      price_preview:    price_preview(itinerary)
    )
  end

  def price_preview(itinerary)
    setting = PlatformSetting.current
    { price_per_seat: money(itinerary.price_per_seat), fee_percent: money(setting.fee_percent), fee_charged_to: setting.fee_charged_to }
  end

  def booking(booking, viewer: nil)
    itinerary = booking.itinerary
    counterpart_confirmed = booking.confirmed? && viewer.present? && booking.participant?(viewer)
    breakdown = booking.price_breakdown
    {
      id: booking.id, status: booking.status, seats: booking.seats, ride_dates: booking.ride_dates.map(&:iso8601), note: booking.note,
      created_at: booking.created_at.iso8601, completed: booking.completed?, itinerary: itinerary_summary(itinerary),
      passenger: user(booking.passenger, confirmed: counterpart_confirmed), driver: user(booking.driver, confirmed: counterpart_confirmed),
      price: {
        price_per_seat: money(booking.price_per_seat), rides: breakdown.ride_count, fare_total: money(booking.fare_total),
        fee_percent: money(booking.fee_percent), fee_charged_to: booking.fee_charged_to, fee_amount: money(booking.fee_amount),
        passenger_total: money(booking.passenger_total), driver_payout: money(booking.driver_payout)
      },
      reviewed: viewer ? booking.reviewed_by?(viewer) : nil,
      payment: { method: booking.payment_method, state: booking.payment_state, held: money(booking.held_amount),
                 can_confirm: booking.wallet_paid? && booking.payment_state == 'held' && booking.confirmed? && booking.first_ride_at.present? && booking.first_ride_at <= Time.current },
      # Only the two people in the booking ever get this serializer, so the pickup point stays between them.
      pickup: (booking.pickup? ? { lat: booking.pickup_lat.to_f, lng: booking.pickup_lng.to_f, label: booking.pickup_label } : nil)
    }
  end

  # A short, readable name for a point: the neighbourhood it is in, else the nearest town, else the first part of
  # its address. Search results show these ("Bole → Piassa") instead of long street addresses.
  def short_name(location, address)
    fallback = address.to_s.split(',').first.to_s.strip
    return fallback unless location

    area = nearest(EthiopianPlace::AREA_PLACES, location, 0.03)
    return area.label if area

    town = nearest(EthiopianPlace.all, location, 0.12)
    # Inside a big city the typed address is more telling than the city's name.
    return town.label if town && !EthiopianPlace::AREAS.key?(town.key)

    fallback.presence || town&.label
  end

  # The closest place within [limit] degrees (about 111 km per degree), or nil.
  def nearest(places, location, limit)
    best = places.min_by { |place| ((place.lat - location.lat)**2) + ((place.lng - location.lon)**2) }
    best if best && Math.sqrt(((best.lat - location.lat)**2) + ((best.lng - location.lon)**2)) <= limit
  end

  # The car's position while a ride is under way. Passengers' pickup points go to the driver only.
  def live(itinerary, viewer:)
    fresh = itinerary.live_updated_at.present? && itinerary.live_updated_at > Itinerary::LIVE_STALE_AFTER.ago
    data = {
      active: itinerary.live?, started_at: itinerary.live_started_at&.iso8601, ended_at: itinerary.live_ended_at&.iso8601,
      position: (itinerary.live? && itinerary.live_lat ? { lat: itinerary.live_lat.to_f, lng: itinerary.live_lng.to_f, heading: itinerary.live_heading&.to_f } : nil),
      updated_at: itinerary.live_updated_at&.iso8601, fresh:
    }
    if viewer.id == itinerary.user_id
      data[:pickups] = itinerary.bookings.confirmed.includes(:passenger).select(&:pickup?).map do |booking|
        { name: booking.passenger.first_name.presence || booking.passenger.to_s, lat: booking.pickup_lat.to_f, lng: booking.pickup_lng.to_f, label: booking.pickup_label, seats: booking.seats }
      end
    end
    data
  end

  # Uploaded photos are stored as paths on this site; the app needs the full address.
  def absolute_image(image)
    return if image.blank?
    return image unless image.start_with?('/')

    "#{NeonAuthClient.origin}#{image}"
  end

  def wallet(wallet)
    { available: money(wallet.available), held: money(wallet.held) }
  end

  def wallet_entry(entry)
    { id: entry.id, kind: entry.kind, available_change: money(entry.available_change), held_change: money(entry.held_change),
      available_after: money(entry.available_after), memo: entry.memo, created_at: entry.created_at.iso8601 }
  end

  def topup(topup)
    { id: topup.id, amount: money(topup.amount), status: topup.status, final: topup.final?, checkout_url: topup.checkout_url, created_at: topup.created_at.iso8601 }
  end

  def withdrawal(withdrawal)
    { id: withdrawal.id, amount: money(withdrawal.amount), method_name: withdrawal.method_name, account_number: withdrawal.account_number, status: withdrawal.status,
      note: withdrawal.note, created_at: withdrawal.created_at.iso8601 }
  end

  def payment_method(method)
    { id: method.id, name: method.label, account_label: method.account_label, needs_account: method.needs_account? }
  end

  # What a driver accepts. The account to pay into is only shown to the driver and to passengers with a confirmed seat.
  def driver_payment_methods(driver, confirmed:)
    driver.driver_payment_methods.includes(:payment_method).select { |entry| entry.payment_method.active? }.sort_by { |entry| entry.payment_method.position }.map do |entry|
      data = { id: entry.payment_method_id, name: entry.payment_method.label }
      data.merge!(account_name: entry.account_name, account_number: entry.account_number) if confirmed
      data
    end
  end

  def identity(user)
    documents = user.identity_documents.without_image.index_by(&:kind)
    IdentityDocument::KINDS.map do |kind|
      document = documents[kind]
      { kind:, status: document&.status || 'missing', number: document&.number, rejection_reason: document&.rejection_reason, submitted_at: document&.updated_at&.iso8601 }
    end
  end

  # Length of the drive along its route, in km.
  def distance_km(itinerary)
    meters = Itinerary.where(id: itinerary.id).pick(Arel.sql('ST_Length(overview_path)'))
    meters ? (meters / 1000.0).round(1) : nil
  end

  # Who already has a confirmed seat: first name, picture and seats only (no contact details).
  def passengers(itinerary)
    itinerary.bookings.confirmed.includes(:passenger).order(:created_at).map do |booking|
      { id: booking.passenger_id, first_name: booking.passenger.first_name.presence || booking.passenger.to_s.split.first, image: booking.passenger.image.presence, seats: booking.seats }
    end
  end

  def itinerary_summary(itinerary)
    {
      id: itinerary.id, slug: itinerary.slug, title: itinerary.title, start_address: itinerary.start_address, end_address: itinerary.end_address,
      start_name: short_name(itinerary.start_location, itinerary.start_address), end_name: short_name(itinerary.end_location, itinerary.end_address), live: itinerary.live?,
      leave_date: itinerary.leave_date&.iso8601, city_commute: itinerary.city_commute?, commute: itinerary.commute?, schedule_summary: itinerary.schedule_summary, cancelled: itinerary.cancelled?
    }
  end

  def conversation(conversation, viewer:, messages: false)
    other = conversation.with(viewer)
    data = {
      id: conversation.id, with: user(other), unread: conversation.unread?(viewer), updated_at: conversation.updated_at.iso8601,
      trip: conversation.conversable.respond_to?(:title) ? { id: conversation.conversable_id, title: conversation.conversable.title } : nil,
      last_message: conversation.messages.order(:created_at).last&.then { |message| message_json(message) }
    }
    data[:messages] = conversation.messages.includes(:sender).order(:created_at).map { |message| message_json(message) } if messages
    data
  end

  def message_json(message)
    { id: message.id, body: message.body, sender_id: message.sender_id, created_at: message.created_at.iso8601, read: !message.unread? }
  end

  def ride_alert(alert)
    {
      id: alert.id, start_label: alert.start_label, end_label: alert.end_label, start_location: point(alert.start_location),
      end_location: point(alert.end_location), active: alert.active?, matches: alert.current_matches.count
    }
  end

  def vehicle_field(field)
    {
      key: field.key, label: field.label_for, field_type: field.field_type, options: field.options_list, required: field.required?,
      visibility: field.visibility, help_text: field.help_text, min_value: field.min_value, max_value: field.max_value
    }
  end

  def notification(notification)
    ids = notification.data.slice('itinerary_id', 'booking_id', 'conversation_id')
    { id: notification.id, kind: notification.kind, title: notification.title, body: notification.body, read: notification.read?,
      created_at: notification.created_at.iso8601, data: ids }
  end
end
