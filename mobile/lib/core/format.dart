import 'package:intl/intl.dart';

/// Ethiopia is always UTC+3 (East Africa Time), whatever the phone's own time zone is.
DateTime eat(DateTime value) => value.toUtc().add(const Duration(hours: 3));

String formatMoney(num amount, String symbol) {
  final whole = amount == amount.roundToDouble();
  final text = NumberFormat(whole ? '#,##0' : '#,##0.00', 'en').format(amount);
  return '$text $symbol';
}

String formatDate(DateTime value, {String locale = 'en'}) => DateFormat('EEE d MMM', _safe(locale)).format(eat(value));

String formatTime(DateTime value, {String locale = 'en'}) => DateFormat('HH:mm', _safe(locale)).format(eat(value));

String formatDateTime(DateTime value, {String locale = 'en'}) => '${formatDate(value, locale: locale)} · ${formatTime(value, locale: locale)}';

String formatIsoDay(String iso, {String locale = 'en'}) => DateFormat('EEE d MMM', _safe(locale)).format(DateTime.parse(iso));

String _safe(String locale) => const ['en', 'am', 'it'].contains(locale) ? locale : 'en';

/// ISO calendar day (2026-11-09) for a date, used when booking commute days.
String isoDay(DateTime date) => DateFormat('yyyy-MM-dd', 'en').format(date);
