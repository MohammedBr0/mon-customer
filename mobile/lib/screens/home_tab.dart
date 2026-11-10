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
import '../widgets/map_style.dart';
import '../widgets/route_map.dart';
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
  final _sheet = DraggableScrollableController();
  BitmapDescriptor? _car;
  BitmapDescriptor? _carSelected;
  final Map<int, List<LatLng>> _routes = {};
  int? _selected; // the ride whose route is highlighted on the map
  double _sheetSize = _mid;

  static const _min = 0.13, _mid = 0.5, _max = 0.9;
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
        _car ??= await carMarker(selected: false, pixelRatio: ratio);
        _carSelected ??= await carMarker(selected: true, pixelRatio: ratio);
      }
      for (final t in page.items) {
        _routes[t.id] = routePoints(polyline: t.polyline, startLat: t.startLat, startLng: t.startLng, endLat: t.endLat, endLng: t.endLng);
      }
      if (!mounted) return;
      setState(() {
        _selected = null;
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

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  /// Highlights a ride on the map: its car, its Google route and where it is heading. The list steps aside.
  void _focus(int index) {
    final points = _routes[_trips[index].id] ?? const <LatLng>[];
    setState(() => _selected = index);
    if (_sheet.isAttached) _sheet.animateTo(_min, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    if (points.length >= 2) _map?.animateCamera(CameraUpdate.newLatLngBounds(boundsOf(points), 70));
  }

  void _toggleSheet() {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(_sheetSize > _min + 0.05 ? _min : _mid, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  double _heading(Trip t) {
    final points = _routes[t.id];
    return points != null && points.length >= 2 ? bearing(points[0], points[1]) : 0;
  }

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
    final height = MediaQuery.of(context).size.height;
    final selected = _selected == null ? null : _trips[_selected!];
    return Stack(children: [
      // ---- the map fills the screen; the list slides over it
      Positioned.fill(
        child: _canShowMap
            ? GoogleMap(
                initialCameraPosition: CameraPosition(target: _center, zoom: 12.5),
                onMapCreated: (c) => _map = c,
                style: mapStyle(context),
                myLocationEnabled: _located,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                padding: EdgeInsets.only(top: top + 64, bottom: height * _min + 70),
                markers: {
                  // Each ride is a car at its starting point, turned to face the way it will drive.
                  for (var i = 0; i < _trips.length; i++)
                    if (_trips[i].startLat != null && _trips[i].startLng != null)
                      Marker(
                        markerId: MarkerId('trip-${_trips[i].id}'),
                        position: LatLng(_trips[i].startLat!, _trips[i].startLng!),
                        icon: (_selected == i ? _carSelected : _car) ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                        anchor: const Offset(0.5, 0.5),
                        flat: true,
                        rotation: _heading(_trips[i]),
                        zIndexInt: _selected == i ? 10 : 2,
                        onTap: () => _focus(i),
                      ),
                  if (selected != null && (_routes[selected.id]?.length ?? 0) >= 2)
                    Marker(markerId: const MarkerId('heading'), position: _routes[selected.id]!.last, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), infoWindow: InfoWindow(title: selected.endAddress)),
                },
                polylines: {
                  for (var i = 0; i < _trips.length; i++)
                    if ((_routes[_trips[i].id]?.length ?? 0) >= 2) routeLine(_routes[_trips[i].id]!, id: 'route-${_trips[i].id}', faint: _selected != i, onTap: () => _focus(i)),
                },
                onTap: (_) {
                  if (_selected != null) setState(() => _selected = null);
                },
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
            Container(decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surface), padding: const EdgeInsets.all(2), child: Avatar(user, size: 44)),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(user.firstName ?? user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface))),
                    if (user.verified) ...[const SizedBox(width: 6), Icon(Icons.verified, size: 16, color: scheme.primary)],
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
      // ---- the selected ride, shown over the map while the list is tucked away
      if (selected != null)
        Positioned(
          left: 14,
          right: 14,
          bottom: height * _min + 78,
          child: Material(
            elevation: 4,
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => openTrip(context, selected.id),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  CircleAvatar(radius: 18, backgroundColor: scheme.primary, child: Icon(Icons.directions_car, size: 18, color: scheme.onPrimary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.t('heading_to', {'place': selected.endAddress}), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${formatMoney(selected.passengerPrice, app.config.currencySymbol)}/${context.t('seat')} · ${selected.driver.firstName ?? selected.driver.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ),
          ),
        ),
      // ---- the rides: a sheet you can drag down to a handle or up to nearly full screen
      DraggableScrollableSheet(
        controller: _sheet,
        initialChildSize: _mid,
        minChildSize: _min,
        maxChildSize: _max,
        snap: true,
        snapSizes: const [_min, _mid, _max],
        builder: (context, scroll) => NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            _sheetSize = n.extent;
            return false;
          },
          child: Material(
            elevation: 8,
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 90), children: [
              // The handle: tap or drag to minimise and restore the list.
              Semantics(
                button: true,
                label: context.t('show_rides'),
                child: InkWell(
                  onTap: _toggleSheet,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 12),
                    child: Column(children: [
                      Container(width: 44, height: 5, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: Text(context.t(_nearby ? 'rides_near_you' : 'latest_trips').toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: scheme.primary))),
                        if (!_loading) Text('${_trips.length}', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
                      ]),
                    ]),
                  ),
                ),
              ),
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
              if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (_error != null && _trips.isEmpty) ErrorState(_error!, onRetry: _load),
              if (!_loading && _error == null && _trips.isEmpty) EmptyState(context.t('no_trips')),
              for (var i = 0; i < _trips.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RideRow(trip: _trips[i], away: _away(_trips[i]), symbol: app.config.currencySymbol, locale: app.locale, onTap: () => openTrip(context, _trips[i].id), onShowOnMap: _canShowMap ? () => _focus(i) : null),
                ),
            ]),
          ),
        ),
      ),
      // ---- the one main action, always within reach
      Positioned(
        left: 16,
        right: 16,
        bottom: 10,
        child: SafeArea(
          top: false,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: app.driverMode ? widget.onOffer : _openMap,
            child: Text(context.t(app.driverMode ? 'post_a_ride' : 'find_a_ride')),
          ),
        ),
      ),
    ]);
  }
}

/// One ride in the home list: where it goes, the price per seat, how far away it starts and seats left.
class RideRow extends StatelessWidget {
  const RideRow({super.key, required this.trip, required this.symbol, required this.locale, required this.onTap, this.away, this.onShowOnMap});
  final VoidCallback? onShowOnMap;
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
            IconButton.filled(
              tooltip: context.t('view_route'),
              style: IconButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
              onPressed: onShowOnMap ?? onTap,
              icon: Icon(trip.commute ? Icons.repeat : Icons.directions_car, size: 20),
            ),
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
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon, color: Theme.of(context).colorScheme.onSurface)),
        ),
      );
}
