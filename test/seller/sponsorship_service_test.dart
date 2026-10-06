import 'dart:convert';

import 'package:cizreapp/core/models/sponsorship_model.dart';
import 'package:cizreapp/features/seller/services/sponsorship_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 3.2 — öne çıkarma istemcisi: paket/satın alma okuma istekleri,
/// satın alma RPC'si ve sunucu ipucunun (HINT) nedene çevrilmesi.

final List<http.Request> _requests = [];
Map<String, dynamic>? _rpcError;

SupabaseClient _client() => SupabaseClient(
  'https://test.invalid',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: MockClient((req) async {
    _requests.add(req);
    final Object body;
    var status = 200;
    switch (req.url.pathSegments.last) {
      case 'sponsorship_packages':
        body = [
          {'id': 'p1', 'placement': 'shop_list', 'name': 'Günlük', 'duration_days': 1, 'price': 30, 'sort_order': 10},
          {'id': 'p9', 'placement': 'homepage_banner', 'name': 'Yeni', 'duration_days': 1, 'price': 1, 'sort_order': 5},
          {'id': 'p2', 'placement': 'product_discount', 'name': 'Haftalık', 'duration_days': 7, 'price': '75.00', 'sort_order': 20},
        ];
      case 'shop_sponsorships':
        body = [
          {
            'id': 's1', 'shop_id': 'shop-1', 'product_id': null, 'placement': 'shop_list',
            'package_name': 'Günlük', 'duration_days': 1, 'price_paid': 30, 'status': 'active',
            'starts_at': '2026-09-28T10:00:00+00:00', 'ends_at': '2026-09-29T10:00:00+00:00',
            'created_at': '2026-09-28T10:00:00+00:00', 'review_note': null,
          },
        ];
      case 'purchase_shop_sponsorship':
        if (_rpcError != null) {
          body = _rpcError!;
          status = 400;
        } else {
          body = {
            'id': 'new', 'status': 'active', 'placement': 'shop_list', 'price': 30,
            'balance_after': 970, 'starts_at': '2026-09-28T10:00:00+00:00', 'ends_at': '2026-09-29T10:00:00+00:00',
          };
        }
      default:
        body = <Object>[];
    }
    return http.Response(jsonEncode(body), status, request: req, headers: {'content-type': 'application/json; charset=utf-8'});
  }),
);

void main() {
  setUp(() {
    _requests.clear();
    _rpcError = null;
  });

  test('paketler: yalnız aktif, artan sıra; tanınmayan vitrin atlanır', () async {
    final packages = await SponsorshipService(client: _client()).fetchPackages();
    final url = _requests.single.url;
    expect(url.path, '/rest/v1/sponsorship_packages');
    expect(url.queryParameters['is_active'], 'eq.true');
    expect(url.queryParameters['order'], 'sort_order.asc.nullslast');
    expect(packages.map((p) => p.id), ['p1', 'p2']);
    expect(packages.last.price, 75);
    expect(packages.last.placement, SponsorPlacement.productDiscount);
  });

  test('satın almalar mağazaya göre, en yeni önce', () async {
    final rows = await SponsorshipService(client: _client()).fetchShopSponsorships('shop-1');
    final url = _requests.single.url;
    expect(url.path, '/rest/v1/shop_sponsorships');
    expect(url.queryParameters['shop_id'], 'eq.shop-1');
    expect(url.queryParameters['order'], 'created_at.desc.nullslast');
    expect(rows.single.status, SponsorshipStatus.active);
  });

  test('satın alma RPC\'si: mağaza vitrininde ürün gönderilmez', () async {
    final result = await SponsorshipService(client: _client()).purchase(shopId: 'shop-1', packageId: 'p1');
    expect(_requests.single.url.path, '/rest/v1/rpc/purchase_shop_sponsorship');
    expect(jsonDecode(_requests.single.body), {'p_shop_id': 'shop-1', 'p_package_id': 'p1'});
    expect((result.id, result.balanceAfter), ('new', 970.0));

    _requests.clear();
    await SponsorshipService(client: _client()).purchase(shopId: 'shop-1', packageId: 'p2', productId: 'prod-1');
    expect(jsonDecode(_requests.single.body), {'p_shop_id': 'shop-1', 'p_package_id': 'p2', 'p_product_id': 'prod-1'});
  });

  test('sunucu ipucu → neden; sunucunun Türkçe mesajı kullanıcıya gider', () async {
    Future<SponsorshipException> failWith(Map<String, dynamic> error) async {
      _rpcError = error;
      try {
        await SponsorshipService(client: _client()).purchase(shopId: 's', packageId: 'p');
      } on SponsorshipException catch (e) {
        return e;
      }
      throw TestFailure('istisna bekleniyordu');
    }

    final noMoney = await failWith({'code': 'P0001', 'message': 'Yetersiz bakiye: bu paket 30.00 TL', 'hint': 'insufficient_balance'});
    expect(noMoney.reason, SponsorshipFailure.insufficientBalance);
    expect(noMoney.message, 'Yetersiz bakiye: bu paket 30.00 TL');

    expect((await failWith({'code': 'P0001', 'message': 'x', 'hint': 'product_not_discounted'})).reason,
        SponsorshipFailure.productNotDiscounted);
    expect((await failWith({'code': 'P0001', 'message': 'x', 'hint': 'disabled'})).reason, SponsorshipFailure.disabled);
    expect((await failWith({'code': 'P0001', 'message': 'x', 'hint': 'shop_not_listed'})).reason, SponsorshipFailure.shopNotListed);
    expect((await failWith({'code': '42501', 'message': 'Bu mağaza size ait değil', 'hint': null})).reason,
        SponsorshipFailure.notAllowed);

    final unknown = await failWith({'code': 'XX000', 'message': 'internal', 'hint': null});
    expect(unknown.reason, SponsorshipFailure.unknown);
    expect(unknown.message, 'Öne çıkarma satın alınamadı. Lütfen tekrar deneyin.');
  });
}
