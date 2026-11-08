import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'trip_screen.dart';

/// Two lists: seats I booked, and requests other people made for my trips.
class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  List<Booking> _made = [];
  List<Booking> _received = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final data = await app.api.bookings();
      if (mounted) {
        setState(() {
          _made = data.made;
          _received = data.received;
          _error = null;
          _loading = false;
        });
      }
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
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorState(_error!, onRetry: () {
        setState(() => _loading = true);
        _load();
      });
    }
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [
          Tab(text: context.t('my_bookings')),
          Tab(text: '${context.t('requests')}${_received.where((b) => b.status == 'pending').isEmpty ? '' : ' (${_received.where((b) => b.status == 'pending').length})'}'),
        ]),
        Expanded(
          child: TabBarView(children: [
            _list(_made, context.t('no_bookings'), false),
            _list(_received, context.t('no_requests'), true),
          ]),
        ),
      ]),
    );
  }

  Widget _list(List<Booking> items, String empty, bool driver) => RefreshIndicator(
        onRefresh: _load,
        child: items.isEmpty
            ? ListView(children: [const SizedBox(height: 60), EmptyState(empty, icon: Icons.confirmation_number_outlined)])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => openTrip(context, items[i].trip.id),
                  child: BookingCard(key: ValueKey(items[i].id), booking: items[i], viewerIsDriver: driver, showTrip: true, onChanged: _load),
                ),
              ),
      );
}
