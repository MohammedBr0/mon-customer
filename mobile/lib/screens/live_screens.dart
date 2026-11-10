import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/device_location.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/map_markers.dart';
import '../widgets/map_style.dart';
import '../widgets/route_map.dart';

/// A passenger's pickup point on the map, with the trip's route, so a driver can judge the detour before
/// accepting a seat request.
class PickupMapScreen extends StatefulWidget {
  const PickupMapScreen({super.key, required this.booking});
  final Booking booking;

  @override
  State<PickupMapScreen> createState() => _PickupMapScreenState();
}

class _PickupMapScreenState extends State<PickupMapScreen> {
  List<LatLng> _route = [];

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    try {
      final trip = await context.read<AppState>().api.trip(widget.booking.trip.id);
      final points = routePoints(polyline: trip.polyline, startLat: trip.startLat, startLng: trip.startLng, endLat: trip.endLat, endLng: trip.endLng);
      if (mounted) setState(() => _route = points);
    } catch (_) {
      // The pickup pin is still shown without the route.
    }
  }

  /// How far the pickup point is from the nearest point of the route, in km.
  double? get _detourKm {
    if (_route.isEmpty) return null;
    final pickup = LatLng(widget.booking.pickup!.lat, widget.booking.pickup!.lng);
    return _route.map((p) => distanceKm(p, pickup)).reduce((a, b) => a < b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final pickup = LatLng(b.pickup!.lat, b.pickup!.lng);
    final detour = _detourKm;
    final all = [pickup, ..._route];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('pickup_of', {'name': b.passenger.firstName ?? b.passenger.name}))),
      body: Stack(children: [
        GoogleMap(
          cameraTargetBounds: ethiopiaCamera,
          minMaxZoomPreference: ethiopiaZoom,
          key: ValueKey(_route.length),
          initialCameraPosition: all.length > 1 ? framing(all) : CameraPosition(target: pickup, zoom: 15),
          style: mapStyle(context),
          markers: {
            Marker(markerId: const MarkerId('pickup'), position: pickup, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange), infoWindow: InfoWindow(title: b.passenger.firstName ?? b.passenger.name, snippet: b.pickup!.name)),
            if (_route.length >= 2) ...endMarkers(_route),
          },
          polylines: {if (_route.length >= 2) routeLine(_route)},
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.person_pin_circle, color: Color(0xFFE08A00), size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text((b.pickup!.name).isEmpty ? context.t('pickup_point') : b.pickup!.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      if (detour != null) Text(context.t('from_your_route', {'distance': detour < 1 ? '${(detour * 1000).round()} m' : '${detour.toStringAsFixed(1)} km'}), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A ride under way. The driver's phone sends its position; passengers with a confirmed seat watch the car move.
class LiveTripScreen extends StatefulWidget {
  const LiveTripScreen({super.key, required this.trip, required this.driving});
  final Trip trip;
  final bool driving;

  @override
  State<LiveTripScreen> createState() => _LiveTripScreenState();
}

class _LiveTripScreenState extends State<LiveTripScreen> {
  GoogleMapController? _map;
  CarIcons? _cars;
  LiveState? _live;
  LatLng? _car;
  double _heading = 90;
  Timer? _poll;
  StreamSubscription<Position>? _positions;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool _follow = true;
  String? _problem;

  late final List<LatLng> _route = routePoints(polyline: widget.trip.polyline, startLat: widget.trip.startLat, startLng: widget.trip.startLng, endLat: widget.trip.endLat, endLng: widget.trip.endLng);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _cars = await CarIcons.load(context);
      if (mounted) setState(() {});
    });
    _refresh();
    // Passengers ask the server where the car is; the driver's own position comes from the phone.
    _poll = Timer.periodic(Duration(seconds: widget.driving ? 20 : 5), (_) => _refresh());
    if (widget.driving) _share();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _positions?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final live = await context.read<AppState>().api.liveTrip(widget.trip.id);
      if (!mounted) return;
      setState(() {
        _live = live;
        if (!widget.driving && live.lat != null && live.lng != null) {
          _car = LatLng(live.lat!, live.lng!);
          if (live.heading != null) _heading = live.heading!;
        }
      });
      if (!widget.driving && _follow && _car != null) _map?.animateCamera(CameraUpdate.newLatLng(_car!));
    } catch (_) {
      // A missed update is replaced by the next one.
    }
  }

  /// Driver: watch the phone's position and send it on, at most every few seconds, while this screen is open.
  Future<void> _share() async {
    final here = await currentLocation();
    if (!mounted) return;
    if (here == null) {
      setState(() => _problem = context.tr('location_denied'));
      return;
    }
    _moved(here.$1, here.$2, null);
    _positions = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15)).listen(
      (p) => _moved(p.latitude, p.longitude, p.heading),
      onError: (_) {
        if (mounted) setState(() => _problem = context.tr('location_denied'));
      },
    );
  }

  void _moved(double lat, double lng, double? heading) {
    if (!mounted) return;
    setState(() {
      _car = LatLng(lat, lng);
      if (heading != null && heading > 0) _heading = heading;
      _problem = null;
    });
    if (_follow) _map?.animateCamera(CameraUpdate.newLatLng(_car!));
    final now = DateTime.now();
    if (_live?.active == true && now.difference(_lastSent) >= const Duration(seconds: 4)) {
      _lastSent = now;
      context.read<AppState>().api.sendLocation(widget.trip.id, lat, lng, heading: heading).catchError((_) {});
    }
  }

  Future<void> _finish() async {
    final app = context.read<AppState>();
    if (!await confirmDialog(context, context.tr('finish_trip_q'), action: context.tr('finish_trip'))) return;
    setState(() => _busy = true);
    try {
      await app.api.finishTrip(widget.trip.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showMessage(context, errorText(context, e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  String _status(BuildContext context) {
    final live = _live;
    if (live == null) return context.t('loading');
    if (!live.active) return context.t(live.ended ? 'trip_finished' : 'trip_not_started');
    if (widget.driving) return context.t('sharing_location');
    if (_car == null) return context.t('waiting_for_car');
    return context.t(live.fresh ? 'car_on_the_way' : 'car_position_old');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trip = widget.trip;
    final live = _live;
    final start = _car ?? (_route.isNotEmpty ? _route.first : addisAbaba);
    return Scaffold(
      appBar: AppBar(title: Text('${trip.from} → ${trip.to}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Stack(children: [
        GoogleMap(
          cameraTargetBounds: ethiopiaCamera,
          minMaxZoomPreference: ethiopiaZoom,
          initialCameraPosition: CameraPosition(target: start, zoom: 14),
          onMapCreated: (c) => _map = c,
          style: mapStyle(context),
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          padding: const EdgeInsets.only(bottom: 150),
          onCameraMoveStarted: () {},
          polylines: {if (_route.length >= 2) routeLine(_route, faint: true)},
          markers: {
            if (_route.length >= 2) ...endMarkers(_route),
            if (_car != null)
              Marker(markerId: const MarkerId('car'), position: _car!, icon: _cars?.icon(_heading, selected: true) ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), anchor: const Offset(0.5, 0.85), zIndexInt: 20),
            for (final p in live?.pickups ?? const [])
              Marker(markerId: MarkerId('pickup-${p.name}-${p.lat}'), position: LatLng(p.lat, p.lng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange), infoWindow: InfoWindow(title: p.name, snippet: p.label)),
          },
        ),
        Positioned(
          right: 12,
          bottom: 170,
          child: FloatingActionButton.small(
            heroTag: 'follow',
            tooltip: context.t('follow_car'),
            backgroundColor: _follow ? scheme.primary : scheme.surface,
            foregroundColor: _follow ? scheme.onPrimary : scheme.onSurface,
            onPressed: () {
              setState(() => _follow = !_follow);
              if (_follow && _car != null) _map?.animateCamera(CameraUpdate.newLatLngZoom(_car!, 15));
            },
            child: const Icon(Icons.navigation_outlined),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(live?.active == true ? Icons.sensors : Icons.sensors_off, color: live?.active == true ? scheme.primary : scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_status(context), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  ]),
                  if (_problem != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_problem!, style: TextStyle(color: scheme.error))),
                  if (widget.driving && live?.active == true) ...[
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('keep_screen_open'), style: Theme.of(context).textTheme.bodySmall)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                      onPressed: _busy ? null : _finish,
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(context.t('finish_trip')),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
