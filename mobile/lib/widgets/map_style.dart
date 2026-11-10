import 'package:flutter/material.dart';

/// The look of every map in the app: a plain road map like ride-hailing apps use. Shops and other
/// points of interest are hidden so cars, routes and your own position stand out.
const _lightStyle = '''
[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#e3f1e1"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#f3f4f6"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#dfe6f3"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9dcf7"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#5b6577"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"}]}
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
