import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icare/core/api.dart';
import 'package:icare/core/app_state.dart';
import 'package:icare/core/format.dart';
import 'package:icare/core/polyline.dart';
import 'package:icare/widgets/route_map.dart';
import 'package:icare/core/phone_notifier.dart';
import 'package:icare/core/token_store.dart';
import 'package:icare/l10n/strings.dart';
import 'package:icare/main.dart';
import 'package:icare/models/models.dart';
import 'package:intl/date_symbol_data_local.dart';

const _profile = {'id': 7, 'name': 'Test User', 'email': 't@example.com', 'role': 'user'};

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

AppState _state(MockClientHandler handler, {TokenStore? store}) =>
    AppState(api: Api(client: MockClient(handler), base: 'https://x.test'), store: store ?? MemoryTokenStore());

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('am');
  });

  group('Strings', () {
    test('every English key has an Amharic translation', () {
      expect(Strings.englishKeys.difference(Strings.amharicKeys), isEmpty);
    });

    test('fills placeholders and falls back to English', () {
      expect(Strings.of('en', 'seats_left', {'available': 2, 'total': 4}), '2 of 4 seats left');
      expect(Strings.of('am', 'no_such_key'), 'no_such_key');
    });
  });

  group('format', () {
    test('shows Ethiopian time (UTC+3)', () {
      expect(formatTime(DateTime.utc(2026, 11, 8, 4, 30)), '07:30');
    });

    test('money drops empty decimals', () {
      expect(formatMoney(120, 'Br'), contains('120'));
      expect(formatMoney(120, 'Br'), isNot(contains('.00')));
    });
  });

  group('models', () {
    test('a trip parses with sensible defaults', () {
      final trip = Trip.fromJson({
        'id': 1,
        'start_address': 'Addis Ababa',
        'end_address': 'Adama',
        'price_per_seat': '150.0',
        'passenger_price_per_seat': 165,
        'driver': _profile,
      });
      expect(trip.pricePerSeat, 150);
      expect(trip.passengerPrice, 165);
      expect(trip.commute, isFalse);
      expect(trip.driver.name, 'Test User');
    });

    test('passenger price adds the fee only when passengers pay it', () {
      const passenger = AppConfig(currencySymbol: 'Br', feePercent: 10, feeChargedTo: 'passenger', maxPrice: 1000, paymentInstructions: null, commutesEnabled: true, horizonDays: 14);
      expect(passenger.passengerPrice(100), 110);
      expect(AppConfig.fallback.passengerPrice(100), 110);
    });
  });

  group('city commutes', () {
    test('config lists cities with their neighbourhoods', () {
      final config = AppConfig.fromJson({
        'cities': [
          {'key': 'addis-ababa', 'name': 'Addis Ababa', 'name_am': 'አዲስ አበባ', 'lat': 9.0, 'lng': 38.7, 'areas': [
            {'key': 'addis-ababa:bole', 'name': 'Bole', 'name_am': 'ቦሌ', 'lat': 9.0, 'lng': 38.78, 'city': 'addis-ababa'}
          ]}
        ]
      });
      expect(config.cities.single.areas.single.label('am'), 'ቦሌ');
      expect(config.cities.single.areas.single.city, 'addis-ababa');
    });

    test('an old server without cities still parses', () {
      expect(AppConfig.fromJson({}).cities, isEmpty);
    });

    test('a city trip is flagged', () {
      final trip = Trip.fromJson({'id': 1, 'city': 'addis-ababa', 'city_commute': true, 'driver': _profile});
      expect(trip.cityCommute, isTrue);
    });

    test('a city search sends the city and neighbourhoods', () async {
      late Uri seen;
      final api = Api(client: MockClient((r) async {
        seen = r.url;
        return _json({'itineraries': [], 'meta': {'page': 1, 'last': true}});
      }), base: 'https://x.test');
      const bole = Place(key: 'addis-ababa:bole', name: 'Bole', lat: 9, lng: 38.7);
      await api.trips(city: 'addis-ababa', fromArea: bole);
      expect(seen.queryParameters['city'], 'addis-ababa');
      expect(seen.queryParameters['from_area'], 'addis-ababa:bole');
      expect(seen.queryParameters.containsKey('to_area'), isFalse);
    });
  });

  group('maps', () {
    test('decodes Google polylines', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points, [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]);
      expect(decodePolyline(null), isEmpty);
      expect(decodePolyline(''), isEmpty);
    });

    test('a route falls back to a straight line between the ends', () {
      final line = routePoints(polyline: null, startLat: 9.0, startLng: 38.7, endLat: 9.1, endLng: 38.8);
      expect(line.length, 2);
      expect(routePoints(), isEmpty);
      expect(routePoints(polyline: '_p~iF~ps|U_ulLnnqC').length, 2);
    });

    test('a trip carries its route and end points', () {
      final trip = Trip.fromJson({'id': 1, 'overview_polyline': 'abc', 'start_location': {'lat': 9.0, 'lng': 38.7}, 'end_location': {'lat': 9.1, 'lng': 38.8}, 'driver': _profile});
      expect(trip.polyline, 'abc');
      expect(trip.startLat, 9.0);
      expect(trip.endLng, 38.8);
    });

    test('a pin on the map is not a listed town', () {
      final pin = Place.pin(9.01, 38.74, 'Mexico');
      expect(pin.isPin, isTrue);
      expect(pin.key, 'pin:9.01000,38.74000');
    });

    test('search, reverse lookup and route preview call the server', () async {
      final seen = <String>[];
      final api = Api(client: MockClient((r) async {
        seen.add(r.url.path);
        if (r.url.path.endsWith('/maps/search')) {
          return _json({'places': [{'name': 'Bole', 'address': 'Bole, Addis Ababa', 'lat': 8.99, 'lng': 38.78}]});
        }
        if (r.url.path.endsWith('/maps/reverse')) return _json({'place': {'address': 'Mexico, Addis Ababa'}});
        if (r.url.path.endsWith('/ride_alerts')) {
          expect(jsonDecode(r.body)['ride_alert']['start'], {'name': 'Bole', 'lat': 8.99, 'lng': 38.78});
          return _json({});
        }
        return _json({'route': {'distance_text': '7.1 km', 'duration_text': '21 min', 'overview_polyline': 'xyz'}});
      }), base: 'https://x.test');

      final found = await api.searchPlaces('Bole', nearLat: 9, nearLng: 38.7);
      expect(found.single.isPin, isTrue);
      expect(found.single.address, 'Bole, Addis Ababa');
      expect((await api.reverse(9.01, 38.74)).name, 'Mexico, Addis Ababa');
      final preview = await api.routePreview(found.single, Place.pin(9.03, 38.74, 'Piassa'));
      expect(preview.distanceText, '7.1 km');
      await api.createAlert(found.single, const Place(key: 'adama', name: 'Adama', lat: 8.5, lng: 39.2));
      expect(seen, containsAll(['/api/v1/maps/search', '/api/v1/maps/reverse', '/api/v1/maps/route', '/api/v1/ride_alerts']));
    });
  });

  group('Api', () {
    test('sends the bearer token and language', () async {
      late http.Request seen;
      final api = Api(client: MockClient((r) async {
        seen = r;
        return _json({'user': _profile});
      }), base: 'https://x.test')
        ..token = 'abc'
        ..locale = 'am';
      final user = await api.me();
      expect(user.id, 7);
      expect(seen.headers['Authorization'], 'Bearer abc');
      expect(seen.headers['Accept-Language'], 'am');
    });

    test('turns server errors into messages', () async {
      final api = Api(client: MockClient((_) async => _json({'error': {'code': 'invalid', 'message': 'Seats are not available'}}, 422)), base: 'https://x.test');
      expect(api.me(), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Seats are not available')));
    });

    test('a 401 signs the session out', () async {
      var expired = false;
      final api = Api(client: MockClient((_) async => _json({'error': {'code': 'unauthorized', 'message': 'Sign in'}}, 401)), base: 'https://x.test')
        ..token = 'old'
        ..onUnauthorized = () async => expired = true;
      await expectLater(api.me(), throwsA(isA<ApiException>()));
      expect(expired, isTrue);
    });
  });

  group('AppState', () {
    test('without a saved token the user is signed out', () async {
      final state = _state((_) async => _json({}));
      await state.start();
      expect(state.status, AuthStatus.signedOut);
    });

    test('sign in stores the token and signs in', () async {
      final store = MemoryTokenStore();
      final state = _state((r) async {
        if (r.url.path.endsWith('/auth/sign_in')) return _json({'token': 'tok', 'user': _profile});
        return _json({'conversations': [], 'unread': 0});
      }, store: store);
      await state.signIn('t@example.com', 'secret123');
      expect(state.status, AuthStatus.signedIn);
      expect(await store.readToken(), 'tok');
    });

    test('an offline start keeps the saved token', () async {
      final store = MemoryTokenStore();
      await store.saveToken('keep');
      final state = _state((_) async => throw http.ClientException('down'), store: store);
      await state.start();
      expect(state.status, AuthStatus.offline);
      expect(await store.readToken(), 'keep');
    });

    test('an expired token signs the user out', () async {
      final store = MemoryTokenStore();
      await store.saveToken('stale');
      final state = _state((r) async {
        if (r.url.path.endsWith('/config')) return _json({});
        return _json({'error': {'code': 'unauthorized', 'message': 'x'}}, 401);
      }, store: store);
      await state.start();
      expect(state.status, AuthStatus.signedOut);
      expect(await store.readToken(), isNull);
    });
  });

  group('notifications', notificationTests);

  testWidgets('the welcome screen validates before sending', (tester) async {
    var calls = 0;
    final state = _state((r) async {
      if (!r.url.path.endsWith('/config')) calls++;
      return _json({});
    });
    await tester.pumpWidget(IcareApp(state: state));
    await state.start();
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('switching to Amharic changes the screen', (tester) async {
    final state = _state((_) async => _json({}));
    await tester.pumpWidget(IcareApp(state: state));
    await state.start();
    await state.setLocale('am');
    await tester.pumpAndSettle();
    expect(find.text('ግባ'), findsWidgets);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

class _Recorder extends NoopNotifier {}

void notificationTests() {
  Map<String, dynamic> n(int id, {bool read = false}) => {'id': id, 'kind': 'new_message', 'title': 'New message', 'body': 'Hi $id', 'read': read, 'created_at': '2026-11-08T10:00:00Z', 'data': {'conversation_id': 3}};

  test('first check only remembers where things stand; later ones raise phone alerts', () async {
    final store = MemoryTokenStore()..token = 't';
    final notifier = _Recorder();
    var batch = [n(2), n(1)];
    final state = AppState(
      api: Api(client: MockClient((r) async {
        if (r.url.path.endsWith('/notifications')) return _json({'notifications': batch, 'unread': batch.length, 'meta': {'last': true}});
        if (r.url.path.endsWith('/me')) return _json({'user': _profile});
        if (r.url.path.endsWith('/conversations')) return _json({'conversations': [], 'unread': 0});
        return _json({});
      }), base: 'https://x.test'),
      store: store,
      notifier: notifier,
      pollEvery: const Duration(hours: 1),
    );
    await state.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifier.shown, isEmpty);
    expect(store.lastNotified, 2);
    expect(state.unreadNotifications, 2);

    batch = [n(4), n(3)];
    await state.checkNotifications();
    expect(notifier.shown, ['New message|Hi 3', 'New message|Hi 4']);
    expect(store.lastNotified, 4);

    await state.setPhoneAlerts(false);
    batch = [n(5)];
    await state.checkNotifications();
    expect(notifier.shown.length, 2);
    state.dispose();
  });

  test('a notification parses its targets', () {
    final item = AppNotification.fromJson({'id': 1, 'kind': 'booking_requested', 'title': 'T', 'body': 'B', 'read': false, 'data': {'itinerary_id': 9, 'booking_id': 4}});
    expect(item.tripId, 9);
    expect(item.bookingId, 4);
    expect(item.conversationId, isNull);
  });
}
