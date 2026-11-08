/// Plain data classes for what the server sends. Each `fromJson` tolerates missing optional fields, so
/// a slightly older or newer server never crashes the app.
library;

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int? _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v');
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) build) =>
    (v as List? ?? const []).map((e) => build(Map<String, dynamic>.from(e as Map))).toList();

class Place {
  const Place({required this.key, required this.name, this.nameAm, required this.lat, required this.lng});
  final String key;
  final String name;
  final String? nameAm;
  final double lat;
  final double lng;

  factory Place.fromJson(Map<String, dynamic> j) =>
      Place(key: j['key'] as String, name: j['name'] as String, nameAm: j['name_am'] as String?, lat: _d(j['lat']), lng: _d(j['lng']));

  String label(String locale) => locale == 'am' && (nameAm ?? '').isNotEmpty ? nameAm! : name;
}

class VehicleField {
  const VehicleField({
    required this.key,
    required this.label,
    required this.type,
    this.options = const [],
    this.required = false,
    this.visibility = 'public',
    this.helpText,
    this.min,
    this.max,
  });
  final String key;
  final String label;
  final String type; // text | select | number | boolean
  final List<String> options;
  final bool required;
  final String visibility;
  final String? helpText;
  final int? min;
  final int? max;

  factory VehicleField.fromJson(Map<String, dynamic> j) => VehicleField(
        key: j['key'] as String,
        label: j['label'] as String,
        type: j['field_type'] as String? ?? 'text',
        options: [for (final o in (j['options'] as List? ?? const [])) '$o'],
        required: j['required'] == true,
        visibility: j['visibility'] as String? ?? 'public',
        helpText: j['help_text'] as String?,
        min: _i(j['min_value']),
        max: _i(j['max_value']),
      );
}

class AppConfig {
  const AppConfig({
    required this.currencySymbol,
    required this.feePercent,
    required this.feeChargedTo,
    required this.maxPrice,
    required this.paymentInstructions,
    required this.commutesEnabled,
    required this.horizonDays,
    this.announcement,
    this.vehicleFields = const [],
    this.popularRoutes = const [],
    this.places = const [],
  });
  final String currencySymbol;
  final double feePercent;
  final String feeChargedTo;
  final double maxPrice;
  final String? paymentInstructions;
  final bool commutesEnabled;
  final int horizonDays;
  final String? announcement;
  final List<VehicleField> vehicleFields;
  final List<({String from, String to})> popularRoutes;
  final List<Place> places;

  static const fallback = AppConfig(
    currencySymbol: 'Br',
    feePercent: 10,
    feeChargedTo: 'passenger',
    maxPrice: 10000,
    paymentInstructions: null,
    commutesEnabled: true,
    horizonDays: 14,
  );

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final fee = Map<String, dynamic>.from(j['fee'] as Map? ?? const {});
    final currency = Map<String, dynamic>.from(j['currency'] as Map? ?? const {});
    return AppConfig(
      currencySymbol: currency['symbol'] as String? ?? 'Br',
      feePercent: _d(fee['percent']),
      feeChargedTo: fee['charged_to'] as String? ?? 'passenger',
      maxPrice: _d(j['max_price_per_seat']),
      paymentInstructions: j['payment_instructions'] as String?,
      commutesEnabled: j['commutes_enabled'] != false,
      horizonDays: _i(j['commute_horizon_days']) ?? 14,
      announcement: j['announcement'] as String?,
      vehicleFields: _list(j['vehicle_fields'], VehicleField.fromJson),
      popularRoutes: [
        for (final r in (j['popular_routes'] as List? ?? const [])) (from: '${(r as Map)['from']}', to: '${r['to']}'),
      ],
      places: _list(j['places'], Place.fromJson),
    );
  }

  Place? placeByName(String name) {
    for (final p in places) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// Price the passenger pays per seat per day (the driver's price plus the fee when passengers pay it).
  double passengerPrice(double driverPrice) =>
      feeChargedTo == 'passenger' ? driverPrice + _round2(driverPrice * feePercent / 100) : driverPrice;
}

double _round2(double v) => (v * 100).round() / 100;

