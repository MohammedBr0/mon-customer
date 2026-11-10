import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'common.dart';

/// A rounded "Br 120" bubble with a pointer, drawn to a bitmap for use as a map pin.
Future<BitmapDescriptor> priceTag(String text, {required bool selected, required double pixelRatio}) async {
  final painter = TextPainter(
    text: TextSpan(text: text, style: TextStyle(color: selected ? Colors.white : const Color(0xFF151E30), fontSize: selected ? 16 : 14, fontWeight: FontWeight.w800)),
    textDirection: TextDirection.ltr,
  )..layout();
  const padX = 12.0, padY = 7.0, pointer = 7.0;
  final width = painter.width + padX * 2;
  final bodyHeight = painter.height + padY * 2;
  final height = bodyHeight + pointer + 4;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, bodyHeight), const Radius.circular(14));
  final path = Path()
    ..addRRect(body)
    ..moveTo(width / 2 - pointer, bodyHeight - 1)
    ..lineTo(width / 2, bodyHeight + pointer)
    ..lineTo(width / 2 + pointer, bodyHeight - 1)
    ..close();
  canvas.drawShadow(path, Colors.black, 3, true);
  canvas.drawPath(path, Paint()..color = selected ? brand : Colors.white);
  if (!selected) canvas.drawPath(path, Paint()..color = brand..style = PaintingStyle.stroke..strokeWidth = 1.5);
  painter.paint(canvas, const Offset(padX, padY));

  final image = await recorder.endRecording().toImage((width * pixelRatio).ceil(), (height * pixelRatio).ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(data!.buffer.asUint8List(), imagePixelRatio: pixelRatio);
}

/// Distance in km between two points (haversine). Used to size a "search this area" radius.
double distanceKm(LatLng a, LatLng b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude), dLng = rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h.toDouble()));
}

/// A car seen from above, pointing up (north). Rotate the marker by [bearing] to face its direction of travel.
Future<BitmapDescriptor> carMarker({required bool selected, required double pixelRatio}) async {
  const w = 30.0, h = 54.0, pad = 6.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  canvas.translate(pad, pad);
  final body = RRect.fromRectAndCorners(const Rect.fromLTWH(0, 0, w, h), topLeft: const Radius.circular(13), topRight: const Radius.circular(13), bottomLeft: const Radius.circular(9), bottomRight: const Radius.circular(9));
  canvas.drawShadow(Path()..addRRect(body), Colors.black, 3, true);
  canvas.drawRRect(body, Paint()..color = selected ? brand : Colors.white);
  canvas.drawRRect(body, Paint()..color = selected ? Colors.white : brand..style = PaintingStyle.stroke..strokeWidth = 2);
  final glass = Paint()..color = selected ? Colors.white : brand;
  // windscreen, rear window
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(5, 11, w - 10, 11), const Radius.circular(4)), glass);
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 37, w - 12, 7), const Radius.circular(3)), glass);
  // headlights
  final lamp = Paint()..color = const Color(0xFFFFD54F);
  canvas.drawCircle(const Offset(7, 4.5), 2.2, lamp);
  canvas.drawCircle(const Offset(w - 7, 4.5), 2.2, lamp);
  final image = await recorder.endRecording().toImage(((w + pad * 2) * pixelRatio).ceil(), ((h + pad * 2) * pixelRatio).ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(data!.buffer.asUint8List(), imagePixelRatio: pixelRatio);
}

/// Compass direction of travel from [a] to [b], in degrees clockwise from north.
double bearing(LatLng a, LatLng b) {
  double rad(double d) => d * math.pi / 180;
  final dLng = rad(b.longitude - a.longitude);
  final y = math.sin(dLng) * math.cos(rad(b.latitude));
  final x = math.cos(rad(a.latitude)) * math.sin(rad(b.latitude)) - math.sin(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
