/// A starting price per seat for a trip: the admins' rate per km times the distance, shared between the seats
/// and rounded to the nearest 5. Returns null when there is nothing to suggest.
double? suggestedSeatPrice({required double distanceKm, required double ratePerKm, required int seats, required double maxPrice}) {
  if (distanceKm <= 0 || ratePerKm <= 0 || seats <= 0) return null;
  final raw = distanceKm * ratePerKm / seats;
  final rounded = (raw / 5).round() * 5.0;
  return rounded.clamp(5.0, maxPrice);
}

/// What a full car brings in, and what the driver keeps once the platform fee is taken (when drivers pay it).
({double total, double driverKeeps}) tripTotals({required double seatPrice, required int seats, required double feePercent, required bool driverPaysFee}) {
  final total = seatPrice * seats;
  final fee = driverPaysFee ? (total * feePercent / 100 * 100).round() / 100 : 0.0;
  return (total: total, driverKeeps: total - fee);
}
