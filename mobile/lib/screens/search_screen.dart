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
      _from = widget.request.from;
      _to = widget.request.to;
      _resultsKey = UniqueKey();
    });
  }

  bool get _ready => _from != null && _to != null && _from!.key != _to!.key;

  void _search() => setState(() => _resultsKey = UniqueKey());

  Future<void> _alert() async {
    if (!_ready) return;
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(children: [
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
            Expanded(flex: 2, child: OutlinedButton.icon(onPressed: _ready ? _alert : null, icon: const Icon(Icons.notifications_none), label: Text(context.t('alert_me')))),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: context.t('map_view'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MapSearchScreen(from: _from, to: _to))),
              icon: const Icon(Icons.map_outlined),
            ),
          ]),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: PagedTrips(
          key: _resultsKey,
          emptyText: _ready ? context.t('no_results') : null,
          loader: (page) => app.api.trips(from: _ready ? _from : null, to: _ready ? _to : null, seats: _ready ? _seats : null, sort: _sort, page: page),
          onOpen: (trip) => openTrip(context, trip.id),
        ),
      ),
    ]);
  }
}
