import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../core/format.dart';
import 'bookings_screen.dart';
import 'home_tab.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'offer_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'trip_screen.dart';

/// Lets the home tab hand a route to the search tab.
class SearchRequest extends ChangeNotifier {
  Place? from;
  Place? to;
  String? city; // set for a search inside one city
  int serial = 0;

  void set(Place? newFrom, Place? newTo, {String? inCity}) {
    from = newFrom;
    to = newTo;
    city = inCity;
    serial++;
    notifyListeners();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _tab = 'home';
  final _search = SearchRequest();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final driver = app.driverMode;
    // Drivers manage their own rides, so they have no search tab; switching to passenger mode brings it back.
    final ids = driver ? const ['home', 'bookings', 'profile'] : const ['home', 'search', 'bookings', 'profile'];
    const pages = ['home', 'search', 'bookings', 'profile'];
    final current = ids.contains(_tab) ? _tab : 'home';
    return Scaffold(
      appBar: current == 'home'
          ? null
          : AppBar(
        titleSpacing: 16,
        title: const BrandLogo(),
        actions: [
          IconButton(
            tooltip: context.t('notifications'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) => app.checkNotifications()),
            icon: Badge(isLabelVisible: app.unreadNotifications > 0, label: Text('${app.unreadNotifications}'), child: const Icon(Icons.notifications_none)),
          ),
          IconButton(
            tooltip: context.t('messages'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesScreen())).then((_) => app.refreshUnread()),
            icon: Badge(isLabelVisible: app.unreadMessages > 0, label: Text('${app.unreadMessages}'), child: const Icon(Icons.chat_bubble_outline)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: pages.indexOf(current), children: [
        HomeTab(key: ValueKey('home-$driver'), onOffer: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfferScreen()))),
        SearchTab(request: _search),
        BookingsTab(key: ValueKey('bookings-$driver')),
        const ProfileTab(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: ids.indexOf(current),
        onDestinationSelected: (i) {
          setState(() => _tab = ids[i]);
        },
        destinations: [
          for (final id in ids)
            switch (id) {
              'home' => NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: context.t('tab_home')),
              'search' => NavigationDestination(icon: const Icon(Icons.search), label: context.t('tab_search')),
              'bookings' => NavigationDestination(icon: const Icon(Icons.confirmation_number_outlined), selectedIcon: const Icon(Icons.confirmation_number), label: context.t(driver ? 'tab_requests' : 'tab_bookings')),
              _ => NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.t('tab_profile')),
            },
        ],
      ),
    );
  }
}

/// Asks before switching between riding and driving, then saves the choice on the account.
Future<void> switchMode(BuildContext context, String mode) async {
  final app = context.read<AppState>();
  if (app.user?.appMode == mode) return;
  try {
    await app.setMode(mode);
    if (context.mounted) showMessage(context, context.tr(mode == 'driver' ? 'now_driver' : 'now_passenger'));
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(context, e), error: true);
  }
}

/// The ride that is coming up next: a passenger's confirmed or pending seat, or a driver's next trip.
class NextRideCard extends StatefulWidget {
  const NextRideCard({super.key, required this.driver});
  final bool driver;

  @override
  State<NextRideCard> createState() => _NextRideCardState();
}

class _NextRideCardState extends State<NextRideCard> {
  ({int id, String title, String when, String? status, int pending})? _next;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      if (widget.driver) {
        final trips = (await app.api.myTrips()).items.where((t) => !t.cancelled && (t.commute || (t.leaveDate?.isAfter(DateTime.now()) ?? false))).toList()
          ..sort((a, b) => (a.leaveDate ?? DateTime(2100)).compareTo(b.leaveDate ?? DateTime(2100)));
        if (trips.isEmpty) return;
        final pending = (await app.api.bookings()).received.where((b) => b.trip.id == trips.first.id && b.status == 'pending').length;
        final t = trips.first;
        _set((id: t.id, title: '${t.startAddress} → ${t.endAddress}', when: t.commute ? (t.scheduleSummary ?? '') : formatDateTime(t.leaveDate!, locale: app.locale), status: null, pending: pending));
      } else {
        final mine = (await app.api.bookings()).made.where((b) => b.isActive && !b.completed && !b.trip.cancelled && (b.trip.commute || (b.trip.leaveDate?.isAfter(DateTime.now()) ?? false))).toList()
          ..sort((a, b) => (a.trip.leaveDate ?? DateTime(2100)).compareTo(b.trip.leaveDate ?? DateTime(2100)));
        if (mine.isEmpty) return;
        final b = mine.first;
        _set((id: b.trip.id, title: '${b.trip.startAddress} → ${b.trip.endAddress}', when: b.trip.commute ? (b.trip.scheduleSummary ?? '') : formatDateTime(b.trip.leaveDate!, locale: app.locale), status: b.status, pending: 0));
      }
    } catch (_) {
      // The home screen works without this card.
    }
  }

  void _set(({int id, String title, String when, String? status, int pending}) value) {
    if (mounted) setState(() => _next = value);
  }

  @override
  Widget build(BuildContext context) {
    final next = _next;
    if (next == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: brand,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: next.id))).then((_) => _load()),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t(widget.driver ? 'next_drive' : 'next_ride').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(next.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(next.when, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  if (next.status != null || next.pending > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Text(next.status != null ? context.t('status_${next.status}') : '${next.pending} ${context.t('requests').toLowerCase()}', style: const TextStyle(color: brand, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ],
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }
}
