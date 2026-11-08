import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api.dart';
import 'token_store.dart';

enum AuthStatus { starting, signedOut, signedIn, offline }

/// What the whole app shares: who is signed in, the server settings, the language and the unread count.
class AppState extends ChangeNotifier {
  AppState({required this.api, required this.store}) {
    api.onUnauthorized = _expire;
  }

  final Api api;
  final TokenStore store;

  AuthStatus status = AuthStatus.starting;
  Profile? user;
  AppConfig config = AppConfig.fallback;
  String locale = 'en';
  int unreadMessages = 0;
  bool offline = false;

  /// Opens the app: restores the language and token, loads settings, and checks the token still works.
  Future<void> start() async {
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

  Future<void> loadConfig() async {
    try {
      config = await api.config();
      offline = false;
    } on ApiException {
      offline = true;
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final session = await api.signIn(email.trim(), password);
    await _adopt(session);
  }

  Future<void> signUp(String name, String email, String password) async {
    final session = await api.signUp(name.trim(), email.trim(), password);
    await _adopt(session);
  }

  Future<void> _adopt(({String token, Profile user}) session) async {
    api.token = session.token;
    await store.saveToken(session.token);
    user = session.user;
    status = AuthStatus.signedIn;
    notifyListeners();
    refreshUnread();
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

  void updateUser(Profile profile) {
    user = profile;
    notifyListeners();
  }
}
