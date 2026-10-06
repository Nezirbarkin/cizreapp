import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/screens/live_sessions_screen.dart';
import 'package:cizreapp/features/market/screens/my_live_streams_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/live_fakes.dart';
import '../helpers/test_fonts.dart';

/// Yayınlarım (2026-10-04): yayıncı kendi biten yayınlarını süre sınırı
/// olmadan görür; Canlı Yayınlar üst çubuğundan yalnız oturum açmış kişiye
/// açılır.
void main() {
  setUpAll(loadTestFonts);

  /// 40 dk süren, 31 en çok izleyicili, 4 sa 20 dk önce biten yayın.
  LiveSession ended(String id, {List<Map<String, dynamic>>? featured, Duration ago = const Duration(hours: 4, minutes: 20)}) =>
      LiveSession.fromJson(liveSessionJson(
        id: id,
        status: 'ended',
        title: 'Yayın $id',
        startedAt: kLiveNow.subtract(ago + const Duration(minutes: 40)),
        endedAt: kLiveNow.subtract(ago),
        peak: 31,
        durationSeconds: 2400,
        messageCount: 12,
        featured: featured,
      ));

  Future<(FakeLiveService, List<String>)> open(WidgetTester tester, FakeLiveService service, {Size size = const Size(420, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MyLiveStreamsScreen(
          service: service,
          now: () => kLiveNow,
          openSession: (_, s) => opened.add(s.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (service, opened);
  }

  testWidgets('kendi biten yayınları: bilgi bandı, süre/izleyici, öne çıkanlar; 24 saati geçen de durur', (tester) async {
    final service = FakeLiveService()
      ..myHistoryPages.add(LiveHistoryPage(
        rows: [
          ended('mine-1', featured: [pinnedJson(id: 'p1', name: 'Demlik'), pinnedJson(id: 'p2', name: 'Bardak')]),
          ended('mine-2', ago: const Duration(days: 40)),
        ],
        total: 2,
      ));
    final (s, opened) = await open(tester, service);
    expect(s.calls, ['mine:0']);
    expect(find.text('Yayınlarım'), findsOneWidget);
    expect(find.byKey(const ValueKey('my-live-info')), findsOneWidget);
    expect(find.text('Yayın mine-1'), findsOneWidget);
    expect(find.text('Çay Evi · 40:00 · 31 izleyici · 4 sa önce'), findsOneWidget);
    expect(find.text('2 ürün öne çıktı'), findsOneWidget);
    expect(find.text('Çay Evi · 40:00 · 31 izleyici · 40 gün önce'), findsOneWidget, reason: 'süre sınırı yok');
    expect(find.text('Toplam 2 yayın'), findsOneWidget);

    await tester.tap(find.text('Yayın mine-2'));
    expect(opened, ['mine-2'], reason: 'dokununca yayının özeti');
  });

  testWidgets('sayfalama: daha fazla yükle sonraki sayfayı ekler', (tester) async {
    final service = FakeLiveService()
      ..myHistoryPages.addAll([
        LiveHistoryPage(rows: [for (var i = 0; i < 20; i++) ended('m$i')], total: 21),
        LiveHistoryPage(rows: [ended('m20', ago: const Duration(days: 3))], total: 21),
      ]);
    final (s, _) = await open(tester, service, size: const Size(420, 2400));
    await tester.scrollUntilVisible(find.text('Daha fazla yükle (1 kaldı)'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Daha fazla yükle (1 kaldı)'));
    await tester.pump();
    await tester.pump();
    expect(s.calls, ['mine:0', 'mine:20']);
    await tester.scrollUntilVisible(find.text('Yayın m20'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Toplam 21 yayın'), findsOneWidget);
  });

  testWidgets('boş durum ve hata + tekrar dene', (tester) async {
    await open(tester, FakeLiveService());
    expect(find.text('Henüz biten bir yayının yok'), findsOneWidget);
    expect(
      find.text('Yayınların bitince burada kalır. Ana sayfada biten yayın yalnız 24 saat görünür.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    final failing = FakeLiveService()..myHistoryError = const LiveException(LiveFailure.connection);
    final (s, _) = await open(tester, failing);
    expect(find.text('Bağlantı kurulamadı; internetini kontrol edip tekrar dene.'), findsOneWidget);
    s
      ..myHistoryError = null
      ..myHistoryPages.add(LiveHistoryPage(rows: [ended('mine-1')], total: 1));
    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Yayın mine-1'), findsOneWidget);
  });

  testWidgets('Canlı Yayınlar: "Yayınlarım" yalnız oturum açmış kişiye; dokununca açılır', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var openedMine = 0;
    Future<void> pump(FakeLiveService service) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LiveSessionsScreen(
            key: UniqueKey(),
            service: service,
            now: () => kLiveNow,
            openMyStreams: (_) => openedMine++,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    await pump(FakeLiveService(userId: 'user-9'));
    expect(find.byTooltip('Yayınlarım'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-my-streams')));
    expect(openedMine, 1);

    await pump(FakeLiveService(userId: null));
    expect(find.byTooltip('Yayınlarım'), findsNothing, reason: 'misafirin yayını yok');
  });
}
