import 'package:cizreapp/okey/widgets/okey_landscape_stage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Web/masaüstünde okey masasını yatay tutan sahnenin testleri.
///
/// NEDEN TEST EDİLİYOR: buradaki hata SESSİZDİR. Döndürme çalışmazsa masa
/// dikey bir tarayıcı penceresinde sıkışır ama hiçbir hata/uyarı çıkmaz;
/// sarmalayıcı yanlış kurulursa da altındaki Navigator sökülüp uygulamanın
/// tüm durumu sıfırlanır. İkisi de ancak elle oynayınca fark edilirdi.
void main() {
  /// Platformu sabitleyerek bir test çalıştırır.
  ///
  /// Testlerde `defaultTargetPlatform` android'dir; orada sahne bilerek
  /// devre dışıdır (ekranı işletim sistemi döndürür). Web'i taklit etmek
  /// için ekranı kendi döndüremeyen bir masaüstü platformu seçilir.
  ///
  /// Override, test GÖVDESİ biterken sıfırlanmak ZORUNDA: flutter_test
  /// gövdenin hemen ardından "foundation hata ayıklama değişkenleri
  /// sıfırlandı mı" kontrolü yapar ve bu kontrol tearDown'lardan ÖNCE
  /// çalışır — tearDown'a bırakılırsa her test bu yüzden patlar.
  void platformTest(
    String name,
    TargetPlatform platform,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        OkeyLandscapeLock.depth.value = 0;
      }
    });
  }

  /// Sahneyi uygulamanın kökündeki gibi kurar ve içine ölçülebilir,
  /// ekranı dolduran bir çocuk koyar.
  Future<Key> pumpStage(WidgetTester tester, Size physicalSize) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const childKey = ValueKey('masa');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            OkeyLandscapeStage(child: child ?? const SizedBox.shrink()),
        home: const SizedBox.expand(
          child: ColoredBox(key: childKey, color: Color(0xFF00C853)),
        ),
      ),
    );
    return childKey;
  }

  group('OkeyLandscapeStage', () {
    platformTest('kilit kapalıyken dikey pencereye dokunmaz',
        TargetPlatform.windows, (tester) async {
      final key = await pumpStage(tester, const Size(400, 800));
      expect(tester.getSize(find.byKey(key)), const Size(400, 800));
    });

    platformTest('kilit açıkken dikey pencerede masa YATAY yerleşir',
        TargetPlatform.windows, (tester) async {
      final key = await pumpStage(tester, const Size(400, 800));

      OkeyLandscapeLock.engage();
      await tester.pump();

      // Kenarlar takas olur: masa artık 800x400'lük bir alana kurulur.
      expect(
        tester.getSize(find.byKey(key)),
        const Size(800, 400),
        reason: 'dikey tarayıcı penceresinde masa yatay kurulmalı',
      );
    });

    platformTest('yatay pencerede döndürme YAPILMAZ',
        TargetPlatform.windows, (tester) async {
      // Masaüstü tarayıcı ya da zaten yan çevrilmiş telefon: burada bir de
      // biz döndürseydik masa ters görünürdü.
      final key = await pumpStage(tester, const Size(900, 500));

      OkeyLandscapeLock.engage();
      await tester.pump();

      expect(tester.getSize(find.byKey(key)), const Size(900, 500));
    });

    platformTest('MediaQuery ölçüsü de döner (SafeArea/ölçü hesapları için)',
        TargetPlatform.windows, (tester) async {
      late Size seenByChild;
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              OkeyLandscapeStage(child: child ?? const SizedBox.shrink()),
          home: Builder(
            builder: (context) {
              seenByChild = MediaQuery.of(context).size;
              return const SizedBox.expand();
            },
          ),
        ),
      );

      OkeyLandscapeLock.engage();
      await tester.pump();

      expect(
        seenByChild,
        const Size(800, 400),
        reason:
            'masa ölçülerini MediaQuery üzerinden çözüyor; dönmezse taş/kutu '
            'boyutları dikey ekrana göre hesaplanırdı',
      );
    });

    platformTest('release() sonrası döndürme geri alınır',
        TargetPlatform.windows, (tester) async {
      final key = await pumpStage(tester, const Size(400, 800));

      OkeyLandscapeLock.engage();
      await tester.pump();
      expect(tester.getSize(find.byKey(key)), const Size(800, 400));

      OkeyLandscapeLock.release();
      await tester.pump();
      expect(tester.getSize(find.byKey(key)), const Size(400, 800));
    });

    platformTest('döndürme açılıp kapanırken çocuk YENİDEN KURULMAZ',
        TargetPlatform.windows, (tester) async {
      // EN KRİTİK DAVRANIŞ: sarmalayıcı ağaca katman ekleyip çıkarsaydı
      // altındaki Navigator elemanı sökülür, yani masaya girip çıkarken
      // uygulamanın tüm durumu (oturum, sepet, akış) sıfırlanırdı.
      await pumpStage(tester, const Size(400, 800));
      final before = tester.element(find.byType(ColoredBox));

      OkeyLandscapeLock.engage();
      await tester.pump();
      OkeyLandscapeLock.release();
      await tester.pump();

      expect(
        identical(tester.element(find.byType(ColoredBox)), before),
        isTrue,
        reason: 'aynı Element korunmalı — aksi halde alttaki durum sıfırlanır',
      );
    });

    platformTest('mobilde sahne devre dışıdır (ekranı işletim sistemi döndürür)',
        TargetPlatform.android, (tester) async {
      final key = await pumpStage(tester, const Size(400, 800));

      OkeyLandscapeLock.engage();
      await tester.pump();

      expect(OkeyLandscapeLock.depth.value, 0);
      expect(tester.getSize(find.byKey(key)), const Size(400, 800));
    });
  });
}
