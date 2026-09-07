import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/theme/okey_ui.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// BOTLAR MASADA GERÇEK OYUNCU GİBİ GÖRÜNÜR (2026-09, kullanıcı isteği)
///
/// Bot olduğunu ele veren HER işaret ayrı ayrı kapatıldı; bu dosya onların
/// geri gelmesini engeller. Geçmişte dört ayrı yerde ("Bot N" adı, robot
/// ikonu, avatarın hiç yüklenmemesi, soluk halka rengi) aynı sızıntı vardı
/// ve biri düzeltilince diğerleri unutuluyordu.

OkeyRoomSeat _bot(int seatNo, {String? name, String? avatar}) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: seatNo,
  isReady: true,
  isBot: true,
  displayName: name,
  avatarUrl: avatar,
);

OkeyRoomSeat _human(int seatNo, {String? name}) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: seatNo,
  userId: 'u$seatNo',
  isReady: true,
  displayName: name,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 260, height: 220, child: child)),
      ),
    ),
  );
}

void main() {
  group('OkeyRoomSeat.displayLabel', () {
    test('admin profili olan bot KENDİ adıyla görünür', () {
      expect(_bot(1, name: 'Aleyna Ü.').displayLabel, 'Aleyna Ü.');
    });

    test('profili OLMAYAN bot "Bot" demeyen bir yedek ad alır', () {
      for (var seat = 0; seat < 4; seat++) {
        final label = _bot(seat).displayLabel;
        expect(
          label.toLowerCase(),
          isNot(contains('bot')),
          reason: '$seat. koltuk bot olduğunu ele veriyor: $label',
        );
        expect(label, isNotEmpty);
      }
    });

    test('yedek ad DETERMİNİSTİK — aynı koltuk her yerde aynı isim', () {
      // Rastgele üretilseydi aynı oyuncu masada, bekleme odasında ve sonuç
      // ekranında üç farklı isimle görünürdü.
      expect(_bot(2).displayLabel, _bot(2).displayLabel);
      expect(_bot(0).displayLabel, isNot(_bot(1).displayLabel));
    });

    test('adı olmayan GERÇEK oyuncuya uydurma kimlik verilmez', () {
      expect(_human(1).displayLabel, 'Oyuncu');
    });

    test('boş ad boşluktan ibaretse yedek ada düşer', () {
      expect(_bot(0, name: '   ').displayLabel.trim(), isNotEmpty);
    });
  });

  group('Masa kartı botu ele vermez', () {
    testWidgets('bot kartında "Bot" yazmaz', (tester) async {
      await _pump(
        tester,
        OkeyCornerPileWidget(
          seat: _bot(1),
          seatNo: 1,
          tileCount: 14,
          isCurrentTurn: false,
          size: 30,
          side: OkeySeatSide.top,
          parts: OkeySeatParts.identity,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Bot'), findsNothing);
    });

    testWidgets('bot kartında ROBOT ikonu yoktur, kişi ikonu vardır', (
      tester,
    ) async {
      await _pump(
        tester,
        OkeyCornerPileWidget(
          seat: _bot(1),
          seatNo: 1,
          tileCount: 14,
          isCurrentTurn: false,
          size: 30,
          side: OkeySeatSide.top,
          parts: OkeySeatParts.identity,
        ),
      );
      expect(find.byIcon(Icons.smart_toy), findsNothing);
      expect(find.byIcon(Icons.person), findsWidgets);
    });

    testWidgets('botun fotoğrafı ÇİZİLİR (eskiden hiç yüklenmiyordu)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await _pump(
          tester,
          OkeyCornerPileWidget(
            seat: _bot(1, name: 'Aleyna Ü.', avatar: 'https://x.invalid/a.png'),
            seatNo: 1,
            tileCount: 14,
            isCurrentTurn: false,
            size: 30,
            side: OkeySeatSide.top,
            parts: OkeySeatParts.identity,
          ),
        );
      });
      // Ağ görseli test ortamında yüklenemez; önemli olan widget'ın AĞACA
      // KONMUŞ olması — koşul `!isBot` iken hiç konmuyordu.
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('bot ile insan kartı AYNI görünür (yalnız ad farkı)', (
      tester,
    ) async {
      Future<Set<IconData>> iconsOf(OkeyRoomSeat seat) async {
        await _pump(
          tester,
          OkeyCornerPileWidget(
            seat: seat,
            seatNo: seat.seatNo,
            tileCount: 14,
            isCurrentTurn: false,
            size: 30,
            side: OkeySeatSide.top,
            parts: OkeySeatParts.identity,
          ),
        );
        return tester
            .widgetList<Icon>(find.byType(Icon))
            .map((i) => i.icon!)
            .toSet();
      }

      final botIcons = await iconsOf(_bot(1, name: 'Aleyna Ü.'));
      final humanIcons = await iconsOf(_human(1, name: 'Aleyna Ü.'));
      expect(botIcons, humanIcons);
    });
  });

  group('OkeyAvatar', () {
    testWidgets('fotoğrafsız avatar her zaman KİŞİ ikonu gösterir', (
      tester,
    ) async {
      await _pump(tester, const OkeyAvatar(size: 40));
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy), findsNothing);
    });
  });
}
