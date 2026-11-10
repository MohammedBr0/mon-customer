import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows a notification in the phone's notification shade.
abstract class PhoneNotifier {
  Future<void> init();
  Future<void> show(int id, String title, String body);
}

/// Does nothing. Used in tests and when the platform has no notification support.
class NoopNotifier implements PhoneNotifier {
  final List<String> shown = [];

  @override
  Future<void> init() async {}
  @override
  Future<void> show(int id, String title, String body) async => shown.add('$title|$body');
}

class LocalPhoneNotifier implements PhoneNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  @override
  Future<void> init() async {
    try {
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false; // The app still works; notifications stay in the in-app inbox.
    }
  }

  @override
  Future<void> show(int id, String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('arifway_updates', 'Trip updates', channelDescription: 'Seat requests, bookings and messages', importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (_) {
      // Permission refused or the system blocked it: ignore.
    }
  }
}