class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.firstName,
    this.email,
    this.phone,
    this.image,
    this.verified = false,
    this.rating,
    this.reviewsCount = 0,
    this.locale,
    this.sendEmail = false,
    this.fuelPerKm = 0,
    this.vehicleData = const {},
    this.vehicleComplete = true,
    this.missingVehicleFields = const [],
    this.gender,
    this.role = 'user',
    this.vehicle = const [],
  });
  final int id;
  final String name;
  final String? firstName;
  final String? email;
  final String? phone;
  final String? image;
  final bool verified;
  final double? rating;
  final int reviewsCount;
  final String? locale;
  final bool sendEmail;
  final double fuelPerKm;
  final Map<String, dynamic> vehicleData;
  final bool vehicleComplete;
  final List<String> missingVehicleFields;
  final String? gender;
  final String role;
  final List<({String label, String value})> vehicle;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: _i(j['id']) ?? 0,
        name: j['name'] as String? ?? '',
        firstName: j['first_name'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        image: j['image'] as String?,
        verified: j['verified'] == true,
        rating: j['rating'] == null ? null : _d(j['rating']),
        reviewsCount: _i(j['reviews_count']) ?? 0,
        locale: j['locale'] as String?,
        sendEmail: j['send_email_messages'] == true,
        fuelPerKm: _d(j['vehicle_avg_consumption']),
        vehicleData: Map<String, dynamic>.from(j['vehicle_data'] as Map? ?? const {}),
        vehicleComplete: j['vehicle_complete'] != false,
        missingVehicleFields: [for (final k in (j['missing_vehicle_fields'] as List? ?? const [])) '$k'],
        gender: j['gender'] as String?,
        role: j['role'] as String? ?? 'user',
        vehicle: [
          for (final v in (j['vehicle'] as List? ?? const [])) (label: '${(v as Map)['label']}', value: '${v['value']}'),
        ],
      );

  bool get isStaff => role != 'user';
}

class TripSummary {
  const TripSummary({required this.id, required this.title, required this.startAddress, required this.endAddress, this.leaveDate, this.commute = false, this.scheduleSummary, this.cancelled = false});
  final int id;
  final String title;
  final String startAddress;
  final String endAddress;
  final DateTime? leaveDate;
  final bool commute;
  final String? scheduleSummary;
  final bool cancelled;

  factory TripSummary.fromJson(Map<String, dynamic> j) => TripSummary(
        id: _i(j['id']) ?? 0,
        title: j['title'] as String? ?? '',
        startAddress: j['start_address'] as String? ?? '',
        endAddress: j['end_address'] as String? ?? '',
        leaveDate: _t(j['leave_date']),
        commute: j['commute'] == true,
        scheduleSummary: j['schedule_summary'] as String?,
        cancelled: j['cancelled'] == true,
      );
}

class Price {
  const Price({required this.perSeat, required this.rides, required this.fare, required this.feePercent, required this.chargedTo, required this.fee, required this.passengerTotal, required this.driverPayout});
  final double perSeat;
  final int rides;
  final double fare;
  final double feePercent;
  final String chargedTo;
  final double fee;
  final double passengerTotal;
  final double driverPayout;

  factory Price.fromJson(Map<String, dynamic> j) => Price(
        perSeat: _d(j['price_per_seat']),
        rides: _i(j['rides']) ?? 1,
        fare: _d(j['fare_total']),
        feePercent: _d(j['fee_percent']),
        chargedTo: j['fee_charged_to'] as String? ?? 'passenger',
        fee: _d(j['fee_amount']),
        passengerTotal: _d(j['passenger_total']),
        driverPayout: _d(j['driver_payout']),
      );
}

class Booking {
  const Booking({required this.id, required this.status, required this.seats, required this.rideDates, this.note, required this.trip, required this.passenger, required this.driver, required this.price, this.completed = false, this.reviewed});
  final int id;
  final String status;
  final int seats;
  final List<String> rideDates;
  final String? note;
  final TripSummary trip;
  final Profile passenger;
  final Profile driver;
  final Price price;
  final bool completed;
  final bool? reviewed;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: _i(j['id']) ?? 0,
        status: j['status'] as String? ?? 'pending',
        seats: _i(j['seats']) ?? 1,
        rideDates: [for (final d in (j['ride_dates'] as List? ?? const [])) '$d'],
        note: j['note'] as String?,
        trip: TripSummary.fromJson(Map<String, dynamic>.from(j['itinerary'] as Map)),
        passenger: Profile.fromJson(Map<String, dynamic>.from(j['passenger'] as Map)),
        driver: Profile.fromJson(Map<String, dynamic>.from(j['driver'] as Map)),
        price: Price.fromJson(Map<String, dynamic>.from(j['price'] as Map)),
        completed: j['completed'] == true,
        reviewed: j['reviewed'] as bool?,
      );

  bool get isActive => status == 'pending' || status == 'confirmed';
}

class DaySeats {
  const DaySeats(this.date, this.seatsAvailable);
  final String date;
  final int? seatsAvailable;
}

