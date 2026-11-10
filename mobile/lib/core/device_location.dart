import 'package:geolocator/geolocator.dart';

/// True for a point inside Ethiopia's bounding box.
bool inEthiopia(double lat, double lng) => lat >= 3.3 && lat <= 15.0 && lng >= 32.9 && lng <= 48.1;

/// The phone's current position, or null when location is off, the person said no, or the phone is outside
/// Ethiopia (the app then stays on Addis Ababa).
Future<(double, double)?> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)));
    if (!inEthiopia(position.latitude, position.longitude)) return null;
    return (position.latitude, position.longitude);
  } catch (_) {
    return null;
  }
}
