import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/paged_trips.dart';
import 'home_shell.dart';
import 'map_screens.dart';
import 'trip_screen.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key, required this.request});
  final SearchRequest request;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  Place? _from;
  Place? _to;
  String? _city; // null = between towns; otherwise searching inside this city
  int _seats = 1;
  String _sort = 'date';
  Key _resultsKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    widget.request.addListener(_onRequest);
  }

  @override
  void dispose() {
    widget.request.removeListener(_onRequest);
    super.dispose();
  }

  void _onRequest() {
    setState(() {
      _city = widget.request.city;
      _from = widget.request.from;
      _to = widget.request.to;
      _resultsKey = UniqueKey();
    });
  }

  bool get _inCity => _city != null;

  bool get _ready => _inCity || (_from != null && _to != null && _from!.key != _to!.key);

  City? _cityData(AppState app) {
    for (final c in app.config.cities) {
      if (c.key == _city) return c;
    }
    return null;
  }

  void _setMode(bool inCity) => setState(() {
        _from = null;
        _to = null;
        _city = inCity ? (context.read<AppState>().config.cities.firstOrNull?.key) : null;
        _resultsKey = UniqueKey();
      });

  void _search() => setState(() => _resultsKey = UniqueKey());

  Future<void> _alert() async {
    if (!_ready || _from == null || _to == null) return;
    final app = context.read<AppState>();
    try {
      await app.api.createAlert(_from!, _to!);
      if (mounted) showMessage(context, context.tr('alert_saved'));
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    }
  }

  void _swap() => setState(() {
        final tmp = _from;
        _from = _to;
        _to = tmp;
      });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final city = _inCity ? _cityData(app) : null;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(children: [
          if (app.config.cities.isNotEmpty) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [ButtonSegment(value: false, label: Text(context.t('mode_towns'))), ButtonSegment(value: true, label: Text(context.t('mode_city')))],
              selected: {_inCity},
              onSelectionChanged: (s) => _setMode(s.first),
            ),
            const SizedBox(height: 10),
          ],
          if (city != null) ...[
            if (app.config.cities.length > 1)
              DropdownButtonFormField<String>(
                initialValue: _city,
                decoration: InputDecoration(labelText: context.t('city')),
                items: [for (final c in app.config.cities) DropdownMenuItem(value: c.key, child: Text(c.place.label(app.locale)))],
                onChanged: (v) => setState(() {
                  _city = v;
                  _from = null;
                  _to = null;
                }),
              )
            else
              Align(alignment: Alignment.centerLeft, child: Chip2(city.place.label(app.locale), icon: Icons.location_city)),
            const SizedBox(height: 10),
            PlaceField(label: context.t('from_area'), value: _from, places: city.areas, placeholder: context.t('any_area'), onChanged: (p) => setState(() => _from = p)),
            const SizedBox(height: 10),
            PlaceField(label: context.t('to_area'), value: _to, places: city.areas, placeholder: context.t('any_area'), icon: Icons.flag_outlined, onChanged: (p) => setState(() => _to = p)),
            if (_from != null || _to != null)
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }), child: Text(context.t('any_area')))),
          ] else
            Row(children: [
              Expanded(
                child: Column(children: [
                  PlaceField(label: context.t('from'), value: _from, onChanged: (p) => setState(() => _from = p)),
                  const SizedBox(height: 10),
                  PlaceField(label: context.t('to'), value: _to, icon: Icons.flag_outlined, onChanged: (p) => setState(() => _to = p)),
                ]),
              ),
              IconButton(onPressed: _swap, tooltip: '⇅', icon: const Icon(Icons.swap_vert)),
            ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _seats,
                decoration: InputDecoration(labelText: context.t('seats_needed')),
                items: [for (var i = 1; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                onChanged: (v) => setState(() => _seats = v ?? 1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _sort,
                decoration: InputDecoration(labelText: context.t('sort')),
                items: [DropdownMenuItem(value: 'date', child: Text(context.t('sort_date'))), DropdownMenuItem(value: 'price', child: Text(context.t('sort_price')))],
                onChanged: (v) => setState(() => _sort = v ?? 'date'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(flex: 3, child: FilledButton.icon(onPressed: _ready ? _search : null, icon: const Icon(Icons.search), label: Text(context.t('search_button')))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: OutlinedButton.icon(onPressed: _ready && !_inCity ? _alert : null, icon: const Icon(Icons.notifications_none), label: Text(context.t('alert_me')))),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: context.t('map_view'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MapSearchScreen(from: _inCity ? null : _from, to: _inCity ? null : _to))),
              icon: const Icon(Icons.map_outlined),
            ),
          ]),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: PagedTrips(
          key: _resultsKey,
          emptyText: _inCity ? context.t('no_city_results') : (_ready ? context.t('no_results') : null),
          loader: (page) => _inCity
              ? app.api.trips(city: _city, fromArea: _from, toArea: _to, seats: _seats, sort: _sort, page: page)
              : app.api.trips(from: _ready ? _from : null, to: _ready ? _to : null, seats: _ready ? _seats : null, sort: _sort, page: page),
          onOpen: (trip) => openTrip(context, trip.id),
        ),
      ),
    ]);
  }
}
