import 'package:flutter/material.dart';

import '../core/api.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'common.dart';

typedef TripLoader = Future<ResultPage<Trip>> Function(int page);

/// A pull-to-refresh, load-more list of trip cards.
class PagedTrips extends StatefulWidget {
  const PagedTrips({super.key, required this.loader, required this.onOpen, this.emptyText, this.header, this.showDriver = true});
  final TripLoader loader;
  final void Function(Trip trip) onOpen;
  final String? emptyText;
  final Widget? header;
  final bool showDriver;

  @override
  State<PagedTrips> createState() => PagedTripsState();
}

class PagedTripsState extends State<PagedTrips> {
  final List<Trip> _trips = [];
  int _page = 0;
  bool _last = false;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    _trips.clear();
    _page = 0;
    _last = false;
    _error = null;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _last) return;
    setState(() => _loading = true);
    try {
      final result = await widget.loader(_page + 1);
      _trips.addAll(result.items);
      _page = result.page;
      _last = result.last;
      _error = null;
    } on ApiException catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: 1 + _trips.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) return widget.header ?? const SizedBox.shrink();
          final i = index - 1;
          if (i < _trips.length) return TripCard(_trips[i], showDriver: widget.showDriver, onTap: () => widget.onOpen(_trips[i]));
          if (_error != null) return ErrorState(_error!, onRetry: _loadMore);
          if (_loading && _trips.isEmpty) return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
          if (_trips.isEmpty) return EmptyState(widget.emptyText ?? context.t('no_trips'));
          if (!_last) {
            return Center(child: TextButton(onPressed: _loading ? null : _loadMore, child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.t('load_more'))));
          }
          return const SizedBox(height: 8);
        },
      ),
    );
  }
}
