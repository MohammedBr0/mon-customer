import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icare/core/api.dart';
import 'package:icare/core/app_state.dart';
import 'package:icare/core/format.dart';
import 'package:icare/core/phone.dart';
import 'package:icare/core/polyline.dart';
import 'package:icare/widgets/common.dart';
import 'package:icare/widgets/map_markers.dart';
import 'package:provider/provider.dart';
import 'package:icare/widgets/route_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

    test('a trip lists its distance and who is riding', () {
      final trip = Trip.fromJson({'id': 1, 'distance_km': 98.4, 'passengers': [{'first_name': 'Rahel', 'image': null, 'seats': 2}], 'driver': _profile});
      expect(trip.distanceKm, 98.4);
      expect(trip.passengers.single.firstName, 'Rahel');
      expect(trip.passengers.single.seats, 2);
      expect(Trip.fromJson({'id': 2, 'driver': _profile}).passengers, isEmpty);
    });

    test('a trip carries its route and end points', () {
      final trip = Trip.fromJson({'id': 1, 'overview_polyline': 'abc', 'start_location': {'lat': 9.0, 'lng': 38.7}, 'end_location': {'lat': 9.1, 'lng': 38.8}, 'driver': _profile});
      expect(trip.polyline, 'abc');
      expect(trip.startLat, 9.0);
      expect(trip.endLng, 38.8);
    });

    test('a car faces the way its ride is heading', () {
      expect(bearing(const LatLng(9.0, 38.7), const LatLng(9.1, 38.7)), closeTo(0, 0.5)); // north
      expect(bearing(const LatLng(9.0, 38.7), const LatLng(9.0, 38.8)), closeTo(90, 0.5)); // east
      expect(bearing(const LatLng(9.0, 38.7), const LatLng(8.9, 38.7)), closeTo(180, 0.5)); // south
    });

    test('distance between points, for sizing a search area', () {
      expect(distanceKm(const LatLng(9.03, 38.74), const LatLng(9.03, 38.74)), 0);
      expect(distanceKm(const LatLng(9.03, 38.74), const LatLng(9.03, 38.83)), closeTo(9.9, 0.3));
    });

    test('a nearby search sends the point and radius', () async {
      late Uri seen;
      final api = Api(client: MockClient((r) async {
        seen = r.url;
        return _json({'itineraries': [], 'meta': {'page': 1, 'last': true}});
      }), base: 'https://x.test');
      await api.trips(nearLat: 9.03, nearLng: 38.74, radiusKm: 6.5);
      expect(seen.queryParameters, containsPair('near_lat', '9.03'));
      expect(seen.queryParameters, containsPair('radius_km', '6.5'));
    });

    test('posting sends a Google place by name and coordinates, a listed town by key', () {
      expect(Api.placeRef(Place.pin(9.01, 38.74, 'Mexico Square')), {'name': 'Mexico Square', 'lat': 9.01, 'lng': 38.74});
      expect(Api.placeRef(const Place(key: 'adama', name: 'Adama', lat: 8.54, lng: 39.27)), {'key': 'adama'});
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

  group('phone sign-up and roles', () {
    test('accepts the ways an Ethiopian mobile number is written', () {
      for (final written in ['0911 22 33 44', '911223344', '251911223344', '+251 911 223 344', '0911-223-344']) {
        expect(normalizeEthiopianPhone(written), '+251911223344');
      }
      expect(normalizeEthiopianPhone('0711223344'), '+251711223344');
      for (final bad in ['0811223344', '091122334', '+15551234567', 'abc', '']) {
        expect(normalizeEthiopianPhone(bad), isNull);
      }
    });

    test('a sign-in box takes a phone number or an email', () {
      expect(isValidLogin('0911223344'), isTrue);
      expect(isValidLogin('a@b.co'), isTrue);
      expect(isValidLogin('a@b'), isFalse);
      expect(isValidLogin('hello'), isFalse);
    });

    test('sign-up sends the phone number and the chosen role; switching saves it', () async {
      final bodies = <String, dynamic>{};
      final state = _state((r) async {
        if (r.url.path.endsWith('/auth/sign_up')) {
          bodies['sign_up'] = jsonDecode(r.body);
          return _json({'token': 'tok', 'user': {..._profile, 'app_mode': 'driver', 'phone_account': true, 'phone': '+251911223344'}});
        }
        if (r.url.path.endsWith('/me') && r.method == 'PATCH') {
          bodies['me'] = jsonDecode(r.body);
          return _json({'user': {..._profile, 'app_mode': 'passenger'}});
        }
        return _json({'conversations': [], 'notifications': [], 'unread': 0});
      });
      await state.signUp('Abebe', '+251911223344', 'secret123', mode: 'driver');
      expect(bodies['sign_up'], containsPair('phone', '+251911223344'));
      expect(bodies['sign_up'], containsPair('app_mode', 'driver'));
      expect(state.driverMode, isTrue);
      expect(state.user!.phoneAccount, isTrue);

      await state.setMode('passenger');
      expect(bodies['me']['user'], {'app_mode': 'passenger'});
      expect(state.driverMode, isFalse);
      state.dispose();
    });

    test('an older server without a mode means passenger', () {
      expect(Profile.fromJson(_profile).appMode, 'passenger');
    });
  });

  testWidgets('with SMS codes on, registering texts a code and finishes on the code screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final calls = <String, dynamic>{};
    final state = _state((r) async {
      if (r.url.path.endsWith('/config')) return _json({'phone_verification': true});
      if (r.url.path.endsWith('/auth/send_code')) {
        calls['send_code'] = jsonDecode(r.body);
        return _json({'verification_id': 'ver-9', 'expires_in': 600, 'code_length': 6}, 201);
      }
      if (r.url.path.endsWith('/auth/sign_up')) {
        calls['sign_up'] = jsonDecode(r.body);
        return _json({'token': 'tok', 'user': {..._profile, 'app_mode': 'driver', 'phone_account': true}}, 201);
      }
      return _json({'conversations': [], 'notifications': [], 'itineraries': [], 'unread': 0, 'meta': {'last': true}});
    });
    await tester.pumpWidget(IcareApp(state: state));
    await state.start();
    await tester.pumpAndSettle();
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Abebe Bikila');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0911 22 33 44');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
    await tester.tap(find.text('Driver'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls['send_code'], {'phone': '+251911223344'});
    expect(find.text('Enter the code'), findsOneWidget);
    expect(calls.containsKey('sign_up'), isFalse);

    await tester.enterText(find.widgetWithText(TextField, 'Code'), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls['sign_up'], containsPair('verification_id', 'ver-9'));
    expect(calls['sign_up'], containsPair('code', '123456'));
    expect(calls['sign_up'], containsPair('app_mode', 'driver'));
    expect(state.status, AuthStatus.signedIn);
    state.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('registration asks for a phone number and a role', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final state = _state((_) async => _json({}));
    await tester.pumpWidget(IcareApp(state: state));
    await state.start();
    await tester.pumpAndSettle();
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Passenger'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '12345');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an Ethiopian mobile number, like 0911 22 33 44'), findsOneWidget);
  });

  testWidgets('place search shows Google results as you type and returns the chosen place', (tester) async {
    final state = _state((r) async {
      if (r.url.path.endsWith('/maps/search')) {
        expect(r.url.queryParameters['q'], 'Bole');
        return _json({'places': [{'name': 'Bole Medhanialem', 'address': 'Bole, Addis Ababa', 'lat': 8.99, 'lng': 38.78}]});
      }
      return _json({'places': [{'key': 'adama', 'name': 'Adama', 'lat': 8.54, 'lng': 39.27}]});
    });
    await state.loadConfig();
    Place? picked;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () async => picked = await pickPlace(context), child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Adama'), findsOneWidget); // listed towns before typing
    expect(find.text('Choose on map'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bole');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Bole Medhanialem'), findsOneWidget);
    await tester.tap(find.text('Bole Medhanialem'));
    await tester.pumpAndSettle();
    expect(picked?.isPin, isTrue);
    expect(picked?.lat, 8.99);
  });

  Map<String, dynamic> homeTrip(int id, String to, int seats) => {
        'id': id, 'start_address': 'Bole Medhanialem, Addis Ababa', 'end_address': to, 'leave_date': '2030-12-01T05:00:00Z',
        'price_per_seat': 120, 'passenger_price_per_seat': 135, 'seats_total': 3, 'seats_available': seats,
        'start_location': {'lat': 9.0, 'lng': 38.78}, 'driver': _profile,
      };

  Future<AppState> openHome(WidgetTester tester, String mode) async {
    tester.view.physicalSize = const Size(720, 1480); // a small phone: 360 x 740 dp
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final booking = {
      'id': 5, 'status': 'pending', 'seats': 1, 'ride_dates': [], 'itinerary': homeTrip(7, 'Adama', 3), 'passenger': _profile, 'driver': _profile,
      'price': {'price_per_seat': 120, 'rides': 1, 'fare_total': 120, 'fee_percent': 10, 'fee_amount': 12, 'passenger_total': 132, 'driver_payout': 120},
    };
    final state = _state((r) async {
      if (r.url.path.endsWith('/me')) return _json({'user': {..._profile, 'app_mode': mode, 'verified': true}});
      if (r.url.path.endsWith('/itineraries/mine')) return _json({'itineraries': [homeTrip(7, 'Adama', 3)], 'meta': {'page': 1, 'last': true}});
      if (r.url.path.endsWith('/itineraries')) return _json({'itineraries': [homeTrip(1, 'Megenagna taxi station with a very long name indeed', 1), homeTrip(2, 'Mexico Square', 3)], 'meta': {'page': 1, 'last': true}});
      if (r.url.path.endsWith('/bookings')) return _json({'made': [], 'received': [booking]});
      return _json({'conversations': [], 'notifications': [], 'unread': 0, 'meta': {'last': true}});
    }, store: MemoryTokenStore()..token = 't');
    await tester.pumpWidget(IcareApp(state: state));
    await state.start();
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('a passenger\'s home lists rides near them with price, seats and one main action', (tester) async {
    final state = await openHome(tester, 'passenger');
    expect(find.text('SHARED RIDES NEAR YOU'), findsOneWidget);
    expect(find.text('To Mexico Square'), findsOneWidget);
    expect(find.textContaining('/Seat'), findsNWidgets(2));
    expect(find.text('1 seats left'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Find a ride'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget); // the search tab
    state.dispose();
  });

  testWidgets('a driver\'s home shows only their own rides and waiting requests, not other drivers\' trips', (tester) async {
    final state = await openHome(tester, 'driver');
    expect(find.text('YOUR RIDES'), findsOneWidget);
    expect(find.text('To Adama'), findsOneWidget);
    expect(find.text('1 requests'), findsOneWidget);
    expect(find.text('To Mexico Square'), findsNothing);
    expect(find.text('Where to?'), findsNothing);
    expect(find.text('Search'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Post a ride'), findsOneWidget);
    state.dispose();
  });

  testWidgets('light, dark or automatic appearance is remembered', (tester) async {
    final store = MemoryTokenStore();
    final state = _state((_) async => _json({}), store: store);
    await tester.pumpWidget(IcareApp(state: state));
    await state.start();
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.system);

    await state.setThemeMode('dark');
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
    expect(store.themeMode, 'dark');

    final again = _state((_) async => _json({}), store: store);
    await again.start();
    expect(again.themeMode, 'dark');
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
    expect(find.text('Enter your phone number or email'), findsOneWidget);
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
