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
