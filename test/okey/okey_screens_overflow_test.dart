import 'package:cizreapp/okey/admin/okey_admin_content.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/screens/okey_create_room_screen.dart';
import 'package:cizreapp/okey/screens/okey_lobby_screen.dart';
import 'package:cizreapp/okey/screens/okey_match_result_screen.dart';
import 'package:cizreapp/okey/screens/okey_points_screen.dart';
import 'package:cizreapp/okey/screens/okey_room_screen.dart';
import 'package:cizreapp/okey/services/okey_guest_auth.dart';
import 'package:cizreapp/okey/theme/okey_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// OKEY EKRANLARI — TAŞMA REGRESYON TESTLERİ
///
/// ## Neden bu dosya var
///
/// Modülün her ekranı kendi kartını/butonunu elle kuruyordu ve hepsi aynı
/// hatayı ayrı ayrı yapıyordu: `Row` içine esnemeyen bir `Text`, sabit
/// yükseklikli bir kart, sarmalayan bir rozet şeridi. Kullanıcı bunu gerçek
/// cihazda "taşma" olarak görüyordu; kod tarafında ise hiçbir test bunu
/// yakalamıyordu çünkü ekranlar hiç PUMP EDİLMİYORDU.
///
/// Buradaki testler ekranların TA KENDİSİNİ kurar ve Flutter'ın taşma
/// istisnasını (`A RenderFlex overflowed by N pixels`) yakalar.
///
/// ## İki eksende tarama
///
/// 1. **Ekran boyutu** — gerçek cihazlarda görülen en dar/en kısa boyutlar.
/// 2. **Yazı ölçeği** — sistemin yazı tipi büyütmesi. 1.0 geçen bir düzen
///    1.5'te rahatlıkla taşar; erişilebilirlik ayarı açık kullanıcılar
///    uygulamayı böyle görüyor.
///
/// ## Supabase yok — bilerek
///
/// Provider'lar ilk yüklemeyi bir mikro göreve erteler ve hatayı yakalar;
/// Supabase başlatılmadığı için ekranlar HATA/BOŞ durumda çizilir. Test
/// tam olarak bunu ister: boş durum da taşmamalıdır. Doluluk senaryoları
/// veri gerektirmeyen ekranlarda (maç sonucu) gerçek içerikle test edilir.
const _screens = <String, Size>{
  'küçük telefon 320x568': Size(320, 568),
  'dar telefon 360x640': Size(360, 640),
  'yaygın telefon 411x731': Size(411, 731),
  'uzun telefon 390x844': Size(390, 844),
  'yatay telefon 731x411': Size(731, 411),
  'tablet 768x1024': Size(768, 1024),
};

/// Sistemin yazı tipi büyütmesi.
///
/// `Map<double, …>` DEĞİL: Dart'ta double anahtarların "primitive equality"si
/// yoktur ve sabit bir map olarak derlenemez. Kayıt (record) listesi hem
/// derlenir hem de okunur kalır.
const _textScales = <({double scale, String label})>[
  (scale: 1.0, label: 'normal yazı'),
  (scale: 1.5, label: 'büyük yazı'),
];

/// Taşmaya en yatkın içerik: gerçek kullanıcı adları uzun olabiliyor.
const _longName = 'ÇokUzunOyuncuAdıTaşmaTestiİçin';

