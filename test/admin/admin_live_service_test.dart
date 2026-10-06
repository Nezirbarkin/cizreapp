import 'dart:convert';

import 'package:cizreapp/features/admin/services/admin_live_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 4.3 — Admin > Canlı Yayınlar veri katmanı: hepsi yönetici RPC'si.
void main() {
  late List<http.Request> requests;
  late Object? Function(http.Request req) respond;

  SupabaseClient client() => SupabaseClient(
    'https://test.invalid',
    'test-key',
    httpClient: MockClient((req) async {
      requests.add(req);
      return http.Response(
        jsonEncode(respond(req)),
        200,
        request: req,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  AdminLiveService service() => AdminLiveService(client: client());

  setUp(() {
    requests = [];
    respond = (_) => null;
  });

  Map<String, dynamic> sessionRow({String id = 's1', String status = 'live'}) => {
    'id': id,
    'shop_id': 'shop-1',
    'host_user_id': 'owner-1',
    'title': 'Çay Evi canlı',
    'channel_name': 'cz_abc',
    'status': status,
    'is_live': status == 'live',
    'started_at': '2026-09-28T11:40:00+00:00',
    'ended_at': status == 'ended' ? '2026-09-28T12:10:00+00:00' : null,
    'ended_reason': status == 'ended' ? 'admin' : null,
    'viewer_count': 12,
    'peak_viewer_count': 30,
    'created_at': '2026-09-28T11:30:00+00:00',
    'shop_name': 'Çay Evi',
    'pinned_product': null,
    'host_name': 'Ayşe Yılmaz',
    'host_username': 'ayse',
    'message_count': 41,
    'duration_seconds': 1200,
    'ended_note': status == 'ended' ? 'Uygunsuz içerik' : null,
    'ended_by_name': status == 'ended' ? 'Yönetici' : null,
    'shop_access': 'LIVE_REVOKED',
  };

  test('yayın listesi: RPC parametreleri; satır, özet ve ayarlar okunur', () async {
    respond = (_) => {
      'total': 2,
      'rows': [sessionRow(), sessionRow(id: 's2', status: 'ended')],
      'summary': {
        'live_now': 1,
        'preparing': 2,
        'today': 5,
        'minutes_7d': 340,
        'admin_closed_30d': 3,
        'granted_shops': 4,
        'revoked_shops': 1,
      },
      'settings': {'enabled': false, 'access': 'invite'},
    };
    final page = await service().fetchSessions('ended', limit: 10, offset: 20);

    expect(requests.single.url.path, '/rest/v1/rpc/admin_live_sessions');
    expect(jsonDecode(requests.single.body), {'p_status': 'ended', 'p_limit': 10, 'p_offset': 20});
    expect(page.total, 2);
    final live = page.rows.first;
    expect(live.session.id, 's1');
    expect(live.session.isLiveNow, isTrue);
    expect(live.session.viewerCount, 12);
    expect(live.hostName, 'Ayşe Yılmaz');
    expect(live.messageCount, 41);
    expect(live.durationSeconds, 1200);
    expect(live.shopAccess, LiveShopAccess.revoked);
    final ended = page.rows.last;
    expect(ended.endedReasonLabel, 'Yönetici kapattı');
    expect(ended.endedNote, 'Uygunsuz içerik');
    expect(ended.endedByName, 'Yönetici');
    expect(page.liveNow, 1);
    expect(page.preparing, 2);
    expect(page.today, 5);
    expect(page.minutes7d, 340);
    expect(page.adminClosed30d, 3);
    expect(page.grantedShops, 4);
    expect(page.revokedShops, 1);
    expect(page.settings.enabled, isFalse);
    expect(page.settings.inviteOnly, isTrue);
  });

  test('mağaza listesi: boş arama null gider; izin ve etkin durum okunur', () async {
    respond = (_) => {
      'total': 1,
      'rows': [
        {
          'shop_id': 'shop-1',
          'shop_name': 'Çay Evi',
          'logo_url': null,
          'is_active': true,
          'is_approved': true,
          'owner_id': 'owner-1',
          'owner_name': null,
          'owner_username': 'ayse',
          'permission': 'revoked',
          'note': 'Kural ihlali',
          'permission_updated_at': '2026-09-28T10:00:00+00:00',
          'updated_by_name': 'Yönetici',
          'effective': 'LIVE_REVOKED',
          'session_count': 3,
          'last_live_at': '2026-09-27T18:00:00+00:00',
          'live_session_id': null,
        },
        {'shop_id': 'shop-2', 'shop_name': 'Dicle', 'permission': 'başka', 'effective': 'ok'},
      ],
      'summary': {'granted': 2, 'revoked': 1},
      'settings': {'enabled': true, 'access': 'open'},
    };
    final page = await service().fetchShops(search: '   ', filter: 'revoked', offset: 30);

    expect(requests.single.url.path, '/rest/v1/rpc/admin_live_shops');
    expect(jsonDecode(requests.single.body), {'p_search': null, 'p_filter': 'revoked', 'p_limit': 30, 'p_offset': 30});
    final shop = page.rows.first;
    expect(shop.permission, 'revoked');
    expect(shop.note, 'Kural ihlali');
    expect(shop.effective, LiveShopAccess.revoked);
    expect(shop.sessionCount, 3);
    expect(shop.isLiveNow, isFalse);
    expect(shop.ownerUsername, 'ayse');
    expect(page.rows.last.permission, isNull, reason: 'bilinmeyen değer varsayılan sayılır');
    expect(page.granted, 2);
    expect(page.revoked, 1);
    expect(page.settings.enabled, isTrue);
    expect(page.settings.inviteOnly, isFalse);

    requests.clear();
    await service().fetchShops(search: '  kebap ');
    expect(jsonDecode(requests.single.body)['p_search'], 'kebap');
  });

  test('kapatma, izin ve ayar RPC\'leri; boş not null gider', () async {
    respond = (req) => switch (req.url.pathSegments.last) {
      'admin_end_live_session' => {'status': 'discarded'},
      'admin_set_shop_live_permission' => {'permission': 'revoked', 'effective': 'LIVE_REVOKED', 'closed': 1},
      _ => {'enabled': false, 'access': 'invite', 'closed': 2},
    };

    expect(await service().endSession('s1', note: '  '), 'discarded');
    expect(jsonDecode(requests.last.body), {'p_session_id': 's1', 'p_note': null});

    final change = await service().setShopPermission('shop-1', 'revoked', note: ' Kural ihlali ');
    expect(jsonDecode(requests.last.body), {'p_shop_id': 'shop-1', 'p_permission': 'revoked', 'p_note': 'Kural ihlali'});
    expect(change.closed, 1);
    expect(change.effective, LiveShopAccess.revoked);

    final settings = await service().setSettings(enabled: false, closeRunning: true);
    expect(requests.last.url.path, '/rest/v1/rpc/admin_set_live_settings');
    expect(jsonDecode(requests.last.body), {'p_enabled': false, 'p_access': null, 'p_close_running': true});
    expect(settings.closed, 2);
    expect(settings.settings!.enabled, isFalse);
    expect(settings.settings!.inviteOnly, isTrue);
  });

  test('etkin durum etiketleri ve hata metinleri', () {
    expect(LiveShopAccess.fromCode('ok').label, 'Yayın açabilir');
    expect(LiveShopAccess.fromCode('LIVE_DISABLED'), LiveShopAccess.disabled);
    expect(LiveShopAccess.fromCode('LIVE_NOT_PERMITTED').label, 'İzin bekliyor (yalnız izinliler modu)');
    expect(
      AdminLiveService.errorMessage(const PostgrestException(message: 'x', hint: 'LIVE_ENDED')),
      'Bu yayın zaten sona ermiş.',
    );
    expect(
      AdminLiveService.errorMessage(const PostgrestException(message: 'x', hint: 'LIVE_NOT_FOUND')),
      'Yayın bulunamadı (satıcı kapatmış olabilir).',
    );
    expect(
      AdminLiveService.errorMessage(const PostgrestException(message: 'x', code: '42501')),
      'Bu işlem için yönetici yetkisi gerekli.',
    );
    expect(AdminLiveService.errorMessage(Exception('ağ')), startsWith('İşlem tamamlanamadı'));
  });
}
