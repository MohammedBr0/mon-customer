/// Decodes Google's encoded polyline format (precision 5) into (latitude, longitude) pairs.
List<(double, double)> decodePolyline(String? encoded) {
  final points = <(double, double)>[];
  if (encoded == null || encoded.isEmpty) return points;
  var index = 0;
  var lat = 0;
  var lng = 0;

  int nextValue() {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    lat += nextValue();
    if (index >= encoded.length) break;
    lng += nextValue();
    points.add((lat / 1e5, lng / 1e5));
  }
  return points;
}
