// EKRAN ÖNİZLEMELERİ — yeniden tasarlanan ekranların PNG'sini üretir.
//
//   flutter test test/okey/okey_ui_preview_test.dart --update-goldens
//
// KARŞILAŞTIRMA YAPMAZ, YALNIZCA ÜRETİR (bkz. okey_table_preview_test.dart'ta
// aynı gerekçe): golden karşılaştırması yazı tipi/GPU farklarına duyarlıdır ve
// başka bir makinede kırmızı yanar. Gerçek taşma regresyonları
// okey_screens_overflow_test.dart'ta ölçülür.
@Tags(['preview'])
library;

import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/screens/okey_create_room_screen.dart';
import 'package:cizreapp/okey/screens/okey_match_result_screen.dart';
import 'package:cizreapp/okey/screens/okey_points_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OkeyRoomSeat _seat(int n, String name, {bool bot = false}) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: n,
  userId: bot ? null : 'u$n',
  isReady: true,
  isBot: bot,
  displayName: bot ? null : name,
);

Future<void> _shoot(
  WidgetTester tester,
  Widget screen,
  String file, {
  Size size = const Size(390, 760),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(debugShowCheckedModeBanner: false, home: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
}

void main() {
  testWidgets('oda kur önizleme', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _shoot(tester, const OkeyCreateRoomScreen(), 'preview_oda_kur.png');
  });

  testWidgets('puanlar önizleme', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _shoot(tester, const OkeyPointsScreen(), 'preview_puanlar.png');
  });

  testWidgets('maç sonucu önizleme', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _shoot(
      tester,
      OkeyMatchResultScreen(
        seats: [
          _seat(0, 'SM-S9..'),
          _seat(1, 'Oyuncu 1'),
          _seat(2, 'Bot', bot: true),
          _seat(3, 'ÇokUzunOyuncuAdıTaşmaTesti'),
        ],
        scores: const {0: -101, 1: 404, 2: 202, 3: 1616},
        mySeat: 0,
        handsPlayed: 5,
        onLeave: () {},
        onRematch: (_, _) {},
      ),
      'preview_mac_sonucu.png',
    );
  });
}
