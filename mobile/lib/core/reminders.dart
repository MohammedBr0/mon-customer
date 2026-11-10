import '../models/models.dart';

/// A ride that is coming up, for which a reminder should be shown.
class UpcomingRide {
  const UpcomingRide({required this.tripId, required this.title, required this.start, required this.driving});
  final int tripId;
  final String title;
  final DateTime start; // UTC
  final bool driving;
}

const _eat = Duration(hours: 3); // Ethiopian time is UTC+3 all year

/// When a ride next leaves, in UTC, looking [days] days ahead. One-off trips leave once; weekly commutes leave
/// at the same Ethiopian clock time on each of their days. [rideDays] limits a commute to the dates a passenger
/// booked (ISO days); [weekdays] are the commute's days (0 = Sunday) for a driver.
List<DateTime> nextStarts({required DateTime? leave, required bool commute, List<String> rideDays = const [], List<int> weekdays = const [], required DateTime now, int days = 7}) {
  if (leave == null) return const [];
  final nowUtc = now.toUtc();
  if (!commute) return leave.toUtc().isAfter(nowUtc) ? [leave.toUtc()] : const [];

  final clock = leave.toUtc().add(_eat); // the departure's clock time in Ethiopia
  final today = nowUtc.add(_eat);
  final starts = <DateTime>[];
  for (var offset = 0; offset <= days; offset++) {
    final day = DateTime.utc(today.year, today.month, today.day).add(Duration(days: offset));
    final iso = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final wanted = rideDays.isNotEmpty ? rideDays.contains(iso) : weekdays.contains(day.weekday % 7);
    if (!wanted) continue;
    final start = DateTime.utc(day.year, day.month, day.day, clock.hour, clock.minute).subtract(_eat);
    if (start.isAfter(nowUtc)) starts.add(start);
  }
  return starts;
}

/// Every ride in the coming week that this person is on, as a passenger or as the driver, soonest first.
List<UpcomingRide> upcomingRides({required List<Booking> made, required List<Trip> mine, required DateTime now}) {
  final rides = <UpcomingRide>[
    for (final b in made)
      if (b.isActive && !b.trip.cancelled)
        for (final start in nextStarts(leave: b.trip.leaveDate, commute: b.trip.commute, rideDays: b.rideDates, now: now))
          UpcomingRide(tripId: b.trip.id, title: '${b.trip.from} → ${b.trip.to}', start: start, driving: false),
    for (final t in mine)
      if (!t.cancelled)
        for (final start in nextStarts(leave: t.leaveDate, commute: t.commute, weekdays: t.commuteDays, now: now))
          UpcomingRide(tripId: t.id, title: '${t.from} → ${t.to}', start: start, driving: true),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return rides;
}
