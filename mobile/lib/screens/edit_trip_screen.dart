import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Change a trip's time, seats, price, meeting points and notes. Allowed until 30 minutes before it leaves;
/// booked passengers are told when the time or the meeting points change.
class EditTripScreen extends StatefulWidget {
  const EditTripScreen({super.key, required this.trip});
  final Trip trip;

  @override
  State<EditTripScreen> createState() => _EditTripScreenState();
}

class _EditTripScreenState extends State<EditTripScreen> {
  final _form = GlobalKey<FormState>();
  late final _price = TextEditingController(text: widget.trip.pricePerSeat.round().toString());
  late final _pickup = TextEditingController(text: widget.trip.pickupPoint ?? '');
  late final _dropoff = TextEditingController(text: widget.trip.dropoffPoint ?? '');
  late final _description = TextEditingController(text: widget.trip.description ?? '');
  late DateTime _date;
  late TimeOfDay _time;
  late int _seats = widget.trip.seatsTotal ?? 3;
  late bool _smoking = widget.trip.smoking;
  late bool _pets = widget.trip.pets;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Times are shown and picked in Ethiopian time (UTC+3), whatever the phone's zone.
    final local = (widget.trip.leaveDate ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
    _date = DateTime(local.year, local.month, local.day);
    _time = TimeOfDay(hour: local.hour, minute: local.minute);
  }

  @override
  void dispose() {
    _price.dispose();
    _pickup.dispose();
    _dropoff.dispose();
    _description.dispose();
    super.dispose();
  }

  DateTime get _leaveUtc => DateTime.utc(_date.year, _date.month, _date.day, _time.hour, _time.minute).subtract(const Duration(hours: 3));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(context: context, initialDate: _date.isBefore(today) ? today : _date, firstDate: today, lastDate: today.add(const Duration(days: 365)));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_leaveUtc.isBefore(DateTime.now().toUtc().add(const Duration(minutes: 30)))) {
      showMessage(context, context.tr('edit_time_too_soon'), error: true);
      return;
    }
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await app.api.updateTrip(widget.trip.id, {
        'leave_date': _leaveUtc.toIso8601String(),
        'num_people': _seats,
        'price_per_seat': _price.text.trim(),
        'pickup_point': _pickup.text.trim(),
        'dropoff_point': _dropoff.text.trim(),
        'description': _description.text.trim(),
        'smoking_allowed': _smoking,
        'pets_allowed': _pets,
      });
      if (!mounted) return;
      showMessage(context, context.tr('trip_updated'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final trip = widget.trip;
    final scheme = Theme.of(context).colorScheme;
    final booked = trip.seatsTotal != null && trip.seatsAvailable != null ? trip.seatsTotal! - trip.seatsAvailable! : 0;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('edit_trip'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(14), child: RouteLine(from: trip.from, to: trip.to))),
          if (trip.editUntil != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Row(children: [
                Icon(Icons.lock_clock, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(child: Text(context.t('edit_until', {'time': formatDateTime(trip.editUntil!, locale: app.locale)}), style: Theme.of(context).textTheme.bodySmall)),
              ]),
            ),
          SectionTitle(context.t(trip.commute ? 'departure_time' : 'trip_when')),
          Row(children: [
            if (!trip.commute) ...[
              Expanded(child: OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event), label: Text(formatIsoDay(isoDay(_date), locale: app.locale)))),
              const SizedBox(width: 10),
            ],
            Expanded(child: OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule), label: Text(_time.format(context)))),
          ]),
          SectionTitle(context.t('seats')),
          Row(children: [
            IconButton.outlined(onPressed: _seats > 1 && _seats > booked ? () => setState(() => _seats--) : null, icon: const Icon(Icons.remove)),
            Expanded(child: Text('$_seats', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            IconButton.outlined(onPressed: _seats < 8 ? () => setState(() => _seats++) : null, icon: const Icon(Icons.add)),
          ]),
          if (booked > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text(context.t('seats_booked_already', {'count': booked}), style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center)),
          SectionTitle(context.t('per_seat')),
          TextFormField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(suffixText: app.config.currencySymbol),
            validator: (v) {
              final price = double.tryParse((v ?? '').trim());
              if (price == null || price < 0) return context.tr('required');
              if (price > app.config.maxPrice) return context.tr('price_limit', {'max': app.config.maxPrice.round()});
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _pickup, decoration: InputDecoration(labelText: context.t('pickup_point'))),
          const SizedBox(height: 12),
          TextFormField(controller: _dropoff, decoration: InputDecoration(labelText: context.t('dropoff_point'))),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 3,
            decoration: InputDecoration(labelText: context.t('description')),
            validator: (v) => (v ?? '').trim().isEmpty ? context.tr('required') : null,
          ),
          const SizedBox(height: 8),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _smoking, onChanged: (v) => setState(() => _smoking = v), title: Text(context.t('smoking_allowed'))),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _pets, onChanged: (v) => setState(() => _pets = v), title: Text(context.t('pets_allowed'))),
          const SizedBox(height: 12),
          Text(context.t('edit_notifies'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(context.t('save_changes'))),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ]),
      ),
    );
  }
}
