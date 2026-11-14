import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'phone_notifier.dart';
import 'token_store.dart';

const _taskName = 'arifway.notifications';

/// Fetches notifications newer than the last one this phone has shown, raises a phone alert for each unread
/// one, and remembers where it got to. Shared by the running app and the background check, so the two never
/// show the same notification twice. Returns the unread count, or null when nothing could be fetched.
///
/// The first time on a phone it only records where things stand, so old items do not flood the shade.
Future<int?> deliverNewNotifications({required Api api, required TokenStore store, required PhoneNotifier notifier, required bool alerts}) async {
  final last = await store.readLastNotified();
  final data = await api.notifications(after: last);
  if (data.items.isNotEmpty) {
    final newest = data.items.map((n) => n.id).reduce((a, b) => a > b ? a : b);
    if (last != null && alerts) {
      for (final n in data.items.where((n) => !n.read).toList().reversed.take(5)) {
        await notifier.show(n.id, n.title, n.body);
      }
    }
    await store.saveLastNotified(newest);
  } else if (last == null) {
    await store.saveLastNotified(0);
  }
  return data.unread;
}

/// What Android runs every 15 minutes or so while the app is closed.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await checkInBackground();
    } catch (_) {
      // A missed check is made up by the next one.
    }
    return true;
  });
}

/// One background check: signed in and alerts on? Then fetch and show what is new.
Future<void> checkInBackground({TokenStore? store, Api? api, PhoneNotifier? notifier}) async {
  store ??= const SecureTokenStore();
  final token = await store.readToken();
  if (token == null || !await store.readPhoneAlerts()) return;

  api ??= Api();
  api
    ..token = token
    ..locale = await store.readLocale() ?? 'en';
  notifier ??= LocalPhoneNotifier(askPermission: false); // nothing can ask for permission while the app is closed
  await notifier.init();
  await deliverNewNotifications(api: api, store: store, notifier: notifier, alerts: true);
}

/// Asks Android to keep checking for notifications while the app is closed. Android decides the exact timing:
/// about every 15 minutes at best, less often when the phone is saving battery.
Future<void> scheduleBackgroundChecks() async {
  try {
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      'arifway-notifications',
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {
    // The app still shows notifications while it is open.
  }
}
