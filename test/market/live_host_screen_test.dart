import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/screens/live_host_screen.dart';
import 'package:cizreapp/features/market/services/live_shopping_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../helpers/live_fakes.dart';
import '../helpers/test_fonts.dart';

/// Görev 3.4 — satıcı canlı yayın ekranı: hazırlık, yayına başlama, canlıyken
/// sinyal/izleyici/sohbet/ürün sabitleme, bitirme özeti ve hata durumları.
void main() {
  setUpAll(loadTestFonts);

  Future<(FakeLiveService, FakeLiveEngine)> open(
    WidgetTester tester, {
    FakeLiveService? service,
    FakeLiveEngine? engine,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = service ?? FakeLiveService();
    final e = engine ?? FakeLiveEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: LiveHostScreen(
          key: UniqueKey(),
          shopId: 'shop-1',
          shopName: 'Çay Evi',
          service: s,
          engineFactory: () => e,
          now: () => kLiveNow.add(const Duration(minutes: 3, seconds: 7)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (s, e);
  }

  Future<void> goLive(WidgetTester tester, FakeLiveService s, FakeLiveEngine e) async {
    await tester.tap(find.text('Yayına Başla'));
    await tester.pump();
    expect(e.calls, contains('joinHost:1'));
    expect(find.text('Yayına bağlanılıyor…'), findsOneWidget);
    e.events!.onJoined!();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('hazırlık: kayıt + anahtar + önizleme; başlık alanı ve ürün sayısı', (tester) async {
    final (s, e) = await open(tester);
    expect(s.calls, ['create', 'token:host']);
    expect(e.calls, ['preview']);
    expect(find.byKey(const ValueKey('fake-local-view')), findsOneWidget);
    expect(find.text('ÖNİZLEME'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Çay Evi canlı yayında'), findsOneWidget);
    expect(find.text('Yayındayken 2 ürününden birini ekranda gösterebilirsin.'), findsOneWidget);
  });

  testWidgets('yayına başla: kanala katılınca yayın canlı; sayaç, izleyici, sinyal', (tester) async {
    final (s, e) = await open(tester);
    await goLive(tester, s, e);
    expect(s.calls, containsAllInOrder(['create', 'token:host', 'start']));
    expect(find.text('CANLI · 3:07'), findsOneWidget);
    expect(s.audienceCountsMe, isFalse, reason: 'satıcı kendini izleyici saymaz');

    s.audience.add(5);
    await tester.pump(Duration.zero);
    expect(find.text('5'), findsOneWidget);

    await tester.pump(const Duration(seconds: 20));
    expect(s.heartbeats, [5], reason: '20 sn\'de bir sinyal, izleyici sayısıyla');
  });

  testWidgets('yayın başlayınca kaç kişiye bildirim gittiği söylenir; kimseye gitmediyse sessiz', (tester) async {
    final (s, e) = await open(tester, service: FakeLiveService()..startNotified = 37);
    await goLive(tester, s, e);
    expect(find.text('🔔 37 kişiye yayın bildirimi gönderildi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // önceki snackbar'ı taşımasın
    final (s2, e2) = await open(tester, service: FakeLiveService()..startNotified = 0);
    await goLive(tester, s2, e2);
    expect(find.textContaining('yayın bildirimi gönderildi'), findsNothing, reason: 'bekleme süresi / kapalı');
  });

  testWidgets('başlık değiştirilirse kayıt güncellenir; kısa başlık reddedilir', (tester) async {
    final (s, e) = await open(tester);
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.tap(find.text('Yayına Başla'));
    await tester.pump();
    expect(find.text('Başlık 3–80 karakter olmalı'), findsOneWidget);
    expect(e.calls, isNot(contains('joinHost:1')));

    await tester.enterText(find.byType(TextField), '  Yeni   sezon ürünleri ');
    await goLive(tester, s, e);
    expect(s.titles.last, 'Yeni sezon ürünleri');
  });

  testWidgets('canlı: sohbet akışı, satıcı mesajı ve moderasyon', (tester) async {
    final (s, e) = await open(tester);
    await goLive(tester, s, e);

    s.chat.add(LiveChatEvent.message(liveMessage('m1', 'Fiyatı ne kadar?')));
    await tester.pump(Duration.zero);
    expect(find.textContaining('Fiyatı ne kadar?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '250 lira');
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pump();
    expect(s.sent, ['250 lira']);
    expect(find.textContaining('250 lira'), findsOneWidget);

    await tester.longPress(find.textContaining('Fiyatı ne kadar?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mesajı sil'));
    await tester.pumpAndSettle();
    expect(s.deleted, ['m1']);
    expect(find.textContaining('Fiyatı ne kadar?'), findsNothing);

    // Başka birinin sildiği (Realtime DELETE) mesaj da düşer
    s.chat.add(LiveChatEvent.message(liveMessage('m2', 'Kargo var mı?')));
    await tester.pump(Duration.zero);
    expect(find.textContaining('Kargo var mı?'), findsOneWidget);
    s.chat.add(const LiveChatEvent.deleted('m2'));
    await tester.pump(Duration.zero);
    expect(find.textContaining('Kargo var mı?'), findsNothing);
  });

  testWidgets('ürün sabitleme ve kaldırma', (tester) async {
    final (s, e) = await open(tester);
    await goLive(tester, s, e);
    await tester.tap(find.byTooltip('Ürün göster'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demlik'));
    await tester.pumpAndSettle();
    expect(s.pinned, ['p1']);
    expect(find.text('Yayında gösteriyorsun'), findsOneWidget);
    expect(find.text('₺250'), findsOneWidget);

    await tester.tap(find.byTooltip('Ürünü kaldır'));
    await tester.pump();
    expect(s.pinned, ['p1', '-']);
    expect(find.text('Yayında gösteriyorsun'), findsNothing);
  });

  testWidgets('kontroller: mikrofon, kamera, kamera çevirme', (tester) async {
    final (s, e) = await open(tester);
    await goLive(tester, s, e);
    await tester.tap(find.byTooltip('Mikrofonu kapat'));
    await tester.pump();
    expect(e.micMuted, isTrue);
    await tester.tap(find.byTooltip('Kamerayı kapat'));
    await tester.pump();
    expect(e.cameraEnabled, isFalse);
    expect(find.textContaining('Kameran kapalı'), findsOneWidget);
    await tester.tap(find.byTooltip('Kamerayı aç'));
    await tester.pump();
    await tester.tap(find.byTooltip('Kamerayı çevir'));
    await tester.pump();
    expect(e.calls, contains('switch'));
  });

  testWidgets('bitir: onay → özet (süre, en çok izleyici, mesaj)', (tester) async {
    final (s, e) = await open(tester);
    await goLive(tester, s, e);
    await tester.tap(find.text('Bitir'));
    await tester.pumpAndSettle();
    expect(find.text('Canlı yayın herkes için sona erecek. Emin misin?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Bitir').last);
    await tester.pumpAndSettle();
    expect(s.calls.last, 'end');
    expect(e.calls, contains('leave'));
    expect(find.text('Yayın sona erdi'), findsOneWidget);
    expect(find.text('Yayını bitirdin.'), findsOneWidget);
    expect(find.text('12:05'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('sunucu yayını kapattıysa (zaman aşımı) sinyal özet ekranına geçirir', (tester) async {
    final (s, e) = await open(tester);
    await goLive(tester, s, e);
    s.heartbeatResult = const LiveHeartbeat(status: 'ended', endedReason: 'timeout');
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(find.text('Yayın sona erdi'), findsOneWidget);
    expect(find.textContaining('Bağlantı 2 dakikadan uzun süre koptuğu için'), findsOneWidget);
    expect(e.calls, contains('leave'));
  });

  testWidgets('yönetici kapatınca (Realtime satırı) özet gösterilir', (tester) async {
    final (s, e) = await open(tester);
    await goLive(tester, s, e);
    s.rows.add({'id': 'sess-1', 'status': 'ended', 'ended_reason': 'admin'});
    await tester.pump(Duration.zero);
    expect(find.text('Yayın yönetici tarafından kapatıldı.'), findsOneWidget);
  });

  testWidgets('açık canlı yayın sürdürülür: hazırlık atlanır, doğrudan kanala girilir', (tester) async {
    final service = FakeLiveService()
      ..resumed = true
      ..created = LiveSession.fromJson(liveSessionJson(status: 'live', isLive: true, startedAt: kLiveNow));
    final (s, e) = await open(tester, service: service);
    expect(find.text('Yayına Başla'), findsNothing);
    expect(e.calls, containsAllInOrder(['preview', 'joinHost:1']));
    e.events!.onJoined!();
    await tester.pump();
    await tester.pump();
    expect(s.calls, contains('start'));
    expect(find.textContaining('CANLI'), findsOneWidget);
  });

  testWidgets('Agora ayarlı değilse açıklama gösterilir ve boş hazırlık kaydı silinir', (tester) async {
    final service = FakeLiveService()..credentialsError = const LiveException(LiveFailure.notConfigured);
    final (s, e) = await open(tester, service: service);
    expect(find.textContaining('Canlı yayın henüz etkin değil'), findsOneWidget);
    expect(s.calls, ['create', 'token:host', 'end']);
    expect(e.calls, isNot(contains('preview')));
    expect(find.text('Tekrar dene'), findsNothing);
  });

  testWidgets('kamera izni yoksa izin düğmesi; sunucu ipucu Türkçe mesaja çevrilir', (tester) async {
    final engine = FakeLiveEngine()..previewError = const LiveException(LiveFailure.permissionDenied);
    await open(tester, engine: engine);
    expect(find.text('Yayın için kamera ve mikrofon izni gerekli.'), findsOneWidget);
    expect(find.text('İzinleri aç'), findsOneWidget);

    final service = FakeLiveService()
      ..createError = const PostgrestException(message: 'x', code: 'P0001', hint: 'LIVE_SHOP_INACTIVE');
    await open(tester, service: service);
    expect(find.text('Yayın için mağazan aktif ve onaylı olmalı.'), findsOneWidget);
  });

  testWidgets('web: motor desteklenmiyor mesajı; sunucuya gidilmez', (tester) async {
    final (s, _) = await open(tester, engine: FakeLiveEngine(supported: false));
    expect(find.text('Canlı yayın yalnız mobil uygulamada çalışır.'), findsOneWidget);
    expect(s.calls, isEmpty);
  });

  testWidgets('hazırlıkta ekrandan çıkılırsa kayıt silinir ve motor kapanır', (tester) async {
    final (s, e) = await open(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(s.calls.last, 'end');
    expect(e.calls.last, 'dispose');
  });

  test('ipucu eşlemesi: sunucu kodları LiveFailure\'a', () {
    LiveFailure map(String hint) => LiveShoppingService.toLiveException(
      PostgrestException(message: 'x', code: 'P0001', hint: hint),
    ).failure;
    expect(map('LIVE_MESSAGE_RATE'), LiveFailure.messageRate);
    expect(map('LIVE_NOT_HOST'), LiveFailure.notHost);
    expect(map('LIVE_PRODUCT_INVALID'), LiveFailure.productInvalid);
    expect(map('LIVE_TITLE_INVALID'), LiveFailure.titleInvalid);
    expect(map('BAŞKA'), LiveFailure.unknown);
  });
}
