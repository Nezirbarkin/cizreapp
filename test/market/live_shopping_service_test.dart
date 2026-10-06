import 'dart:convert';

import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/services/live_shopping_service.dart';
import 'package:cizreapp/features/market/widgets/live_stream_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/live_fakes.dart';

/// Görev 3.4 — canlı yayın servis/model: RPC adları ve parametreleri, Edge
/// Function çağrısı, hata eşlemesi, Realtime satırının uygulanması.

final List<http.Request> _requests = [];

void main() {
  late Object? Function(http.Request req) respond;
  int status = 200;

  SupabaseClient client() => SupabaseClient(
    'https://test.invalid',
    'test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((req) async {
      _requests.add(req);
      return http.Response(
        jsonEncode(respond(req)),
        status,
        request: req,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  setUp(() {
    _requests.clear();
    status = 200;
    respond = (_) => liveSessionJson(status: 'live', isLive: true, startedAt: kLiveNow);
  });

  Map<String, dynamic> body(int i) => jsonDecode(_requests[i].body) as Map<String, dynamic>;

  group('RPC çağrıları', () {
    test('keşfet: tek RPC, canlı ve biten listeler', () async {
      respond = (_) => {
        'live': [liveSessionJson(id: 'a', status: 'live', isLive: true, viewers: 4)],
        'recent': [liveSessionJson(id: 'b', status: 'ended', endedReason: 'timeout')],
      };
      final feed = await LiveShoppingService(client: client()).fetchFeed();
      expect(_requests.single.url.path, '/rest/v1/rpc/live_sessions_feed');
      expect(body(0), {'p_limit': 30});
      expect(feed.live.single.viewerCount, 4);
      expect(feed.live.single.isLiveNow, isTrue);
      expect(feed.recent.single.endedReason, 'timeout');
    });

    test('hazırla / başlat / sinyal / sabitle / bitir', () async {
      final service = LiveShoppingService(client: client());
      respond = (_) => {...liveSessionJson(), 'resumed': true};
      final created = await service.createSession(shopId: 'shop-1', title: 'Başlık', description: 'Açıklama');
      expect(created.resumed, isTrue);
      expect(_requests.last.url.path, '/rest/v1/rpc/live_create_session');
      expect(body(0), {'p_shop_id': 'shop-1', 'p_title': 'Başlık', 'p_description': 'Açıklama'});

      respond = (_) => liveSessionJson(status: 'live', isLive: true, startedAt: kLiveNow);
      expect((await service.startLive('sess-1')).isLive, isTrue);
      expect(_requests.last.url.path, '/rest/v1/rpc/start_live_session');

      respond = (_) => {'status': 'live', 'viewer_count': 7, 'peak_viewer_count': 9};
      final beat = await service.heartbeat('sess-1', 7);
      expect(_requests.last.url.path, '/rest/v1/rpc/live_session_heartbeat');
      expect(jsonDecode(_requests.last.body), {'p_session_id': 'sess-1', 'p_viewer_count': 7});
      expect((beat.isEnded, beat.peakViewerCount), (false, 9));

      respond = (_) => liveSessionJson(status: 'live', pinned: pinnedJson(id: 'p9', price: 120, discount: 99.9));
      final pinned = await service.pinProduct('sess-1', 'p9');
      expect(jsonDecode(_requests.last.body), {'p_session_id': 'sess-1', 'p_product_id': 'p9'});
      expect(pinned.pinnedProduct!.effectivePrice, 99.9);
      expect(pinned.pinnedProduct!.hasDiscount, isTrue);

      respond = (_) => liveSessionJson(status: 'live');
      expect((await service.unpinProduct('sess-1')).pinnedProduct, isNull);
      expect(_requests.last.url.path, '/rest/v1/rpc/live_unpin_product');

      respond = (_) => {'status': 'ended', 'ended_reason': 'host', 'duration_seconds': 725, 'peak_viewer_count': 9, 'message_count': 14};
      final summary = await service.endLive('sess-1');
      expect(_requests.last.url.path, '/rest/v1/rpc/end_live_session');
      expect((summary.duration, summary.peakViewerCount, summary.messageCount), (const Duration(seconds: 725), 9, 14));
    });

    test('Agora anahtarı Edge Function\'dan; ok:false → Türkçe hata', () async {
      final service = LiveShoppingService(client: client());
      respond = (_) => {'ok': true, 'app_id': 'a' * 32, 'channel': 'cz_x', 'uid': 555, 'host_uid': 1, 'token': '007t', 'expires_in': 3600};
      final creds = await service.fetchCredentials('sess-1', asHost: false);
      expect(_requests.single.url.path, '/functions/v1/live-token');
      expect(body(0), {'session_id': 'sess-1', 'role': 'viewer'});
      expect((creds.uid, creds.hostUid, creds.token, creds.expiresIn), (555, 1, '007t', const Duration(hours: 1)));

      respond = (_) => {'ok': false, 'error': 'LIVE_NOT_CONFIGURED'};
      await expectLater(
        service.fetchCredentials('sess-1', asHost: true),
        throwsA(isA<LiveException>().having((e) => e.failure, 'failure', LiveFailure.notConfigured)),
      );
      expect(body(1), {'session_id': 'sess-1', 'role': 'host'});

      status = 429;
      respond = (_) => {'ok': false, 'error': 'RATE_LIMITED'};
      await expectLater(
        service.fetchCredentials('sess-1', asHost: false),
        throwsA(isA<LiveException>().having((e) => e.failure, 'failure', LiveFailure.rateLimited)),
      );
    });

    test('sunucu ipucu (HINT) → LiveFailure', () async {
      status = 400;
      respond = (_) => {'code': 'P0001', 'message': 'Yayın şu an canlı değil', 'hint': 'LIVE_NOT_LIVE', 'details': null};
      await expectLater(
        LiveShoppingService(client: client()).startLive('sess-1'),
        throwsA(isA<LiveException>().having((e) => e.failure, 'failure', LiveFailure.notLive)),
      );
    });

    test('mesaj geçmişi: yazar alanları tablodan, en eski başta', () async {
      respond = (_) => [
        {'id': 'm2', 'session_id': 's', 'user_id': 'u', 'message': 'ikinci', 'is_host': false, 'author_name': 'ali', 'created_at': '2026-09-28T12:01:00Z'},
        {'id': 'm1', 'session_id': 's', 'user_id': 'o', 'message': 'ilk', 'is_host': true, 'author_name': 'Çay Evi', 'created_at': '2026-09-28T12:00:00Z'},
      ];
      final list = await LiveShoppingService(client: client()).fetchRecentMessages('s');
      final url = _requests.single.url;
      expect(url.path, '/rest/v1/live_messages');
      expect(url.queryParameters['session_id'], 'eq.s');
      expect(url.queryParameters['order'], startsWith('created_at.desc'));
      expect(url.queryParameters['select'], contains('author_name'));
      expect(list.map((m) => m.message), ['ilk', 'ikinci']);
      expect(list.first.isHost, isTrue);
      expect(list.first.authorName, 'Çay Evi');
    });
  });

  group('model', () {
    test('Realtime satırı: durum, izleyici, sabit ürün kimliği; ayrıntı gerekince işaretlenir', () {
      final session = LiveSession.fromJson(liveSessionJson(
        status: 'live',
        isLive: true,
        startedAt: kLiveNow,
        pinned: pinnedJson(id: 'p1'),
      ));
      final beat = session.applyRow({'id': 'sess-1', 'status': 'live', 'viewer_count': 11, 'pinned_product_id': 'p1'});
      expect((beat.viewerCount, beat.pinnedProduct?.id, beat.needsPinnedDetail), (11, 'p1', false));

      final repinned = session.applyRow({'status': 'live', 'pinned_product_id': 'p2'});
      expect((repinned.pinnedProduct, repinned.pinnedProductId, repinned.needsPinnedDetail), (null, 'p2', true));

      final ended = session.applyRow({'status': 'ended', 'ended_reason': 'timeout', 'ended_at': '2026-09-28T12:30:00Z'});
      expect((ended.isEnded, ended.endedReason), (true, 'timeout'));
      expect(ended.durationAt(kLiveNow.add(const Duration(hours: 5))), const Duration(minutes: 30));
    });

    test('süre biçimi ve bitiş nedeni metni', () {
      expect(formatLiveDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(formatLiveDuration(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
      expect(liveEndedReasonText('admin', forHost: true), 'Yayın yönetici tarafından kapatıldı.');
      expect(liveEndedReasonText('host', forHost: false), 'Satıcı yayını bitirdi.');
      expect(liveEndedReasonText('timeout', forHost: false), 'Satıcının bağlantısı koptuğu için yayın sona erdi.');
    });

    test('Edge Function hata kodları ve sunucu ipuçları aynı eşlemede', () {
      expect(LiveFailure.fromCode('NOT_LIVE'), LiveFailure.notLive);
      expect(LiveFailure.fromCode('LIVE_NOT_LIVE'), LiveFailure.notLive);
      expect(LiveFailure.fromCode('ENDED'), LiveFailure.ended);
      expect(LiveFailure.fromCode('FORBIDDEN'), LiveFailure.notHost);
      expect(LiveFailure.fromCode('SHOP_INACTIVE'), LiveFailure.shopInactive);
      expect(LiveFailure.fromCode(null), LiveFailure.unknown);
    });
  });
}
