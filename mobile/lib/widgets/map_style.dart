import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The look of every map in the app: a plain road map like ride-hailing apps use. Shops and other
/// points of interest are hidden so cars, routes and your own position stand out.
const _lightStyle = '''
[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]''';

const _darkStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#151e30"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#16283a"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#27344d"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#34456a"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0b1322"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#9aa7bd"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#151e30"}]}
]''';

/// The map style for the current light or dark theme.
String mapStyle(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? _darkStyle : _lightStyle;

/// The app serves Ethiopia: maps cannot be dragged outside the country or zoomed out past it.
final ethiopiaBounds = LatLngBounds(southwest: const LatLng(3.3, 32.9), northeast: const LatLng(15.0, 48.1));
final ethiopiaCamera = CameraTargetBounds(ethiopiaBounds);
const ethiopiaZoom = MinMaxZoomPreference(5.6, 20);

/// Where maps open when there is nothing more specific to show.
const addisAbaba = LatLng(9.0300, 38.7400);
