import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../screens/map_screens.dart';

const brand = Color(0xFF0B7A4B);
const accent = Color(0xFFF2B705);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness, primary: brightness == Brightness.light ? brand : const Color(0xFF3FBF86));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF4F7F5) : const Color(0xFF0E1612),
    fontFamilyFallback: const ['Noto Sans Ethiopic', 'Abyssinica SIL', 'Roboto'],
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: brightness == Brightness.light ? Colors.white : const Color(0xFF16211B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.light ? Colors.white : const Color(0xFF16211B),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.outlineVariant)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, foregroundColor: scheme.onSurface, elevation: 0, scrolledUnderElevation: 1),
    navigationBarTheme: NavigationBarThemeData(indicatorColor: scheme.primaryContainer),
  );
}

/// A person-readable message for any failure.
String errorText(BuildContext context, Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'network':
        return context.tr('error_network');
      case 'timeout':
        return context.tr('error_timeout');
    }
    if (error.message.startsWith('server_')) return context.tr('error_server');
    return error.message;
  }
  return context.tr('error_server');
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
}

Future<bool> confirmDialog(BuildContext context, String message, {String? action}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action ?? ctx.tr('confirm')),
        ),
      ],
    ),
  );
  return result ?? false;
}

class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key, this.icon, this.tone = ChipTone.brand});
  final String label;
  final IconData? icon;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      ChipTone.brand => (scheme.primaryContainer, scheme.onPrimaryContainer),
      ChipTone.muted => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      ChipTone.warn => (const Color(0x33F2B705), const Color(0xFF8A6500)),
      ChipTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Flexible(child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

enum ChipTone { brand, muted, warn, danger }

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) => Chip2(
        context.t('status_$status'),
        tone: switch (status) { 'confirmed' => ChipTone.brand, 'pending' => ChipTone.warn, _ => ChipTone.muted },
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.route_outlined, this.action});
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState(this.error, {super.key, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        errorText(context, error),
        icon: Icons.cloud_off_outlined,
        action: OutlinedButton(onPressed: onRetry, child: Text(context.t('retry'))),
      );
}

class Avatar extends StatelessWidget {
  const Avatar(this.profile, {super.key, this.size = 40});
  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = profile.name.isEmpty ? '?' : String.fromCharCode(profile.name.runes.first).toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundImage: (profile.image ?? '').isEmpty ? null : NetworkImage(profile.image!),
      child: Text(initial, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onPrimaryContainer)),
    );
  }
}

class RatingLine extends StatelessWidget {
  const RatingLine(this.profile, {super.key});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    if (profile.reviewsCount == 0) return Text(context.t('no_reviews'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 16, color: Color(0xFFB8860B)),
      const SizedBox(width: 2),
      Text(context.t('reviews_count', {'rating': profile.rating?.toStringAsFixed(1) ?? '-', 'count': profile.reviewsCount}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// A trip in a list: route, price, time, seats and driver.
class TripCard extends StatelessWidget {
  const TripCard(this.trip, {super.key, required this.onTap, this.showDriver = true});
  final Trip trip;
  final VoidCallback onTap;
  final bool showDriver;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final symbol = app.config.currencySymbol;
    return Opacity(
      opacity: trip.cancelled ? 0.6 : 1,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: RouteLine(from: trip.startAddress, to: trip.endAddress)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(formatMoney(trip.passengerPrice, symbol), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.primary)),
                  Text(context.t('per_seat'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.schedule, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(trip.commute ? (trip.scheduleSummary ?? '') : (trip.leaveDate == null ? '' : formatDateTime(trip.leaveDate!, locale: app.locale)), style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ]),
                if (trip.cancelled)
                  Chip2(context.t('cancelled'), tone: ChipTone.muted)
                else if (trip.full)
                  Chip2(context.t('fully_booked'), tone: ChipTone.danger)
                else if (trip.seatsAvailable != null)
                  Chip2(context.t('seats_left', {'available': trip.seatsAvailable, 'total': trip.seatsTotal}))
                else
                  Chip2(context.t('seats_unlimited')),
                if (trip.cityCommute) Chip2(context.t('city_chip'), icon: Icons.location_city),
                if (trip.commute) Chip2(context.t('commute'), icon: Icons.repeat),
                if (trip.pink) Chip2(context.t('women_only'), icon: Icons.lock_outline, tone: ChipTone.warn),
              ]),
              if (showDriver) ...[
                const Divider(height: 24),
                Row(children: [
                  Avatar(trip.driver, size: 28),
                  const SizedBox(width: 8),
                  Flexible(child: Text(trip.driver.firstName ?? trip.driver.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  if (trip.driver.verified) ...[const SizedBox(width: 4), Icon(Icons.verified, size: 16, color: scheme.primary)],
                  const Spacer(),
                  RatingLine(trip.driver),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class RouteLine extends StatelessWidget {
  const RouteLine({super.key, required this.from, required this.to});
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget stop(String text, bool filled) => Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? scheme.primary : Colors.transparent, border: Border.all(color: scheme.primary, width: 3))),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      stop(from, false),
      Container(margin: const EdgeInsets.only(left: 5), width: 2, height: 14, color: scheme.outlineVariant),
      stop(to, true),
    ]);
  }
}

/// Fare, fee and total lines for a booking or a preview of one.
class PriceBreakdown extends StatelessWidget {
  const PriceBreakdown({super.key, required this.perSeat, required this.seats, required this.days, required this.feePercent, required this.chargedTo, this.forDriver = false});
  final double perSeat;
  final int seats;
  final int days;
  final double feePercent;
  final String chargedTo;
  final bool forDriver;

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<AppState>().config.currencySymbol;
    final fare = perSeat * seats * days;
    final fee = (fare * feePercent / 100 * 100).round() / 100;
    final passengerTotal = chargedTo == 'passenger' ? fare + fee : fare;
    final payout = chargedTo == 'driver' ? fare - fee : fare;
    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400, fontSize: bold ? 16 : 14))),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : 14)),
          ]),
        );
    final fareLabel = days > 1
        ? context.t('fare_line_days', {'seats': seats, 'days': days, 'price': formatMoney(perSeat, symbol)})
        : context.t('fare_line', {'seats': seats, 'price': formatMoney(perSeat, symbol)});
    final percent = feePercent == feePercent.roundToDouble() ? feePercent.toStringAsFixed(0) : feePercent.toString();
    return Column(children: [
      line(fareLabel, formatMoney(fare, symbol)),
      if (!forDriver && chargedTo == 'passenger' && feePercent > 0) line(context.t('service_fee', {'percent': percent}), formatMoney(fee, symbol)),
      if (forDriver && chargedTo == 'driver' && feePercent > 0) line(context.t('service_fee', {'percent': percent}), '- ${formatMoney(fee, symbol)}'),
      const Divider(height: 14),
      line(forDriver ? context.t('you_receive') : context.t('total_to_pay'), formatMoney(forDriver ? payout : passengerTotal, symbol), bold: true),
    ]);
  }
}

