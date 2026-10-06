import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cizreapp/features/chat/widgets/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sohbet duvar kâğıdı artık önceden çizilmiş bir karonun tekrarıyla
/// doldurulur (her karede ~650 vektör simge çizmek yerine). Bu test yeni
/// çizimin, eski "her hücreyi doğrudan çiz" yöntemiyle aynı göründüğünü
/// piksel düzeyinde doğrular.
void main() {
  // Eski _WallpaperPainter'ın birebir kopyası (karşılaştırma için).
  void paintLegacy(Canvas canvas, Size size) {
    const cell = 64.0;
    final stroke = Paint()
      ..color = ChatPalette.wallpaperGlyph
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = ChatPalette.wallpaperGlyph;
    var row = 0;
    for (double y = 0; y < size.height + cell; y += cell, row++) {
      var col = 0;
      final shift = row.isOdd ? cell / 2 : 0.0;
      for (double x = -shift; x < size.width + cell; x += cell, col++) {
        final c = Offset(x + cell / 2, y + cell / 2);
        switch ((row + col) % 4) {
          case 0:
            final rect = Rect.fromCenter(center: c, width: 18, height: 13);
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(5)),
              stroke,
            );
            canvas.drawLine(
              rect.bottomLeft + const Offset(4, 0),
              rect.bottomLeft + const Offset(1, 4),
              stroke,
            );
          case 1:
            canvas.drawCircle(c, 5, stroke);
          case 2:
            for (final dx in const [-6.0, 0.0, 6.0]) {
              canvas.drawCircle(c + Offset(dx, 0), 1.6, fill);
            }
          default:
            final heart = Path()
              ..moveTo(c.dx, c.dy + 5)
              ..cubicTo(c.dx - 9, c.dy - 1, c.dx - 4, c.dy - 8, c.dx, c.dy - 3)
              ..cubicTo(c.dx + 4, c.dy - 8, c.dx + 9, c.dy - 1, c.dx, c.dy + 5);
            canvas.drawPath(heart, stroke);
        }
      }
    }
  }

  Future<Uint8List> legacyPixels(Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = ChatPalette.wallpaper,
    );
    paintLegacy(canvas, size);
    final image = await recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  testWidgets('karo ile döşenen desen eski doğrudan çizimle aynı görünür', (
    tester,
  ) async {
    const size = Size(400, 700);
    final key = GlobalKey();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: const ChatWallpaper(child: SizedBox.expand()),
        ),
      ),
    );

    late Uint8List actual;
    late Uint8List expected;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      actual = data!.buffer.asUint8List();
      expected = await legacyPixels(size);
    });

    expect(actual.length, expected.length);
    var maxDiff = 0;
    var differing = 0;
    for (var i = 0; i < actual.length; i++) {
      final d = (actual[i] - expected[i]).abs();
      if (d > maxDiff) maxDiff = d;
      if (d > 2) differing++;
    }
    // Glifler %6 opaklıkta; karo kenarlarındaki kenar yumuşatma en fazla
    // birkaç birimlik fark yaratabilir, desen kaymaz.
    expect(maxDiff, lessThanOrEqualTo(4), reason: 'farklı kanal: $differing');
  });
}
