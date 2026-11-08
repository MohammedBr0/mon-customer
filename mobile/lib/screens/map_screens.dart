import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/device_location.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/route_map.dart';
import 'trip_screen.dart';

const _addis = LatLng(9.0300, 38.7400);

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
          initialCameraPosition: CameraPosition(target: _center, zoom: widget.initial != null ? 15 : 12),
          onMapCreated: (c) => _map = c,
          onCameraMove: (p) {
            _center = p.target;
            _moved = true;
          },
          onCameraIdle: () {
            if (_moved || widget.initial == null) _lookup();
          },
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
        ),
        // The pin stays in the middle; the map moves under it.
        const IgnorePointer(child: Center(child: Padding(padding: EdgeInsets.only(bottom: 44), child: Icon(Icons.location_on, size: 48, color: brand)))),
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
          bottom: 150,
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
        initialCameraPosition: framing(points),
        markers: endMarkers(points),
        polylines: {routeLine(points)},
        onMapCreated: (c) => Future.delayed(const Duration(milliseconds: 350), () => c.animateCamera(CameraUpdate.newLatLngBounds(boundsOf(points), 64))),
        mapToolbarEnabled: false,
        myLocationButtonEnabled: false,
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _navigate, icon: const Icon(Icons.navigation_outlined), label: Text(context.t('open_in_maps'))),
    );
  }
}

/// Browse trips on a map, ride-app style: set From and To (search, pick on map, or a listed town),
/// see matching trips as pins, tap a pin to see its route, and swipe the list up for details.
class MapSearchScreen extends StatefulWidget {
  const MapSearchScreen({super.key, this.from, this.to});
  final Place? from;
  final Place? to;

  @override
  State<MapSearchScreen> createState() => _MapSearchScreenState();
}

class _MapSearchScreenState extends State<MapSearchScreen> {
  GoogleMapController? _map;
  Place? _from;
  Place? _to;
  List<Trip> _trips = [];
  bool _loading = true;
  Object? _error;
  Trip? _selected;
  List<LatLng> _selectedLine = [];
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to = widget.to;
    _load();
  }

  Future<void> _load() async {
    final mine = ++_serial;
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
      _selectedLine = [];
    });
    try {
      final both = _from != null && _to != null && _from!.key != _to!.key;
      final page = await app.api.trips(from: both ? _from : null, to: both ? _to : null);
      if (!mounted || mine != _serial) return;
      setState(() {
        _trips = page.items;
        _loading = false;
      });
      _fit();
    } catch (e) {
      if (mounted && mine == _serial) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
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
    if (points.length == 1) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 13));
    } else {
      _map!.animateCamera(CameraUpdate.newLatLngBounds(boundsOf(points), 80));
    }
  }

  Future<void> _select(Trip trip) async {
    final app = context.read<AppState>();
    setState(() => _selected = trip);
    try {
      final detail = await app.api.trip(trip.id);
      if (!mounted || _selected?.id != trip.id) return;
      final points = routePoints(polyline: detail.polyline, startLat: detail.startLat, startLng: detail.startLng, endLat: detail.endLat, endLng: detail.endLng);
      setState(() => _selectedLine = points);
      if (points.length >= 2) _map?.animateCamera(CameraUpdate.newLatLngBounds(boundsOf(points), 90));
    } catch (_) {
      // The pin still works; only the line is missing.
    }
  }

  Future<void> _setPlace(bool isFrom) async {
    final picked = await pickPlace(context, selected: isFrom ? _from : _to);
    if (picked == null) return;
    setState(() => isFrom ? _from = picked : _to = picked);
    _load();
  }

  Set<Marker> get _markers => {
        for (final t in _trips)
          if (t.startLat != null && t.startLng != null)
            Marker(
              markerId: MarkerId('trip-${t.id}'),
              position: LatLng(t.startLat!, t.startLng!),
              icon: BitmapDescriptor.defaultMarkerWithHue(_selected?.id == t.id ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueGreen),
              infoWindow: InfoWindow(title: t.endAddress, snippet: formatPriceShort(context, t)),
              onTap: () => _select(t),
            ),
        if (_from != null) Marker(markerId: const MarkerId('from'), position: LatLng(_from!.lat, _from!.lng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: InfoWindow(title: context.t('from'), snippet: _from!.name)),
        if (_to != null) Marker(markerId: const MarkerId('to'), position: LatLng(_to!.lat, _to!.lng), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), infoWindow: InfoWindow(title: context.t('to'), snippet: _to!.name)),
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(target: _addis, zoom: 11),
          onMapCreated: (c) {
            _map = c;
            Future.delayed(const Duration(milliseconds: 400), _fit);
          },
          markers: _markers,
          polylines: {if (_selectedLine.length >= 2) routeLine(_selectedLine)},
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          padding: EdgeInsets.only(top: 160, bottom: MediaQuery.of(context).size.height * 0.28),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                child: Row(children: [
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  Expanded(
                    child: Column(children: [
                      _Stop(icon: Icons.trip_origin, color: scheme.primary, label: context.t('from'), place: _from, locale: app.locale, onTap: () => _setPlace(true)),
                      const Divider(height: 8),
                      _Stop(icon: Icons.place, color: scheme.error, label: context.t('to'), place: _to, locale: app.locale, onTap: () => _setPlace(false)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.28,
          minChildSize: 0.12,
          maxChildSize: 0.85,
          builder: (context, scroll) => Material(
            elevation: 12,
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(_error!, onRetry: _load)
                    : ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                        const SizedBox(height: 10),
                        Text(context.t('trips_on_map', {'count': _trips.length}), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        if (_trips.isEmpty) EmptyState(context.t('no_results')),
                        for (final trip in _trips)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              decoration: _selected?.id == trip.id ? BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: accent, width: 2)) : null,
                              child: TripCard(trip, onTap: () => openTrip(context, trip.id)),
                            ),
                          ),
                      ]),
          ),
        ),
      ]),
    );
  }
}

String formatPriceShort(BuildContext context, Trip trip) => '${context.read<AppState>().config.currencySymbol} ${trip.passengerPrice.round()}';

class _Stop extends StatelessWidget {
  const _Stop({required this.icon, required this.color, required this.label, required this.place, required this.locale, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final Place? place;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(place?.label(locale) ?? label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: place == null ? FontWeight.w400 : FontWeight.w700, color: place == null ? Theme.of(context).colorScheme.onSurfaceVariant : null))),
          ]),
        ),
      );
}
