import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/screens/live_sessions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, PostgresChangePayload;

import '../helpers/live_fakes.dart';
import '../helpers/test_fonts.dart';

/// Görev 3.4 — canlı yayınları keşfet: canlı/biten listeler, izleyici sayısının
/// yerinde güncellenmesi, yeni yayında yeniden yükleme, boş/hata durumları.
void main() {
  setUpAll(loadTestFonts);

  LiveFeed feed() => LiveFeed(
    live: [
      LiveSession.fromJson(liveSessionJson(
        id: 'live-1',
        status: 'live',
        isLive: true,
        title: 'Yeni sezon çaydanlıklar',
        startedAt: kLiveNow.subtract(const Duration(minutes: 20)),
        viewers: 12,
        pinned: pinnedJson(name: 'Demlik'),
      )),
    ],
    recent: [
      LiveSession.fromJson(liveSessionJson(
        id: 'old-1',
        status: 'ended',
        title: 'Hafta sonu indirimi',
        startedAt: kLiveNow.subtract(const Duration(hours: 5)),
        endedAt: kLiveNow.subtract(const Duration(hours: 4, minutes: 20)),
        peak: 31,
      )),
    ],
  );

  PostgresChangePayload change(PostgresChangeEvent type, Map<String, dynamic> row) => PostgresChangePayload(
    schema: 'public',
    table: 'live_sessions',
    commitTimestamp: kLiveNow,
    eventType: type,
    newRecord: row,
    oldRecord: const {},
    errors: null,
  );

  Future<(FakeLiveService, List<String>)> open(
    WidgetTester tester,
    FakeLiveService service, {
    int initialTab = 0,
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LiveSessionsScreen(
          service: service,
          now: () => kLiveNow,
          initialTab: initialTab,
          openSession: (_, s) => opened.add(s.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (service, opened);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text(label)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Geçmiş satırı: 40 dk süren, 31 en çok izleyicili biten yayın.
  LiveSession ended(String id, {List<Map<String, dynamic>>? featured}) => LiveSession.fromJson(liveSessionJson(
    id: id,
    status: 'ended',
    title: 'Yayın $id',
    startedAt: kLiveNow.subtract(const Duration(hours: 5)),
    endedAt: kLiveNow.subtract(const Duration(hours: 4, minutes: 20)),
    peak: 31,
    durationSeconds: 2400,
    messageCount: 12,
    featured: featured,
  ));

  testWidgets('Şimdi canlı: canlı yayınlar; dokununca izleyici; geçmiş ilk açılışta yüklenmez', (tester) async {
    final (s, opened) = await open(tester, FakeLiveService()..feed = feed());
    expect(find.text('Şimdi canlı (1)'), findsOneWidget);
    expect(find.text('Yeni sezon çaydanlıklar'), findsOneWidget);
    expect(find.text('12 izliyor'), findsOneWidget);
    expect(find.text('Demlik'), findsOneWidget);
    expect(find.text('Hafta sonu indirimi'), findsNothing, reason: 'biten yayınlar Geçmiş sekmesinde');
    expect(s.calls.where((c) => c.startsWith('history')), isEmpty);
    await tester.tap(find.text('Yeni sezon çaydanlıklar'));
    expect(opened, ['live-1']);
  });

  testWidgets('Geçmiş: sekmeye geçince yüklenir; süre, izleyici, öne çıkanlar; sayfalama; dokununca özet', (tester) async {
    final service = FakeLiveService()
      ..feed = feed()
      ..historyPages.addAll([
        LiveHistoryPage(
          rows: [
            ended('old-0', featured: [pinnedJson(id: 'p1', name: 'Demlik'), pinnedJson(id: 'p2', name: 'Bardak')]),
            for (var i = 1; i < 20; i++) ended('old-$i'),
          ],
          total: 21,
          days: 45,
        ),
        LiveHistoryPage(rows: [ended('old-20', featured: [pinnedJson(id: 'p3', name: 'Semaver')])], total: 21, days: 45),
      ]);
    final (s, opened) = await open(tester, service, size: const Size(420, 2400));
    await openTab(tester, 'Geçmiş');
    expect(s.calls, contains('history:0'));
    expect(find.text('Yayın old-0'), findsOneWidget);
    expect(find.text('Çay Evi · 40:00 · 31 izleyici · 4 sa önce'), findsWidgets);
    expect(find.text('2 ürün öne çıktı'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Daha fazla yükle (1 kaldı)'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Daha fazla yükle (1 kaldı)'));
    await tester.pump();
    await tester.pump();
    expect(s.calls, contains('history:20'));
    await tester.scrollUntilVisible(find.text('Yayın old-20'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Semaver'), findsOneWidget, reason: 'tek ürün adıyla');
    expect(find.text('Son 45 günün yayınları gösteriliyor.'), findsOneWidget);

    await tester.tap(find.text('Yayın old-20'));
    expect(opened, ['old-20']);
  });

  testWidgets('Geçmiş: boş durum; canlı yokken "Geçmiş yayınlara göz at"; doğrudan Geçmiş açılışı', (tester) async {
    final (s, _) = await open(tester, FakeLiveService());
    expect(find.text('Şu an canlı yayın yok'), findsOneWidget);
    await tester.tap(find.text('Geçmiş yayınlara göz at'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(s.calls, contains('history:0'));
    expect(find.text('Geçmiş yayın yok'), findsOneWidget);
    expect(find.text('Son 30 günde biten yayınlar burada listelenir.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final direct = FakeLiveService()..historyPages.add(LiveHistoryPage(rows: [ended('old-1')], total: 1));
    await open(tester, direct, initialTab: 1);
    expect(direct.calls, contains('history:0'), reason: 'ana sayfa kartından Geçmiş açılır');
    expect(find.text('Yayın old-1'), findsOneWidget);
  });

  testWidgets('Geçmiş: hata ve tekrar dene; yayın bitince açık geçmiş sessizce tazelenir', (tester) async {
    final service = FakeLiveService()
      ..feed = feed()
      ..historyError = const LiveException(LiveFailure.connection);
    final (s, _) = await open(tester, service, initialTab: 1);
    expect(find.text('Bağlantı kurulamadı; internetini kontrol edip tekrar dene.'), findsOneWidget);
    s
      ..historyError = null
      ..historyPages.add(LiveHistoryPage(rows: [ended('old-1')], total: 1));
    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Yayın old-1'), findsOneWidget);

    s.changes.add(change(PostgresChangeEvent.update, {'id': 'live-1', 'status': 'ended'}));
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(s.calls.where((c) => c == 'feed'), hasLength(2));
    expect(s.calls.where((c) => c == 'history:0'), hasLength(3), reason: 'hata + tekrar + bitiş tazelemesi');
  });

  testWidgets('sinyal güncellemesi yerinde; yeni yayın listeyi yeniden yükler', (tester) async {
    final (s, _) = await open(tester, FakeLiveService()..feed = feed());
    expect(s.calls.where((c) => c == 'feed'), hasLength(1));

    s.changes.add(change(PostgresChangeEvent.update, {'id': 'live-1', 'status': 'live', 'viewer_count': 20}));
    await tester.pump(Duration.zero);
    expect(find.text('20 izliyor'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(s.calls.where((c) => c == 'feed'), hasLength(1), reason: 'yalnız sayı değişti');

    // listede olmayan hazırlık kaydı yok sayılır
    s.changes.add(change(PostgresChangeEvent.update, {'id': 'x', 'status': 'scheduled'}));
    await tester.pump(const Duration(seconds: 2));
    expect(s.calls.where((c) => c == 'feed'), hasLength(1));

    // yeni yayın başladı → 1 sn içinde toplanıp tek yükleme
    s.changes.add(change(PostgresChangeEvent.update, {'id': 'new', 'status': 'live'}));
    s.changes.add(change(PostgresChangeEvent.insert, {'id': 'new2', 'status': 'scheduled'}));
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(s.calls.where((c) => c == 'feed'), hasLength(2));
  });

  testWidgets('boş liste ve hata durumu', (tester) async {
    await open(tester, FakeLiveService());
    expect(find.text('Şu an canlı yayın yok'), findsOneWidget);

    final failing = FakeLiveService()..feedError = const LiveException(LiveFailure.connection);
    await tester.pumpWidget(const SizedBox());
    await open(tester, failing);
    expect(find.text('Bağlantı kurulamadı; internetini kontrol edip tekrar dene.'), findsOneWidget);
    failing.feedError = null;
    failing.feed = feed();
    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Yeni sezon çaydanlıklar'), findsOneWidget);
  });
}
