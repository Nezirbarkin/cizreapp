import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/screens/okey_match_result_screen.dart';
import 'package:cizreapp/okey/screens/okey_create_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MAÇ SONUCU — kullanıcı isteği, 2026-09-05:
/// "oyun bittiğinde direkt puanla birlikte kazananı belirle."
///
/// Başlık eskiden yalnızca iki şey diyebiliyordu: "KAZANDIN!" ya da
/// "Maç bitti". İkincisi kaybedene sonucun YARISINI söylüyordu — kazananı
/// öğrenmek için aşağıdaki sıralamayı okuyup en düşük sayıyı kendisi bulmak
/// zorundaydı.
OkeyRoomSeat _seat(int no, String name) =>
    OkeyRoomSeat(roomId: 'r', seatNo: no, isReady: true, displayName: name);

Widget _screen({
  required Map<int, int> scores,
  int mySeat = 0,
  String teamMode = 'essiz',
  int handsPlayed = 2,
}) => MaterialApp(
  home: OkeyMatchResultScreen(
    seats: [
      _seat(0, 'Ben'),
      _seat(1, 'Ayşe'),
      _seat(2, 'Kadir'),
      _seat(3, 'Zeynep'),
    ],
    scores: scores,
    mySeat: mySeat,
    teamMode: teamMode,
    handsPlayed: handsPlayed,
    onLeave: () {},
  ),
);

void main() {
  group('Maç sonucu — kazanan ve puanı', () {
    testWidgets('KAYBEDENE de kazananın adı ve puanı söylenir', (tester) async {
      await tester.pumpWidget(
        _screen(scores: const {0: 240, 1: 118, 2: 305, 3: 402}),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Ayşe kazandı'), findsOneWidget);
      expect(
        find.textContaining('118 puan'),
        findsWidgets,
        reason: 'kazananın puanı başlıkla birlikte yazılmalı',
      );
      expect(find.text('Maç bitti'), findsNothing);
    });

    testWidgets('kazanan BENSEM kutlama korunur, puan yine yazılır', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screen(scores: const {0: 96, 1: 118, 2: 305, 3: 402}),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('KAZANDIN!'), findsOneWidget);
      expect(find.textContaining('Ben · 96 puan'), findsOneWidget);
    });

    testWidgets('beraberlikte iki ad birden yazılır', (tester) async {
      await tester.pumpWidget(
        _screen(scores: const {0: 305, 1: 118, 2: 118, 3: 402}),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Berabere'), findsOneWidget);
      expect(find.textContaining('Ayşe · Kadir'), findsOneWidget);
    });

    testWidgets('EŞLİ modda kazanan TAKIM ve toplam puanı yazılır', (
      tester,
    ) async {
      // Takım 1 = 0. + 3. koltuk (100 + 40), Takım 2 = 1. + 4. (200 + 90).
      await tester.pumpWidget(
        _screen(
          scores: const {0: 100, 1: 200, 2: 40, 3: 90},
          mySeat: 1,
          teamMode: 'esli',
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Takım 1 kazandı'), findsOneWidget);
      expect(find.textContaining('Takım 1 · 140 puan'), findsOneWidget);
    });

    testWidgets('el sayısı sonuçla aynı cümlede', (tester) async {
      await tester.pumpWidget(
        _screen(scores: const {0: 240, 1: 118, 2: 305, 3: 402}, handsPlayed: 2),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('2 el ·'), findsOneWidget);
    });
  });

  group('Masa kurulumu — el sayısı', () {
    test('2 EL seçeneği sunulur', () {
      // KULLANICI İSTEĞİ (2026-09-05): "oyunda 2 el de olsun."
      //
      // Kural zaten hazırdı — el sonundaki cezalar toplanır ve toplamı en
      // düşük olan kazanır (okey_internal_award_match), eşli modda iki eşin
      // toplamı yarışır. Eksik olan tek şey SEÇENEKTİ.
      expect(
        OkeyCreateRoomScreen.handOptions,
        containsAll(<int>[1, 2, 3]),
        reason: '2 el seçilemiyor',
      );
      expect(
        OkeyCreateRoomScreen.handOptions,
        everyElement(greaterThanOrEqualTo(1)),
      );
      // Sunucu 1..20 kabul ediyor; sunulan hiçbir seçenek bunun dışına
      // çıkmamalı (APP:invalid_total_hands).
      expect(
        OkeyCreateRoomScreen.handOptions,
        everyElement(lessThanOrEqualTo(20)),
      );
    });
  });
}
