import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api.dart';
import 'phone_notifier.dart';
import 'reminders.dart';
import 'token_store.dart';

enum AuthStatus { starting, signedOut, signedIn, offline }

/// What the whole app shares: who is signed in, the server settings, the language and the unread count.
class AppState extends ChangeNotifier {
  AppState({required this.api, required this.store, PhoneNotifier? notifier, this.pollEvery = const Duration(seconds: 30)}) : notifier = notifier ?? NoopNotifier() {
    api.onUnauthorized = _expire;
  }

  final Api api;
  final TokenStore store;
  final PhoneNotifier notifier;
  final Duration pollEvery;
  Timer? _timer;
  int unreadNotifications = 0;
  bool phoneAlerts = true;
  String themeMode = 'system'; // system | light | dark
  bool _checking = false;

  AuthStatus status = AuthStatus.starting;
  Profile? user;
  AppConfig config = AppConfig.fallback;
  String locale = 'en';
  int unreadMessages = 0;
  bool offline = false;

  /// Opens the app: restores the language and token, loads settings, and checks the token still works.
  Future<void> start() async {
    phoneAlerts = await store.readPhoneAlerts();
    themeMode = await store.readThemeMode() ?? 'system';
    locale = await store.readLocale() ?? 'en';
    api.locale = locale;
    await loadConfig();
    final token = await store.readToken();
    if (token == null) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    api.token = token;
    try {
      user = await api.me();
      status = AuthStatus.signedIn;
      offline = false;
      refreshUnread();
      _startPolling();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _clear();
        status = AuthStatus.signedOut;
      } else {
        // No connection: keep the token and let the person retry instead of signing them out.
        offline = true;
        status = AuthStatus.offline;
      }
    }
    notifyListeners();
  }

  /// True once the server's settings (payment methods, vehicle questions, fees, towns) have arrived.
  bool configLoaded = false;
  Timer? _configRetry;

  /// Fetches the server's settings. The server can take up to a minute to wake after being idle, so a failed
  /// attempt is retried in the background until it succeeds instead of leaving the app on empty defaults.
  Future<void> loadConfig() async {
    try {
      config = await api.config();
      configLoaded = true;
      offline = false;
      _configRetry?.cancel();
      _configRetry = null;
    } on ApiException {
      offline = true;
      if (!configLoaded) {
        _configRetry ??= Timer.periodic(const Duration(seconds: 8), (_) {
          if (!_disposed) loadConfig();
        });
      }
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final session = await api.signIn(email.trim(), password);
    await _adopt(session);
  }

  Future<void> signUp(String name, String phone, String password, {required String mode, String? verificationId, String? code}) async {
    final session = await api.signUp(name.trim(), phone.trim(), password, mode: mode, verificationId: verificationId, code: code);
    await _adopt(session);
  }

  Future<void> _adopt(({String token, Profile user}) session) async {
    api.token = session.token;
    await store.saveToken(session.token);
    user = session.user;
    status = AuthStatus.signedIn;
    notifyListeners();
    refreshUnread();
    _startPolling();
  }

  Future<void> signOut() async {
    await api.signOut();
    await _clear();
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    await _clear();
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> _expire() async {
    await _clear();
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> _clear() async {
    _timer?.cancel();
    notifier.scheduleReminders(const []);
    unreadNotifications = 0;
    api.token = null;
    user = null;
    unreadMessages = 0;
    await store.clearToken();
  }

  Future<void> setLocale(String value) async {
    locale = value;
    api.locale = value;
    await store.saveLocale(value);
    notifyListeners();
    if (status == AuthStatus.signedIn) {
      try {
        user = await api.updateMe({'locale': value == 'am' ? 'am-ET' : 'en-US'});
        notifyListeners();
      } on ApiException {
        // The language still changes on this phone.
      }
    }
  }

  Future<void> refreshUser() async {
    user = await api.me();
    notifyListeners();
  }

  Future<void> refreshUnread() async {
    try {
      unreadMessages = (await api.conversations()).unread;
      notifyListeners();
    } on ApiException {
      // Not critical.
    }
  }

  void _startPolling() {
    _timer?.cancel();
    notifier.init().then((_) => syncReminders());
    checkNotifications();
    _timer = Timer.periodic(pollEvery, (_) => checkNotifications());
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _configRetry?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  // Background checks can finish after the app state has gone; telling listeners then would throw.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Fetches anything new from the server, raises phone notifications for it, and updates the badges.
  /// The first time on a phone it only remembers where things stand, so old items do not flood the shade.
  Future<void> checkNotifications() async {
    if (status != AuthStatus.signedIn || _checking) return;
    _checking = true;
    try {
      final last = await store.readLastNotified();
      final data = await api.notifications(after: last);
      unreadNotifications = data.unread;
      if (data.items.isNotEmpty) {
        final newest = data.items.map((n) => n.id).reduce((a, b) => a > b ? a : b);
        if (last != null && phoneAlerts) {
          for (final n in data.items.where((n) => !n.read).toList().reversed.take(5)) {
            await notifier.show(n.id, n.title, n.body);
          }
        }
        await store.saveLastNotified(newest);
      } else if (last == null) {
        await store.saveLastNotified(0);
      }
      notifyListeners();
    } on ApiException {
      // Try again at the next tick.
    } finally {
      _checking = false;
    }
  }

  /// Texts shown in a ride reminder; set by the app so they follow the chosen language.
  ({String title, String Function(String trip, int minutes, bool driving) body}) reminderText = (title: 'Ride reminder', body: _defaultReminderBody);
  static String _defaultReminderBody(String trip, int minutes, bool driving) => '$trip starts in $minutes minutes';

  /// Schedules a phone reminder before each ride in the coming week (15 or 30 minutes ahead, as chosen).
  /// Call it after anything that changes someone's rides: signing in, booking, cancelling, posting a trip.
  Future<void> syncReminders() async {
    final minutes = user?.reminderMinutes ?? 0;
    if (status != AuthStatus.signedIn || minutes <= 0) {
      await notifier.scheduleReminders(const []);
      return;
    }
    try {
      final made = (await api.bookings()).made;
      final mine = driverMode ? (await api.myTrips()).items : const <Trip>[];
      final now = DateTime.now();
      await notifier.scheduleReminders([
        for (final ride in upcomingRides(made: made, mine: mine, now: now))
          if (ride.start.subtract(Duration(minutes: minutes)).isAfter(now))
            (id: ride.tripId, at: ride.start.subtract(Duration(minutes: minutes)), title: reminderText.title, body: reminderText.body(ride.title, minutes, ride.driving)),
      ]);
    } on ApiException {
      // Keep whatever was scheduled before; it is retried on the next change.
    }
  }

  Future<void> setReminderMinutes(int minutes) async {
    user = await api.updateMe({'reminder_minutes': minutes});
    notifyListeners();
    await syncReminders();
  }

  Future<void> setThemeMode(String mode) async {
    themeMode = mode;
    await store.saveThemeMode(mode);
    notifyListeners();
  }

  Future<void> setPhoneAlerts(bool on) async {
    phoneAlerts = on;
    await store.savePhoneAlerts(on);
    notifyListeners();
  }

  void setUnreadNotifications(int count) {
    unreadNotifications = count;
    notifyListeners();
  }

  bool get driverMode => user?.appMode == 'driver';

  /// Switches between riding and driving. The choice is saved on the account, so it follows the person.
  Future<void> setMode(String mode) async {
    user = await api.updateMe({'app_mode': mode});
    notifyListeners();
    syncReminders();
  }

  void updateUser(Profile profile) {
    user = profile;
    notifyListeners();
  }
}