/// Opens a searchable list of Ethiopian towns.
Future<Place?> pickPlace(BuildContext context, {Place? selected, List<Place>? places}) {
  final allowAny = places == null; // a fixed list (like a city's neighbourhoods) stays a fixed list
  final app = context.read<AppState>();
  return showModalBottomSheet<Place>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PlaceSheet(places: places ?? app.config.places, locale: app.locale, selected: selected, allowAny: allowAny),
  );
}

class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet({required this.places, required this.locale, this.selected, this.allowAny = false});
  final bool allowAny;
  final List<Place> places;
  final String locale;
  final Place? selected;

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  String _query = '';
  Timer? _debounce;
  List<Place> _remote = [];
  bool _searching = false;
  int _serial = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (!widget.allowAny || value.trim().length < 3) {
      setState(() {
        _remote = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final mine = ++_serial;
      try {
        final found = await context.read<AppState>().api.searchPlaces(value.trim());
        if (mounted && mine == _serial) setState(() => _remote = found);
      } catch (_) {
        // Listed towns still work if the lookup fails.
      } finally {
        if (mounted && mine == _serial) setState(() => _searching = false);
      }
    });
  }

  Future<void> _chooseOnMap() async {
    final picked = await Navigator.push<Place>(context, MaterialPageRoute(builder: (_) => PlacePickerScreen(initial: widget.selected?.isPin == true ? widget.selected : null)));
    if (picked != null && mounted) Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = widget.places.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || (p.nameAm ?? '').contains(_query.trim())).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: InputDecoration(hintText: widget.allowAny ? context.t('search_any_place') : context.t('search_places'), prefixIcon: const Icon(Icons.search), suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))) : null),
                onChanged: _changed,
              ),
            ),
            if (widget.allowAny)
              ListTile(
                leading: const CircleAvatar(backgroundColor: brand, child: Icon(Icons.map_outlined, color: Colors.white)),
                title: Text(context.t('choose_on_map'), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: _chooseOnMap,
              ),
            Expanded(
              child: ListView(children: [
                for (final place in _remote)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(place.address ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, place),
                  ),
                if (_remote.isNotEmpty && shown.isNotEmpty) const Divider(),
                for (final place in shown)
                  ListTile(
                    leading: const Icon(Icons.location_city_outlined),
                    title: Text(place.label(widget.locale)),
                    subtitle: widget.locale == 'am' ? Text(place.name) : ((place.nameAm ?? '').isEmpty ? null : Text(place.nameAm!)),
                    trailing: widget.selected?.key == place.key ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, place),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A tappable field that shows the chosen town and opens the picker.
class PlaceField extends StatelessWidget {
  const PlaceField({super.key, required this.label, required this.value, required this.onChanged, this.icon = Icons.trip_origin, this.places, this.placeholder});
  final List<Place>? places;
  final String? placeholder;
  final String label;
  final Place? value;
  final ValueChanged<Place> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<AppState>().locale;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final place = await pickPlace(context, selected: value, places: places);
        if (place != null) onChanged(place);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), suffixIcon: const Icon(Icons.arrow_drop_down)),
        child: Text(value?.label(locale) ?? placeholder ?? context.t('pick_place'), style: TextStyle(color: value == null ? Theme.of(context).colorScheme.onSurfaceVariant : null)),
      ),
    );
  }
}
