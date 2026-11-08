import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the sign-in token (and chosen language) on the phone, in the platform's secure storage.
abstract class TokenStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> clearToken();
  Future<String?> readLocale();
  Future<void> saveLocale(String locale);
  Future<int?> readLastNotified();
  Future<void> saveLastNotified(int id);
  Future<bool> readPhoneAlerts();
  Future<void> savePhoneAlerts(bool on);
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: 'token');
  @override
  Future<void> saveToken(String token) => _storage.write(key: 'token', value: token);
  @override
  Future<void> clearToken() => _storage.delete(key: 'token');
  @override
  Future<String?> readLocale() => _storage.read(key: 'locale');
  @override
  Future<void> saveLocale(String locale) => _storage.write(key: 'locale', value: locale);
  @override
  Future<int?> readLastNotified() async => int.tryParse(await _storage.read(key: 'last_notified') ?? '');
  @override
  Future<void> saveLastNotified(int id) => _storage.write(key: 'last_notified', value: '$id');
  @override
  Future<bool> readPhoneAlerts() async => (await _storage.read(key: 'phone_alerts')) != 'off';
  @override
  Future<void> savePhoneAlerts(bool on) => _storage.write(key: 'phone_alerts', value: on ? 'on' : 'off');
}

/// For tests: nothing touches the device.
class MemoryTokenStore implements TokenStore {
  String? token;
  String? locale;
  int? lastNotified;
  bool phoneAlerts = true;

  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> saveToken(String value) async => token = value;
  @override
  Future<void> clearToken() async => token = null;
  @override
  Future<String?> readLocale() async => locale;
  @override
  Future<void> saveLocale(String value) async => locale = value;
  @override
  Future<int?> readLastNotified() async => lastNotified;
  @override
  Future<void> saveLastNotified(int id) async => lastNotified = id;
  @override
  Future<bool> readPhoneAlerts() async => phoneAlerts;
  @override
  Future<void> savePhoneAlerts(bool on) async => phoneAlerts = on;
}
