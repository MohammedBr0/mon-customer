import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'dialogs.dart';
import 'live_screens.dart';
import 'map_screens.dart';
import '../widgets/route_map.dart';

void openTrip(BuildContext context, int id) => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: id)));

class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.tripId});
  final int tripId;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  Trip? _trip;
  List<Booking> _requests = [];
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final trip = await app.api.trip(widget.tripId);
      var requests = <Booking>[];
      if (trip.driver.id == app.user?.id) {
        requests = (await app.api.bookings()).received.where((b) => b.trip.id == trip.id).toList();
      }
      if (mounted) {
        setState(() {
          _trip = trip;
          _requests = requests;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) context.read<AppState>().syncReminders();
      if (mounted && done != null) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final trip = _trip;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('trip_details')),
        actions: [
          if (trip != null && trip.driver.id != app.user?.id)
            IconButton(tooltip: context.t('report'), onPressed: () => showReportDialog(context, type: 'Itinerary', id: trip.id), icon: const Icon(Icons.flag_outlined)),
        ],
      ),
      body: _error != null && trip == null
          ? ErrorState(_error!, onRetry: _load)
          : trip == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: _body(context, app, trip)),
    );
  }

  Widget _body(BuildContext context, AppState app, Trip trip) {
    final scheme = Theme.of(context).colorScheme;
    final symbol = app.config.currencySymbol;
    final mine = trip.driver.id == app.user?.id;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (trip.cancelled)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0x33F2B705), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [const Icon(Icons.block), const SizedBox(width: 8), Expanded(child: Text(context.t('trip_cancelled')))]),
        ),
      Builder(builder: (context) {
        final points = routePoints(polyline: trip.polyline, startLat: trip.startLat, startLng: trip.startLng, endLat: trip.endLat, endLng: trip.endLng);
        if (points.length < 2) return const SizedBox.shrink();
        void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => TripMapScreen(trip: trip, points: points)));
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Stack(children: [
            RouteMap(points: points, height: 210, onTap: open),
            Positioned(
              right: 10,
              bottom: 10,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14), backgroundColor: Colors.white, foregroundColor: brand),
                onPressed: open,
                icon: const Icon(Icons.open_in_full, size: 16),
                label: Text(context.t('view_route')),
              ),
            ),
            if (trip.distanceKm != null)
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.route, size: 16, color: brand), const SizedBox(width: 6), Text('${trip.distanceKm!.toStringAsFixed(trip.distanceKm! >= 20 ? 0 : 1)} km', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF151E30)))]),
                ),
              ),
          ]),
        );
      }),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: JourneyTimeline(
            from: trip.from,
            to: trip.to,
            fromNote: [if (trip.from != trip.startAddress) trip.startAddress, if ((trip.pickupPoint ?? '').isNotEmpty) trip.pickupPoint!].join(' · '),
            toNote: [if (trip.to != trip.endAddress) trip.endAddress, if ((trip.dropoffPoint ?? '').isNotEmpty) trip.dropoffPoint!].join(' · '),
            time: trip.commute ? trip.scheduleSummary : (trip.leaveDate == null ? null : formatDateTime(trip.leaveDate!, locale: app.locale)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _Fact(label: context.t('per_seat'), value: formatMoney(trip.passengerPrice, symbol)),
        _Fact(
          label: context.t('seats'),
          value: trip.cancelled ? context.t('cancelled') : trip.full ? context.t('fully_booked') : trip.seatsAvailable == null ? context.t('seats_unlimited') : context.t('seats_left', {'available': trip.seatsAvailable, 'total': trip.seatsTotal}),
        ),
      ]),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('driver').toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Row(children: [
              Avatar(trip.driver, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(trip.driver.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                    if (trip.driver.verified) ...[const SizedBox(width: 6), Chip2(context.t('verified'), icon: Icons.verified)],
                  ]),
                  RatingLine(trip.driver),
                ]),
              ),
            ]),
            if (trip.driver.vehicle.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final v in trip.driver.vehicle) Chip2('${v.label}: ${v.value}', tone: ChipTone.muted)]),
            ],
            if (!mine) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(tripId: trip.id, title: trip.driver.firstName ?? trip.driver.name))),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(context.t('message')),
                  ),
                ),
                if ((trip.driver.phone ?? '').isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), onPressed: () => launchUrl(Uri.parse('tel:${trip.driver.phone}')), icon: const Icon(Icons.call), label: Text(context.t('call')))),
                ],
              ]),
              if ((trip.driver.phone ?? '').isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('phone_after_confirm'), style: Theme.of(context).textTheme.bodySmall)),
            ],
            if ((trip.description ?? '').isNotEmpty) ...[const SizedBox(height: 12), Text(trip.description!)],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (trip.pink) Chip2(context.t('women_only'), icon: Icons.lock_outline, tone: ChipTone.warn),
              Chip2(context.t(trip.smoking ? 'smoking_allowed' : 'smoking_forbidden'), tone: ChipTone.muted, icon: trip.smoking ? Icons.smoking_rooms : Icons.smoke_free),
              Chip2(context.t(trip.pets ? 'pets_allowed' : 'pets_forbidden'), tone: ChipTone.muted, icon: Icons.pets),
            ]),
          ]),
        ),
      ),
      if (trip.payments.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('pay_with').toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              for (final p in trip.payments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if ((p.accountNumber ?? '').isNotEmpty) SelectableText([p.accountNumber!, if ((p.accountName ?? '').isNotEmpty) p.accountName!].join(' · '), style: TextStyle(color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                  ]),
                ),
              if (!mine && trip.payments.every((p) => (p.accountNumber ?? '').isEmpty) && trip.myBooking?.status != 'confirmed') Text(context.t('pay_details_after_confirm'), style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      ],
      if (trip.passengers.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('riding_together').toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 14, runSpacing: 10, children: [
                for (final p in trip.passengers)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 16, backgroundColor: scheme.primaryContainer, foregroundImage: (p.image ?? '').isEmpty ? null : NetworkImage(p.image!), child: Text(p.firstName.isEmpty ? '?' : p.firstName.characters.first.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer))),
                    const SizedBox(width: 8),
                    Text(p.seats > 1 ? '${p.firstName} ×${p.seats}' : p.firstName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
              ]),
            ]),
          ),
        ),
      ],
      if (mine) ..._driverSection(context, app, trip) else ..._passengerSection(context, app, trip),
      const SizedBox(height: 24),
      if (_busy) const LinearProgressIndicator(),
      SizedBox(height: scheme.brightness == Brightness.dark ? 0 : 0),
    ]);
  }

  // ---- driver ----
  List<Widget> _driverSection(BuildContext context, AppState app, Trip trip) {
    return [
      if (!trip.cancelled) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  if (!trip.live) {
                    if (!await confirmDialog(context, context.tr('start_trip_q'), action: context.tr('start_trip')) || !context.mounted) return;
                    setState(() => _busy = true);
                    try {
                      await app.api.startTrip(trip.id);
                    } catch (e) {
                      if (context.mounted) showMessage(context, errorText(context, e), error: true);
                      if (mounted) setState(() => _busy = false);
                      return;
                    }
                    if (mounted) setState(() => _busy = false);
                  }
                  if (!context.mounted) return;
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveTripScreen(trip: trip, driving: true)));
                  _load();
                },
          icon: Icon(trip.live ? Icons.sensors : Icons.play_arrow),
          label: Text(context.t(trip.live ? 'continue_trip' : 'start_trip')),
        ),
      ],
      SectionTitle(context.t('requests')),
      if (_requests.isEmpty) Card(child: EmptyState(context.t('no_requests'), icon: Icons.confirmation_number_outlined)),
      for (final booking in _requests) ...[
        BookingCard(booking: booking, viewerIsDriver: true, onChanged: _load),
        const SizedBox(height: 10),
      ],
      if (!trip.cancelled) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: _busy
              ? null
              : () async {
                  final done = context.tr('trip_cancelled');
                  if (await confirmDialog(context, context.tr('cancel_trip_confirm'), action: context.tr('cancel_trip'))) {
                    await _run(() => app.api.cancelTrip(trip.id), done: done);
                  }
                },
          icon: const Icon(Icons.block),
          label: Text(context.t('cancel_trip')),
        ),
      ],
    ];
  }

  // ---- passenger ----
  List<Widget> _passengerSection(BuildContext context, AppState app, Trip trip) {
    final booking = trip.myBooking;
    if (booking != null && booking.isActive) {
      return [
        SectionTitle(context.t('your_booking')),
        if (trip.live && booking.status == 'confirmed') ...[
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveTripScreen(trip: trip, driving: false))).then((_) => _load()),
            icon: const Icon(Icons.sensors),
            label: Text(context.t('track_ride')),
          ),
          const SizedBox(height: 10),
        ],
        BookingProgress(confirmed: booking.status == 'confirmed', completed: booking.completed),
        const SizedBox(height: 10),
        BookingCard(booking: booking, viewerIsDriver: false, onChanged: _load),
        if (booking.status == 'confirmed' && (app.config.paymentInstructions ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [const Icon(Icons.account_balance_wallet_outlined), const SizedBox(width: 10), Expanded(child: Text(app.config.paymentInstructions!))]))),
        ],
      ];
    }
    if (trip.bookable) {
      return [SectionTitle(context.t('book_title')), BookingForm(trip: trip, onBooked: _load)];
    }
    return [
      if (booking != null) ...[SectionTitle(context.t('your_booking')), BookingCard(booking: booking, viewerIsDriver: false, onChanged: _load)],
    ];
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 42) / 2;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// Seats, days and a live price, then the request button.
class BookingForm extends StatefulWidget {
  const BookingForm({super.key, required this.trip, required this.onBooked});
  final Trip trip;
  final Future<void> Function() onBooked;

