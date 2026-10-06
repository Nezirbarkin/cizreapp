import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/screens/live_host_screen.dart';
import 'package:cizreapp/features/market/screens/live_sessions_screen.dart';
import 'package:cizreapp/features/market/services/live_shopping_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../helpers/live_fakes.dart';
import '../helpers/test_fonts.dart';

/// Görev 4.3 — yönetim kontrollerinin satıcı/izleyici tarafı: yeni hata
/// kodları, izin kaldırma notu, "canlı yayın kapalı" bilgisi.
void main() {
  setUpAll(loadTestFonts);

  test('yönetim kodları LiveFailure\'a; yalnız izin kaldırmada not mesaja eklenir', () {
    expect(LiveFailure.fromCode('LIVE_DISABLED'), LiveFailure.disabled);
    expect(LiveFailure.fromCode('LIVE_REVOKED'), LiveFailure.revoked);
    expect(LiveFailure.fromCode('LIVE_NOT_PERMITTED'), LiveFailure.notPermitted);

    final revoked = LiveShoppingService.toLiveException(
      const PostgrestException(message: 'x', code: 'P0001', hint: 'LIVE_REVOKED', details: 'Kurallara aykırı yayın'),
    );
    expect(revoked.failure, LiveFailure.revoked);
    expect(
      revoked.message,
      'Mağazanın canlı yayın izni yönetim tarafından kaldırıldı.\n\nYönetim notu: Kurallara aykırı yayın',
    );

    final withoutNote = LiveShoppingService.toLiveException(
      const PostgrestException(message: 'x', code: 'P0001', hint: 'LIVE_REVOKED', details: ''),
    );
    expect(withoutNote.message, LiveFailure.revoked.message);

    final disabled = LiveShoppingService.toLiveException(
      const PostgrestException(message: 'x', code: 'P0001', hint: 'LIVE_DISABLED', details: 'yok sayılır'),
    );
    expect(disabled.message, 'Canlı yayın şu anda kapalı.');
  });

  test('akış: "enabled" yoksa açık sayılır', () {
    expect(LiveFeed.fromJson(const {'live': [], 'recent': []}).enabled, isTrue);
    expect(LiveFeed.fromJson(const {'live': [], 'recent': [], 'enabled': false}).enabled, isFalse);
  });

  Future<void> openSessions(WidgetTester tester, FakeLiveService service) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LiveSessionsScreen(service: service, now: () => kLiveNow, openSession: (_, __) {}),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('izleyici listesi: yönetim kapattıysa boş ekran ve bant bunu söyler', (tester) async {
    await openSessions(tester, FakeLiveService()..feed = const LiveFeed(enabled: false));
    expect(find.text('Canlı yayınlar şu anda kapalı'), findsOneWidget);
    expect(find.text('Şu an canlı yayın yok'), findsNothing);

    // Kapalıyken süren yayın bitene kadar listelenir; üstte bilgi bandı
    final service = FakeLiveService()
      ..feed = LiveFeed(
        enabled: false,
        live: [
          LiveSession.fromJson(liveSessionJson(
            id: 'live-1',
            status: 'live',
            isLive: true,
            title: 'Son yayın',
            startedAt: kLiveNow.subtract(const Duration(minutes: 5)),
          )),
        ],
      );
    await tester.pumpWidget(const SizedBox());
    await openSessions(tester, service);
    expect(find.byKey(const ValueKey('live-feed-disabled')), findsOneWidget);
    expect(find.text('Son yayın'), findsOneWidget);
  });

  Future<void> openHost(WidgetTester tester, FakeLiveService service) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LiveHostScreen(
          key: UniqueKey(),
          shopId: 'shop-1',
          shopName: 'Çay Evi',
          service: service,
          engineFactory: FakeLiveEngine.new,
          now: () => kLiveNow,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('satıcı: izni kaldırılmışsa not gösterilir, tekrar dene yok; kamera açılmaz', (tester) async {
    final service = FakeLiveService()
      ..createError = const PostgrestException(
        message: 'x',
        code: 'P0001',
        hint: 'LIVE_REVOKED',
        details: 'Kurallara aykırı yayın',
      );
    await openHost(tester, service);

    expect(
      find.text('Mağazanın canlı yayın izni yönetim tarafından kaldırıldı.\n\nYönetim notu: Kurallara aykırı yayın'),
      findsOneWidget,
    );
    expect(find.text('Tekrar dene'), findsNothing);
    expect(find.text('Kapat'), findsOneWidget);
    expect(service.calls, ['create'], reason: 'izin yokken anahtar istenmez');
  });

  testWidgets('satıcı: modül kapalı / yalnız izinliler mesajları', (tester) async {
    await openHost(
      tester,
      FakeLiveService()..createError = const PostgrestException(message: 'x', code: 'P0001', hint: 'LIVE_DISABLED'),
    );
    expect(find.text('Canlı yayın şu anda kapalı.'), findsOneWidget);

    await openHost(
      tester,
      FakeLiveService()
        ..createError = const PostgrestException(message: 'x', code: 'P0001', hint: 'LIVE_NOT_PERMITTED'),
    );
    expect(
      find.text('Canlı yayın şu an yalnız izin verilen mağazalara açık. İzin için yönetimle iletişime geç.'),
      findsOneWidget,
    );
  });
}
