import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/screens/live_session_route_screen.dart';
import 'package:cizreapp/features/market/widgets/live_home_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/live_fakes.dart';
import '../helpers/test_fonts.dart';

/// Canlı yayın ek özellikleri (2026-09-28): yanıt modelleri, ana sayfadaki
/// (Şehiriçi kartının yanındaki) canlı yayın kartı ve bildirimden açılan
/// `/live/<id>` rotası.
void main() {
  setUpAll(loadTestFonts);
  setUp(LiveHomeStoryCard.resetCache);

  group('modeller', () {
    test('geçmiş sayfası: satırlar, öne çıkan ürünler, süre, mesaj; gün varsayılanı', () {
      final page = LiveHistoryPage.fromJson({
        'total': 3,
        'days': 45,
        'rows': [
          liveSessionJson(
            id: 'e1',
            status: 'ended',
            durationSeconds: 754,
            messageCount: 9,
            featured: [
              pinnedJson(id: 'p1', name: 'Demlik', price: 250, discount: 200),
              {'name': 'kimliksiz atlanır'},
            ],
          ),
        ],
      });
      expect(page.total, 3);
      expect(page.days, 45);
      final row = page.rows.single;
      expect(row.durationSeconds, 754);
      expect(row.messageCount, 9);
      expect(row.featuredProducts.map((p) => p.id), ['p1']);
      expect(row.featuredProducts.single.hasDiscount, isTrue);
      expect(LiveHistoryPage.fromJson(const {}).days, 30);
    });

    test('ana sayfa kartı: canlı önce, yoksa son biten; kapalıyken görünmez', () {
      final live = LiveHomeCard.fromJson({
        'enabled': true,
        'live_count': 2,
        'live': liveSessionJson(id: 'l1', status: 'live', isLive: true),
        'last': liveSessionJson(id: 'e1', status: 'ended'),
      });
      expect(live.isLive, isTrue);
      expect(live.session!.id, 'l1');
      expect(live.isVisible, isTrue);

      final last = LiveHomeCard.fromJson({'enabled': true, 'live_count': 0, 'live': null, 'last': liveSessionJson(id: 'e1', status: 'ended')});
      expect(last.isLive, isFalse);
      expect(last.session!.id, 'e1');

      expect(LiveHomeCard.fromJson({'enabled': false}).isVisible, isFalse);
      expect(LiveHomeCard.fromJson({'enabled': true, 'live': null, 'last': null}).isVisible, isFalse);
    });

    test('abonelik ve başlatma yanıtındaki bildirim sayısı', () {
      final sub = LiveSubscription.fromJson({'subscribed': true, 'subscribers': 7}, shopId: 'shop-9');
      expect(sub.shopId, 'shop-9');
      expect(sub.subscribed, isTrue);
      expect(sub.subscribers, 7);

      final started = LiveSession.fromJson({...liveSessionJson(status: 'live'), 'notified': 12});
      expect(started.notified, 12);
      expect(LiveSession.fromJson(liveSessionJson(status: 'live')).notified, isNull);
    });

    test('paylaşım metni: canlı ve biten yayın', () {
      final live = LiveSession.fromJson(liveSessionJson(status: 'live', isLive: true));
      expect(liveShareText(live), startsWith('🔴 Çay Evi şu an CizreApp\'te canlı yayında!\n"Çay Evi canlı yayında"'));
      final ended = LiveSession.fromJson(liveSessionJson(status: 'ended'));
      expect(liveShareText(ended), startsWith('🎥 Çay Evi CizreApp\'te canlı yayın yaptı.'));
    });
  });

  group('ana sayfa kartı', () {
    Future<List<LiveHomeCard>> pumpCard(WidgetTester tester, FakeLiveService service, {bool compact = true}) async {
      tester.view.physicalSize = const Size(420, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <LiveHomeCard>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            // Hikâye satırındaki gibi: yatay liste, kompakt 95 px / tam 200 px.
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: compact ? 95 : 200,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    LiveHomeStoryCard(
                      service: service,
                      compact: compact,
                      width: 130,
                      onOpen: (_, card) => opened.add(card),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return opened;
    }

    LiveHomeCard card({int liveCount = 1, bool live = true, Duration endedAgo = const Duration(hours: 2)}) {
      final now = DateTime.now().toUtc();
      return LiveHomeCard(
        enabled: true,
        liveCount: liveCount,
        live: live
            ? LiveSession.fromJson(liveSessionJson(id: 'l1', status: 'live', isLive: true, viewers: 9, startedAt: now))
            : null,
        last: LiveSession.fromJson(liveSessionJson(
          id: 'e1',
          status: 'ended',
          title: 'Hafta sonu indirimi',
          startedAt: now.subtract(endedAgo + const Duration(minutes: 30)),
          endedAt: now.subtract(endedAgo),
        )),
      );
    }

    testWidgets('kapalıysa ya da yayın yoksa yer kaplamaz', (tester) async {
      await pumpCard(tester, FakeLiveService()..homeCard = const LiveHomeCard(enabled: false));
      expect(find.byKey(const ValueKey('live-home-card')), findsNothing);
      expect(tester.getSize(find.byType(LiveHomeStoryCard, skipOffstage: false)).width, 0, reason: 'satırda yer kaplamaz');

      LiveHomeStoryCard.resetCache();
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, FakeLiveService()..homeCard = const LiveHomeCard(enabled: true));
      expect(find.byKey(const ValueKey('live-home-card')), findsNothing);
    });

    testWidgets('canlı yayın: CANLI rozeti ve mağaza; dokununca açılır', (tester) async {
      final opened = await pumpCard(tester, FakeLiveService()..homeCard = card());
      expect(find.text('CANLI'), findsOneWidget);
      expect(find.text('Çay Evi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-home-card')));
      expect(opened.single.live!.id, 'l1');
    });

    testWidgets('birden çok canlı yayın sayıyla yazılır', (tester) async {
      await pumpCard(tester, FakeLiveService()..homeCard = card(liveCount: 3));
      expect(find.text('3 canlı yayın'), findsOneWidget);
    });

    testWidgets('yayın bitince son yayın kalır (kompakt ve tam görünüm)', (tester) async {
      final service = FakeLiveService()..homeCard = card(live: false);
      final opened = await pumpCard(tester, service);
      expect(find.text('SON YAYIN'), findsOneWidget);
      expect(find.text('CANLI'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('live-home-card')));
      expect(opened.single.live, isNull);
      expect(opened.single.last!.id, 'e1');

      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, service, compact: false);
      expect(find.text('Son yayın · 2 sa önce'), findsOneWidget);
      expect(find.text('Hafta sonu indirimi'), findsOneWidget);
    });

    testWidgets('60 sn önbellek: satır yeniden kurulunca yeniden istenmez', (tester) async {
      final service = FakeLiveService()..homeCard = card();
      await pumpCard(tester, service);
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, service);
      expect(find.text('CANLI'), findsOneWidget, reason: 'önbellekten hemen çizilir');
      expect(service.calls.where((c) => c == 'home'), hasLength(1));

      LiveHomeStoryCard.resetCache();
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, service);
      expect(service.calls.where((c) => c == 'home'), hasLength(2));
    });
  });

  group('/live/<id> rotası', () {
    Future<void> pumpRoute(WidgetTester tester, FakeLiveService service) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: LiveSessionRouteScreen(
            sessionId: 'sess-1',
            service: service,
            viewerBuilder: (session) => Text('İZLEYİCİ ${session.id} ${session.status}'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('yayını yükleyip izleyiciyi açar (bitmişse özet izleyicide)', (tester) async {
      final service = FakeLiveService()..detail = LiveSession.fromJson(liveSessionJson(status: 'ended'));
      await pumpRoute(tester, service);
      expect(service.calls, ['detail']);
      expect(find.text('İZLEYİCİ sess-1 ended'), findsOneWidget);
    });

    testWidgets('kayıt yoksa açıklama; tekrar dene', (tester) async {
      final service = FakeLiveService();
      await pumpRoute(tester, service);
      expect(find.text(LiveFailure.notFound.message), findsOneWidget);

      service.detail = LiveSession.fromJson(liveSessionJson(status: 'live', isLive: true));
      await tester.tap(find.text('Tekrar dene'));
      await tester.pump();
      await tester.pump();
      expect(find.text('İZLEYİCİ sess-1 live'), findsOneWidget);
    });
  });
}
