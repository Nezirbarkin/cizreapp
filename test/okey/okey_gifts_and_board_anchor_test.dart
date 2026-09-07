import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/services/okey_gift_service.dart';
import 'package:cizreapp/okey/widgets/okey_board_widget.dart';
import 'package:cizreapp/okey/widgets/okey_gift_badge.dart';
import 'package:cizreapp/okey/widgets/okey_gift_sheet.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-09-05 kullanıcı istekleri — masadaki per hizası ve hediye akışı.
///
/// Her ikisi de yalnızca EKRANDA görülebilen davranışlar: birincisi bir
/// hizalama, ikincisi bir akış. İkisi de derleyiciden sessizce geçer, bu
/// yüzden burada gerçek widget ağacıyla ölçülüyor.
OkeyTableMeld _run(int id, OkeyColor color, int base) => OkeyTableMeld(
  id: id,
  matchId: 'm',
  laidBySeat: 0,
  meldType: 'run',
  tiles: [
    OkeyTile.numbered(color, base),
    OkeyTile.numbered(color, base + 1),
    OkeyTile.numbered(color, base + 2),
  ],
);

OkeyRoomSeat _seat(int no, {String? name, bool bot = false}) => OkeyRoomSeat(
  roomId: 'r',
  seatNo: no,
  isReady: true,
  isBot: bot,
  userId: bot ? null : 'u$no',
  displayName: name,
  botProfileId: bot ? 'b$no' : null,
);