  @override
  State<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  int _seats = 1;
  late final Set<String> _days;
  final _note = TextEditingController();
  Place? _pickup; // where the passenger wants to be picked up; the driver sees it on a map with the request
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final open = widget.trip.days.where((d) => d.seatsAvailable == null || d.seatsAvailable! > 0).map((d) => d.date);
    _days = widget.trip.commute ? open.take(5).toSet() : <String>{};
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _maxSeats {
    final selected = widget.trip.days.where((d) => !widget.trip.commute || _days.contains(d.date)).map((d) => d.seatsAvailable).whereType<int>();
    final limit = selected.isEmpty ? (widget.trip.seatsAvailable ?? 8) : selected.reduce((a, b) => a < b ? a : b);
    return limit.clamp(1, 8);
  }

  Future<void> _book() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await app.api.book(widget.trip.id, seats: _seats.clamp(1, _maxSeats), days: _days.toList()..sort(), note: _note.text.trim(), pickup: _pickup);
      if (mounted) showMessage(context, context.tr('request_sent'));
      await widget.onBooked();
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
    final seats = _seats.clamp(1, _maxSeats);
    final days = trip.commute ? _days.length : 1;
    final canBook = !_busy && (!trip.commute || _days.isNotEmpty);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (trip.commute) ...[
            Text(context.t('days_to_ride'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final d in trip.days)
                FilterChip(
                  label: Text(formatIsoDay(d.date, locale: app.locale)),
                  selected: _days.contains(d.date),
                  onSelected: (d.seatsAvailable != null && d.seatsAvailable! <= 0) ? null : (on) => setState(() => on ? _days.add(d.date) : _days.remove(d.date)),
                ),
            ]),
            Padding(padding: const EdgeInsets.only(top: 4, bottom: 12), child: Text(context.t('days_hint'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(context.t('seats'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(children: [
              IconButton.outlined(onPressed: seats > 1 ? () => setState(() => _seats = seats - 1) : null, icon: const Icon(Icons.remove), tooltip: '-'),
              SizedBox(width: 40, child: Center(child: Text('$seats', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))),
              IconButton.outlined(onPressed: seats < _maxSeats ? () => setState(() => _seats = seats + 1) : null, icon: const Icon(Icons.add), tooltip: '+'),
            ]),
          ]),
          const Divider(height: 24),
          PriceBreakdown(perSeat: trip.pricePerSeat, seats: seats, days: days, feePercent: app.config.feePercent, chargedTo: app.config.feeChargedTo),
          const SizedBox(height: 12),
          PlaceField(label: context.t('your_pickup'), value: _pickup, placeholder: context.t('your_pickup_hint'), icon: Icons.person_pin_circle_outlined, onChanged: (p) => setState(() => _pickup = p)),
          Padding(padding: const EdgeInsets.only(top: 4, left: 4, bottom: 12), child: Text(context.t('your_pickup_note'), style: Theme.of(context).textTheme.bodySmall)),
          TextField(controller: _note, maxLength: 500, decoration: InputDecoration(labelText: context.t('note_to_driver'))),
          if ((app.config.paymentInstructions ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.account_balance_wallet_outlined, size: 18), const SizedBox(width: 8), Expanded(child: Text(app.config.paymentInstructions!, style: const TextStyle(fontSize: 13)))])),
          FilledButton.icon(onPressed: canBook ? _book : null, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.confirmation_number_outlined), label: Text(context.t('request_seats'))),
        ]),
      ),
    );
  }
}

