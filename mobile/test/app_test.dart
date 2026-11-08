import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icare/core/api.dart';
import 'package:icare/core/app_state.dart';
import 'package:icare/core/format.dart';
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
