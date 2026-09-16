import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PROFİL RESİMLERİ BÜYÜK — kullanıcı isteği, 2026-09-08: "profil resimleri
/// daha büyük göster, yeniden tasarla, taşma vs olmasın".
///
/// ## Ne vardı
///
/// Yatay plaka (üst şerit ve konsol) doğal boyunda büyüyor, şeride sığmayınca
/// bir [FittedBox] onu TOPTAN küçültüyordu. Yani avatarı büyütmenin bir yolu
/// yoktu: her büyütme aynı oranda geri küçültülüyordu. Tipik bir telefonda
/// karşıdaki oyuncunun fotoğrafı ~28 piksellik bir noktaydı.
///
/// ## Ne değişti
///
/// Plaka yüksekliğini DIŞARIDAN alıyor ([OkeyCornerPileWidget.plateHeight]),
/// avatar da o yükseklikten türüyor. Bu test iki şeyi birden kilitler:
/// avatar gerçekten büyük ÇİZİLİYOR ve plaka verilen kutuyu AŞMIYOR.
OkeyRoomSeat _seat() => const OkeyRoomSeat(
  roomId: 'r',
  seatNo: 1,
  isReady: true,
  userId: 'u1',
  displayName: 'Mehmet Yılmaz',
);

/// Plakanın içindeki avatar dairesinin çapı.
///
/// Avatar, resmi yuvarlağa kırpan tek [ClipOval]'dir; ölçüsü doğrudan
/// ekranda kapladığı yerdir — hesaplanmış bir sayı değil, ÇİZİLEN boy.
double _avatarDiameter(WidgetTester tester) {
  final ovals = find.byType(ClipOval);
  expect(ovals, findsOneWidget, reason: 'avatar çizilmedi — test anlamsız');
  return tester.getSize(ovals).height;
}

