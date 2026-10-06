import 'dart:convert';

import 'package:cizreapp/ilanlar/models/ilan_models.dart';
import 'package:cizreapp/ilanlar/services/ilan_service.dart';
import 'package:cizreapp/ilanlar/utils/ilan_ui.dart';
import 'package:cizreapp/ilanlar/widgets/ilan_card.dart';
import 'package:cizreapp/ilanlar/widgets/ilan_expiry_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.9 — ilan süresi: etkin durum (cron gecikse bile), uzatma koşulu,
/// sahibin paneli ve listedeki "Süreyi Uzat" düğmesi, uzatma RPC'si.

final _now = DateTime(2026, 9, 28, 12);

Ilan _ilan({IlanStatus status = IlanStatus.published, DateTime? expiresAt}) => Ilan(
  id: 'ilan-1',
  ownerId: 'owner-1',
  categoryId: 'cat-1',
  title: 'Satılık bisiklet',
  description: 'Az kullanılmış, bakımlı dağ bisikleti',
  status: status,
  city: 'Şırnak',
  district: 'Cizre',
  createdAt: _now.subtract(const Duration(days: 55)),
  viewCount: 12,
  favoriteCount: 3,
  expiresAt: expiresAt,
);

void main() {
  setUpAll(loadTestFonts);

  group('IlanUi', () {
    test('bitişi geçmiş yayındaki ilan "Süresi Doldu" sayılır (cron gecikse de)', () {
      final past = _ilan(expiresAt: _now.subtract(const Duration(hours: 2)));
      expect(IlanUi.isExpired(past, _now), isTrue);
      expect(IlanUi.effectiveStatus(past, _now), IlanStatus.expired);
      expect(IlanUi.isExpired(_ilan(status: IlanStatus.expired), _now), isTrue);
      final live = _ilan(expiresAt: _now.add(const Duration(days: 20)));
      expect(IlanUi.effectiveStatus(live, _now), IlanStatus.published);
      expect(IlanUi.effectiveStatus(_ilan(status: IlanStatus.sold, expiresAt: _now.subtract(const Duration(days: 1))), _now),
          IlanStatus.sold, reason: 'satılan ilan süresi dolmuş sayılmaz');
    });

    test('uzatma: dolmuşsa her zaman, yayındaysa son 7 günde', () {
      expect(IlanUi.canExtend(_ilan(status: IlanStatus.expired), _now), isTrue);
      expect(IlanUi.canExtend(_ilan(expiresAt: _now.add(const Duration(days: 6))), _now), isTrue);
      expect(IlanUi.canExtend(_ilan(expiresAt: _now.add(const Duration(days: 7))), _now), isTrue);
      expect(IlanUi.canExtend(_ilan(expiresAt: _now.add(const Duration(days: 8))), _now), isFalse);
      expect(IlanUi.canExtend(_ilan(status: IlanStatus.pending, expiresAt: _now.add(const Duration(days: 1))), _now), isFalse);
      expect(IlanUi.canExtend(_ilan(), _now), isFalse, reason: 'süresiz ilan');
    });

    test('tarih ve sunucu hata ipuçları', () {
      expect(IlanUi.longDate(DateTime(2026, 11, 27, 9)), '27 Kasım 2026');
      String msg(String hint) => IlanUi.friendlyError(PostgrestException(message: 'x', code: 'P0001', hint: hint));
      expect(msg('ILAN_TOO_EARLY'), 'Süreyi, bitimine 7 günden az kalınca uzatabilirsin.');
      expect(msg('ILAN_NOT_EXTENDABLE'), 'Bu ilanın süresi uzatılamaz.');
      expect(
        IlanUi.friendlyError(const PostgrestException(message: 'Aktif ilan limitine ulaştın', hint: 'ILAN_ACTIVE_LIMIT')),
        'Aktif ilan limitinize ulaştınız.',
      );
    });
  });

  group('IlanExpiryPanel', () {
    Future<int> pump(WidgetTester tester, Ilan ilan) async {
      var taps = 0;
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: IlanExpiryPanel(ilan: ilan, extensionDays: 60, now: () => _now, onExtend: () => taps++),
            ),
          ),
        ),
      );
      final button = find.byWidgetPredicate((w) => w is FilledButton);
      if (button.evaluate().isNotEmpty) await tester.tap(button);
      return taps;
    }

    testWidgets('süresi dolmuş: Yeniden Yayınla (60 gün)', (tester) async {
      final taps = await pump(tester, _ilan(status: IlanStatus.expired, expiresAt: DateTime(2026, 9, 20, 10)));
      expect(find.text('Süresi doldu'), findsOneWidget);
      expect(find.text('İlan 20 Eylül 2026 tarihinde yayından kalktı.'), findsOneWidget);
      expect(find.text('Yeniden Yayınla (60 gün)'), findsOneWidget);
      expect(taps, 1);
    });

    testWidgets('son 7 gün: Süreyi Uzat', (tester) async {
      final taps = await pump(tester, _ilan(expiresAt: _now.add(const Duration(days: 3, hours: 2))));
      expect(find.text('Süreyi Uzat (60 gün)'), findsOneWidget);
      expect(taps, 1);
    });

    testWidgets('daha uzun süre: yalnız bitiş bilgisi, düğme yok; satılan ilanda panel yok', (tester) async {
      final taps = await pump(tester, _ilan(expiresAt: DateTime(2026, 10, 30, 10)));
      expect(find.text('Yayın bitişi: 30 Ekim 2026'), findsOneWidget);
      expect(find.text('Bitimine 7 günden az kalınca süreyi uzatabilirsin.'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsNothing);
      expect(taps, 0);

      await pump(tester, _ilan(status: IlanStatus.sold, expiresAt: DateTime(2026, 9, 1)));
      expect(find.text('Süresi doldu'), findsNothing);
    });
  });

  testWidgets('İlanlarım kartı: süresi geçen "Süresi Doldu" rozeti ve Yeniden Yayınla düğmesi', (tester) async {
    var extends_ = 0;
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 364,
            child: IlanCard(
              ilan: _ilan(expiresAt: DateTime.now().subtract(const Duration(hours: 1))),
              onTap: () {},
              showStatusBadge: true,
              onExtend: () => extends_++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Süresi Doldu'), findsOneWidget);
    await tester.tap(find.text('Yeniden Yayınla'));
    expect(extends_, 1);
    expect(tester.takeException(), isNull, reason: 'kart 364 yüksekliğe sığar');
  });

  test('uzatma RPC\'si: ilan kimliğiyle, yeni bitişi döner', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://test.invalid',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((req) async {
        requests.add(req);
        return http.Response(
          jsonEncode({'status': 'published', 'expires_at': '2026-11-27T12:00:00+00:00', 'republished': true}),
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final until = await IlanService(client: client).extendMyIlan('ilan-9');
    expect(requests.single.url.path, '/rest/v1/rpc/extend_my_ilan');
    expect(jsonDecode(requests.single.body), {'p_ilan_id': 'ilan-9'});
    expect(until, DateTime.utc(2026, 11, 27, 12));
  });
}
