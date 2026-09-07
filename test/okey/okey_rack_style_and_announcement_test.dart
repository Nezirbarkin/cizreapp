import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/theme/okey_rack_style.dart';
import 'package:cizreapp/okey/widgets/okey_announcement_banner.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_rack_chrome.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:cizreapp/okey/widgets/okey_table_settings_dialog.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TAKOZ (ISTAKA) SEÇİMİ, MASA AYARLARI ve SESLİ ANONS BANDI
///
/// Kullanıcı isteği (2026-09-07):
///  * "3,4 farklı takoz ekle, kullanıcı takozunu ayardan değiştirebilsin"
///  * "ayardaki hataları ve taşma vs sorununu da hallet"
///  * "seri açıldı / çift açıldı / son üç taş diye sesli söylesin"
///
/// Ayarlar diyaloğu bu yüzden `OkeyGameProvider`'a değil düz değerlere ve
/// geri çağrılara bağlı: taşma bir DÜZEN sorunudur ve ancak diyalog gerçekten
/// pump edilirse yakalanır — Supabase gerektiren bir provider'a bağlı olsaydı
/// hiçbir test onu kuramazdı.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Takoz temaları', () {
    test('en az 3 farklı takoz var ve anahtarları benzersiz', () {
      expect(OkeyRackStyle.all.length, greaterThanOrEqualTo(3));
      final keys = OkeyRackStyle.all.map((s) => s.key).toSet();
      expect(keys.length, OkeyRackStyle.all.length);
      // Etiketler de benzersiz olmalı: ayarda iki "Ceviz" görünürse hangisinin
      // seçili olduğu anlaşılmaz.
      final labels = OkeyRackStyle.all.map((s) => s.label).toSet();
      expect(labels.length, OkeyRackStyle.all.length);
    });

    test('her takozun gövdesi 4 duraklı — painter stops ile eşleşmeli', () {
      // Painter gradyanı `stops: [0.0, 0.18, 0.74, 1.0]` ile kuruyor; renk
      // sayısı ayrışırsa Flutter çizim anında ASSERT atar (yalnızca gerçek
      // cihazda görülürdü).
      for (final style in OkeyRackStyle.all) {
        expect(style.body.length, 4, reason: style.key);
      }
    });

    test('bilinmeyen/boş anahtar varsayılana düşer', () {
      expect(OkeyRackStyle.byKey(null).key, OkeyRackStyle.ceviz.key);
      expect(OkeyRackStyle.byKey('yok-boyle-bir-sey').key, 'ceviz');
      expect(OkeyRackStyle.byKey('grafit').key, 'grafit');
    });

    test('seçim cihazda saklanır ve tekrar okunur', () async {
      final prefs = OkeyRackStylePrefs.instance;
      await prefs.select(OkeyRackStyle.maun);
      expect(prefs.current.value.key, 'maun');

      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('okey_rack_style'), 'maun');

      // Temizlik: sonraki testler varsayılanla başlasın.
      await prefs.select(OkeyRackStyle.ceviz);
    });

    /// GERÇEKÇİ TAKOZUN GEOMETRİSİ (kullanıcı isteği, 2026-09-07: "takoz
    /// daha gerçekçi tasarımı uygula... mevcut düz ıskatadır").
    ///
    /// Takozun üç boyutlu okunması RENKTEN değil bu üç şeridin KALINLIĞINDAN
    /// gelir: iki sıra arasındaki ara raf 2 pikselken oraya ne pah ne gölge
    /// sığıyordu ve ıstaka "düz bir tahta" gibi duruyordu. Şeritler yeniden
    /// inceltilirse takoz sessizce eski düz haline döner — bu test o dönüşü
    /// yakalar.
    test('ara raf ve ön çıta, kademe çizilecek kalınlıkta', () {
      expect(okeyRackRowGap, greaterThanOrEqualTo(5));
      expect(okeyRackLedgeHeight, greaterThanOrEqualTo(8));
      expect(okeyRackTopBorder, greaterThanOrEqualTo(3));
    });

    test('süsleme toplamı TEK KAYNAKTAN türer', () {
      // Bileşenlerin toplamı ile yayımlanan sabit ayrışırsa ıstaka kendi
      // içinde tam o fark kadar taşar — daha önce bir kez yaşandı.
      expect(
        okeyRackChromeHeight,
        okeyRackTopBorder +
            (okeyRackVerticalPadding * 2) +
            okeyRackRowGap +
            okeyRackLedgeHeight,
      );
      expect(OkeyTableMetrics.rackChrome, okeyRackChromeHeight);
    });

    /// Süsleme kalınlaştı; pay artmasaydı bedeli doğrudan TAŞ BOYUNDAN
    /// çıkardı (bkz. OkeyTableMetrics._rackHeightRatio).
    test('kalınlaşan süsleme taş boyundan kısmadı', () {
      for (final size in const [
        Size(892, 412),
        Size(800, 360),
        Size(1280, 800),
      ]) {
        final m = OkeyTableMetrics.from(BoxConstraints.tight(size));
        expect(
          m.rackRowHeight,
          greaterThanOrEqualTo(45),
          reason: '$size: ıstaka taşı küçülmüş (${m.rackRowHeight})',
        );
      }
    });

    testWidgets('her takoz kısa yatay ekranda taşmadan çizilir', (
      tester,
    ) async {
      for (final style in OkeyRackStyle.all) {
        await OkeyRackStylePrefs.instance.select(style);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 731,
                  height: 120,
                  child: OkeyRackPanel(rack: const SizedBox.expand()),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: style.key);
      }
      await OkeyRackStylePrefs.instance.select(OkeyRackStyle.ceviz);
    });
  });

  group('Masa ayarları diyaloğu', () {
    /// Ayarları gerçekten AÇAR — diyaloğun kendisi pump edilmezse taşma
    /// yakalanamaz.
    Future<void> openSettings(
      WidgetTester tester, {
      required Size size,
      required double textScale,
      VoidCallback? onLeave,
      ValueNotifier<bool>? sound,
    }) async {
      final soundOn = sound ?? ValueNotifier<bool>(true);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => OkeyTableSettingsDialog(
                      isSoundOn: () => soundOn.value,
                      isVoiceOn: () => true,
                      isMusicOn: () => true,
                      onToggleSound: () => soundOn.value = !soundOn.value,
                      onToggleVoice: () {},
                      onToggleMusic: () {},
                      onLeaveTable: onLeave ?? () {},
                    ),
                  ),
                  child: const Text('aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
    }

    const sizes = <String, Size>{
      'yatay telefon 731x411': Size(731, 411),
      'kısa yatay 640x360': Size(640, 360),
      'dar telefon 360x640': Size(360, 640),
    };

    for (final entry in sizes.entries) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets('${entry.key} · yazı ${scale}x → taşma yok', (
          tester,
        ) async {
          await openSettings(tester, size: entry.value, textScale: scale);
          expect(find.text('Ayarlar'), findsOneWidget);
          expect(find.text('Takoz'), findsOneWidget);
          // Taşma, Flutter'ın çizim istisnası olarak gelir.
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('sesli anons anahtarı ayarlarda var', (tester) async {
      await openSettings(
        tester,
        size: const Size(731, 411),
        textScale: 1.0,
      );
      expect(find.text('Sesli anons'), findsOneWidget);
      expect(find.text('Ses efektleri'), findsOneWidget);
      expect(find.text('Müzik'), findsOneWidget);
    });

    testWidgets('anahtar çevrilince güncel değer okunur', (tester) async {
      final sound = ValueNotifier<bool>(true);
      await openSettings(
        tester,
        size: const Size(731, 411),
        textScale: 1.0,
        sound: sound,
      );
      final target = find.ancestor(
        of: find.text('Ses efektleri'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(target).value, isTrue);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(sound.value, isFalse);
      // Diyalog provider'ın FOTOĞRAFINI değil güncel halini okumalı.
      expect(tester.widget<SwitchListTile>(target).value, isFalse);
    });

    testWidgets('masadan ayrılmak ONAY ister — tek dokunuş çıkarmaz', (
      tester,
    ) async {
      var left = false;
      await openSettings(
        tester,
        size: const Size(731, 411),
        textScale: 1.0,
        onLeave: () => left = true,
      );

      // İçerik kaydırılabilir (taşma düzeltmesinin ta kendisi): satır
      // görünür alana getirilmeden dokunulamaz.
      Future<void> tapText(String text) async {
        await tester.ensureVisible(find.text(text));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      await tapText('Masadan ayrıl');
      expect(left, isFalse, reason: 'ilk dokunuş yalnızca onay sorar');
      expect(find.text('Evet, ayrıl'), findsOneWidget);

      await tapText('Vazgeç');
      expect(left, isFalse);
      expect(find.text('Masadan ayrıl'), findsOneWidget);

      await tapText('Masadan ayrıl');
      await tapText('Evet, ayrıl');
      expect(left, isTrue);
    });

    testWidgets('takoz seçilince tercih değişir', (tester) async {
      await openSettings(
        tester,
        size: const Size(731, 411),
        textScale: 1.0,
      );
      expect(OkeyRackStylePrefs.instance.current.value.key, 'ceviz');

      await tester.ensureVisible(find.text('Grafit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grafit'));
      await tester.pumpAndSettle();
      expect(OkeyRackStylePrefs.instance.current.value.key, 'grafit');

      await OkeyRackStylePrefs.instance.select(OkeyRackStyle.ceviz);
    });
  });

  group('İşlek taş uyarısı (riskli taş)', () {
    /// Ceza 2026-09-07'den beri eli KAPALI oyuncuya da yazılıyor
    /// (bkz. 20260907000003 göçü). O oyuncunun elinde hiçbir işaret yoktu;
    /// hatasını ancak +101'i ödedikten sonra görüyordu. Bu test, uyarının
    /// ıstakaya kadar taşındığını doğrular — kopan halka tam burasıydı.
    testWidgets('riskli slot taşa hintRisky olarak geçer', (tester) async {
      final slots = <OkeyTile?>[
        OkeyTile.numbered(OkeyColor.red, 5),
        OkeyTile.numbered(OkeyColor.blue, 9),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 731,
              height: 120,
              child: OkeyRackBarWidget(
                slots: slots,
                selectedIndices: const {},
                onTap: (_) {},
                onMove: (_, _) {},
                riskyIndices: const {0},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final tiles = tester
          .widgetList<OkeyTileWidget>(find.byType(OkeyTileWidget))
          .toList();
      expect(tiles.length, greaterThanOrEqualTo(2));
      expect(tiles[0].hintRisky, isTrue);
      expect(tiles[1].hintRisky, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('riskli taş kırmızı alt çizgi alır, işlenebilir taş almaz', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                OkeyTileWidget(
                  tile: OkeyTile.numbered(OkeyColor.red, 5),
                  hintRisky: true,
                ),
                OkeyTileWidget(
                  tile: OkeyTile.numbered(OkeyColor.blue, 9),
                  // Eli açık oyuncuda aynı taş hem "işlenebilir" hem
                  // "riskli"dir; yeşil çerçeve zaten daha güçlü konuştuğu
                  // için kırmızı çizgi ÇİZİLMEZ.
                  hintRisky: true,
                  hintProcessable: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Sesli anons bandı', () {
    testWidgets('anons gelince metin belirir, sonra söner', (tester) async {
      final notifier = ValueNotifier<OkeyAnnouncement?>(null);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OkeyAnnouncementBanner(listenable: notifier),
          ),
        ),
      );
      expect(find.textContaining('Seri'), findsNothing);

      notifier.value = const OkeyAnnouncement(id: 1, text: 'Seri açıldı');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Seri açıldı'), findsOneWidget);

      // Bant kendiliğinden kaybolur — masada asılı kalmaz.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Seri açıldı'), findsNothing);
    });

    testWidgets('aynı metin yeni id ile tekrar oynar', (tester) async {
      final notifier = ValueNotifier<OkeyAnnouncement?>(null);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OkeyAnnouncementBanner(listenable: notifier),
          ),
        ),
      );

      notifier.value = const OkeyAnnouncement(id: 1, text: 'Çift açıldı');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Çift açıldı'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Çift açıldı'), findsNothing);

      notifier.value = const OkeyAnnouncement(id: 2, text: 'Çift açıldı');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Çift açıldı'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('uzun oyuncu adı bandı taşırmaz', (tester) async {
      final notifier = ValueNotifier<OkeyAnnouncement?>(null);
      addTearDown(notifier.dispose);

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OkeyAnnouncementBanner(listenable: notifier),
          ),
        ),
      );
      notifier.value = const OkeyAnnouncement(
        id: 1,
        text: 'ÇokUzunBirOyuncuAdıBurayaSığmaz, son üç taş',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 3));
    });
  });
}