/// Plakayı masadaki gerçek kutusuna koyar.
///
/// [plateHeight] null verilirse ESKİ tasarım kurulur (doğal boy + toptan
/// küçültme) — testler yeniyi eskiyle aynı kutuda karşılaştırabilsin diye.
Widget _plate({
  required OkeySeatSide side,
  required double boxHeight,
  required double avatarSize,
  required double boxWidth,
  double? plateHeight,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: boxWidth,
        height: boxHeight,
        // Masadaki gerçek yerleşimin aynısı: plaka ortalanır ve sığmazsa
        // FittedBox onu küçültür (bkz. OkeyTableScaffold._TopStrip).
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: OkeyCornerPileWidget(
              seat: _seat(),
              seatNo: 1,
              tileCount: 14,
              score: 101,
              openPoints: 45,
              isCurrentTurn: true,
              size: 30,
              avatarSize: avatarSize,
              plateHeight: plateHeight,
              side: side,
              parts: OkeySeatParts.identity,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('Yatay oyuncu plakası — avatar şeridin boyunu doldurur', () {
    // Gerçek masa ölçüleri: yaygın yatay telefonlar ve bir tablet.
    for (final entry in const {
      'yatay telefon 731x411': Size(731, 411),
      'yaygın telefon 892x412': Size(892, 412),
      'küçük telefon 640x320': Size(640, 320),
      'tablet 1280x800': Size(1280, 800),
    }.entries) {
      testWidgets('${entry.key} — avatar plakayı DOLDURUR, taşmaz', (
        tester,
      ) async {
        final m = OkeyTableMetrics.from(BoxConstraints.tight(entry.value));

        for (final side in const [OkeySeatSide.top, OkeySeatSide.bottom]) {
          final top = side == OkeySeatSide.top;
          // Şeridin plakaya bıraktığı gerçek kutu: üst şeritte dolgu 3+1,
          // konsolda 2+2 (bkz. OkeyTableScaffold).
          final boxH = (top ? m.topStripHeight : m.consoleHeight) - 4;
          // Karşıdaki oyuncu üst şeridin %40'ını, ben konsolun %30'unu
          // alırım.
          final boxW = entry.value.width * (top ? 0.40 : 0.30);

          await tester.pumpWidget(
            _plate(
              side: side,
              boxHeight: boxH,
              boxWidth: boxW,
              avatarSize: m.avatarSize,
              plateHeight: m.seatPlateHeight(top: top),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);

          final d = _avatarDiameter(tester);

          // TASARIMIN ÖZÜ: avatar plakanın en büyük öğesi. Şeridin en az
          // %60'ını kaplamıyorsa ya plaka küçültülmüştür (eski hata) ya da
          // avatar yine yanına sıkışmış küçük bir rozettir.
          expect(
            d,
            greaterThan(boxH * 0.60),
            reason:
                '${entry.key} / $side: avatar $d px / şerit $boxH px — '
                'plaka yine toptan küçültülüyor olabilir',
          );
          // TAŞMA YOK: avatar şeridin dışına sarkarsa masaya taşar.
          expect(
            d,
            lessThanOrEqualTo(boxH),
            reason: '${entry.key} / $side: avatar şeritten taşıyor',
          );
        }
      });
    }

    testWidgets('yaygın telefonda avatar en az 34 piksel', (tester) async {
      // ESKİ tasarımda aynı şeritte çizilen çap ~26 pikseldi (plaka doğal
      // boyunda büyüyüp FittedBox ile geri küçültüldüğü için). Bu sayı,
      // "daha büyük göster" isteğinin ölçülebilir karşılığı.
      final m = OkeyTableMetrics.from(
        BoxConstraints.tight(const Size(892, 412)),
      );
      await tester.pumpWidget(
        _plate(
          side: OkeySeatSide.top,
          boxHeight: m.topStripHeight - 4,
          boxWidth: 892 * 0.40,
          avatarSize: m.avatarSize,
          plateHeight: m.seatPlateHeight(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_avatarDiameter(tester), greaterThanOrEqualTo(34.0));
    });

    testWidgets('uzun ad plakayı taşırmaz, kırpılır', (tester) async {
      // Dar konsolda 40 karakterlik bir ad: Flexible sütun + ellipsis
      // olmasaydı "RenderFlex overflowed" verirdi.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 150,
                height: 44,
                child: OkeyCornerPileWidget(
                  seat: const OkeyRoomSeat(
                    roomId: 'r',
                    seatNo: 2,
                    isReady: true,
                    userId: 'u2',
                    displayName: 'Abdurrahman Muhammed Şerafettin Oğuzhan',
                  ),
                  seatNo: 2,
                  tileCount: 21,
                  score: 999,
                  openPoints: 101,
                  isCurrentTurn: false,
                  size: 30,
                  avatarSize: 48,
                  plateHeight: 44,
                  side: OkeySeatSide.bottom,
                  parts: OkeySeatParts.identity,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(OkeyCornerPileWidget), findsOneWidget);
      expect(
        tester.getSize(find.byType(OkeyCornerPileWidget)).width,
        lessThanOrEqualTo(150.0),
      );
    });
  });

  group('Dikey levha — avatar kenar sütununu doldurur', () {
    testWidgets('kare avatar sütun genişliğine yakın çizilir', (tester) async {
      final m = OkeyTableMetrics.from(
        BoxConstraints.tight(const Size(892, 412)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: m.sidePodWidth,
                // Kenar sütununda levhaya kalan tipik boy: sütun eksi iki
                // ıskarta kutusu.
                height: 130,
                child: OkeyCornerPileWidget(
                  seat: _seat(),
                  seatNo: 1,
                  tileCount: 14,
                  isCurrentTurn: false,
                  size: m.discardTileWidth,
                  avatarSize: m.avatarSize,
                  side: OkeySeatSide.left,
                  parts: OkeySeatParts.identity,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Dikey levhada avatar KARE bir ClipRRect'tir; boyu levhanın boyunun
      // 0,44'ü ile sınırlı (bkz. _verticalPlate).
      final avatar = find.descendant(
        of: find.byType(OkeyCornerPileWidget),
        matching: find.byType(ClipRRect),
      );
      expect(avatar, findsOneWidget);
      final size = tester.getSize(avatar);
      expect(
        size.height,
        greaterThan(43.0),
        reason: 'dikey levhada avatar hâlâ eski (0,34) sınırında',
      );
      expect(size.height, lessThanOrEqualTo(130 * 0.44 + 0.5));
    });
  });
}
