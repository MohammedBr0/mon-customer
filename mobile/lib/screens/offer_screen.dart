import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/route_map.dart';
import 'profile_screen.dart';
import 'trip_screen.dart';

/// Post a trip: one-off or repeating weekly (a commute). Times are entered in Ethiopian time (UTC+3).
class OfferScreen extends StatefulWidget {
  const OfferScreen({super.key});

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  final _form = GlobalKey<FormState>();
  final _price = TextEditingController();
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _description = TextEditingController();
  Place? _from;
  Place? _to;
  String? _city; // set when the trip stays inside one city
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  int _seats = 3;
  bool _repeat = false;
  final Set<int> _days = {};
  DateTime? _until;
  bool _womenOnly = false;
  bool _smoking = false;
  bool _pets = false;
  bool _busy = false;
  String? _placeError;
  RoutePreview? _preview;
  bool _previewing = false;
  int _previewSerial = 0;

  /// Shows the drive (distance, time, line on the map) once both ends are chosen outside a city.
  Future<void> _loadPreview() async {
    final from = _from, to = _to;
    final mine = ++_previewSerial;
    if (_city != null || from == null || to == null || from.key == to.key) {
      setState(() => _preview = null);
      return;
    }
    setState(() => _previewing = true);
    try {
      final preview = await context.read<AppState>().api.routePreview(from, to);
      if (mounted && mine == _previewSerial) setState(() => _preview = preview);
    } catch (_) {
      if (mounted && mine == _previewSerial) setState(() => _preview = null);
    } finally {
      if (mounted && mine == _previewSerial) setState(() => _previewing = false);
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _pickup.dispose();
    _dropoff.dispose();
    _description.dispose();
    super.dispose();
  }

  /// The chosen date and time as the moment it happens in Ethiopia, expressed in UTC.
  DateTime get _leaveUtc => DateTime.utc(_date.year, _date.month, _date.day, _time.hour, _time.minute).subtract(const Duration(hours: 3));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: _date.isBefore(now) ? now : _date, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickUntil() async {
    final picked = await showDatePicker(context: context, initialDate: _until ?? _date.add(const Duration(days: 30)), firstDate: _date, lastDate: _date.add(const Duration(days: 365)));
    if (picked != null) setState(() => _until = picked);
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();
    setState(() => _placeError = (_from == null || _to == null || _from!.key == _to!.key) ? context.tr('required') : null);
    if (!_form.currentState!.validate() || _from == null || _to == null || _from!.key == _to!.key) return;
    if (_repeat && _days.isEmpty) {
      showMessage(context, context.tr('repeat_hint'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final trip = await app.api.createTrip({
        if (_city != null) 'city': _city,
        'start': {'key': _from!.key},
        'end': {'key': _to!.key},
        'leave_date': _leaveUtc.toIso8601String(),
        'price_per_seat': _price.text.trim(),
        'num_people': _seats,
        if (_repeat) 'commute_days': _days.toList()..sort(),
        if (_repeat && _until != null) 'commute_until': isoDay(_until!),
        if (_pickup.text.trim().isNotEmpty) 'pickup_point': _pickup.text.trim(),
        if (_dropoff.text.trim().isNotEmpty) 'dropoff_point': _dropoff.text.trim(),
        'description': _description.text.trim(),
        'smoking_allowed': _smoking,
        'pets_allowed': _pets,
        if (_womenOnly) 'pink': true,
      });
      if (!mounted) return;
      showMessage(context, context.tr('trip_posted'));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: trip.id)));
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final config = app.config;
    final user = app.user;
    final locale = app.locale;
    final symbol = config.currencySymbol;
    final price = double.tryParse(_price.text.trim());
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('offer_title'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (user != null && !user.vehicleComplete)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.t('offer_vehicle_needed', {'fields': user.missingVehicleFields.join(', ')})),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VehicleScreen())).then((_) => app.refreshUser()),
                  child: Text(context.t('complete_vehicle')),
                ),
              ]),
            ),
          if (config.cities.isNotEmpty) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [ButtonSegment(value: false, label: Text(context.t('mode_towns'))), ButtonSegment(value: true, label: Text(context.t('mode_city')))],
              selected: {_city != null},
              onSelectionChanged: (s) => setState(() {
                _from = null;
                _to = null;
                _preview = null;
                _city = s.first ? config.cities.first.key : null;
              }),
            ),
            const SizedBox(height: 12),
          ],
          if (_city != null) ...[
            if (config.cities.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: _city,
                decoration: InputDecoration(labelText: context.t('city')),
                items: [for (final c in config.cities) DropdownMenuItem(value: c.key, child: Text(c.place.label(locale)))],
                onChanged: (v) => setState(() {
                  _city = v;
                  _from = null;
                  _to = null;
                }),
              ),
              const SizedBox(height: 12),
            ],
            PlaceField(label: context.t('from_area'), value: _from, places: config.cities.firstWhere((c) => c.key == _city).areas, placeholder: context.t('pick_area'), onChanged: (p) => setState(() => _from = p)),
            const SizedBox(height: 12),
            PlaceField(label: context.t('to_area'), value: _to, places: config.cities.firstWhere((c) => c.key == _city).areas, placeholder: context.t('pick_area'), icon: Icons.place_outlined, onChanged: (p) => setState(() => _to = p)),
            Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text(context.t('area_note'), style: Theme.of(context).textTheme.bodySmall)),
          ] else ...[
            PlaceField(label: context.t('from'), value: _from, onChanged: (p) {
              setState(() => _from = p);
              _loadPreview();
            }),
            const SizedBox(height: 12),
            PlaceField(label: context.t('to'), value: _to, icon: Icons.place_outlined, onChanged: (p) {
              setState(() => _to = p);
              _loadPreview();
            }),
            if (_previewing) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (_preview != null && _from != null && _to != null) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final points = routePoints(polyline: _preview!.polyline, startLat: _from!.lat, startLng: _from!.lng, endLat: _to!.lat, endLng: _to!.lng);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  RouteMap(points: points, height: 170),
                  Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text('${_preview!.distanceText} · ${_preview!.durationText}', style: const TextStyle(fontWeight: FontWeight.w700))),
                ]);
              }),
            ],
          ],
          if (_placeError != null) Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text(_placeError!, style: TextStyle(color: scheme.error, fontSize: 12))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _PickerField(label: context.t('date'), value: formatDate(_date, locale: locale), icon: Icons.calendar_today_outlined, onTap: _pickDate)),
            const SizedBox(width: 12),
            Expanded(child: _PickerField(label: context.t('time'), value: '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}', icon: Icons.schedule, onTap: _pickTime)),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: context.t('your_price'), prefixText: '$symbol '),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final n = double.tryParse((v ?? '').trim());
              if (n == null || n < 0 || n > config.maxPrice) return context.tr('price_limit', {'max': config.maxPrice.round()});
              return null;
            },
          ),
          if (price != null && config.feePercent > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                config.feeChargedTo == 'passenger'
                    ? context.t('price_with_fee_passenger', {'percent': config.feePercent.toStringAsFixed(config.feePercent % 1 == 0 ? 0 : 1), 'price': formatMoney(config.passengerPrice(price), symbol)})
                    : context.t('price_with_fee_driver', {'percent': config.feePercent.toStringAsFixed(config.feePercent % 1 == 0 ? 0 : 1)}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(labelText: context.t('free_seats')),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton.outlined(onPressed: _seats > 1 ? () => setState(() => _seats--) : null, icon: const Icon(Icons.remove)),
              Text('$_seats', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              IconButton.outlined(onPressed: _seats < 8 ? () => setState(() => _seats++) : null, icon: const Icon(Icons.add)),
            ]),
          ),
          if (config.commutesEnabled) ...[
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('repeat_weekly')), subtitle: Text(context.t('repeat_hint')), value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
            if (_repeat) ...[
              Wrap(spacing: 8, children: [
                for (final d in const [1, 2, 3, 4, 5, 6, 0])
                  FilterChip(
                    label: Text(context.t('weekday_$d')),
                    selected: _days.contains(d),
                    onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                  ),
              ]),
              const SizedBox(height: 12),
              _PickerField(label: context.t('repeat_until'), value: _until == null ? '—' : formatDate(_until!, locale: locale), icon: Icons.event_repeat, onTap: _pickUntil),
            ],
          ],
          const SizedBox(height: 12),
          TextFormField(controller: _pickup, maxLength: 140, decoration: InputDecoration(labelText: context.t('pickup_point'), counterText: '')),
          const SizedBox(height: 12),
          TextFormField(controller: _dropoff, maxLength: 140, decoration: InputDecoration(labelText: context.t('dropoff_point'), counterText: '')),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(labelText: context.t('description'), hintText: context.t('description_hint')),
            validator: (v) => (v ?? '').trim().isEmpty ? context.tr('description_required') : null,
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('smoking_allowed')), value: _smoking, onChanged: (v) => setState(() => _smoking = v)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('pets_allowed')), value: _pets, onChanged: (v) => setState(() => _pets = v)),
          if (user?.gender == 'female') SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('women_only_option')), value: _womenOnly, onChanged: (v) => setState(() => _womenOnly = v)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(context.t('post_trip')),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.label, required this.value, required this.icon, required this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: InputDecorator(decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)), child: Text(value)),
      );
}
