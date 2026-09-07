import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// OYUNCU LEVHASINDA SAHTE İKRAM YOK — kullanıcı isteği, 2026-09-05:
/// "profillerde bulunan karpuz ikonunu ve diğer profillerde bulunanı kaldır".
///
/// ## Ne vardı
///
/// Her levhanın dibinde koltuk numarasından türeyen SABİT, renkli bir yuvarlak
/// çip duruyordu: içecek, top, pizza, dondurma. Gerçek bir hediye değildi —
/// hediye özelliği gelene kadar yerini tutan dekoratif bir yer tutucuydu.
/// Kimse göndermediği hâlde her oyuncunun altında bir "ikram" görünüyor,
/// yeşil/koyu-yeşil olanı da karpuz dilimi gibi okunuyordu.
///
/// Hediyeler artık gerçek ve gönderilen hediye alıcının levhasının YANINDA
/// asılı kalıyor (bkz. OkeySeatGiftBadge). Bu test yer tutucunun geri
/// dönmediğini garanti eder.
OkeyRoomSeat _seat(int no) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: no,
  isReady: true,
  userId: 'u$no',
  displayName: 'Oyuncu $no',
);

/// Yer tutucunun kullandığı dört ikon.
const _placeholderIcons = <IconData>[
  Icons.local_drink,
  Icons.sports_volleyball,
  Icons.local_pizza,
  Icons.icecream,
];

void main() {
  group('Koltuk levhası — dekoratif hediye çipi kaldırıldı', () {
    for (final side in OkeySeatSide.values) {
      testWidgets('$side kenarında sahte ikram ikonu yok', (tester) async {
        // DÖRT KOLTUĞUN HEPSİ: çip koltuk numarasına göre farklı bir ikon
        // seçiyordu, yani yalnız birini kontrol etmek yetmez.
        for (var seatNo = 0; seatNo < 4; seatNo++) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: OkeyCornerPileWidget(
                      seat: _seat(seatNo),
                      seatNo: seatNo,
                      tileCount: 14,
                      isCurrentTurn: false,
                      size: 30,
                      avatarSize: 30,
                      side: side,
                      parts: OkeySeatParts.identity,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          // TEST BOŞA DÖNMESİN: levha gerçekten çizildi mi? Widget hiç
          // kurulmasaydı "ikon yok" iddiası kendiliğinden doğru çıkardı.
          expect(
            find.text('Oyuncu $seatNo'),
            findsOneWidget,
            reason: 'levha çizilmedi — test anlamsız',
          );
          for (final icon in _placeholderIcons) {
            expect(
              find.byIcon(icon),
              findsNothing,
              reason:
                  '$seatNo. koltuk / $side: dekoratif ikram ikonu ($icon) '
                  'geri geldi',
            );
          }
        }
      });
    }
  });
}
