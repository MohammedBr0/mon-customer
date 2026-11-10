import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/models.dart';
import 'config.dart';

/// An error the server (or the network) reported, with a message safe to show to a person.
class ApiException implements Exception {
  ApiException(this.message, {this.code, this.status});
  final String message;
  final String? code;
  final int? status;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Talks to the icare JSON API. Holds the bearer token and the caller's language.
class Api {
  Api({http.Client? client, String? base}) : _client = client ?? http.Client(), _base = base ?? apiBase;

  final http.Client _client;
  final String _base;

  String? token;
  String locale = 'en';

  /// Called when the server says the token is no longer valid, so the app can return to sign-in.
  void Function()? onUnauthorized;

  Uri _uri(String path, [Map<String, dynamic>? query]) => Uri.parse('$_base/api/v1$path').replace(
        queryParameters: query == null
            ? null
            : {for (final e in query.entries) if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}'},
      );

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Accept-Language': locale,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    final request = http.Request(method, _uri(path, query))..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    return _run(request, const Duration(seconds: 25));
  }

  Future<Map<String, dynamic>> _run(http.BaseRequest request, Duration limit) async {
    http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(limit));
    } on TimeoutException {
      throw ApiException('timeout', code: 'timeout');
    } on http.ClientException {
      throw ApiException('network', code: 'network');
    } catch (_) {
      throw ApiException('network', code: 'network');
    }
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // A non-JSON body (for example a gateway error page) is handled below by the status code.
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final error = Map<String, dynamic>.from(data['error'] as Map? ?? const {});
    if (response.statusCode == 401 && token != null) onUnauthorized?.call();
    throw ApiException(error['message'] as String? ?? 'server_${response.statusCode}', code: error['code'] as String?, status: response.statusCode);
  }

  // ---- public ----
  Future<AppConfig> config() async => AppConfig.fromJson(await _send('GET', '/config'));

  // ---- auth ----
  /// [login] is an Ethiopian mobile number or an email address.
  Future<({String token, Profile user})> signIn(String login, String password) async {
    final data = await _send('POST', '/auth/sign_in', body: {'login': login, 'password': password, 'device_name': 'android'});
    return (token: data['token'] as String, user: Profile.fromJson(Map<String, dynamic>.from(data['user'] as Map)));
  }

  /// Texts a security code to the number. Returns the id to send back with the code.
  Future<({String verificationId, int codeLength})> sendCode(String phone) async {
    final data = await _send('POST', '/auth/send_code', body: {'phone': phone});
    return (verificationId: '${data['verification_id']}', codeLength: (data['code_length'] as num?)?.toInt() ?? 6);
  }

  Future<({String token, Profile user})> signUp(String name, String phone, String password, {required String mode, String? verificationId, String? code}) async {
    final data = await _send('POST', '/auth/sign_up', body: {
      'name': name, 'phone': phone, 'password': password, 'app_mode': mode, 'device_name': 'android',
      'verification_id': ?verificationId,
      'code': ?code,
    });
    return (token: data['token'] as String, user: Profile.fromJson(Map<String, dynamic>.from(data['user'] as Map)));
  }

  Future<void> signOut() async {
    try {
      await _send('DELETE', '/auth/sign_out');
    } on ApiException {
      // Signing out locally is enough if the server cannot be reached.
    }
  }

  // ---- profile ----
  Future<Profile> me() async => Profile.fromJson(Map<String, dynamic>.from((await _send('GET', '/me'))['user'] as Map));

  Future<Profile> updateMe(Map<String, dynamic> fields) async =>
      Profile.fromJson(Map<String, dynamic>.from((await _send('PATCH', '/me', body: {'user': fields}))['user'] as Map));

  Future<void> deleteAccount() => _send('DELETE', '/me');

  // ---- trips ----
  Future<ResultPage<Trip>> trips({Place? from, Place? to, int? seats, String? sort, int page = 1, String? city, Place? fromArea, Place? toArea, double? nearLat, double? nearLng, double? radiusKm}) async {
    final data = await _send('GET', '/itineraries', query: {
      'start_lat': from?.lat, 'start_lng': from?.lng, 'end_lat': to?.lat, 'end_lng': to?.lng, 'seats': seats, 'sort': sort, 'page': page,
      'city': city, 'from_area': fromArea?.key, 'to_area': toArea?.key,
      'near_lat': nearLat, 'near_lng': nearLng, 'radius_km': radiusKm,
    });
    return _tripPage(data);
  }

  Future<ResultPage<Trip>> myTrips({int page = 1}) async => _tripPage(await _send('GET', '/itineraries/mine', query: {'page': page}));

  ResultPage<Trip> _tripPage(Map<String, dynamic> data) {
    final meta = Map<String, dynamic>.from(data['meta'] as Map? ?? const {});
    return ResultPage([for (final t in (data['itineraries'] as List? ?? const [])) Trip.fromJson(Map<String, dynamic>.from(t as Map))], (meta['page'] as num?)?.toInt() ?? 1, meta['last'] != false);
  }

  Future<Trip> trip(int id) async => Trip.fromJson(Map<String, dynamic>.from((await _send('GET', '/itineraries/$id'))['itinerary'] as Map));

  Future<Trip> createTrip(Map<String, dynamic> fields) async =>
      Trip.fromJson(Map<String, dynamic>.from((await _send('POST', '/itineraries', body: {'itinerary': fields}))['itinerary'] as Map));

  Future<Trip> cancelTrip(int id) async => Trip.fromJson(Map<String, dynamic>.from((await _send('PATCH', '/itineraries/$id/cancel'))['itinerary'] as Map));

  // ---- bookings ----
  Future<({List<Booking> made, List<Booking> received})> bookings() async {
    final data = await _send('GET', '/bookings');
    List<Booking> parse(Object? v) => [for (final b in (v as List? ?? const [])) Booking.fromJson(Map<String, dynamic>.from(b as Map))];
    return (made: parse(data['made']), received: parse(data['received']));
  }

  Future<Booking> book(int tripId, {required int seats, List<String> days = const [], String? note, Place? pickup}) async {
    final data = await _send('POST', '/itineraries/$tripId/bookings', body: {
      'booking': {'seats': seats, if (days.isNotEmpty) 'ride_dates': days, if (note != null && note.isNotEmpty) 'note': note, if (pickup != null) 'pickup': {'lat': pickup.lat, 'lng': pickup.lng, 'label': pickup.name}}
    });
    return Booking.fromJson(Map<String, dynamic>.from(data['booking'] as Map));
  }

  Future<Booking> _bookingAction(int id, String action, [Map<String, dynamic>? body]) async =>
      Booking.fromJson(Map<String, dynamic>.from((await _send('PATCH', '/bookings/$id/$action', body: body))['booking'] as Map));

  Future<Booking> confirm(int id) => _bookingAction(id, 'confirm');
  Future<Booking> decline(int id) => _bookingAction(id, 'decline');
  Future<Booking> cancelBooking(int id) => _bookingAction(id, 'cancel');
  Future<Booking> skipDate(int id, String isoDay) => _bookingAction(id, 'skip_date', {'date': isoDay});

  Future<void> review(int bookingId, int rating, String comment) =>
      _send('POST', '/bookings/$bookingId/reviews', body: {'review': {'rating': rating, 'comment': comment}});

  // ---- messages ----
  Future<({List<Conversation> items, int unread})> conversations() async {
    final data = await _send('GET', '/conversations');
    return (
      items: [for (final c in (data['conversations'] as List? ?? const [])) Conversation.fromJson(Map<String, dynamic>.from(c as Map))],
      unread: (data['unread'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Conversation> conversation(int id) async => Conversation.fromJson(Map<String, dynamic>.from((await _send('GET', '/conversations/$id'))['conversation'] as Map));

  Future<Conversation> startConversation(int tripId, String body) async =>
      Conversation.fromJson(Map<String, dynamic>.from((await _send('POST', '/conversations', body: {'itinerary_id': tripId, 'body': body}))['conversation'] as Map));

  Future<Conversation> sendMessage(int id, String body) async =>
      Conversation.fromJson(Map<String, dynamic>.from((await _send('POST', '/conversations/$id/message', body: {'body': body}))['conversation'] as Map));

  // ---- alerts and reports ----
  Future<List<RideAlert>> alerts() async =>
      [for (final a in ((await _send('GET', '/ride_alerts'))['ride_alerts'] as List? ?? const [])) RideAlert.fromJson(Map<String, dynamic>.from(a as Map))];

  /// How a chosen place is sent to the server: a listed town by its key, any other spot by name and coordinates.
  static Map<String, dynamic> placeRef(Place p) => p.isPin ? {'name': p.name, 'lat': p.lat, 'lng': p.lng} : {'key': p.key};

  Future<void> createAlert(Place from, Place to) =>
      _send('POST', '/ride_alerts', body: {'ride_alert': {'start': placeRef(from), 'end': placeRef(to)}});

  Future<void> deleteAlert(int id) => _send('DELETE', '/ride_alerts/$id');

  Future<void> report(String type, int id, String reason, String details) =>
      _send('POST', '/reports', body: {'type': type, 'id': id, 'reason': reason, 'details': details});

  // ---- notifications ----
  Future<({List<AppNotification> items, int unread, bool last})> notifications({int page = 1, int? after}) async {
    final data = await _send('GET', '/notifications', query: {'page': page, 'after': after});
    final meta = Map<String, dynamic>.from(data['meta'] as Map? ?? const {});
    return (
      items: [for (final n in (data['notifications'] as List? ?? const [])) AppNotification.fromJson(Map<String, dynamic>.from(n as Map))],
      unread: (data['unread'] as num?)?.toInt() ?? 0,
      last: meta['last'] != false,
    );
  }

  Future<void> markNotificationRead(int id) => _send('PATCH', '/notifications/$id/read');
  Future<void> markAllNotificationsRead() => _send('POST', '/notifications/read_all');

  // ---- maps ----
  /// Places matching what was typed, nearest to [nearLat]/[nearLng] first.
  Future<List<Place>> searchPlaces(String q, {double? nearLat, double? nearLng}) async {
    final data = await _send('GET', '/maps/search', query: {'q': q, 'lat': nearLat, 'lng': nearLng});
    return [
      for (final p in (data['places'] as List? ?? const []))
        Place.pin((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble(), '${p['name'] ?? p['address']}', address: p['address'] as String?),
    ];
  }

  /// The address at a point on the map.
  Future<Place> reverse(double lat, double lng) async {
    final data = await _send('GET', '/maps/reverse', query: {'lat': lat, 'lng': lng});
    final place = Map<String, dynamic>.from(data['place'] as Map);
    return Place.pin(lat, lng, '${place['address']}', address: place['address'] as String?);
  }

  Future<RoutePreview> routePreview(Place from, Place to) async {
    final data = await _send('GET', '/maps/route', query: {'from': '${from.lat},${from.lng}', 'to': '${to.lat},${to.lng}'});
    return RoutePreview.fromJson(Map<String, dynamic>.from(data['route'] as Map));
  }

  // ---- payment methods and identity ----
  /// Replaces the payment methods this driver accepts.
  Future<Profile> savePaymentMethods(List<DriverPayment> methods) async {
    final data = await _send('PUT', '/me/payment_methods', body: {
      'methods': [for (final m in methods) {'id': m.id, 'account_name': m.accountName, 'account_number': m.accountNumber}],
    });
    return Profile.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  /// Sends a photo of a driving licence or national ID to be checked by staff.
  Future<Profile> submitIdentity({required String kind, required String number, required List<int> imageBytes, required String filename}) async {
    final lower = filename.toLowerCase();
    final type = lower.endsWith('.png') ? 'png' : (lower.endsWith('.webp') ? 'webp' : 'jpeg');
    final headers = Map<String, String>.from(_headers)..remove('Content-Type');
    final request = http.MultipartRequest('POST', _uri('/me/identity', null))
      ..headers.addAll(headers)
      ..fields['kind'] = kind
      ..fields['number'] = number
      ..files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: filename, contentType: MediaType('image', type)));
    final data = await _run(request, const Duration(seconds: 90));
    return Profile.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  // ---- live tracking ----
  LiveState _live(Map<String, dynamic> data) => LiveState.fromJson(Map<String, dynamic>.from(data['live'] as Map));

  /// The driver sets off: confirmed passengers are told and can follow the car.
  Future<LiveState> startTrip(int id) async => _live(await _send('POST', '/itineraries/$id/start'));
  Future<void> sendLocation(int id, double lat, double lng, {double? heading}) => _send('POST', '/itineraries/$id/location', body: {'lat': lat, 'lng': lng, 'heading': ?heading});
  Future<LiveState> finishTrip(int id) async => _live(await _send('POST', '/itineraries/$id/finish'));
  Future<LiveState> liveTrip(int id) async => _live(await _send('GET', '/itineraries/$id/live'));
}
