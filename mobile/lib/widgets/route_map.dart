import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/polyline.dart';
import 'common.dart';

/// The line a trip drives, as map points. Falls back to a straight line between the two ends.
List<LatLng> routePoints({String? polyline, double? startLat, double? startLng, double? endLat, double? endLng}) {
  final decoded = decodePolyline(polyline);
  if (decoded.length >= 2) return [for (final p in decoded) LatLng(p.$1, p.$2)];
  if (startLat != null && startLng != null && endLat != null && endLng != null) {
    return [LatLng(startLat, startLng), LatLng(endLat, endLng)];
  }
  return const [];
}

LatLngBounds boundsOf(Iterable<LatLng> points) {
  final list = points.toList();
  var south = list.first.latitude, north = list.first.latitude, west = list.first.longitude, east = list.first.longitude;
  for (final p in list) {
    south = math.min(south, p.latitude);
    north = math.max(north, p.latitude);
    west = math.min(west, p.longitude);
    east = math.max(east, p.longitude);
  }
  return LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east));
}

/// A camera that roughly frames the points, without needing a map controller (so it also suits lite maps).
CameraPosition framing(Iterable<LatLng> points) {
  final b = boundsOf(points);
  final span = math.max((b.northeast.longitude - b.southwest.longitude).abs(), (b.northeast.latitude - b.southwest.latitude).abs() * 1.3);
  final zoom = span < 0.0005 ? 15.0 : (math.log(380 / span) / math.ln2).clamp(3.0, 16.0);
  return CameraPosition(target: LatLng((b.southwest.latitude + b.northeast.latitude) / 2, (b.southwest.longitude + b.northeast.longitude) / 2), zoom: zoom - 0.4);
}

Set<Marker> endMarkers(List<LatLng> points) => {
      Marker(markerId: const MarkerId('a'), position: points.first, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: const InfoWindow(title: 'A')),
      Marker(markerId: const MarkerId('b'), position: points.last, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), infoWindow: const InfoWindow(title: 'B')),
    };

/// Satellite is the default map look, so the route is drawn in a bright yellow that stands out on imagery.
const satelliteRouteColor = Color(0xFFFFD54F);

Polyline routeLine(List<LatLng> points, {bool satellite = true}) => Polyline(polylineId: const PolylineId('route'), points: points, color: satellite ? satelliteRouteColor : brand, width: satellite ? 6 : 5, jointType: JointType.round, startCap: Cap.roundCap, endCap: Cap.roundCap);

/// A small, non-interactive map of a route (lite mode), for cards. Tap it to open something bigger.
class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.points, this.height = 180, this.onTap});
  final List<LatLng> points;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          GoogleMap(
            initialCameraPosition: framing(points),
            markers: endMarkers(points),
            polylines: {routeLine(points)},
            liteModeEnabled: true,
            mapType: MapType.hybrid,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
            compassEnabled: false,
          ),
          if (onTap != null) Positioned.fill(child: Material(color: Colors.transparent, child: InkWell(onTap: onTap))),
        ]),
      ),
    );
  }
}
