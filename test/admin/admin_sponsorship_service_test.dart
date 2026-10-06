import 'dart:convert';

import 'package:cizreapp/core/models/sponsorship_model.dart';
import 'package:cizreapp/features/admin/services/admin_sponsorship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin > Öne Çıkarma veri katmanı (Görev 4.2): kararlar RPC ile, paketler ve
/// anahtarlar admin RLS'iyle doğrudan tabloya.
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

  AdminSponsorshipService service() => AdminSponsorshipService(client: client());

  setUp(() {
    requests = [];
    respond = (_) => null;
  });

  test('liste: tek RPC, parametreler; tanınmayan vitrin atlanır, özet ve ayarlar okunur', () async {
    respond = (_) => {
      'total': 3,
      'rows': [
        {
          'id': 's1',
          'shop_id': 'shop-1',
          'shop_name': 'Cizre Kebap',
          'product_id': null,
          'product_name': null,
          'placement': 'shop_list',
          'package_name': 'Haftalık',
          'duration_days': 7,
          'price_paid': 150,
          'status': 'active',
          'starts_at': '2026-09-28T08:00:00+00:00',
          'ends_at': '2026-10-05T08:00:00+00:00',
          'created_at': '2026-09-28T07:59:00+00:00',
          'created_by_name': 'Ayşe',
          'reviewed_at': null,
          'review_note': null,
          'is_running': true,
          'is_queued': false,
        },
        {'id': 's2', 'placement': 'yeni_vitrin', 'status': 'active', 'created_at': '2026-09-28T07:00:00+00:00'},
        {
          'id': 's3',
          'shop_id': 'shop-2',
          'shop_name': 'Dicle Market',
          'product_id': 'p1',
          'product_name': 'Çay 1 kg',
          'placement': 'product_discount',
          'package_name': 'Günlük',
          'duration_days': 1,
          'price_paid': '15.50',
          'status': 'active',
          'starts_at': '2026-10-05T08:00:00+00:00',
          'ends_at': '2026-10-06T08:00:00+00:00',
          'created_at': '2026-09-28T06:00:00+00:00',
          'is_running': false,
          'is_queued': true,
        },
      ],
      'summary': {'pending': 2, 'running': 1, 'queued': 1, 'revenue_30d': 245.5},
      'settings': {'enabled': true, 'requires_approval': true},
    };

    final page = await service().fetch('active', limit: 30, offset: 60);

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/rest/v1/rpc/admin_sponsorships_list');
    expect(jsonDecode(requests.single.body), {'p_status': 'active', 'p_limit': 30, 'p_offset': 60});
    expect(page.total, 3);
    expect(page.rows.map((r) => r.id), ['s1', 's3'], reason: 'tanınmayan vitrin listelenmez');
    final running = page.rows.first;
    expect(running.shopName, 'Cizre Kebap');
    expect(running.placement, SponsorPlacement.shopList);
    expect(running.pricePaid, 150);
    expect(running.status, SponsorshipStatus.active);
    expect(running.startsAt, DateTime.utc(2026, 9, 28, 8));
    expect(running.statusLabel, 'Yayında');
    final queued = page.rows.last;
    expect(queued.pricePaid, 15.5, reason: 'numeric metin olarak da gelebilir');
    expect(queued.productName, 'Çay 1 kg');
    expect(queued.statusLabel, 'Sırada');
    expect(page.pending, 2);
    expect(page.running, 1);
    expect(page.queued, 1);
    expect(page.revenue30d, 245.5);
    expect(page.enabled, isTrue);
    expect(page.requiresApproval, isTrue);
  });

  test('durum etiketleri', () {
    AdminSponsorshipRow row(String status, {bool running = false, bool queued = false}) =>
        AdminSponsorshipRow.tryFromJson({
          'id': 'x',
          'placement': 'shop_category',
          'status': status,
          'created_at': '2026-09-28T07:00:00Z',
          'is_running': running,
          'is_queued': queued,
        })!;
    expect(row('pending').statusLabel, 'Onay bekliyor');
    expect(row('rejected').statusLabel, 'Reddedildi');
    expect(row('cancelled').statusLabel, 'İptal edildi');
    expect(row('active', running: true).statusLabel, 'Yayında');
    expect(row('active', queued: true).statusLabel, 'Sırada');
    expect(row('active').statusLabel, 'Süresi bitti');
  });

  test('onay/ret: RPC parametreleri ve iade tutarı', () async {
    respond = (_) => {'id': 's1', 'status': 'rejected', 'refunded': 30};
    final refunded = await service().review('s1', approve: false, note: 'Görsel uygun değil');
    expect(refunded, 30);
    expect(requests.single.url.path, '/rest/v1/rpc/admin_review_sponsorship');
    expect(jsonDecode(requests.single.body), {'p_id': 's1', 'p_approve': false, 'p_note': 'Görsel uygun değil'});

    requests.clear();
    respond = (_) => {'id': 's1', 'status': 'active', 'refunded': 0};
    expect(await service().review('s1', approve: true), 0);
    expect(jsonDecode(requests.single.body), {'p_id': 's1', 'p_approve': true, 'p_note': null});
  });

  test('iptal: iade seçimi ve not RPC\'ye gider', () async {
    respond = (_) => {'id': 's1', 'status': 'cancelled', 'refunded': 12.75};
    final refunded = await service().cancel('s1', refund: true, note: 'Kural ihlali');
    expect(refunded, 12.75);
    expect(requests.single.url.path, '/rest/v1/rpc/admin_cancel_sponsorship');
    expect(jsonDecode(requests.single.body), {'p_id': 's1', 'p_refund': true, 'p_note': 'Kural ihlali'});
  });

  test('paketler: pasifler dahil okunur, vitrin/sıra/süreye göre', () async {
    respond = (_) => [
      {
        'id': 'k1',
        'placement': 'shop_list',
        'name': 'Günlük',
        'duration_days': 1,
        'price': 30,
        'is_active': true,
        'sort_order': 0,
      },
      {
        'id': 'k2',
        'placement': 'shop_list',
        'name': 'Haftalık',
        'duration_days': 7,
        'price': '150.00',
        'is_active': false,
        'sort_order': 1,
      },
      {'id': 'k3', 'placement': 'bilinmeyen', 'name': 'X', 'duration_days': 3, 'price': 1},
    ];
    final packages = await service().fetchPackages();
    expect(packages.map((p) => p.id), ['k1', 'k2']);
    expect(packages.last.price, 150);
    expect(packages.last.isActive, isFalse);
    final req = requests.single;
    expect(req.method, 'GET');
    expect(req.url.path, '/rest/v1/sponsorship_packages');
    expect(req.url.queryParameters['select'], 'id,placement,name,duration_days,price,is_active,sort_order');
    expect(
      req.url.queryParameters['order'],
      'placement.asc.nullslast,sort_order.asc.nullslast,duration_days.asc.nullslast',
    );
  });

  test('paket kaydetme: yeni = POST, düzenleme = PATCH id ile; ad kırpılır', () async {
    await service().savePackage(
      placement: SponsorPlacement.productDiscount,
      name: '  Hafta sonu ',
      durationDays: 2,
      price: 12.5,
      isActive: true,
      sortOrder: 3,
    );
    var req = requests.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/rest/v1/sponsorship_packages');
    var body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['placement'], 'product_discount');
    expect(body['name'], 'Hafta sonu');
    expect(body['duration_days'], 2);
    expect(body['price'], 12.5);
    expect(body['is_active'], isTrue);
    expect(body['sort_order'], 3);

    requests.clear();
    await service().savePackage(
      id: 'k2',
      placement: SponsorPlacement.shopList,
      name: 'Haftalık',
      durationDays: 7,
      price: 175,
      isActive: false,
    );
    req = requests.single;
    expect(req.method, 'PATCH');
    expect(req.url.queryParameters['id'], 'eq.k2');
    body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['price'], 175);
    expect(body['is_active'], isFalse);
  });

  test('pasifleştirme ve silme yalnız o paketi hedefler', () async {
    await service().setPackageActive('k1', false);
    expect(requests.single.method, 'PATCH');
    expect(requests.single.url.queryParameters['id'], 'eq.k1');
    expect(jsonDecode(requests.single.body), {'is_active': false});

    requests.clear();
    await service().deletePackage('k1');
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.queryParameters['id'], 'eq.k1');
  });

  test('anahtar: app_settings düz metin yazılır (tırnaklı değil)', () async {
    await service().setFlag('sponsorship_requires_approval', false);
    final req = requests.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/rest/v1/app_settings');
    expect(req.url.queryParameters['on_conflict'], 'key');
    expect(jsonDecode(req.body), {'key': 'sponsorship_requires_approval', 'value': 'false'});
  });

  test('hata metinleri', () {
    expect(
      AdminSponsorshipService.errorMessage(const PostgrestException(message: 'x', hint: 'SPONSORSHIP_NOT_PENDING')),
      'Bu başvuru zaten sonuçlanmış.',
    );
    expect(
      AdminSponsorshipService.errorMessage(const PostgrestException(message: 'x', hint: 'SPONSORSHIP_NOT_ACTIVE')),
      'Yalnız süren ya da sıradaki öne çıkarma iptal edilebilir.',
    );
    expect(
      AdminSponsorshipService.errorMessage(const PostgrestException(message: 'x', hint: 'SPONSORSHIP_NOT_FOUND')),
      'Kayıt bulunamadı.',
    );
    expect(
      AdminSponsorshipService.errorMessage(const PostgrestException(message: 'dup', code: '23505')),
      'Bu vitrin için aynı süreli bir paket zaten var.',
    );
    expect(
      AdminSponsorshipService.errorMessage(const PostgrestException(message: 'chk', code: '23514')),
      contains('1–90 gün'),
    );
    expect(
      AdminSponsorshipService.errorMessage(const PostgrestException(message: 'no', code: '42501')),
      'Bu işlem için yönetici yetkisi gerekli.',
    );
    expect(AdminSponsorshipService.errorMessage(const PostgrestException(message: 'Başka')), 'Başka');
    expect(AdminSponsorshipService.errorMessage(Exception('ağ')), startsWith('İşlem tamamlanamadı'));
  });
}
