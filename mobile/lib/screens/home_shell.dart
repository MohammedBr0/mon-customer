import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/paged_trips.dart';
import 'dart:io' show Platform;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/device_location.dart';
import '../core/format.dart';
import 'bookings_screen.dart';
import 'map_screens.dart';
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
        Text(context.t(app.driverMode ? 'home_prompt_driver' : 'home_prompt_passenger'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 12),
        HomeMapHero(driver: app.driverMode),
        const SizedBox(height: 12),
        NextRideCard(key: ValueKey('next-${app.driverMode}'), driver: app.driverMode),
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

/// The map at the top of the home screen, with the main action on it: search for passengers, offer for drivers.
class HomeMapHero extends StatefulWidget {
  const HomeMapHero({super.key, required this.driver});
  final bool driver;

  @override
  State<HomeMapHero> createState() => _HomeMapHeroState();
}

class _HomeMapHeroState extends State<HomeMapHero> {
  LatLng _center = const LatLng(9.0300, 38.7400);
  bool _located = false;

  // Widget tests have no map engine; they get a plain panel instead.
  static final bool _canShowMap = !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (_canShowMap) _locate();
  }

  Future<void> _locate() async {
    final here = await currentLocation();
    if (here != null && mounted) {
      setState(() {
        _center = LatLng(here.$1, here.$2);
        _located = true;
      });
    }
  }

  void _openMap() => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapSearchScreen()));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 210,
        child: Stack(children: [
          Positioned.fill(
            child: _canShowMap
                ? GoogleMap(
                    key: ValueKey(_located),
                    initialCameraPosition: CameraPosition(target: _center, zoom: 13),
                    mapType: MapType.hybrid,
                    liteModeEnabled: true,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    myLocationButtonEnabled: false,
                    markers: {if (_located) Marker(markerId: const MarkerId('me'), position: _center, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure))},
                  )
                : ColoredBox(color: scheme.primaryContainer),
          ),
          Positioned.fill(child: Material(color: Colors.transparent, child: InkWell(onTap: _openMap))),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              elevation: 3,
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _openMap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(children: [
                    Icon(Icons.search, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(context.t('where_to'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                    Icon(Icons.map_outlined, color: scheme.onSurfaceVariant),
                  ]),
                ),
              ),
            ),
          ),
          if (widget.driver)
            Positioned(
              left: 12,
              bottom: 12,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfferScreen())),
                icon: const Icon(Icons.add),
                label: Text(context.t('offer_cta')),
              ),
            ),
        ]),
      ),
    );
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
