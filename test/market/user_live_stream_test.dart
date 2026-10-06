import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/admin/services/admin_live_service.dart';
import 'package:cizreapp/features/market/screens/live_host_screen.dart';
import 'package:cizreapp/features/market/screens/live_sessions_screen.dart';
import 'package:cizreapp/features/market/screens/live_viewer_screen.dart';
import 'package:cizreapp/features/market/services/live_shopping_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../helpers/live_fakes.dart';
import '../helpers/test_fonts.dart';

/// Kullanıcı (mağazasız) canlı yayını: model, "Yayın aç" düğmesi, yayıncı ve
/// izleyici ekranları, yönetim modelleri. Sunucu kuralları canlıda
/// `supabase/tests/manual/user_live_streams_test.sql` ile doğrulanır.
void main() {
  setUpAll(loadTestFonts);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('model', () {
    test('kullanıcı yayını: tür, görünen ad ve görsel yayıncıdan', () {
      final user = LiveSession.fromJson(liveSessionJson(user: true, hostName: 'zeynep'));
      expect(user.isUserStream, isTrue);
      expect(user.shopId, isEmpty);
      expect(user.displayName, 'zeynep');
      expect(user.hostUserId, 'host-9');
      expect(liveShareText(user), contains('zeynep'));

      final shop = LiveSession.fromJson(liveSessionJson());
      expect(shop.isUserStream, isFalse);
      expect(shop.displayName, 'Çay Evi');
    });

    test('Realtime satırı yayıncı alanlarını korur', () {
      final user = LiveSession.fromJson(liveSessionJson(user: true, status: 'live', isLive: true));
      final updated = user.applyRow({'viewer_count': 4, 'status': 'live', 'last_heartbeat_at': kLiveNow.toIso8601String()});
      expect(updated.displayName, 'zeynep');
      expect(updated.viewerCount, 4);
    });

    test('akış: "Yayın aç" yalnız erişim ok ve modül açıkken', () {
      expect(LiveFeed.fromJson({'my_access': 'ok'}).canStartUserStream, isTrue);
      expect(LiveFeed.fromJson({'my_access': 'ok', 'enabled': false}).canStartUserStream, isFalse);
      expect(LiveFeed.fromJson({'my_access': 'LIVE_USER_NOT_PERMITTED'}).canStartUserStream, isFalse);
      expect(LiveFeed.fromJson({'my_access': 'AUTH_REQUIRED'}).canStartUserStream, isFalse);
      expect(const LiveFeed().canStartUserStream, isFalse, reason: 'eski sunucu yanıtı: düğme yok');
    });

    test('yeni sunucu kodları Türkçe hataya; iptal notu DETAIL\'den', () {
      expect(LiveFailure.fromCode('LIVE_USERS_OFF'), LiveFailure.usersOff);
      expect(LiveFailure.fromCode('LIVE_USER_NOT_PERMITTED'), LiveFailure.userNotPermitted);
      expect(LiveFailure.fromCode('LIVE_ACCOUNT_INACTIVE'), LiveFailure.accountInactive);
      final revoked = LiveShoppingService.toLiveException(
        const PostgrestException(message: 'x', code: 'P0001', hint: 'LIVE_USER_REVOKED', details: 'Şikayet'),
      );
      expect(revoked.failure, LiveFailure.userRevoked);
      expect(revoked.message, contains('Yönetim notu: Şikayet'));
    });

    test('yönetim: kullanıcı satırı, erişim kodları ve kullanıcı modu', () {
      final page = AdminLiveUsersPage.fromJson({
        'total': 1,
        'rows': [
          {
            'user_id': 'u1',
            'username': 'zeynep',
            'full_name': 'Zeynep K.',
            'permission': 'revoked',
            'note': 'Şikayet',
            'effective': 'LIVE_USER_REVOKED',
            'session_count': 3,
            'live_session_id': 's1',
          },
        ],
        'summary': {'granted': 2, 'revoked': 1},
        'settings': {'enabled': true, 'user_mode': 'invite'},
      });
      final row = page.rows.single;
      expect(row.displayName, '@zeynep');
      expect(row.effective, LiveShopAccess.revoked);
      expect(row.isLiveNow, isTrue);
      expect(page.granted, 2);
      expect(page.settings.userMode, 'invite');
      expect(LiveShopAccess.fromCode('LIVE_USERS_OFF'), LiveShopAccess.usersOff);
      expect(LiveShopAccess.fromCode('LIVE_USER_NOT_PERMITTED'), LiveShopAccess.notPermitted);
      expect(AdminLiveSettings.fromJson({}).userMode, 'open');

      final session = AdminLiveSessionRow.fromJson(liveSessionJson(user: true, status: 'ended', endedReason: 'host'));
      expect(session.endedReasonLabel, 'Yayıncı bitirdi');
    });
  });

  group('Canlı Yayınlar › Yayın aç', () {
    Future<List<String>> open(WidgetTester tester, FakeLiveService service) async {
      phone(tester);
      final started = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LiveSessionsScreen(
            service: service,
            now: () => kLiveNow,
            openSession: (_, s) => started.add('open:${s.id}'),
            startStream: (_) async => started.add('start'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return started;
    }

    testWidgets('erişim ok: düğme görünür, dokununca yayıncı ekranı; kullanıcı yayını yayıncı adıyla', (tester) async {
      final service = FakeLiveService(userId: 'user-1')
        ..feed = LiveFeed(
          myAccess: 'ok',
          live: [
            LiveSession.fromJson(liveSessionJson(
              id: 'u-live',
              status: 'live',
              isLive: true,
              user: true,
              title: 'Akşam sohbeti',
              startedAt: kLiveNow,
            )),
          ],
        );
      final started = await open(tester, service);
      expect(find.text('zeynep'), findsOneWidget);
      expect(find.text('Akşam sohbeti'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400)); // FAB giriş animasyonu
      await tester.tap(find.byKey(const ValueKey('live-start-user-stream')));
      await tester.pump();
      expect(started, ['start']);
      expect(service.calls.where((c) => c == 'feed'), hasLength(2), reason: 'dönünce akış yenilenir');
    });

    testWidgets('izin yok / misafir: düğme yok', (tester) async {
      await open(tester, FakeLiveService(userId: 'user-1')..feed = const LiveFeed(myAccess: 'LIVE_USER_NOT_PERMITTED'));
      expect(find.byKey(const ValueKey('live-start-user-stream')), findsNothing);
      await open(tester, FakeLiveService(userId: null)..feed = const LiveFeed(myAccess: 'AUTH_REQUIRED'));
      expect(find.byKey(const ValueKey('live-start-user-stream')), findsNothing);
    });
  });

  group('yayıncı ekranı (kullanıcı)', () {
    Future<(FakeLiveService, FakeLiveEngine)> open(WidgetTester tester, {FakeLiveService? service}) async {
      phone(tester);
      final s = service ?? FakeLiveService(userId: 'host-9');
      final e = FakeLiveEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: LiveHostScreen(
            key: UniqueKey(),
            shopName: '',
            service: s,
            engineFactory: () => e,
            now: () => kLiveNow.add(const Duration(minutes: 1)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return (s, e);
    }

    testWidgets('kullanıcı kaydı hazırlanır; ürün yüklenmez, ürün düğmesi yok; yayına başlar', (tester) async {
      final (s, e) = await open(tester);
      expect(s.calls, ['create:user', 'token:host']);
      expect(find.widgetWithText(TextField, 'Canlı yayındayım'), findsOneWidget);
      expect(find.textContaining('takipçilerine bildirim gider'), findsOneWidget);

      await tester.tap(find.text('Yayına Başla'));
      await tester.pump();
      e.events!.onJoined!();
      await tester.pump();
      await tester.pump();
      expect(s.calls, containsAllInOrder(['create:user', 'token:host', 'start']));
      expect(find.text('CANLI · 1:00'), findsOneWidget);
      expect(find.byTooltip('Ürün göster'), findsNothing);
      expect(find.byTooltip('Kamerayı çevir'), findsOneWidget);
    });

    testWidgets('başlık değişince kullanıcı kaydı güncellenir', (tester) async {
      final (s, _) = await open(tester);
      await tester.enterText(find.byType(TextField), 'Gece sohbeti');
      await tester.tap(find.text('Yayına Başla'));
      await tester.pump();
      expect(s.titles, ['Canlı yayındayım', 'Gece sohbeti']);
      expect(s.calls.where((c) => c == 'create'), isEmpty, reason: 'mağaza RPC\'si çağrılmaz');
    });

    testWidgets('izin yoksa açıklayıcı hata', (tester) async {
      await open(
        tester,
        service: FakeLiveService(userId: 'host-9')
          ..createError = const PostgrestException(message: 'x', code: 'P0001', hint: 'LIVE_USER_NOT_PERMITTED'),
      );
      expect(find.text(LiveFailure.userNotPermitted.message), findsOneWidget);
    });
  });

  group('izleyici ekranı (kullanıcı yayını)', () {
    Future<(FakeLiveService, FakeLiveEngine, List<String>)> open(WidgetTester tester, LiveSession session) async {
      phone(tester);
      final s = FakeLiveService(userId: 'user-1')..credentials = kViewerCredentials;
      final e = FakeLiveEngine();
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LiveViewerScreen(
            key: UniqueKey(),
            session: session,
            service: s,
            engineFactory: () => e,
            openShop: (_, id) => opened.add('shop:$id'),
            openProfile: (_, id) => opened.add('profile:$id'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return (s, e, opened);
    }

    testWidgets('üst bilgi yayıncının profilini açar; abonelik düğmesi yok; "Yayıncı" metinleri', (tester) async {
      final session = LiveSession.fromJson(liveSessionJson(
        status: 'live',
        isLive: true,
        user: true,
        title: 'Akşam sohbeti',
        startedAt: kLiveNow,
      ));
      final (s, e, opened) = await open(tester, session);
      e.events!.onJoined!();
      await tester.pump();
      expect(find.text('Yayıncının görüntüsü bekleniyor…'), findsOneWidget);
      expect(find.text('zeynep'), findsOneWidget);
      expect(s.calls.where((c) => c.startsWith('sub:')), isEmpty);
      await tester.tap(find.text('zeynep'));
      await tester.pump();
      expect(opened, ['profile:host-9']);
    });

    testWidgets('biten kullanıcı yayını: profiline git', (tester) async {
      final session = LiveSession.fromJson(liveSessionJson(
        status: 'ended',
        user: true,
        startedAt: kLiveNow.subtract(const Duration(minutes: 30)),
        endedAt: kLiveNow,
        endedReason: 'host',
      ));
      final (_, _, opened) = await open(tester, session);
      expect(find.text('Yayıncı yayını bitirdi.'), findsOneWidget);
      await tester.tap(find.text('zeynep profiline git'));
      await tester.pump();
      expect(opened, ['profile:host-9']);
    });
  });
}
