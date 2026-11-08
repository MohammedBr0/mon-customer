import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<RideAlert> _items = [];
  bool _loading = true;
  Object? _error;
  Place? _from;
  Place? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final items = await app.api.alerts();
      if (mounted) {
        setState(() {
          _items = items;
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

  Future<void> _add() async {
    if (_from == null || _to == null) return;
    try {
      await context.read<AppState>().api.createAlert(_from!, _to!);
      setState(() {
        _from = null;
        _to = null;
      });
      if (mounted) showMessage(context, context.tr('alert_saved'));
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    }
  }

  Future<void> _remove(RideAlert alert) async {
    try {
      await context.read<AppState>().api.deleteAlert(alert.id);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('alerts_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(_error!, onRetry: () {
                  setState(() => _loading = true);
                  _load();
                })
              : ListView(padding: const EdgeInsets.all(16), children: [
                  SectionTitle(context.t('new_alert')),
                  PlaceField(label: context.t('from'), value: _from, onChanged: (p) => setState(() => _from = p)),
                  const SizedBox(height: 12),
                  PlaceField(label: context.t('to'), value: _to, icon: Icons.place_outlined, onChanged: (p) => setState(() => _to = p)),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _from == null || _to == null ? null : _add, icon: const Icon(Icons.notifications_active_outlined), label: Text(context.t('alert_me'))),
                  const SizedBox(height: 16),
                  if (_items.isEmpty) EmptyState(context.t('alerts_empty'), icon: Icons.notifications_none),
                  for (final alert in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: const Icon(Icons.notifications_outlined),
                          title: Text('${alert.start} → ${alert.end}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(context.t('alert_matches', {'count': alert.matches})),
                          trailing: IconButton(tooltip: context.t('delete'), onPressed: () => _remove(alert), icon: const Icon(Icons.delete_outline)),
                        ),
                      ),
                    ),
                ]),
    );
  }
}