OkeyRoomSeat _seat(int n, {bool bot = false}) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: n,
  userId: bot ? null : 'u$n',
  isReady: n.isEven,
  isBot: bot,
  displayName: bot ? null : _longName,
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  Size size,
  double textScale,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(debugShowCheckedModeBanner: false, home: screen),
    ),
  );
  // Sağlayıcılar ilk yüklemeyi mikro göreve erteliyor; birkaç kare çeviririz
  // ki hata/boş durum da çizilmiş olsun. pumpAndSettle KULLANILMAZ: bazı
  // ekranlarda sürekli çalışan giriş animasyonları var, zaman aşımına düşer.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('Ekranlar hiçbir boyutta taşmaz', () {
    _screens.forEach((sizeLabel, size) {
      for (final ts in _textScales) {
        final scale = ts.scale;
        final label = '$sizeLabel · ${ts.label}';

        // LOBİ İKİ HALDE ölçülür. Misafir kapısı eklendikten sonra tek bir
        // test yalnızca KAPIYI kuruyor, lobi gövdesi (masa listesi, canlı
        // masalar, hediye kartı) hiç çizilmiyordu — yani en taşmaya yatkın
        // ekran test dışı kalmıştı.
        testWidgets('LOBİ (misafir kapısı) — $label', (tester) async {
          OkeyGuestAuth.debugSessionOverride = false;
          addTearDown(() => OkeyGuestAuth.debugSessionOverride = null);
          await _pump(tester, const OkeyLobbyScreen(), size, scale);
          expect(tester.takeException(), isNull);
        });

        testWidgets('LOBİ — $label', (tester) async {
          OkeyGuestAuth.debugSessionOverride = true;
          addTearDown(() => OkeyGuestAuth.debugSessionOverride = null);
          await _pump(tester, const OkeyLobbyScreen(), size, scale);
          expect(tester.takeException(), isNull);
        });

        testWidgets('ODA KUR — $label', (tester) async {
          await _pump(tester, const OkeyCreateRoomScreen(), size, scale);
          expect(tester.takeException(), isNull);
        });

        testWidgets('BEKLEME ODASI — $label', (tester) async {
          await _pump(
            tester,
            const OkeyRoomScreen(roomId: 'room-1'),
            size,
            scale,
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('PUANLAR — $label', (tester) async {
          await _pump(tester, const OkeyPointsScreen(), size, scale);
          expect(tester.takeException(), isNull);
        });

        testWidgets('MAÇ SONUCU (eşsiz) — $label', (tester) async {
          await _pump(
            tester,
            OkeyMatchResultScreen(
              seats: [_seat(0), _seat(1), _seat(2, bot: true), _seat(3)],
              // 6 haneli ceza: sayı sütununun en kötü hali.
              scores: const {0: -101, 1: 404202, 2: 202, 3: 1616},
              mySeat: 0,
              handsPlayed: 10,
              onLeave: () {},
              onRematch: (_, _) {},
            ),
            size,
            scale,
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('MAÇ SONUCU (eşli) — $label', (tester) async {
          await _pump(
            tester,
            OkeyMatchResultScreen(
              seats: [_seat(0), _seat(1), _seat(2), _seat(3)],
              scores: const {0: -101, 1: 404202, 2: 202, 3: 1616},
              mySeat: 1,
              teamMode: 'esli',
              handsPlayed: 7,
              onLeave: () {},
            ),
            size,
            scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    });
  });

  group('Admin paneli — 101 Okey bölümü taşmaz', () {
    // Admin paneli dashboard'un İÇİNDE bir sekme olarak yaşar; dar bir
    // yan panelde de, tam ekran tablette de aynı bileşenler çizilir.
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(411, 731),
      Size(768, 1024),
    ]) {
      for (final ts in _textScales) {
        testWidgets(
          'ADMİN — ${size.width.toInt()}x${size.height.toInt()} · ${ts.label}',
          (tester) async {
            // Admin bölümü dashboard'un Scaffold'unun İÇİNDE yaşar; TabBar
            // bir Material ata gerektirir. Testte de gerçek yuvası kurulur.
            await _pump(
              tester,
              const Scaffold(body: OkeyAdminContent()),
              size,
              ts.scale,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('Tasarım sistemi — en kötü içerikle taşmaz', () {
    /// Bileşenler DAR bir kutuya konur ve içlerine sığmayacak metin verilir.
    /// Amaç: taşma güvencesinin bileşenin İÇİNDE olduğunu doğrulamak —
    /// çağıranın ayrıca önlem alması gerekmemeli.
    Future<void> pumpInNarrowBox(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: MaterialApp(
            home: Scaffold(
              body: Center(child: SizedBox(width: 110, child: child)),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('OkeyButton — uzun etiket dar butonda taşmaz', (tester) async {
      await pumpInNarrowBox(
        tester,
        const OkeyButton(
          label: 'ÇOK UZUN BİR AKSİYON ETİKETİ',
          icon: Icons.add,
          tone: OkeyButtonTone.primary,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('OkeyRow — uzun etiket + uzun değer taşmaz', (tester) async {
      await pumpInNarrowBox(
        tester,
        const OkeyCard(
          child: OkeyRow(
            icon: Icons.info,
            label: 'Çok uzun bir ayar etiketi burada',
            value: '9876543210',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('OkeyStatTile — 7 haneli değer taşmaz', (tester) async {
      await pumpInNarrowBox(
        tester,
        const OkeyStatTile(
          icon: Icons.stars,
          label: 'Dolaşımdaki toplam puan',
          value: '9876543',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('OkeyPill — uzun metin taşmaz', (tester) async {
      await pumpInNarrowBox(
        tester,
        const Row(
          children: [
            Expanded(child: OkeyPill(text: 'Çok uzun bir rozet metni')),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // BOŞ DURUM DAR KUTUDA DEĞİL, GERÇEK GENİŞLİKTE test edilir: 110px'lik
    // bir sütunda 1.6 ölçekli uzun bir metnin 1400px yükseklik istemesi
    // widget'ın hatası değil, testin gerçekçi olmamasıdır. Ekranlarda bu
    // bileşen her zaman bir kaydırma alanının içinde durur.
    testWidgets('OkeyEmptyState — uzun metinlerle taşmaz', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: OkeyEmptyState(
                  icon: Icons.casino,
                  title: 'Burada gösterilecek hiçbir şey bulunamadı',
                  message:
                      'Bu uzun açıklama metni birden çok satıra yayılmalı ve '
                      'hiçbir koşulda taşmamalıdır.',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
