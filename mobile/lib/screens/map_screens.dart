import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/device_location.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../core/format.dart';
import '../widgets/map_markers.dart';
import '../widgets/map_style.dart';
import '../widgets/route_map.dart';
import 'trip_screen.dart';

const _addis = addisAbaba;

/// Searches places by name as the person types. Shared by the map screens.
class _PlaceSearchBox extends StatefulWidget {
  const _PlaceSearchBox({required this.onPicked, required this.nearby, this.hint});
  final void Function(Place place) onPicked;
  final LatLng Function() nearby;
  final String? hint;

  @override
  State<_PlaceSearchBox> createState() => _PlaceSearchBoxState();
}

class _PlaceSearchBoxState extends State<_PlaceSearchBox> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<Place> _results = [];
  bool _loading = false;
  bool _searched = false;
  int _serial = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _run(text.trim()));
  }

  Future<void> _run(String text) async {
    final mine = ++_serial;
    final near = widget.nearby();
    try {
      final found = await context.read<AppState>().api.searchPlaces(text, nearLat: near.latitude, nearLng: near.longitude);
      if (mounted && mine == _serial) {
        setState(() {
          _results = found;
          _searched = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && mine == _serial) {
        setState(() => _loading = false);
        showMessage(context, errorText(context, e), error: true);
      }
    }
  }

  void _pick(Place place) {
    _focus.unfocus();
    _controller.text = place.name;
    setState(() {
      _results = [];
      _searched = false;
    });
    widget.onPicked(place);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(14),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          decoration: InputDecoration(
            hintText: widget.hint ?? context.t('search_any_place'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : (_controller.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () {
                    _controller.clear();
                    _changed('');
                  })),
          ),
        ),
      ),
      if (_results.isNotEmpty || (_searched && !_loading))
        Container(
          margin: const EdgeInsets.only(top: 6),
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))]),
          child: _results.isEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text(context.t('no_places')))
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(_results[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_results[i].address ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _pick(_results[i]),
                  ),
                ),
        ),
    ]);
  }
}

/// Choose any spot: search for it, or drag the map under the pin. Returns the chosen [Place].
class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({super.key, this.initial, this.title});
  final Place? initial;
  final String? title;

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  GoogleMapController? _map;
  late LatLng _center = widget.initial != null ? LatLng(widget.initial!.lat, widget.initial!.lng) : _addis;
  String? _address;
  bool _looking = false;
  bool _moved = false;
  bool _dragging = false;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _address = widget.initial!.address ?? widget.initial!.name;
    _locateOnStart();
  }

  Future<void> _locateOnStart() async {
    if (widget.initial != null) return;
    final here = await currentLocation();
    if (here != null && mounted && !_moved) {
      _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(here.$1, here.$2), 15));
    }
  }

  Future<void> _lookup() async {
    final mine = ++_serial;
    final at = _center;
    setState(() => _looking = true);
    try {
      final place = await context.read<AppState>().api.reverse(at.latitude, at.longitude);
      if (mounted && mine == _serial) {
        setState(() {
          _address = place.name;
          _looking = false;
        });
      }
    } catch (_) {
      if (mounted && mine == _serial) {
        setState(() {
          _address = '${at.latitude.toStringAsFixed(5)}, ${at.longitude.toStringAsFixed(5)}';
          _looking = false;
        });
      }
    }
  }

  Future<void> _myLocation() async {
    final here = await currentLocation();
    if (!mounted) return;
    if (here == null) {
      showMessage(context, context.tr('location_denied'), error: true);
      return;
    }
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(here.$1, here.$2), 16));
  }

  void _confirm() => Navigator.pop(context, Place.pin(_center.latitude, _center.longitude, _address ?? '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}', address: _address));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          cameraTargetBounds: ethiopiaCamera,
          minMaxZoomPreference: ethiopiaZoom,
          initialCameraPosition: CameraPosition(target: _center, zoom: widget.initial != null ? 15 : 12),
          onMapCreated: (c) => _map = c,
          onCameraMove: (p) {
            _center = p.target;
            _moved = true;
            if (!_dragging) setState(() => _dragging = true);
          },
          onCameraIdle: () {
            if (_dragging) setState(() => _dragging = false);
            if (_moved || widget.initial == null) _lookup();
          },
          style: mapStyle(context),
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
        ),
        // The pin stays in the middle; the map moves under it.
        IgnorePointer(child: Center(child: AnimatedPadding(duration: const Duration(milliseconds: 150), padding: EdgeInsets.only(bottom: _dragging ? 70 : 44), child: const Icon(Icons.location_on, size: 48, color: brand)))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Material(shape: const CircleBorder(), elevation: 3, color: Theme.of(context).colorScheme.surface, child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: _PlaceSearchBox(
                  nearby: () => _center,
                  hint: widget.title,
                  onPicked: (place) {
                    setState(() {
                      _center = LatLng(place.lat, place.lng);
                      _address = place.address ?? place.name;
                      _moved = true;
                    });
                    _map?.animateCamera(CameraUpdate.newLatLngZoom(_center, 16));
                  },
                ),
              ),
            ]),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 190,
          child: FloatingActionButton.small(heroTag: 'loc', onPressed: _myLocation, child: const Icon(Icons.my_location)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.place, color: brand),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_looking ? context.t('finding_address') : (_address ?? context.t('move_map_hint')), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 12),
                FilledButton(onPressed: _looking ? null : _confirm, child: Text(context.t('confirm_location'))),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A trip's route on a full, pannable map, with a shortcut to navigate it in Google Maps.
