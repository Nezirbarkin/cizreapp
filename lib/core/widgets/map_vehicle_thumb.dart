import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/map_vehicle_painters.dart';

/// Haritadaki tepeden görünüm araç çiziminin küçük resmi.
///
/// Listelerde ve admin ekranlarında Material ikonu yerine, haritada görülenin
/// AYNISI gösterilsin diye aynı çizim motorunu ([paintMapVehicle]) kullanır.
/// Yükseklik verilir, genişlik aracın en/boy oranından gelir.
class MapVehicleThumb extends StatelessWidget {
  final MapVehicleShape shape;
  final Color color;
  final double height;

  /// Saat yönünde derece — ör. yön demosunda aracı çevirmek için.
  final double rotationDegrees;

  const MapVehicleThumb({
    super.key,
    required this.shape,
    required this.color,
    this.height = 44,
    this.rotationDegrees = 0,
  });

  @override
  Widget build(BuildContext context) {
    final base = mapVehicleLogicalSize(shape);
    final width = base.width * height / base.height;
    Widget child = SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _VehicleThumbPainter(shape, color)),
    );
    if (rotationDegrees != 0) {
      child = Transform.rotate(
        angle: rotationDegrees * math.pi / 180,
        child: child,
      );
    }
    return child;
  }
}

class _VehicleThumbPainter extends CustomPainter {
  final MapVehicleShape shape;
  final Color color;
  const _VehicleThumbPainter(this.shape, this.color);

  @override
  void paint(Canvas canvas, Size size) =>
      paintMapVehicle(canvas, size, shape, color);

  @override
  bool shouldRepaint(covariant _VehicleThumbPainter old) =>
      old.shape != shape || old.color != color;
}

/// Haritadaki durak çiziminin küçük resmi.
class MapStopThumb extends StatelessWidget {
  final MapStopStyle style;
  final MapStopDetail detail;
  final MapStopState state;
  final List<Color> lineColors;
  final double height;
  final bool isStart;
  final bool isEnd;

  const MapStopThumb({
    super.key,
    required this.style,
    this.detail = MapStopDetail.near,
    this.state = MapStopState.normal,
    this.lineColors = const [],
    this.height = 48,
    this.isStart = false,
    this.isEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = mapStopLogicalSize(style, detail);
    final width = base.width * height / base.height;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _StopThumbPainter(
          style,
          detail,
          state,
          lineColors,
          isStart,
          isEnd,
        ),
      ),
    );
  }
}

class _StopThumbPainter extends CustomPainter {
  final MapStopStyle style;
  final MapStopDetail detail;
  final MapStopState state;
  final List<Color> lineColors;
  final bool isStart;
  final bool isEnd;

  const _StopThumbPainter(
    this.style,
    this.detail,
    this.state,
    this.lineColors,
    this.isStart,
    this.isEnd,
  );

  @override
  void paint(Canvas canvas, Size size) => paintMapStop(
        canvas,
        size,
        style,
        detail,
        state,
        lineColors,
        isStart: isStart,
        isEnd: isEnd,
      );

  @override
  bool shouldRepaint(covariant _StopThumbPainter old) =>
      old.style != style ||
      old.detail != detail ||
      old.state != state ||
      old.isStart != isStart ||
      old.isEnd != isEnd ||
      old.lineColors.length != lineColors.length ||
      !_sameColors(old.lineColors, lineColors);

  static bool _sameColors(List<Color> a, List<Color> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
