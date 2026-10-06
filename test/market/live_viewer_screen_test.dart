import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/screens/live_viewer_screen.dart';
import 'package:cizreapp/features/market/services/live_shopping_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/live_fakes.dart';
import '../helpers/test_fonts.dart';

/// Görev 3.4 — izleyici ekranı: bağlanma, satıcı görüntüsü, izleyici sayısı,
/// sohbet, sabit ürün, yayın bitişi ve misafir/hata durumları.
void main() {
  setUpAll(loadTestFonts);

  final liveSession = LiveSession.fromJson(
    liveSessionJson(status: 'live', isLive: true, startedAt: kLiveNow, viewers: 3),
  );

  Future<(FakeLiveService, FakeLiveEngine, List<String>)> open(
    WidgetTester tester, {
    FakeLiveService? service,
    FakeLiveEngine? engine,
    LiveSession? session,
    Future<void> Function(String text)? share,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = service ?? (FakeLiveService(userId: 'user-9')..credentials = kViewerCredentials);
    final e = engine ?? FakeLiveEngine();
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LiveViewerScreen(
          key: UniqueKey(),
          session: session ?? liveSession,
          service: s,
          engineFactory: () => e,
          openProduct: (_, id) => opened.add('product:$id'),
          openShop: (_, id) => opened.add('shop:$id'),
          share: share,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (s, e, opened);
  }

  testWidgets('bağlanır: izleyici anahtarı, izleyici olarak katılma, satıcı gelince görüntü', (tester) async {
    final (s, e, _) = await open(tester);
    expect(s.calls, contains('token:viewer'));
    expect(e.calls, ['joinViewer:424242']);
    expect(s.audienceCountsMe, isTrue, reason: 'izleyici kendini sayar');
    expect(find.text('Yayına bağlanılıyor…'), findsOneWidget);

    e.events!.onJoined!();
    await tester.pump();
    expect(find.text('Satıcının görüntüsü bekleniyor…'), findsOneWidget);

    e.events!.onRemoteJoined!(777); // satıcı olmayan uid yok sayılır
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-remote-view-1')), findsNothing);

    e.events!.onRemoteJoined!(1);
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-remote-view-1')), findsOneWidget);
    expect(find.text('Çay Evi'), findsOneWidget);

    e.events!.onRemoteVideo!(1, false);
    await tester.pump();
    expect(find.text('Satıcı kamerasını kısa süreliğine kapattı.'), findsOneWidget);
    e.events!.onRemoteLeft!(1);
    await tester.pump();
    expect(find.text('Satıcının görüntüsü bekleniyor…'), findsOneWidget);
  });

  testWidgets('izleyici sayısı presence\'tan; yoksa satırdaki sayı', (tester) async {
    final (s, e, _) = await open(tester);
    e.events!.onJoined!();
    await tester.pump();
    expect(find.text('3'), findsOneWidget, reason: 'presence gelmeden satırdaki sayı');
    s.audience.add(8);
    await tester.pump(Duration.zero);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('sohbet: geçmiş + canlı mesaj + gönderme; hız sınırı mesajı', (tester) async {
    final service = FakeLiveService(userId: 'user-9')
      ..credentials = kViewerCredentials
      ..recent = [liveMessage('m0', 'Hoş geldiniz', host: true)];
    final (s, e, _) = await open(tester, service: service);
    e.events!.onJoined!();
    await tester.pump(Duration.zero);
    expect(find.textContaining('Hoş geldiniz'), findsOneWidget);

    s.chat.add(LiveChatEvent.message(liveMessage('m1', 'Rengi var mı?')));
    await tester.pump(Duration.zero);
    expect(find.textContaining('Rengi var mı?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Kırmızısı var mı?');
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pump(Duration.zero);
    expect(s.sent, ['Kırmızısı var mı?']);
    expect(find.textContaining('Kırmızısı var mı?'), findsOneWidget);

    s.sendError = const LiveException(LiveFailure.messageRate);
    await tester.enterText(find.byType(TextField), 'tekrar');
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(find.text('Çok hızlı mesaj gönderiyorsun; biraz bekle.'), findsOneWidget);
  });

  testWidgets('sabit ürün: satırda kimlik değişince ayrıntı yüklenir; dokununca ürün açılır', (tester) async {
    final service = FakeLiveService(userId: 'user-9')
      ..credentials = kViewerCredentials
      ..detail = LiveSession.fromJson(liveSessionJson(
        status: 'live',
        isLive: true,
        startedAt: kLiveNow,
        pinned: pinnedJson(id: 'p7', name: 'Bakır cezve', price: 400, discount: 350),
      ));
    final (s, e, opened) = await open(tester, service: service);
    e.events!.onJoined!();
    s.rows.add({'id': 'sess-1', 'status': 'live', 'pinned_product_id': 'p7', 'last_heartbeat_at': '2026-09-28T12:00:00Z'});
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(s.calls, contains('detail'));
    expect(find.text('Bakır cezve'), findsOneWidget);
    expect(find.text('₺350'), findsOneWidget);
    expect(find.text('₺400'), findsOneWidget, reason: 'eski fiyat üstü çizili');
    await tester.tap(find.text('İncele'));
    expect(opened, ['product:p7']);

    // Satıcı ürünü kaldırınca kart gider
    s.rows.add({'id': 'sess-1', 'status': 'live', 'pinned_product_id': null});
    await tester.pump(Duration.zero);
    expect(find.text('Bakır cezve'), findsNothing);
  });

  testWidgets('satıcı bitirince Realtime ile "Yayın sona erdi"; mağazaya gidilebilir', (tester) async {
    final (s, e, opened) = await open(tester);
    e.events!.onJoined!();
    await tester.pump();
    s.rows.add({'id': 'sess-1', 'status': 'ended', 'ended_reason': 'host'});
    await tester.pump(Duration.zero);
    expect(find.text('Yayın sona erdi'), findsOneWidget);
    expect(find.text('Satıcı yayını bitirdi.'), findsOneWidget);
    expect(e.calls, contains('leave'));
    await tester.tap(find.text('Çay Evi mağazasına git'));
    expect(opened, ['shop:shop-1']);
  });

  testWidgets('bitmiş yayına girilirse ya da anahtar NOT_LIVE dönerse bitti ekranı', (tester) async {
    final service = FakeLiveService(userId: 'user-9')
      ..credentialsError = const LiveException(LiveFailure.notLive);
    final (_, e, _) = await open(tester, service: service);
    expect(find.text('Yayın sona erdi'), findsOneWidget);
    expect(e.calls, isNot(contains('joinViewer:424242')));

    final ended = LiveSession.fromJson(liveSessionJson(status: 'ended', endedReason: 'timeout'));
    final (s2, e2, _) = await open(tester, session: ended);
    expect(find.text('Satıcının bağlantısı koptuğu için yayın sona erdi.'), findsOneWidget);
    expect(s2.calls.where((c) => c.startsWith('token')), isEmpty, reason: 'bitmiş yayına bağlanılmaz');
    expect(s2.calls, contains('detail'), reason: 'özet için ayrıntı');
    expect(e2.calls, isEmpty);
  });

  testWidgets('bitti özeti: süre, en çok izleyici, mesaj, öne çıkan ürünler; ürüne ve mağazaya gidilir', (tester) async {
    final ended = LiveSession.fromJson(liveSessionJson(
      status: 'ended',
      endedReason: 'host',
      startedAt: kLiveNow.subtract(const Duration(minutes: 30)),
      endedAt: kLiveNow.subtract(const Duration(minutes: 5)),
      peak: 18,
    ));
    final service = FakeLiveService(userId: 'user-9')
      ..detail = LiveSession.fromJson(liveSessionJson(
        status: 'ended',
        endedReason: 'host',
        startedAt: kLiveNow.subtract(const Duration(minutes: 30)),
        endedAt: kLiveNow.subtract(const Duration(minutes: 5)),
        peak: 18,
        durationSeconds: 1500,
        messageCount: 42,
        featured: [pinnedJson(id: 'p1', name: 'Demlik', price: 250, discount: 200), pinnedJson(id: 'p2', name: 'Bardak')],
      ));
    final (s, _, opened) = await open(tester, service: service, session: ended);
    expect(find.text('Yayın sona erdi'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Bu yayında öne çıkanlar'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-featured-p2')), findsOneWidget);
    expect(find.text('Mağaza yeniden canlı yayına başlayınca bildirim gelir.'), findsOneWidget);
    expect(s.calls, contains('sub:get:shop-1'));

    await tester.tap(find.byKey(const ValueKey('live-featured-p1')));
    await tester.ensureVisible(find.text('Çay Evi mağazasına git'));
    await tester.tap(find.text('Çay Evi mağazasına git'));
    expect(opened, ['product:p1', 'shop:shop-1']);
  });

  testWidgets('biten yayının özeti web\'de de açılır (görüntü motoru gerekmez)', (tester) async {
    final ended = LiveSession.fromJson(liveSessionJson(status: 'ended', endedReason: 'host'));
    await open(tester, session: ended, engine: FakeLiveEngine(supported: false));
    expect(find.text('Yayın sona erdi'), findsOneWidget);
    expect(find.text('Canlı yayın yalnız mobil uygulamada çalışır.'), findsNothing);
  });

  testWidgets('Haberdar ol: abone olur/çıkar; misafire giriş önerilir', (tester) async {
    final (s, e, _) = await open(tester);
    e.events!.onJoined!();
    await tester.pump();
    expect(s.calls, contains('sub:get:shop-1'));
    expect(find.text('Haberdar ol'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-subscribe')));
    await tester.pump();
    await tester.pump();
    expect(s.calls, contains('sub:set:shop-1:true'));
    expect(find.text('Haberdarsın'), findsOneWidget);
    expect(find.text('🔔 Çay Evi canlı yayına başlayınca haber vereceğiz'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-subscribe')));
    await tester.pump();
    await tester.pump();
    expect(s.calls, contains('sub:set:shop-1:false'));
    expect(find.text('Haberdar ol'), findsOneWidget);

    s.subscriptionError = const LiveException(LiveFailure.connection);
    await tester.tap(find.byKey(const ValueKey('live-subscribe')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Bağlantı kurulamadı; internetini kontrol edip tekrar dene.'), findsOneWidget);
    expect(find.text('Haberdar ol'), findsOneWidget, reason: 'hata durumu değiştirmez');

    final guest = FakeLiveService(userId: null)..credentials = kViewerCredentials;
    final (g, ge, _) = await open(tester, service: guest);
    ge.events!.onJoined!();
    await tester.pump();
    expect(g.calls.where((c) => c.startsWith('sub:')), isEmpty, reason: 'misafirin durumu okunmaz');
    await tester.tap(find.byKey(const ValueKey('live-subscribe')));
    await tester.pump();
    expect(find.text('Yayın bildirimi almak için giriş yapmalısın'), findsOneWidget);
    expect(g.calls.where((c) => c.startsWith('sub:')), isEmpty);
  });

  testWidgets('paylaş: mağaza ve başlıkla yayın metni', (tester) async {
    final shared = <String>[];
    final (_, e, _) = await open(tester, share: (text) async => shared.add(text));
    e.events!.onJoined!();
    await tester.pump();
    await tester.tap(find.byTooltip('Paylaş'));
    await tester.pump();
    expect(shared, [liveShareText(liveSession)]);
    expect(shared.single, contains('🔴 Çay Evi şu an CizreApp\'te canlı yayında!'));
    expect(shared.single, contains('"Çay Evi canlı yayında"'));
  });

  testWidgets('misafir izler; yazmak için giriş düğmesi', (tester) async {
    final service = FakeLiveService(userId: null)..credentials = kViewerCredentials;
    final (s, e, _) = await open(tester, service: service);
    e.events!.onJoined!();
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Yorum yapmak için giriş yap'));
    await tester.pump();
    expect(find.text('Yorum yapmak için giriş yapmalısın'), findsOneWidget);
    expect(find.text('Giriş Yap'), findsOneWidget);
    expect(s.sent, isEmpty);
  });

  testWidgets('ses kapatma ve anahtar yenileme', (tester) async {
    final (s, e, _) = await open(tester);
    e.events!.onJoined!();
    await tester.pump();
    await tester.tap(find.byTooltip('Sesi kapat'));
    await tester.pump();
    expect(e.remoteMuted, isTrue);
    e.events!.onTokenExpiring!();
    await tester.pump(Duration.zero);
    expect(s.calls.where((c) => c == 'token:viewer'), hasLength(2));
    expect(e.renewedToken, '007viewer');
  });

  testWidgets('Agora ayarlı değilse açıklama; web desteklenmiyor', (tester) async {
    final service = FakeLiveService(userId: 'user-9')
      ..credentialsError = LiveShoppingService.toLiveException(const LiveException(LiveFailure.notConfigured));
    await open(tester, service: service);
    expect(find.textContaining('Canlı yayın henüz etkin değil'), findsOneWidget);

    final (s2, _, _) = await open(tester, engine: FakeLiveEngine(supported: false));
    expect(find.text('Canlı yayın yalnız mobil uygulamada çalışır.'), findsOneWidget);
    expect(s2.calls, isEmpty);
  });
}
