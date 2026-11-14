import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icare/core/api.dart';
import 'package:icare/core/app_state.dart';
import 'package:icare/core/background_check.dart';
import 'package:icare/core/device_location.dart';
import 'package:icare/core/format.dart';
import 'package:icare/widgets/map_style.dart';
import 'package:icare/core/phone.dart';
import 'package:icare/core/pricing.dart';
import 'package:icare/core/reminders.dart';
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

    test('only positions inside Ethiopia count; maps are held to the country', () {
      expect(inEthiopia(9.03, 38.74), isTrue); // Addis Ababa
      expect(inEthiopia(13.5, 39.47), isTrue); // Mekelle
      expect(inEthiopia(-1.29, 36.82), isFalse); // Nairobi
      expect(inEthiopia(51.5, -0.12), isFalse); // London
      expect(ethiopiaBounds.contains(addisAbaba), isTrue);
      expect(ethiopiaBounds.contains(const LatLng(-1.29, 36.82)), isFalse);
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
    expect(find.textContaining('→ Mexico Square'), findsOneWidget);
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
    expect(find.textContaining('→ Adama'), findsOneWidget);
    expect(find.text('1 requests'), findsOneWidget);
    expect(find.textContaining('→ Mexico Square'), findsNothing);
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

  group('payments and identity', () {
    test('config lists the admins\' payment methods; a profile carries the driver\'s choices and document status', () {
      final config = AppConfig.fromJson({'payment_methods': [{'id': 1, 'name': 'Cash', 'needs_account': false}, {'id': 2, 'name': 'Telebirr', 'account_label': 'Telebirr number', 'needs_account': true}]});
      expect(config.paymentMethods.map((m) => m.name), ['Cash', 'Telebirr']);
      expect(config.paymentMethods.last.needsAccount, isTrue);

      final profile = Profile.fromJson({..._profile, 'payment_methods': [{'id': 2, 'name': 'Telebirr', 'account_number': '0911223344'}],
        'identity': [{'kind': 'driver_license', 'status': 'rejected', 'rejection_reason': 'Blurred'}, {'kind': 'national_id', 'status': 'missing'}]});
      expect(profile.payments.single.accountNumber, '0911223344');
      expect(profile.identity.first.rejectionReason, 'Blurred');
      expect(Profile.fromJson(_profile).identity, isEmpty);
    });

    test('a trip shows what the driver accepts, with or without the account', () {
      final trip = Trip.fromJson({'id': 1, 'driver': _profile, 'payment_methods': [{'id': 1, 'name': 'Cash'}, {'id': 2, 'name': 'Telebirr'}]});
      expect(trip.payments.map((p) => p.name), ['Cash', 'Telebirr']);
      expect(trip.payments.last.accountNumber, isNull);
    });

    test('saving payment methods and sending a document call the server', () async {
      final seen = <String, http.BaseRequest>{};
      final api = Api(client: MockClient.streaming((request, body) async {
        seen[request.url.path] = request;
        final bytes = await body.toBytes();
        if (request.url.path.endsWith('/me/payment_methods')) {
          expect(jsonDecode(utf8.decode(bytes))['methods'], [{'id': 2, 'account_name': 'Dawit', 'account_number': '0911223344'}]);
        } else {
          final text = String.fromCharCodes(bytes);
          expect(text, contains('name="kind"'));
          expect(text, contains('national_id'));
          expect(text, contains('filename="id.jpg"'));
          expect(request.headers['content-type'], startsWith('multipart/form-data'));
          expect(request.headers['Authorization'], 'Bearer tok');
        }
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'user': _profile}))), 200, headers: {'content-type': 'application/json'});
      }), base: 'https://x.test')
        ..token = 'tok';
      await api.savePaymentMethods(const [DriverPayment(id: 2, name: 'Telebirr', accountName: 'Dawit', accountNumber: '0911223344')]);
      await api.submitIdentity(kind: 'national_id', number: 'ET-1', imageBytes: [1, 2, 3], filename: 'id.jpg');
      expect(seen.keys, containsAll(['/api/v1/me/payment_methods', '/api/v1/me/identity']));
    });
  });

  group('pickup, names, price and reminders', () {
    test('a booking carries the passenger\'s pickup point; a trip its short names and live state', () {
      final booking = Booking.fromJson({
        'id': 1, 'status': 'pending', 'seats': 1, 'ride_dates': [], 'passenger': _profile, 'driver': _profile,
        'itinerary': {'id': 3, 'start_address': 'XQWR+7CV, Unnamed Road', 'end_address': 'Churchill Ave', 'start_name': 'Bole', 'end_name': 'Piassa', 'live': true},
        'price': {'price_per_seat': 100, 'rides': 1, 'fare_total': 100, 'fee_percent': 10, 'fee_amount': 10, 'passenger_total': 110, 'driver_payout': 100},
        'pickup': {'lat': 9.01, 'lng': 38.76, 'label': 'Mexico Square'},
      });
      expect(booking.pickup!.name, 'Mexico Square');
      expect(booking.pickup!.lat, 9.01);
      expect('${booking.trip.from} → ${booking.trip.to}', 'Bole → Piassa');
      expect(booking.trip.live, isTrue);

      final old = Trip.fromJson({'id': 1, 'start_address': 'A street', 'end_address': 'B street', 'driver': _profile});
      expect('${old.from} → ${old.to}', 'A street → B street'); // an older server without short names
      expect(old.live, isFalse);
    });

    test('booking sends the pickup point', () async {
      late Map<String, dynamic> sent;
      final api = Api(client: MockClient((r) async {
        sent = jsonDecode(r.body) as Map<String, dynamic>;
        return _json({'booking': {'id': 1, 'status': 'pending', 'seats': 1, 'ride_dates': [], 'passenger': _profile, 'driver': _profile, 'itinerary': {'id': 3},
          'price': {'price_per_seat': 1, 'rides': 1, 'fare_total': 1, 'fee_percent': 0, 'fee_amount': 0, 'passenger_total': 1, 'driver_payout': 1}}}, 201);
      }), base: 'https://x.test');
      await api.book(3, seats: 1, pickup: Place.pin(9.01, 38.76, 'Mexico Square'));
      expect(sent['booking']['pickup'], {'lat': 9.01, 'lng': 38.76, 'label': 'Mexico Square'});
    });

    test('a price is suggested from the distance, shared between seats and rounded to 5', () {
      expect(suggestedSeatPrice(distanceKm: 99, ratePerKm: 6, seats: 3, maxPrice: 2500), 200); // 594 / 3 = 198
      expect(suggestedSeatPrice(distanceKm: 7, ratePerKm: 6, seats: 3, maxPrice: 2500), 15); // 14 -> 15
      expect(suggestedSeatPrice(distanceKm: 1, ratePerKm: 6, seats: 4, maxPrice: 2500), 5); // never below 5
      expect(suggestedSeatPrice(distanceKm: 900, ratePerKm: 20, seats: 1, maxPrice: 2500), 2500); // never above the cap
      expect(suggestedSeatPrice(distanceKm: 50, ratePerKm: 0, seats: 3, maxPrice: 2500), isNull); // suggestions switched off
      expect(suggestedSeatPrice(distanceKm: 0, ratePerKm: 6, seats: 3, maxPrice: 2500), isNull);
    });

    test('the trip total is seats times price, less the fee when drivers pay it', () {
      expect(tripTotals(seatPrice: 200, seats: 3, feePercent: 10, driverPaysFee: false), (total: 600.0, driverKeeps: 600.0));
      expect(tripTotals(seatPrice: 200, seats: 3, feePercent: 10, driverPaysFee: true), (total: 600.0, driverKeeps: 540.0));
    });

    test('a one-off ride starts once; a past one never', () {
      final now = DateTime.utc(2026, 11, 10, 6);
      expect(nextStarts(leave: DateTime.utc(2026, 11, 10, 9), commute: false, now: now), [DateTime.utc(2026, 11, 10, 9)]);
      expect(nextStarts(leave: DateTime.utc(2026, 11, 9, 9), commute: false, now: now), isEmpty);
      expect(nextStarts(leave: null, commute: false, now: now), isEmpty);
    });

    test('a commute starts at the same Ethiopian time on each of its days', () {
      // First ride Monday 2 Nov 2026 at 07:30 in Ethiopia (04:30 UTC); now is Tuesday 10 Nov, 06:00 UTC.
      final leave = DateTime.utc(2026, 11, 2, 4, 30);
      final now = DateTime.utc(2026, 11, 10, 6);
      final driver = nextStarts(leave: leave, commute: true, weekdays: [1, 3], now: now); // Mondays and Wednesdays
      expect(driver, [DateTime.utc(2026, 11, 11, 4, 30), DateTime.utc(2026, 11, 16, 4, 30)]);
      final passenger = nextStarts(leave: leave, commute: true, rideDays: ['2026-11-10', '2026-11-12'], now: now);
      expect(passenger, [DateTime.utc(2026, 11, 12, 4, 30)]); // today's 07:30 has already gone
    });

    test('reminders are scheduled the chosen minutes before each ride, and cleared when switched off', () async {
      final notifier = NoopNotifier();
      final soon = DateTime.now().toUtc().add(const Duration(hours: 5));
      var minutes = 30;
      final state = AppState(
        api: Api(client: MockClient((r) async {
          if (r.url.path.endsWith('/me')) return _json({'user': {..._profile, 'reminder_minutes': minutes}});
          if (r.url.path.endsWith('/bookings')) {
            return _json({'made': [{'id': 1, 'status': 'confirmed', 'seats': 1, 'ride_dates': [], 'passenger': _profile, 'driver': _profile,
              'itinerary': {'id': 9, 'start_name': 'Bole', 'end_name': 'Piassa', 'leave_date': soon.toIso8601String()},
              'price': {'price_per_seat': 1, 'rides': 1, 'fare_total': 1, 'fee_percent': 0, 'fee_amount': 0, 'passenger_total': 1, 'driver_payout': 1}}], 'received': []});
          }
          return _json({'conversations': [], 'notifications': [], 'unread': 0});
        }), base: 'https://x.test'),
        store: MemoryTokenStore()..token = 't',
        notifier: notifier,
        pollEvery: const Duration(hours: 1),
      );
      await state.start();
      await state.syncReminders();
      expect(notifier.scheduled.single.body, contains('Bole → Piassa'));
      expect(soon.difference(notifier.scheduled.single.at).inMinutes, 30);

      minutes = 0;
      await state.setReminderMinutes(0);
      expect(notifier.scheduled, isEmpty);
      state.dispose();
    });

    test('live state: where the car is, and the driver\'s pickup pins', () {
      final live = LiveState.fromJson({'active': true, 'fresh': true, 'position': {'lat': 9.01, 'lng': 38.74, 'heading': 92.5}, 'pickups': [{'name': 'Rahel', 'lat': 9.0, 'lng': 38.7, 'label': 'Mexico', 'seats': 2}]});
      expect((live.lat, live.lng, live.heading), (9.01, 38.74, 92.5));
      expect(live.pickups.single.name, 'Rahel');
      final waiting = LiveState.fromJson({'active': true, 'position': null});
      expect(waiting.lat, isNull);
      expect(LiveState.fromJson({'active': false, 'ended_at': '2026-11-10T10:00:00Z'}).ended, isTrue);
    });
  });

  group('photos, FAN and refresh', () {
    test('a FAN is 16 digits, with or without spaces', () {
      expect(isFan('1234 5678 9012 3456'), isTrue);
      expect(isFan('1234567890123456'), isTrue);
      expect(isFan('1234-5678-9012-3456'), isTrue);
      expect(isFan('123456789012'), isFalse); // 12 digits is the FIN, not the FAN
      expect(isFan('12345678901234567'), isFalse);
      expect(isFan('abcd 5678 9012 3456'), isFalse);
    });

    test('a profile knows whether the ID and the licence were checked', () {
      final p = Profile.fromJson({..._profile, 'verified': true, 'licence_verified': false});
      expect(p.verified, isTrue);
      expect(p.licenceVerified, isFalse);
    });

    test('a profile photo is uploaded as a photo and can be removed', () async {
      final seen = <String>[];
      final api = Api(client: MockClient.streaming((request, body) async {
        seen.add('${request.method} ${request.url.path}');
        final bytes = await body.toBytes();
        if (request.method == 'POST') {
          expect(request.headers['content-type'], startsWith('multipart/form-data'));
          expect(String.fromCharCodes(bytes), contains('filename="me.jpg"'));
        }
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'user': {..._profile, 'image': 'https://x.test/avatars/7?v=1'}}))), 200, headers: {'content-type': 'application/json'});
      }), base: 'https://x.test');
      expect((await api.uploadAvatar([1, 2, 3], 'me.jpg')).image, 'https://x.test/avatars/7?v=1');
      await api.removeAvatar();
      expect(seen, ['POST /api/v1/me/avatar', 'DELETE /api/v1/me/avatar']);
    });
  });

  test('settings that fail to load at start are fetched again instead of staying empty', () async {
    var calls = 0;
    final state = _state((r) async {
      if (r.url.path.endsWith('/config')) {
        calls++;
        if (calls == 1) throw http.ClientException('server asleep');
        return _json({'payment_methods': [{'id': 1, 'name': 'Cash'}], 'vehicle_fields': [{'key': 'make', 'label': 'Make'}]});
      }
      return _json({});
    });
    await state.start();
    expect(state.configLoaded, isFalse);
    expect(state.config.paymentMethods, isEmpty);

    await state.loadConfig(); // what the retry timer and the screens do
    expect(state.configLoaded, isTrue);
    expect(state.config.paymentMethods.single.name, 'Cash');
    expect(state.config.vehicleFields.single.key, 'make');
    state.dispose();
  });

  group('wallet', () {
    test('config says whether the wallet is on and how to top up; an older server means off', () {
      final config = AppConfig.fromJson({'wallet': {'enabled': true, 'min_topup': 10, 'max_topup': 20000, 'min_withdrawal': 100}});
      expect(config.walletEnabled, isTrue);
      expect(config.minWithdrawal, 100);
      expect(AppConfig.fromJson({}).walletEnabled, isFalse);
    });

    test('history lines read as money in or out', () {
      expect(WalletEntry.fromJson({'id': 1, 'kind': 'topup', 'available_change': 500, 'held_change': 0}).amount, 500);
      expect(WalletEntry.fromJson({'id': 2, 'kind': 'hold', 'available_change': -220, 'held_change': 220}).amount, -220);
      expect(WalletEntry.fromJson({'id': 3, 'kind': 'payment', 'available_change': 0, 'held_change': -220}).amount, 220);
    });

    test('a booking knows how it is paid and whether the ride can be confirmed', () {
      final b = Booking.fromJson({'id': 1, 'status': 'confirmed', 'seats': 1, 'ride_dates': [], 'passenger': _profile, 'driver': _profile, 'itinerary': {'id': 3},
        'price': {'price_per_seat': 1, 'rides': 1, 'fare_total': 1, 'fee_percent': 0, 'fee_amount': 0, 'passenger_total': 1, 'driver_payout': 1},
        'payment': {'method': 'wallet', 'state': 'held', 'can_confirm': true}});
      expect((b.paymentMethod, b.paymentState, b.canConfirmRide), ('wallet', 'held', true));
    });

    test('top-up, its status, paying from the wallet, banks and withdrawing call the server', () async {
      final sent = <String, dynamic>{};
      final api = Api(client: MockClient((r) async {
        final key = '${r.method} ${r.url.path.replaceFirst('/api/v1', '')}';
        if (r.body.isNotEmpty) sent[key] = jsonDecode(r.body);
        if (key == 'POST /wallet/topup') return _json({'topup': {'id': 4, 'amount': 500, 'status': 'pending', 'final': false, 'checkout_url': 'https://checkout.chapa.co/checkout/payment/abc'}}, 201);
        if (key == 'GET /wallet/topups/4') return _json({'topup': {'id': 4, 'amount': 500, 'status': 'success', 'final': true}});
        if (key == 'GET /wallet/banks') return _json({'banks': [{'id': 855, 'name': 'telebirr', 'account_length': 10, 'mobile': true}]});
        if (key == 'GET /wallet') return _json({'wallet': {'available': 500, 'held': 0}, 'entries': [{'id': 1, 'kind': 'topup', 'available_change': 500, 'held_change': 0}], 'withdrawals': [], 'meta': {'last': true}});
        return _json({'booking': {'id': 1, 'status': 'pending', 'seats': 1, 'ride_dates': [], 'passenger': _profile, 'driver': _profile, 'itinerary': {'id': 3},
          'price': {'price_per_seat': 1, 'rides': 1, 'fare_total': 1, 'fee_percent': 0, 'fee_amount': 0, 'passenger_total': 1, 'driver_payout': 1}}}, 201);
      }), base: 'https://x.test');

      final topup = await api.startTopup(500);
      expect(topup.done, isFalse);
      expect(topup.checkoutUrl, startsWith('https://checkout.chapa.co/'));
      expect(sent['POST /wallet/topup'], {'amount': 500.0});
      final settled = await api.topupStatus(4);
      expect((settled.done, settled.succeeded), (true, true));
      expect((await api.wallet()).balance.available, 500);

      await api.book(3, seats: 1, paymentMethod: 'wallet');
      expect(sent['POST /itineraries/3/bookings']['booking']['payment_method'], 'wallet');
      final bank = (await api.payoutBanks()).single;
      expect((bank.id, bank.mobile, bank.accountLength), (855, true, 10));
      await api.requestWithdrawal(amount: 300, bank: bank, accountNumber: '0911223344', accountName: 'Dawit');
      expect(sent['POST /wallet/withdraw'], {'amount': 300.0, 'bank_code': 855, 'method_name': 'telebirr', 'account_number': '0911223344', 'account_name': 'Dawit'});
    });
  });

  group('notifications while the app is closed', () {
    Map<String, dynamic> note(int id, {bool read = false}) => {'id': id, 'kind': 'announcement', 'title': 'Notice $id', 'body': 'Body $id', 'read': read, 'data': {}};
    Api apiReturning(List<Map<String, dynamic>> Function() items, {List<Uri>? seen}) => Api(
          client: MockClient((r) async {
            seen?.add(r.url);
            expect(r.headers['Authorization'], 'Bearer tok');
            return _json({'notifications': items(), 'unread': items().length, 'meta': {'last': true}});
          }),
          base: 'https://x.test',
        );

    test('a background check shows what is new, once, and remembers where it got to', () async {
      final store = MemoryTokenStore()
        ..token = 'tok'
        ..lastNotified = 10;
      final notifier = NoopNotifier();
      final seen = <Uri>[];
      var items = [note(12), note(11)];
      final api = apiReturning(() => items, seen: seen);

      await checkInBackground(store: store, api: api, notifier: notifier);
      expect(seen.single.queryParameters['after'], '10');
      expect(notifier.shown, ['Notice 11|Body 11', 'Notice 12|Body 12']);
      expect(store.lastNotified, 12);

      items = [];
      await checkInBackground(store: store, api: api, notifier: notifier);
      expect(notifier.shown.length, 2); // nothing new: nothing shown again
    });

    test('it stays quiet when signed out, when alerts are off, and on a phone\'s first check', () async {
      final notifier = NoopNotifier();
      final api = apiReturning(() => [note(5)]);

      await checkInBackground(store: MemoryTokenStore(), api: api, notifier: notifier); // signed out
      final off = MemoryTokenStore()
        ..token = 'tok'
        ..lastNotified = 1
        ..phoneAlerts = false;
      await checkInBackground(store: off, api: api, notifier: notifier);
      final first = MemoryTokenStore()..token = 'tok';
      await checkInBackground(store: first, api: api, notifier: notifier);
      expect(notifier.shown, isEmpty);
      expect(first.lastNotified, 5); // only records where things stand
    });

    test('read notifications are not shown again', () async {
      final store = MemoryTokenStore()
        ..token = 'tok'
        ..lastNotified = 1;
      final notifier = NoopNotifier();
      await checkInBackground(store: store, api: apiReturning(() => [note(3, read: true), note(2)]), notifier: notifier);
      expect(notifier.shown, ['Notice 2|Body 2']);
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
