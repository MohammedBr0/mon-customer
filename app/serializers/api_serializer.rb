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
      id: user.id, name: user.to_s, first_name: user.first_name, image: user.image.presence,
      verified: user.verified?, rating: user.average_rating, reviews_count: user.reviews_count
    }
    data[:phone] = user.phone if confirmed && user.phone.present?
    data[:vehicle] = user.visible_vehicle_details(confirmed:).map { |field, value| { key: field.key, label: field.label_for, value: } } if vehicle
    data
  end

  def me(user)
    user(user).merge(
      email: (user.email unless user.phone_account?), phone_account: user.phone_account?, app_mode: user.app_mode, phone_verified: user.phone_verified_at.present?, phone: user.phone, locale: user.locale, time_zone: user.time_zone, send_email_messages: user.send_email_messages,
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
      distance_km: distance_km(itinerary), passengers: passengers(itinerary),
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
      reviewed: viewer ? booking.reviewed_by?(viewer) : nil
    }
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
