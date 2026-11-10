import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/device_location.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'map_screens.dart';

/// Find any place by name with Google's place search: type a street, landmark, building or town.
/// Also offers the phone's current location, picking a spot on the map, and the listed towns.
class PlaceSearchScreen extends StatefulWidget {
  const PlaceSearchScreen({super.key, this.selected, this.title});
  final Place? selected;
  final String? title;

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Place> _results = [];
  bool _loading = false;
  bool _searched = false;
  bool _locating = false;
  Object? _error;
  int _serial = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    final query = text.trim();
    if (query.length < 2) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    final mine = ++_serial;
    try {
      final found = await context.read<AppState>().api.searchPlaces(query);
      if (!mounted || mine != _serial) return;
      setState(() {
        _results = found;
        _searched = true;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || mine != _serial) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _useMyLocation() async {
    final app = context.read<AppState>();
    setState(() => _locating = true);
    final here = await currentLocation();
    if (!mounted) return;
    if (here == null) {
      setState(() => _locating = false);
      showMessage(context, context.tr('location_denied'), error: true);
      return;
    }
    Place place;
    try {
      place = await app.api.reverse(here.$1, here.$2);
    } catch (_) {
      place = Place.pin(here.$1, here.$2, '${here.$1.toStringAsFixed(4)}, ${here.$2.toStringAsFixed(4)}');
    }
    if (mounted) Navigator.pop(context, place);
  }

  Future<void> _chooseOnMap() async {
    final picked = await Navigator.push<Place>(context, MaterialPageRoute(builder: (_) => PlacePickerScreen(initial: widget.selected?.isPin == true ? widget.selected : null)));
    if (picked != null && mounted) Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final typing = _controller.text.trim().length >= 2;
    final towns = app.config.places;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          cursorColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 17),
          decoration: InputDecoration(
            hintText: widget.title ?? context.t('search_any_place'),
            hintStyle: const TextStyle(color: Color(0xCCFFFFFF)),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: context.t('clear'),
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _changed('');
              },
            ),
        ],
        bottom: _loading ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
      ),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.my_location, color: scheme.onPrimaryContainer)),
          title: Text(context.t('use_my_location'), style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: _locating ? null : _useMyLocation,
        ),
        ListTile(
          leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(Icons.map_outlined, color: scheme.onPrimaryContainer)),
          title: Text(context.t('choose_on_map'), style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: _chooseOnMap,
        ),
        const Divider(height: 1),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(errorText(context, _error!), style: TextStyle(color: scheme.error))),
        if (typing && _searched && _results.isEmpty && _error == null) Padding(padding: const EdgeInsets.all(16), child: Text(context.t('no_places'))),
        for (final place in _results)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: (place.address ?? '').isEmpty ? null : Text(place.address!, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(context, place),
          ),
        if (!typing) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(context.t('popular_towns').toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
          for (final town in towns)
            ListTile(
              dense: true,
              leading: const Icon(Icons.location_city_outlined),
              title: Text(town.label(app.locale)),
              trailing: widget.selected?.key == town.key ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, town),
            ),
        ],
        if (typing && _results.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(context.t('powered_by_google'), style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
