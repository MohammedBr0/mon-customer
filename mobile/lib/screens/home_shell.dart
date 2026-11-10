import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/paged_trips.dart';
import 'bookings_screen.dart';
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

  void _goSearch(Place? from, Place? to, {String? city}) {
    _search.set(from, to, inCity: city);
    setState(() => _tab = 'search');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final driver = app.driverMode;
    // Drivers get the Offer button; passengers get a simpler bar without it.
    final ids = driver ? const ['home', 'search', 'offer', 'bookings', 'profile'] : const ['home', 'search', 'bookings', 'profile'];
    const pages = ['home', 'search', 'bookings', 'profile'];
    final current = ids.contains(_tab) ? _tab : 'home';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('icare', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
        actions: [
          ModeSwitchChip(driver: driver),
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
        HomeTab(onRoute: _goSearch),
        SearchTab(request: _search),
        BookingsTab(key: ValueKey('bookings-$driver')),
        const ProfileTab(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: ids.indexOf(current),
        onDestinationSelected: (i) {
          if (ids[i] == 'offer') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OfferScreen()));
            return;
          }
          setState(() => _tab = ids[i]);
        },
        destinations: [
          for (final id in ids)
            switch (id) {
              'home' => NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: context.t('tab_home')),
              'search' => NavigationDestination(icon: const Icon(Icons.search), label: context.t('tab_search')),
              'offer' => NavigationDestination(icon: const CircleAvatar(radius: 18, backgroundColor: brand, child: Icon(Icons.add, color: Colors.white)), label: context.t('tab_offer')),
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

/// The current mode in the top bar; tap it to switch.
class ModeSwitchChip extends StatelessWidget {
  const ModeSwitchChip({super.key, required this.driver});
  final bool driver;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: context.t(driver ? 'switch_to_passenger' : 'switch_to_driver'),
        child: ActionChip(
          visualDensity: VisualDensity.compact,
          backgroundColor: driver ? scheme.primaryContainer : null,
          avatar: Icon(driver ? Icons.directions_car : Icons.airline_seat_recline_normal, size: 18),
          label: Text(context.t(driver ? 'role_driver' : 'role_passenger'), style: const TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () async {
            final target = driver ? 'passenger' : 'driver';
            if (await confirmDialog(context, context.tr(driver ? 'switch_to_passenger_q' : 'switch_to_driver_q'), action: context.tr(driver ? 'switch_to_passenger' : 'switch_to_driver')) && context.mounted) {
              await switchMode(context, target);
            }
          },
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onRoute});
  final void Function(Place? from, Place? to, {String? city}) onRoute;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final config = app.config;
    final scheme = Theme.of(context).colorScheme;
    return PagedTrips(
      loader: (page) => app.api.trips(page: page),
      onOpen: (trip) => openTrip(context, trip.id),
      header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((config.announcement ?? '').isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [const Icon(Icons.campaign_outlined, color: Color(0xFF3A2C00)), const SizedBox(width: 8), Expanded(child: Text(config.announcement!, style: const TextStyle(color: Color(0xFF3A2C00), fontWeight: FontWeight.w600)))]),
          ),
        if (config.cities.isNotEmpty) ...[
          SectionTitle(context.t('city_commutes')),
          for (final city in config.cities)
            Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(Icons.location_city, color: scheme.onPrimaryContainer)),
                title: Text(city.place.label(app.locale), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(context.t('city_commutes_hint')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onRoute(null, null, city: city.key),
              ),
            ),
          const SizedBox(height: 4),
        ],
        if (config.popularRoutes.isNotEmpty) ...[
          SectionTitle(context.t('popular_routes')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final route in config.popularRoutes)
              ActionChip(
                avatar: Icon(Icons.alt_route, size: 16, color: scheme.primary),
                label: Text('${route.from} → ${route.to}'),
                onPressed: () => onRoute(config.placeByName(route.from), config.placeByName(route.to)),
              ),
          ]),
        ],
        SectionTitle(context.t('latest_trips')),
      ]),
    );
  }
}
