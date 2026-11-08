import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the sign-in token (and chosen language) on the phone, in the platform's secure storage.
abstract class TokenStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> clearToken();
  Future<String?> readLocale();
  Future<void> saveLocale(String locale);
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
}

/// For tests: nothing touches the device.
class MemoryTokenStore implements TokenStore {
  String? token;
  String? locale;

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
}
