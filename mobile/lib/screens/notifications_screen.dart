import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'trip_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<AppNotification> _items = [];
  int _page = 0;
  bool _last = false;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    final app = context.read<AppState>();
    setState(() => _loading = true);
    try {
      final next = reset ? 1 : _page + 1;
      final data = await app.api.notifications(page: next);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(data.items);
        _page = next;
        _last = data.last;
        _error = null;
      });
      app.setUnreadNotifications(data.unread);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAll() async {
    final app = context.read<AppState>();
    try {
      await app.api.markAllNotificationsRead();
      app.setUnreadNotifications(0);
      await _load(reset: true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    }
  }

  Future<void> _open(AppNotification n) async {
    final app = context.read<AppState>();
    if (!n.read) {
      app.api.markNotificationRead(n.id).then((_) => app.checkNotifications(), onError: (_) {});
      setState(() {
        final i = _items.indexWhere((e) => e.id == n.id);
        if (i >= 0) {
          _items[i] = AppNotification(id: n.id, kind: n.kind, title: n.title, body: n.body, read: true, createdAt: n.createdAt, tripId: n.tripId, bookingId: n.bookingId, conversationId: n.conversationId);
        }
      });
      app.setUnreadNotifications((app.unreadNotifications - 1).clamp(0, 9999));
    }
    final Widget? target = n.conversationId != null
        ? ChatScreen(conversationId: n.conversationId, title: n.title)
        : n.tripId != null
            ? TripScreen(tripId: n.tripId!)
            : null;
    if (target != null) await Navigator.push(context, MaterialPageRoute(builder: (_) => target));
  }

  IconData _icon(String kind) => switch (kind) {
        'booking_requested' => Icons.event_seat_outlined,
        'booking_confirmed' => Icons.check_circle_outline,
        'booking_declined' || 'booking_cancelled' || 'itinerary_cancelled' => Icons.cancel_outlined,
        'date_skipped' => Icons.event_busy_outlined,
        'new_message' => Icons.chat_bubble_outline,
        'review_received' => Icons.star_outline,
        'alert_match' => Icons.notifications_active_outlined,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('notifications')),
        actions: [
          if (app.unreadNotifications > 0) TextButton(onPressed: _markAll, child: Text(context.t('mark_all_read'))),
        ],
      ),
      body: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty && _error != null
              ? ErrorState(_error!, onRetry: () => _load(reset: true))
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: _items.isEmpty
                      ? ListView(children: [const SizedBox(height: 80), EmptyState(context.t('no_notifications'), icon: Icons.notifications_none)])
                      : ListView.separated(
                          itemCount: _items.length + (_last ? 0 : 1),
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            if (i == _items.length) {
                              return Padding(padding: const EdgeInsets.all(12), child: OutlinedButton(onPressed: () => _load(), child: Text(context.t('load_more'))));
                            }
                            final n = _items[i];
                            return ListTile(
                              tileColor: n.read ? null : scheme.primaryContainer.withValues(alpha: 0.35),
                              leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(_icon(n.kind), color: scheme.onPrimaryContainer)),
                              title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w600 : FontWeight.w800)),
                              subtitle: Text([n.body, if (n.createdAt != null) formatDateTime(n.createdAt!, locale: app.locale)].where((s) => s.isNotEmpty).join('\n')),
                              isThreeLine: n.body.isNotEmpty && n.createdAt != null,
                              onTap: () => _open(n),
                            );
                          },
                        ),
                ),
    );
  }
}