/// A booking with its days, price and the actions that apply to the viewer.
class BookingCard extends StatefulWidget {
  const BookingCard({super.key, required this.booking, required this.viewerIsDriver, required this.onChanged, this.showTrip = false});
  final Booking booking;
  final bool viewerIsDriver;
  final Future<void> Function() onChanged;
  final bool showTrip;

  @override
  State<BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<BookingCard> {
  bool _busy = false;

  Future<void> _do(Future<Object?> Function(Api api) action, String done) async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await action(app.api);
      if (mounted) showMessage(context, done);
      await widget.onChanged();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final b = widget.booking;
    final other = widget.viewerIsDriver ? b.passenger : b.driver;
    final today = isoDay(DateTime.now());
    final showDays = b.rideDates.length > 1 || b.trip.commute;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(other, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.showTrip ? '${b.trip.from} → ${b.trip.to}' : other.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                Text(widget.showTrip ? '${other.name} · ${context.t('seats')}: ${b.seats}' : '${context.t('seats')}: ${b.seats}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            StatusChip(b.status),
          ]),
          if (!widget.showTrip && b.trip.leaveDate != null && !b.trip.commute) Padding(padding: const EdgeInsets.only(top: 6), child: Text(formatDateTime(b.trip.leaveDate!, locale: app.locale), style: const TextStyle(fontSize: 13))),
          if ((b.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('“${b.note}”', style: const TextStyle(fontStyle: FontStyle.italic))),
          if (b.status == 'confirmed' && (other.phone ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: InkWell(onTap: () => launchUrl(Uri.parse('tel:${other.phone}')), child: Row(children: [const Icon(Icons.call, size: 16), const SizedBox(width: 6), Text(other.phone!, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600))]))),
          if (b.pickup != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.person_pin_circle_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(b.pickup!.name.isEmpty ? context.t('pickup_point') : '${context.t('pickup_point')}: ${b.pickup!.name}', maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (widget.viewerIsDriver)
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PickupMapScreen(booking: b))),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: Text(context.t('see_on_map')),
                ),
            ]),
          ],
          if (showDays && b.rideDates.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in b.rideDates)
                InputChip(
                  label: Text(formatIsoDay(d, locale: app.locale)),
                  visualDensity: VisualDensity.compact,
                  onDeleted: (b.isActive && d.compareTo(today) >= 0 && !_busy)
                      ? () async {
                          final done = context.tr('booking_cancelled');
                          if (await confirmDialog(context, context.tr('skip_day_confirm', {'day': formatIsoDay(d, locale: app.locale)}), action: context.tr('skip_day'))) {
                            await _do((api) => api.skipDate(b.id, d), done);
                          }
                        }
                      : null,
                  deleteIconColor: Theme.of(context).colorScheme.error,
                ),
            ]),
          ],
          const Divider(height: 22),
          PriceBreakdown(perSeat: b.price.perSeat, seats: b.seats, days: b.price.rides, feePercent: b.price.feePercent, chargedTo: b.price.chargedTo, forDriver: widget.viewerIsDriver),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (widget.viewerIsDriver && b.status == 'pending') ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                onPressed: _busy ? null : () => _do((api) => api.confirm(b.id), context.tr('booking_confirmed')),
                icon: const Icon(Icons.check),
                label: Text(context.t('confirm')),
              ),
              OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: _busy ? null : () => _do((api) => api.decline(b.id), context.tr('booking_declined')), child: Text(context.t('decline'))),
            ],
            if (b.isActive && !(widget.viewerIsDriver && b.status == 'pending'))
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(110, 44), foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: _busy
                    ? null
                    : () async {
                        final done = context.tr('booking_cancelled');
                        if (await confirmDialog(context, context.tr('cancel_booking_confirm'), action: context.tr('cancel_booking'))) {
                          await _do((api) => api.cancelBooking(b.id), done);
                        }
                      },
                child: Text(context.t('cancel_booking')),
              ),
            if (b.completed && b.reviewed == false)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
                onPressed: () async {
                  final sent = await showReviewDialog(context, bookingId: b.id, ofDriver: !widget.viewerIsDriver);
                  if (sent) await widget.onChanged();
                },
                icon: const Icon(Icons.star_outline),
                label: Text(context.t(widget.viewerIsDriver ? 'rate_passenger' : 'rate_driver')),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Pickup and drop-off as a vertical line with stops, the way ride apps show a journey.
