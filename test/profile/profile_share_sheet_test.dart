import 'dart:io';
import 'dart:ui' as ui;

import 'package:cizreapp/features/profile/widgets/profile_share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../helpers/test_fonts.dart';

/// Profil paylaşım sayfası (2026-10-23): QR kod profil linkini taşır,
/// "Linki kopyala" panoya yazar. CIZRE_PREVIEW_DIR verilirse görünümün
/// PNG'si oraya yazılır (görsel kontrol için).

void main() {
  setUpAll(loadTestFonts);

  testWidgets('QR linki taşır, kopyala panoya yazar', (tester) async {
    tester.view.physicalSize = const Size(400, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            RepaintBoundary(key: boundaryKey, child: child),
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF17232D),
            body: Center(
              child: ElevatedButton(
                onPressed: () => showProfileShareSheet(
                  context,
                  username: 'bilginbarkın',
                  fullName: 'Bilgin Barkın',
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // QR ve altındaki link aynı adresi taşır (QrImageView verisini dışa açmıyor).
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('cizreapp.com/u/@bilginbarkın'), findsOneWidget);
    expect(find.text('Bilgin Barkın'), findsOneWidget);
    expect(find.text('Linki kopyala'), findsOneWidget);
    expect(find.text('Paylaş'), findsOneWidget);
    expect(find.text("QR'ı paylaş"), findsOneWidget);

    final dir = Platform.environment['CIZRE_PREVIEW_DIR'];
    if (dir != null) {
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$dir/profile_share_sheet.png')
            .writeAsBytes(data!.buffer.asUint8List());
      });
    }

    await tester.tap(find.text('Linki kopyala'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(clipboard, 'https://cizreapp.com/u/@bilginbark%C4%B1n');
    expect(find.text('Kopyalandı'), findsOneWidget);
  });
}
