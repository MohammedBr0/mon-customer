import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/device_location.dart';
import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/map_markers.dart';
import 'home_shell.dart';
import 'map_screens.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'trip_screen.dart';

const _addis = LatLng(9.0300, 38.7400);

/// Home: the map with you on it, the shared rides near you, and one main action.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.onOffer});
  final VoidCallback onOffer;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // Widget tests have no map engine; they get a plain panel instead.
  static final bool _canShowMap = !Platform.environment.containsKey('FLUTTER_TEST');

  GoogleMapController? _map;
  final Map<String, BitmapDescriptor> _icons = {};
  LatLng _center = _addis;
  bool _located = false;
  List<Trip> _trips = [];
  bool _loading = true;
  bool _nearby = false; // false when the list had to fall back to the latest trips anywhere
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_canShowMap) {
      final here = await currentLocation();
      if (here != null && mounted) {
        setState(() {
          _center = LatLng(here.$1, here.$2);
          _located = true;
        });
        _map?.animateCamera(CameraUpdate.newLatLngZoom(_center, 13));
      }
    }
    await _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (mounted) setState(() => _error = null);
    try {
      var page = await app.api.trips(nearLat: _center.latitude, nearLng: _center.longitude, radiusKm: 15);
      var nearby = true;
      if (page.items.isEmpty) {
        page = await app.api.trips();
        nearby = false;
      }
      if (!mounted) return;
      if (_canShowMap) {
        final ratio = MediaQuery.of(context).devicePixelRatio;
        for (final t in page.items) {
          final label = _price(app, t);
          _icons[label] ??= await priceTag(label, selected: false, pixelRatio: ratio);
        }
      }
      if (!mounted) return;
      setState(() {
        _trips = page.items;
        _nearby = nearby;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  String _price(AppState app, Trip t) => '${app.config.currencySymbol} ${t.passengerPrice.round()}';

  void _openMap() => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapSearchScreen()));

  String? _away(Trip t) {
    if (!_located || t.startLat == null || t.startLng == null) return null;
    final km = distanceKm(_center, LatLng(t.startLat!, t.startLng!));
    return km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final user = app.user;
    final top = MediaQuery.of(context).padding.top;
    final mapHeight = MediaQuery.of(context).size.height * 0.36;
    return Stack(children: [
      // ---- the map, edge to edge
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: mapHeight + 28,
        child: _canShowMap
            ? GoogleMap(
                initialCameraPosition: CameraPosition(target: _center, zoom: 12.5),
                onMapCreated: (c) => _map = c,
                myLocationEnabled: _located,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                padding: EdgeInsets.only(top: top + 64, bottom: 28),
                markers: {
                  for (final t in _trips)
                    if (t.startLat != null && t.startLng != null)
                      Marker(
                        markerId: MarkerId('trip-${t.id}'),
                        position: LatLng(t.startLat!, t.startLng!),
                        icon: _icons[_price(app, t)] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                        onTap: () => openTrip(context, t.id),
                      ),
                },
                onTap: (_) => _openMap(),
              )
            : ColoredBox(color: scheme.primaryContainer),
      ),
      // ---- who you are, over the map
      Positioned(
        top: top + 10,
        left: 14,
        right: 14,
        child: Row(children: [
          if (user != null) ...[
            Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white), padding: const EdgeInsets.all(2), child: Avatar(user, size: 44)),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(user.firstName ?? user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF151E30)))),
                    if (user.verified) ...[const SizedBox(width: 6), const Icon(Icons.verified, size: 16, color: brand)],
                  ]),
                ),
              ),
            ),
          ] else
            const Spacer(),
          _RoundButton(
            icon: Icons.chat_bubble_outline,
            tooltip: context.t('messages'),
            badge: app.unreadMessages,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesScreen())).then((_) => app.refreshUnread()),
          ),
          const SizedBox(width: 8),
          _RoundButton(
            icon: Icons.notifications_none,
            tooltip: context.t('notifications'),
            badge: app.unreadNotifications,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) => app.checkNotifications()),
          ),
        ]),
      ),
      // ---- the rides, on a sheet over the bottom of the map
      Positioned(
        top: mapHeight,
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), children: [
                  // Search first: most people open the app to go somewhere.
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _openMap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Icon(Icons.search, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text(context.t('where_to'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  NextRideCard(key: ValueKey('next-${app.driverMode}'), driver: app.driverMode),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: 2),
                    child: Text(context.t(_nearby ? 'rides_near_you' : 'latest_trips').toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: scheme.primary)),
                  ),
                  if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                  if (_error != null && _trips.isEmpty) ErrorState(_error!, onRetry: _load),
                  if (!_loading && _error == null && _trips.isEmpty) EmptyState(context.t('no_trips')),
                  for (final trip in _trips)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: RideRow(trip: trip, away: _away(trip), symbol: app.config.currencySymbol, locale: app.locale, onTap: () => openTrip(context, trip.id))),
                ]),
              ),
            ),
            // ---- the one main action
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: app.driverMode ? widget.onOffer : _openMap,
                  child: Text(context.t(app.driverMode ? 'post_a_ride' : 'find_a_ride')),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// One ride in the home list: where it goes, the price per seat, how far away it starts and seats left.
class RideRow extends StatelessWidget {
  const RideRow({super.key, required this.trip, required this.symbol, required this.locale, required this.onTap, this.away});
  final Trip trip;
  final String symbol;
  final String locale;
  final String? away;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seats = trip.seatsAvailable;
    final few = seats != null && seats <= 1;
    final when = trip.commute ? (trip.scheduleSummary ?? '') : (trip.leaveDate == null ? '' : formatDateTime(trip.leaveDate!, locale: locale));
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('to_place', {'place': trip.endAddress}), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('${context.t('from')} ${trip.startAddress} · $when', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                Row(children: [
                  // The price takes what room is left and shrinks before anything overflows on a narrow phone.
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${formatMoney(trip.passengerPrice, symbol)}/${context.t('seat')}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (away != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(context.t('away', {'distance': away}), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: trip.full ? scheme.surfaceContainerHighest : (few ? const Color(0xFFFFF3D6) : scheme.primaryContainer), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      trip.full ? context.t('fully_booked') : (seats == null ? context.t('seats_unlimited') : context.t('seats_left_short', {'count': seats})),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: trip.full ? scheme.onSurfaceVariant : (few ? const Color(0xFF7A5200) : scheme.onPrimaryContainer)),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            CircleAvatar(radius: 18, backgroundColor: const Color(0xFF151E30), child: Icon(trip.commute ? Icons.repeat : Icons.directions_car, size: 18, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.badge = 0});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon, color: const Color(0xFF151E30))),
        ),
      );
}