class JourneyTimeline extends StatelessWidget {
  const JourneyTimeline({super.key, required this.from, required this.to, this.fromNote, this.toNote, this.time});
  final String from;
  final String to;
  final String? fromNote;
  final String? toNote;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget stop({required bool end, required String title, String? note, String? extra}) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 24,
              child: Column(children: [
                Container(width: 14, height: 14, margin: const EdgeInsets.only(top: 3), decoration: BoxDecoration(shape: end ? BoxShape.rectangle : BoxShape.circle, borderRadius: end ? BorderRadius.circular(3) : null, color: end ? scheme.primary : Colors.transparent, border: Border.all(color: scheme.primary, width: 3))),
                if (!end) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: scheme.outlineVariant)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: end ? 0 : 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (extra != null) Text(extra, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if ((note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [Icon(Icons.push_pin_outlined, size: 14, color: scheme.onSurfaceVariant), const SizedBox(width: 4), Expanded(child: Text(note!, style: TextStyle(color: scheme.onSurfaceVariant)))])),
                ]),
              ),
            ),
          ]),
        );
    return Column(children: [
      stop(end: false, title: from, note: fromNote, extra: time),
      stop(end: true, title: to, note: toNote),
    ]);
  }
}

/// Where a seat request stands: asked, confirmed by the driver, ride done.
class BookingProgress extends StatelessWidget {
  const BookingProgress({super.key, required this.confirmed, required this.completed});
  final bool confirmed;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reached = [true, confirmed, completed];
    final labels = [context.t('step_requested'), context.t('step_confirmed'), context.t('step_done')];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Row(children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) Expanded(child: Container(height: 3, margin: const EdgeInsets.only(bottom: 20), color: reached[i] ? scheme.primary : scheme.outlineVariant)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 12, backgroundColor: reached[i] ? scheme.primary : scheme.outlineVariant, child: Icon(reached[i] ? Icons.check : Icons.circle, size: reached[i] ? 14 : 6, color: Colors.white)),
              const SizedBox(height: 4),
              Text(labels[i], style: TextStyle(fontSize: 12, fontWeight: reached[i] ? FontWeight.w700 : FontWeight.w400, color: reached[i] ? scheme.onSurface : scheme.onSurfaceVariant)),
            ]),
          ],
        ]),
      ),
    );
  }
}
