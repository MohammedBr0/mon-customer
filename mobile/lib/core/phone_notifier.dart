import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Shows a notification in the phone's notification shade.
abstract class PhoneNotifier {
  Future<void> init();
  Future<void> show(int id, String title, String body);

  /// Replaces every scheduled ride reminder with the given ones. Reminders fire even when the app is closed.
  Future<void> scheduleReminders(List<({int id, DateTime at, String title, String body})> reminders);
}

/// Does nothing. Used in tests and when the platform has no notification support.
class NoopNotifier implements PhoneNotifier {
  final List<String> shown = [];

  @override
  Future<void> init() async {}
  @override
  Future<void> show(int id, String title, String body) async => shown.add('$title|$body');

  List<({int id, DateTime at, String title, String body})> scheduled = [];
  @override
  Future<void> scheduleReminders(List<({int id, DateTime at, String title, String body})> reminders) async => scheduled = reminders;
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

  // Reminder ids live in their own range so replacing them never touches other notifications.
  static const _reminderBase = 900000;
  static const _reminderSlots = 40;
  bool _zonesReady = false;

  @override
  Future<void> scheduleReminders(List<({int id, DateTime at, String title, String body})> reminders) async {
    if (!_ready) return;
    try {
      if (!_zonesReady) {
        tzdata.initializeTimeZones();
        _zonesReady = true;
      }
      for (var slot = 0; slot < _reminderSlots; slot++) {
        await _plugin.cancel(id: _reminderBase + slot);
      }
      var slot = 0;
      for (final r in reminders.take(_reminderSlots)) {
        await _plugin.zonedSchedule(
          id: _reminderBase + slot++,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
          // Inexact needs no special permission; Android may deliver it a few minutes either side.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('arifway_reminders', 'Ride reminders', channelDescription: 'A reminder before your ride starts', importance: Importance.high, priority: Priority.high),
          ),
        );
      }
    } catch (_) {
      // Reminders are a convenience; the in-app list still shows every ride.
    }
  }
}