class TripMapScreen extends StatefulWidget {
  const TripMapScreen({super.key, required this.trip, required this.points});
  final Trip trip;
  final List<LatLng> points;

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  Future<void> _navigate() async {
    final a = widget.points.first, b = widget.points.last;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=${a.latitude},${a.longitude}&destination=${b.latitude},${b.longitude}&travelmode=driving');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    return Scaffold(
      appBar: AppBar(title: Text(widget.trip.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: GoogleMap(
        cameraTargetBounds: ethiopiaCamera,
        minMaxZoomPreference: ethiopiaZoom,
        initialCameraPosition: framing(points),
        markers: endMarkers(points),
        polylines: {routeLine(points)},
        style: mapStyle(context),
        onMapCreated: (c) => Future.delayed(const Duration(milliseconds: 350), () => c.animateCamera(CameraUpdate.newLatLngBounds(boundsOf(points), 64))),
        mapToolbarEnabled: false,
        myLocationButtonEnabled: false,
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _navigate, icon: const Icon(Icons.navigation_outlined), label: Text(context.t('open_in_maps'))),
    );
  }
}

/// Browse trips on a map, ride-app style: price pins, swipeable trip cards, tap or long-press the map to set
/// pickup and destination, search by name, "search this area", and your own location.
class MapSearchScreen extends StatefulWidget {
  const MapSearchScreen({super.key, this.from, this.to});
  final Place? from;
  final Place? to;

  @override
  State<MapSearchScreen> createState() => _MapSearchScreenState();
}

class _MapSearchScreenState extends State<MapSearchScreen> {
  GoogleMapController? _map;
  final _cards = PageController(viewportFraction: 0.9);
  CarIcons? _cars;
  final Map<int, List<LatLng>> _routes = {};

  Place? _from;
  Place? _to;
  String? _picking; // 'from' or 'to' while waiting for a tap on the map
  List<Trip> _trips = [];
  int? _selected;
  bool _loading = true;
  Object? _error;
  bool _dirty = false; // the map moved since the last search
  bool _programmatic = false;
  bool _located = false;
  String _sort = 'date';
  static const _seats = 1;
  LatLng _center = _addis;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to = widget.to;
    _start();
  }

  @override
  void dispose() {
    _cards.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // Start where the person is, when they allow it; otherwise from the route they chose or Addis Ababa.
    final here = await currentLocation();
    if (here != null && mounted) {
      _located = true;
      if (_from == null && _to == null) _center = LatLng(here.$1, here.$2);
    } else if (_from != null) {
      _center = LatLng(_from!.lat, _from!.lng);
    }
    if (mounted) setState(() {});
    _move(CameraUpdate.newLatLngZoom(_center, 12.5));
    await _load();
  }

  bool get _hasRoute => _from != null && _to != null && _from!.key != _to!.key;

  void _move(CameraUpdate update) {
    _programmatic = true;
    _map?.animateCamera(update);
  }