void main() {
  group('Istakada SON TAŞ cılız kalmaz', () {
    // KULLANICI İSTEĞİ (2026-09-05): "takozda taş dizilirken sondaki taş
    // boyut olarak zayıf oluyor."
    //
    // ## Hatanın kökü
    //
    // Perler arası ayrım, öbeğin SON TAŞININ GENİŞLİĞİNDEN ~5px kısılarak
    // açılıyordu (bkz. OkeyRackBarWidget'taki `groupGap`). Ama bir öbek —
    // tanımı gereği — ya bir BOŞ SLOTLA ya da SATIR SONUYLA biter
    // (contiguousGroups yalnızca bunlarda böler). Yani kısmanın ayıracağı
    // bir komşu HİÇBİR ZAMAN yoktu: pay boşa gidiyor, geriye sadece
    // diğerlerinden dar duran bir son taş kalıyordu.
    OkeyTile t(int n) => OkeyTile.numbered(OkeyColor.red, n);

    test('ardında BOŞ slot olan öbeğin son taşı kısılmaz', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[0] = t(1);
      slots[1] = t(2);
      slots[2] = t(3);
      // slots[3] boş — ayrım ZATEN tam bir slot genişliğinde var.
      expect(OkeyRackLayout.groupEndSlots(slots), isEmpty);
    });

    test('satırın sonunda biten öbeğin son taşı kısılmaz', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      for (var i = 13; i < OkeyRackLayout.slotsPerRow; i++) {
        slots[i] = t(i - 12);
      }
      // 15. slot satırın son slotu: sağında ayrılacak komşu yok.
      expect(OkeyRackLayout.groupEndSlots(slots), isEmpty);
    });

    test('tek taş "per" sayılmaz', () {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[0] = t(1);
      slots[1] = t(5);
      slots[2] = t(9);
      expect(OkeyRackLayout.groupEndSlots(slots), isEmpty);
    });

    test('SERİ DİZ ile dizilmiş GERÇEK bir elde hiçbir taş kısılmaz', () {
      // Asıl güvence bu: dizme motorunun ürettiği yerleşimde kısma
      // uygulanacak tek bir slot bile kalmamalı.
      final okey = OkeyTile.numbered(OkeyColor.black, 7);
      final hand = <OkeyTile>[
        for (var n = 1; n <= 5; n++) OkeyTile.numbered(OkeyColor.red, n),
        for (final c in [OkeyColor.red, OkeyColor.blue, OkeyColor.yellow])
          OkeyTile.numbered(c, 9),
        for (var n = 3; n <= 6; n++) OkeyTile.numbered(OkeyColor.blue, n),
        OkeyTile.numbered(OkeyColor.yellow, 12),
        OkeyTile.numbered(OkeyColor.black, 2),
      ];

      final slots = OkeyRackLayout.buildSorted(hand, okey, byPairs: false);
      expect(OkeyRackLayout.groupEndSlots(slots), isEmpty);
    });

    testWidgets('dizilmiş ıstakada TÜM taşlar aynı genişlikte', (tester) async {
      final okey = OkeyTile.numbered(OkeyColor.black, 7);
      final hand = <OkeyTile>[
        for (var n = 1; n <= 5; n++) OkeyTile.numbered(OkeyColor.red, n),
        for (var n = 3; n <= 6; n++) OkeyTile.numbered(OkeyColor.blue, n),
      ];
      final slots = OkeyRackLayout.buildSorted(hand, okey, byPairs: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 90,
              child: OkeyRackBarWidget(
                slots: slots,
                selectedIndices: const {},
                groupEndSlots: OkeyRackLayout.groupEndSlots(slots),
                onTap: (_) {},
                onMove: (_, _) {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final tiles = find.byType(OkeyTileWidget);
      final count = tester.widgetList(tiles).length;
      expect(count, hand.length);

      final widths = [
        for (var i = 0; i < count; i++) tester.getRect(tiles.at(i)).width,
      ];
      for (var i = 0; i < widths.length; i++) {
        expect(
          widths[i],
          closeTo(widths.first, 0.6),
          reason:
              '$i. taş diğerlerinden farklı genişlikte (${widths[i]} vs '
              '${widths.first}) — "sondaki taş cılız" hatası geri geldi',
        );
      }
    });
  });

  group('Açılan perler SOL ÜST köşeden başlar', () {
    testWidgets('tek per masanın ortasında asılı kalmaz', (tester) async {
      // KULLANICI İSTEĞİ (2026-09-05): "masada açılan perler sol üst
      // köşeden alt alta dizilerek başlasın."
      //
      // Eski davranış Center'dı: masada tek bir per varken o per keçenin tam
      // ortasında duruyor, ikinci per gelince İKİSİ BİRDEN yana kayıyordu.
      // Yani daha önce bakılan bir per, kendisi hiç değişmediği halde yer
      // değiştiriyordu.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: OkeyBoardWidget(melds: [_run(1, OkeyColor.red, 2)]),
            ),
          ),
        ),
      );

      final board = tester.getRect(find.byType(OkeyBoardWidget));
      final tiles = find.byType(OkeyTileWidget);
      expect(tiles, findsNWidgets(3));

      final first = tester.getRect(tiles.first);
      // Sol üst köşeye yaslı: aradaki fark yalnızca perin oturma zemininin
      // iç payı kadardır (birkaç piksel).
      expect(
        first.left - board.left,
        lessThan(12),
        reason: 'per sola yaslanmadı',
      );
      expect(
        first.top - board.top,
        lessThan(12),
        reason: 'per üste yaslanmadı',
      );
    });

    testWidgets('ikinci per birincinin ALTINA gelir, onu oynatmaz', (
      tester,
    ) async {
      // KULLANICI İSTEĞİ (2026-09-05): "açılan perler alt alta dizilsin."
      //
      // Sarmalı (soldan sağa) akışın asıl bedeli buydu: yeni bir per masaya
      // konduğunda ondan SONRAKİ perlerin hepsi kayıyordu. Sütun aşağı
      // büyüdüğü için yeni per sıranın sonuna eklenir, önündekiler durur.
      Future<List<Rect>> tileRects(List<OkeyTableMeld> melds) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: OkeyBoardWidget(melds: melds),
              ),
            ),
          ),
        );
        final tiles = find.byType(OkeyTileWidget);
        return [
          for (var i = 0; i < tester.widgetList(tiles).length; i++)
            tester.getRect(tiles.at(i)),
        ];
      }

      final alone = await tileRects([_run(1, OkeyColor.red, 2)]);
      final withSecond = await tileRects([
        _run(1, OkeyColor.red, 2),
        _run(2, OkeyColor.blue, 6),
      ]);

      // İlk perin ilk taşı YERİNDEN OYNAMAZ.
      expect(withSecond.first.left, closeTo(alone.first.left, 0.5));
      expect(withSecond.first.top, closeTo(alone.first.top, 0.5));

      // İkinci per ALTTA ve aynı hizada başlar.
      final secondMeldFirstTile = withSecond[3];
      expect(
        secondMeldFirstTile.top,
        greaterThan(withSecond.first.bottom - 1),
        reason: 'ikinci per alta inmedi',
      );
      expect(
        secondMeldFirstTile.left,
        closeTo(withSecond.first.left, 1.0),
        reason: 'sütundaki perler aynı hizada başlamalı',
      );
    });
  });

  group('Hediye gönderme sayfası', () {
    List<OkeyGift> manyGifts(int n) => [
      for (var i = 0; i < n; i++)
        OkeyGift(
          id: 'g$i',
          code: 'g$i',
          name: 'Hediye $i',
          icon: '🎁',
          price: 25 * (i + 1),
          anim: const ['bounce', 'shake', 'beat', 'spin', 'float'][i % 5],
        ),
    ];

    testWidgets('YATAY ekranda taşmaz — hediye sayısı ne olursa olsun', (
      tester,
    ) async {
      // GERÇEK HATA (2026-09-05): "BOTTOM OVERFLOWED BY 94 PIXELS".
      //
      // Okey masası yatay oynanır; o ekranda sayfaya düşen yükseklik
      // ~360px'dir. Sayfa sabit yükseklikli bir yığındı ve hediye sayısını
      // ADMİN belirlediği için içerik yüksekliği önceden bilinemez —
      // dolayısıyla "biraz kısaltmak" bir çözüm değil, ertelemeydi.
      for (final size in const [Size(800, 360), Size(640, 320)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: OkeyGiftSheet(
                  seats: [
                    _seat(0, name: 'Ben'),
                    _seat(1, name: 'Ayşe'),
                    _seat(2, name: 'Kadir'),
                    _seat(3, name: 'Zeynep'),
                  ],
                  mySeatNo: 0,
                  loadCatalog: () async => manyGifts(16),
                  onSend: (_, _) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${size.width.toInt()}x${size.height.toInt()} ekranda taştı',
        );
      }
    });

    testWidgets('kendi koltuğum listede yok, diğerleri var', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OkeyGiftSheet(
              seats: [
                _seat(0, name: 'Ben'),
                _seat(1, name: 'Ayşe'),
                // Bot koltuğu da hediye alabilir: listeden çıkarılsaydı
                // "kime gönderemiyorum" sorusunun cevabı doğrudan "hangi
                // koltuk bot" olurdu.
                _seat(2, name: 'Kadir', bot: true),
              ],
              mySeatNo: 0,
              loadCatalog: () async => const [
                OkeyGift(
                  id: 'g1',
                  code: 'cay',
                  name: 'Çay',
                  icon: '🍵',
                  price: 50,
                ),
              ],
              onSend: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ben'), findsNothing);
      expect(find.text('Ayşe'), findsOneWidget);
      expect(find.text('Kadir'), findsOneWidget);
      expect(find.text('Çay'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('hediyeye dokunmak SEÇİLİ koltuğa gönderir', (tester) async {
      int? sentSeat;
      String? sentCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OkeyGiftSheet(
              seats: [
                _seat(0, name: 'Ben'),
                _seat(3, name: 'Zeynep'),
              ],
              mySeatNo: 0,
              loadCatalog: () async => const [
                OkeyGift(
                  id: 'g2',
                  code: 'kahve',
                  name: 'Kahve',
                  icon: '☕',
                  price: 100,
                ),
              ],
              onSend: (seat, code) async {
                sentSeat = seat;
                sentCode = code;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tek aday varsa seçim sorusu sorulmaz: hediyeye dokunmak hem seçim
      // hem gönderimdir (masanın ortasında iki adımlık bir akış işlemez).
      await tester.tap(find.text('Kahve'));
      await tester.pumpAndSettle();

      expect(sentSeat, 3);
      expect(sentCode, 'kahve');
    });

    testWidgets('çip yetmezse masaya anlaşılır bir cümle döner', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OkeyGiftSheet(
              seats: [
                _seat(0, name: 'Ben'),
                _seat(1, name: 'Ayşe'),
              ],
              mySeatNo: 0,
              loadCatalog: () async => const [
                OkeyGift(
                  id: 'g3',
                  code: 'kalp',
                  name: 'Kalp',
                  icon: '❤️',
                  price: 500,
                ),
              ],
              // Sunucunun ham metni: "APP:insufficient_points | mevcut: 40..."
              onSend: (_, _) async =>
                  throw Exception('APP:insufficient_points | mevcut: 40'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kalp'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Çipin yetmiyor'),
        findsOneWidget,
        reason: 'ham PostgrestException metni masada gösterilmemeli',
      );
    });
  });

  group('Hediye rozeti — profilin yanında ve SABİT', () {
    OkeyGiftEvent event(int id, String icon, {int seat = 2, String? from}) =>
        OkeyGiftEvent(
          id: id,
          senderName: from ?? 'Ayşe',
          recipientSeat: seat,
          recipientName: 'Kadir',
          giftName: 'Hediye',
          giftIcon: icon,
          giftAnim: 'bounce',
          price: 100,
        );

    testWidgets('rozet YALNIZCA alıcının koltuğunda belirir ve KALIR', (
      tester,
    ) async {
      // KULLANICI İSTEKLERİ (2026-09-05): "iconlar profillerin yanında
      // belirsin" + "atılan hediyeler sabitlensin".
      //
      // Rozet önce üç saniyede siliniyordu; masaya o an bakmayan herkes için
      // hediye hiç olmamış sayılıyordu.
      final gifts = ValueNotifier<Map<int, List<OkeyGiftEvent>>>(const {});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                OkeySeatGiftBadge(seatNo: 1, gifts: gifts),
                OkeySeatGiftBadge(seatNo: 2, gifts: gifts),
              ],
            ),
          ),
        ),
      );

      expect(find.text('☕'), findsNothing);

      gifts.value = {
        2: [event(7, '☕')],
      };
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 2 numaralı koltukta bir tane — 1 numaralıda hiç.
      expect(find.text('☕'), findsOneWidget);
      // Taze: gönderenin adı da yazılır.
      expect(find.text('Ayşe'), findsOneWidget);

      // TAZELİK GEÇER ama HEDİYE KALIR.
      await tester.pump(OkeySeatGiftBadge.freshFor);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text('☕'),
        findsOneWidget,
        reason: 'hediye kayboldu — sabit kalmalıydı',
      );
      expect(
        find.text('Ayşe'),
        findsNothing,
        reason: 'gönderen adı tazeyken bir haber, sonra yalnızca yer kaplar',
      );

      gifts.dispose();
    });

    testWidgets('yeni hediye başa geçer, eskiler asılı kalır', (tester) async {
      final gifts = ValueNotifier<Map<int, List<OkeyGiftEvent>>>({
        2: [event(1, '☕')],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OkeySeatGiftBadge(seatNo: 2, gifts: gifts)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('☕'), findsOneWidget);

      gifts.value = {
        2: [event(2, '😂'), event(1, '☕')],
      };
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('😂'), findsOneWidget);
      expect(find.text('☕'), findsOneWidget, reason: 'eski hediye silindi');

      await tester.pump(OkeySeatGiftBadge.freshFor);
      gifts.dispose();
    });

    testWidgets('masaya girerken ASILI hediyeler animasyonsuz gösterilir', (
      tester,
    ) async {
      // İlk kuruluşta gönderen adı YAZILMAZ: masaya girerken zaten orada
      // duran bir hediye "az önce geldi" gibi görünmemeli.
      final gifts = ValueNotifier<Map<int, List<OkeyGiftEvent>>>({
        3: [event(9, '💐', seat: 3, from: 'Zeynep')],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OkeySeatGiftBadge(seatNo: 3, gifts: gifts)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('💐'), findsOneWidget);
      expect(find.text('Zeynep'), findsNothing);

      gifts.dispose();
    });

    testWidgets('rozet dokunma olaylarını YUTMAZ', (tester) async {
      // Bir animasyonun hamleyi kaçırtması hediyeden çok daha pahalı.
      final gifts = ValueNotifier<Map<int, List<OkeyGiftEvent>>>({
        0: [event(1, '😂', seat: 0)],
      });
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                  ),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: OkeySeatGiftBadge(seatNo: 0, gifts: gifts),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('😂'), findsOneWidget);

      await tester.tap(find.text('😂'), warnIfMissed: false);
      await tester.pump();
      expect(tapped, isTrue, reason: 'rozet dokunmayı yuttu');

      gifts.dispose();
    });

    test('bilinmeyen hareket adı ÇÖKMEZ, bounce olur', () {
      // Admin panelinden yarın 'confetti' yazılabilir; o hediyenin
      // uygulamayı çökertmesi ya da hiç görünmemesi kabul edilemez.
      expect(OkeyGiftAnim.parse('confetti'), OkeyGiftAnim.bounce);
      expect(OkeyGiftAnim.parse(null), OkeyGiftAnim.bounce);
      expect(OkeyGiftAnim.parse('  SHAKE '), OkeyGiftAnim.shake);
      expect(OkeyGiftAnim.parse('beat'), OkeyGiftAnim.beat);
    });
  });
}