class Trip {
  const Trip({
    required this.id,
    required this.title,
    required this.startAddress,
    required this.endAddress,
    this.leaveDate,
    this.commute = false,
    this.commuteDays = const [],
    this.commuteUntil,
    this.scheduleSummary,
    this.pickupPoint,
    this.dropoffPoint,
    required this.pricePerSeat,
    required this.passengerPrice,
    this.seatsTotal,
    this.seatsAvailable,
    this.full = false,
    this.cancelled = false,
    this.pink = false,
    this.smoking = false,
    this.pets = false,
    this.description,
    required this.driver,
    this.days = const [],
    this.bookable = false,
    this.myBooking,
  });
  final int id;
  final String title;
  final String startAddress;
  final String endAddress;
  final DateTime? leaveDate;
  final bool commute;
  final List<int> commuteDays;
  final String? commuteUntil;
  final String? scheduleSummary;
  final String? pickupPoint;
  final String? dropoffPoint;
  final double pricePerSeat;
  final double passengerPrice;
  final int? seatsTotal;
  final int? seatsAvailable;
  final bool full;
  final bool cancelled;
  final bool pink;
  final bool smoking;
  final bool pets;
  final String? description;
  final Profile driver;
  final List<DaySeats> days;
  final bool bookable;
  final Booking? myBooking;

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: _i(j['id']) ?? 0,
        title: j['title'] as String? ?? '',
        startAddress: j['start_address'] as String? ?? '',
        endAddress: j['end_address'] as String? ?? '',
        leaveDate: _t(j['leave_date']),
        commute: j['commute'] == true,
        commuteDays: [for (final d in (j['commute_days'] as List? ?? const [])) _i(d) ?? 0],
        commuteUntil: j['commute_until'] as String?,
        scheduleSummary: j['schedule_summary'] as String?,
        pickupPoint: j['pickup_point'] as String?,
        dropoffPoint: j['dropoff_point'] as String?,
        pricePerSeat: _d(j['price_per_seat']),
        passengerPrice: _d(j['passenger_price_per_seat']),
        seatsTotal: _i(j['seats_total']),
        seatsAvailable: _i(j['seats_available']),
        full: j['full'] == true,
        cancelled: j['cancelled'] == true,
        pink: j['pink'] == true,
        smoking: j['smoking_allowed'] == true,
        pets: j['pets_allowed'] == true,
        description: j['description'] as String?,
        driver: Profile.fromJson(Map<String, dynamic>.from(j['driver'] as Map)),
        days: [
          for (final d in (j['occurrence_dates'] as List? ?? const []))
            DaySeats('${(d as Map)['date']}', _i(d['seats_available'])),
        ],
        bookable: j['bookable'] == true,
        myBooking: j['my_booking'] == null ? null : Booking.fromJson(Map<String, dynamic>.from(j['my_booking'] as Map)),
      );
}

class ResultPage<T> {
  const ResultPage(this.items, this.page, this.last);
  final List<T> items;
  final int page;
  final bool last;
}

class Message {
  const Message({required this.id, required this.body, required this.senderId, this.createdAt});
  final int id;
  final String body;
  final int senderId;
  final DateTime? createdAt;

  factory Message.fromJson(Map<String, dynamic> j) =>
      Message(id: _i(j['id']) ?? 0, body: j['body'] as String? ?? '', senderId: _i(j['sender_id']) ?? 0, createdAt: _t(j['created_at']));
}

class Conversation {
  const Conversation({required this.id, required this.with_, this.tripTitle, this.unread = false, this.last, this.messages = const []});
  final int id;
  final Profile with_;
  final String? tripTitle;
  final bool unread;
  final Message? last;
  final List<Message> messages;

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: _i(j['id']) ?? 0,
        with_: Profile.fromJson(Map<String, dynamic>.from(j['with'] as Map)),
        tripTitle: (j['trip'] as Map?)?['title'] as String?,
        unread: j['unread'] == true,
        last: j['last_message'] == null ? null : Message.fromJson(Map<String, dynamic>.from(j['last_message'] as Map)),
        messages: _list(j['messages'], Message.fromJson),
      );
}

class RideAlert {
  const RideAlert({required this.id, required this.start, required this.end, this.matches = 0});
  final int id;
  final String start;
  final String end;
  final int matches;

  factory RideAlert.fromJson(Map<String, dynamic> j) =>
      RideAlert(id: _i(j['id']) ?? 0, start: j['start_label'] as String? ?? '', end: j['end_label'] as String? ?? '', matches: _i(j['matches']) ?? 0);
}

class AppNotification {
  const AppNotification({required this.id, required this.kind, required this.title, required this.body, required this.read, this.createdAt, this.tripId, this.bookingId, this.conversationId});
  final int id;
  final String kind;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;
  final int? tripId;
  final int? bookingId;
  final int? conversationId;

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final data = Map<String, dynamic>.from(j['data'] as Map? ?? const {});
    return AppNotification(
      id: _i(j['id']) ?? 0,
      kind: j['kind'] as String? ?? '',
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      read: j['read'] == true,
      createdAt: _t(j['created_at']),
      tripId: _i(data['itinerary_id']),
      bookingId: _i(data['booking_id']),
      conversationId: _i(data['conversation_id']),
    );
  }
}