  // ---- loading ----
  Future<void> _load({bool visibleArea = false}) async {
    final mine = ++_serial;
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
      _dirty = false;
    });
    try {
      ResultPage<Trip> page;
      if (_hasRoute) {
        page = await app.api.trips(from: _from, to: _to, seats: _seats, sort: _sort);
      } else {
        var radius = 10.0;
        final at = visibleArea || _from == null ? _center : LatLng(_from!.lat, _from!.lng);
        if (visibleArea && _map != null) {
          try {
            final region = await _map!.getVisibleRegion();
            radius = distanceKm(at, region.northeast).clamp(2.0, 50.0);
          } catch (_) {
            radius = 10;
          }
        }
        page = await app.api.trips(nearLat: at.latitude, nearLng: at.longitude, radiusKm: radius, seats: _seats, sort: _sort);
      }
      if (!mounted || mine != _serial) return;
      await _makeIcons(page.items);
      if (!mounted || mine != _serial) return;
      setState(() {
        _trips = page.items;
        _selected = null;
        _loading = false;
      });
      if (_cards.hasClients && _trips.isNotEmpty) _cards.jumpToPage(0);
      if (!visibleArea) _fit();
    } catch (e) {
      if (mounted && mine == _serial) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// Draws the two car pictures once, and reads each ride's route from the list.
  Future<void> _makeIcons(List<Trip> trips) async {
    _cars ??= await CarIcons.load(context);
    for (final t in trips) {
      _routes[t.id] = routePoints(polyline: t.polyline, startLat: t.startLat, startLng: t.startLng, endLat: t.endLat, endLng: t.endLng);
    }
  }

  void _fit() {
    final points = <LatLng>[
      if (_from != null) LatLng(_from!.lat, _from!.lng),
      if (_to != null) LatLng(_to!.lat, _to!.lng),
      for (final t in _trips)
        if (t.startLat != null && t.startLng != null) LatLng(t.startLat!, t.startLng!),
    ];
    if (points.isEmpty || _map == null) return;
    _move(points.length == 1 ? CameraUpdate.newLatLngZoom(points.first, 13) : CameraUpdate.newLatLngBounds(boundsOf(points), 90));
  }

  // ---- selecting a trip ----
  Future<void> _select(int index, {bool animateCards = true}) async {
    if (index < 0 || index >= _trips.length) return;
    final trip = _trips[index];
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
    if (animateCards && _cards.hasClients) _cards.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    if (trip.startLat != null && trip.startLng != null) _move(CameraUpdate.newLatLng(LatLng(trip.startLat!, trip.startLng!)));
    _fitRoute(_routes[trip.id] ?? const []);
  }

  void _fitRoute(List<LatLng> points) {
    if (points.length >= 2) _move(CameraUpdate.newLatLngBounds(boundsOf(points), 80));
  }

  // ---- setting points ----
  Future<void> _setFromMap(String side, LatLng at) async {
    final app = context.read<AppState>();
    HapticFeedback.mediumImpact();
    setState(() => _picking = null);
    Place place;
    try {
      place = await app.api.reverse(at.latitude, at.longitude);
    } catch (_) {
      place = Place.pin(at.latitude, at.longitude, '${at.latitude.toStringAsFixed(4)}, ${at.longitude.toStringAsFixed(4)}');
    }
    if (!mounted) return;
    setState(() => side == 'from' ? _from = place : _to = place);
    _load();
  }

  Future<void> _longPress(LatLng at) async {
    final side = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.trip_origin, color: brand), title: Text(ctx.tr('set_pickup_here')), onTap: () => Navigator.pop(ctx, 'from')),
          ListTile(leading: const Icon(Icons.place, color: Colors.red), title: Text(ctx.tr('set_destination_here')), onTap: () => Navigator.pop(ctx, 'to')),
        ]),
      ),
    );
    if (side != null) _setFromMap(side, at);
  }

  Future<void> _editStop(String side) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.search), title: Text(ctx.tr('search_any_place')), onTap: () => Navigator.pop(ctx, 'search')),
          ListTile(leading: const Icon(Icons.touch_app_outlined), title: Text(ctx.tr('tap_on_map')), onTap: () => Navigator.pop(ctx, 'map')),
          if (side == 'from') ListTile(leading: const Icon(Icons.my_location), title: Text(ctx.tr('use_my_location')), onTap: () => Navigator.pop(ctx, 'here')),
          if ((side == 'from' ? _from : _to) != null) ListTile(leading: const Icon(Icons.close), title: Text(ctx.tr('clear')), onTap: () => Navigator.pop(ctx, 'clear')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'search':
        final picked = await pickPlace(context, selected: side == 'from' ? _from : _to);
        if (picked != null) {
          setState(() => side == 'from' ? _from = picked : _to = picked);
          _load();
        }
      case 'map':
        setState(() => _picking = side);
      case 'here':
        final here = await currentLocation();
        if (here == null) {
          if (mounted) showMessage(context, context.tr('location_denied'), error: true);
          return;
        }
        _move(CameraUpdate.newLatLngZoom(LatLng(here.$1, here.$2), 14));
        _setFromMap('from', LatLng(here.$1, here.$2));
      case 'clear':
        setState(() => side == 'from' ? _from = null : _to = null);
        _load();
    }
  }

  Future<void> _myLocation() async {
    final here = await currentLocation();
    if (!mounted) return;
    if (here == null) {
      showMessage(context, context.tr('location_denied'), error: true);
      return;
    }
    setState(() => _located = true);
    _move(CameraUpdate.newLatLngZoom(LatLng(here.$1, here.$2), 14.5));
  }

  Future<void> _alert() async {
    if (!_hasRoute) return;
    try {
      await context.read<AppState>().api.createAlert(_from!, _to!);
      if (mounted) showMessage(context, context.tr('alert_saved'));
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    }
  }

  void _showList() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.8,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: _trips.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => TripCard(_trips[i], onTap: () {
            Navigator.pop(ctx);
            openTrip(context, _trips[i].id);
          }),
        ),
      ),
    );
  }

  // ---- map objects ----
  // Each ride is a car at its starting point, turned to face the way it will drive.
  Set<Marker> get _markers => {
        for (var i = 0; i < _trips.length; i++)
          if (_trips[i].startLat != null && _trips[i].startLng != null)
            Marker(
              markerId: MarkerId('trip-${_trips[i].id}'),
              position: LatLng(_trips[i].startLat!, _trips[i].startLng!),
              icon: _cars?.icon(_heading(_trips[i]), selected: _selected == i) ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              anchor: const Offset(0.5, 0.85),
              zIndexInt: _selected == i ? 10 : 2,
              onTap: () => _select(i),
            ),
        if (_selected != null && (_routes[_trips[_selected!].id]?.length ?? 0) >= 2)
          Marker(markerId: const MarkerId('heading'), position: _routes[_trips[_selected!].id]!.last, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), infoWindow: InfoWindow(title: _trips[_selected!].endAddress)),
        if (_from != null) Marker(markerId: const MarkerId('from'), position: LatLng(_from!.lat, _from!.lng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: InfoWindow(title: context.t('from'), snippet: _from!.name)),
        if (_to != null && _selected == null) Marker(markerId: const MarkerId('to'), position: LatLng(_to!.lat, _to!.lng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), infoWindow: InfoWindow(title: context.t('to'), snippet: _to!.name)),
      };

  double _heading(Trip t) {
    final points = _routes[t.id];
    return points != null && points.length >= 2 ? bearing(points[0], points[1]) : 0;
  }

  // Every ride's route is on the map; the selected one is drawn strong, the rest faint.
  Set<Polyline> get _lines => {
        for (var i = 0; i < _trips.length; i++)
          if ((_routes[_trips[i].id]?.length ?? 0) >= 2) routeLine(_routes[_trips[i].id]!, id: 'route-${_trips[i].id}', faint: _selected != i, onTap: () => _select(i)),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          cameraTargetBounds: ethiopiaCamera,
          minMaxZoomPreference: ethiopiaZoom,
          initialCameraPosition: CameraPosition(target: _center, zoom: 11.5),
          onMapCreated: (c) => _map = c,
          markers: _markers,
          polylines: _lines,
          style: mapStyle(context),
          myLocationEnabled: _located,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          padding: EdgeInsets.only(top: 170, bottom: _trips.isEmpty ? 120 : 190),
          onCameraMove: (p) => _center = p.target,
          onCameraIdle: () {
            if (_programmatic) {
              _programmatic = false;
            } else if (!_loading && !_hasRoute) {
              setState(() => _dirty = true);
            }
          },
          onTap: (at) {
            if (_picking != null) {
              _setFromMap(_picking!, at);
            } else if (_selected != null) {
              setState(() => _selected = null);
            }
          },
          onLongPress: _longPress,
        ),
        // ---- top: search, stops, filters ----
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Material(shape: const CircleBorder(), elevation: 3, color: scheme.surface, child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
                const SizedBox(width: 8),
                Expanded(
                  child: _PlaceSearchBox(
                    nearby: () => _center,
                    hint: context.t('where_to'),
                    onPicked: (place) {
                      setState(() => _to = place);
                      _move(CameraUpdate.newLatLngZoom(LatLng(place.lat, place.lng), 13.5));
                      _load();
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  _MapChip(icon: Icons.trip_origin, label: _from?.label(app.locale) ?? context.t('from'), active: _from != null, onTap: () => _editStop('from')),
                  _MapChip(icon: Icons.place, label: _to?.label(app.locale) ?? context.t('to'), active: _to != null, onTap: () => _editStop('to')),
                  _MapChip(icon: Icons.sort, label: _sort == 'price' ? context.t('sort_price') : context.t('sort_date'), onTap: () {
                    setState(() => _sort = _sort == 'price' ? 'date' : 'price');
                    _load();
                  }),
                ]),
              ),
              if (_picking != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.touch_app, color: scheme.onInverseSurface),
                    const SizedBox(width: 10),
                    Expanded(child: Text(context.t(_picking == 'from' ? 'tap_pickup' : 'tap_destination'), style: TextStyle(color: scheme.onInverseSurface))),
                    TextButton(onPressed: () => setState(() => _picking = null), child: Text(context.t('cancel'))),
                  ]),
                ),
              if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(4)), child: LinearProgressIndicator(minHeight: 3))),
              if (_dirty && !_loading)
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 18)),
                      onPressed: () => _load(visibleArea: true),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(context.t('search_this_area')),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        // ---- side buttons ----
        Positioned(
          right: 12,
          bottom: (_trips.isEmpty ? 140 : 250),
          child: FloatingActionButton.small(heroTag: 'here', tooltip: context.t('my_location'), onPressed: _myLocation, child: const Icon(Icons.my_location)),
        ),
        // ---- bottom: trip cards ----
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _error != null
                  ? Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Card(child: ErrorState(_error!, onRetry: _load)))
                  : _trips.isEmpty
                      ? (_loading ? const SizedBox(height: 100) : _EmptyMapCard(canAlert: _hasRoute, onAlert: _alert))
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Material(
                              elevation: 3,
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 14, right: 4),
                                child: Row(children: [
                                  Expanded(child: Text(context.t('trips_on_map', {'count': _trips.length}), style: const TextStyle(fontWeight: FontWeight.w800))),
                                  TextButton.icon(onPressed: _showList, icon: const Icon(Icons.view_list_outlined, size: 18), label: Text(context.t('list_view'))),
                                ]),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 132,
                            child: PageView.builder(
                              controller: _cards,
                              itemCount: _trips.length,
                              onPageChanged: (i) {
                                if (_selected != i) _select(i, animateCards: false);
                              },
                              itemBuilder: (_, i) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                child: _MapTripCard(trip: _trips[i], selected: _selected == i, onTap: () => openTrip(context, _trips[i].id)),
                              ),
                            ),
                          ),
                        ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        color: active ? scheme.primaryContainer : scheme.surface,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _MapTripCard extends StatelessWidget {
  const _MapTripCard({required this.trip, required this.selected, required this.onTap});
  final Trip trip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final symbol = app.config.currencySymbol;
    final when = trip.commute ? (trip.scheduleSummary ?? '') : (trip.leaveDate == null ? '' : formatDateTime(trip.leaveDate!, locale: app.locale));
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? brand : scheme.outlineVariant, width: selected ? 2 : 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${trip.startAddress} → ${trip.endAddress}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Row(children: [
                  Avatar(trip.driver, size: 22),
                  const SizedBox(width: 6),
                  Flexible(child: Text(trip.driver.firstName ?? trip.driver.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                  if (trip.driver.rating != null) ...[const SizedBox(width: 6), const Icon(Icons.star_rounded, size: 14, color: Color(0xFFB8860B)), Text(trip.driver.rating!.toStringAsFixed(1), style: const TextStyle(fontSize: 12))],
                ]),
              ]),
            ),
            const SizedBox(width: 10),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(trip.passengerPrice, symbol), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: brand)),
              Text(context.t('per_seat'), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Chip2(trip.full ? context.t('fully_booked') : (trip.seatsAvailable == null ? context.t('seats_unlimited') : '${trip.seatsAvailable} ${context.t('seats').toLowerCase()}'), icon: Icons.event_seat_outlined, tone: trip.full ? ChipTone.muted : ChipTone.brand),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _EmptyMapCard extends StatelessWidget {
  const _EmptyMapCard({required this.canAlert, required this.onAlert});
  final bool canAlert;
  final VoidCallback onAlert;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(context.t('no_trips_here'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (canAlert) ...[const SizedBox(height: 10), OutlinedButton.icon(onPressed: onAlert, icon: const Icon(Icons.notifications_none), label: Text(context.t('alert_me')))],
            ]),
          ),
        ),
      );
}
