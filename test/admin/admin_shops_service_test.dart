import 'dart:convert';

import 'package:cizreapp/features/admin/services/admin_shops_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin > Dükkanlar veri katmanı (Görev 1.3): sayfa TEK istekle gelir;
/// eskiden her dükkan için sırayla 4–5 istek atılıyordu.
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

  setUp(() {
    requests = [];
    respond = (_) => {
      'total': 12,
      'rows': [
        {
          'id': 'shop-1',
          'name': 'Dükkan 1',
          'profiles': {'full_name': 'Sahip', 'email': 'sahip@example.com'},
          'product_count': 7,
          'total_earnings': 1250.5,
          'net_earnings': 0,
        },
      ],
      'summary': {
        'total': 12,
        'pending': 2,
        'admin_courier': 5,
        'revenue': 1250.5,
        'commission': 125,
      },
    };
  });

  test('tek istek: doğru RPC ve parametreler', () async {
    final page = await AdminShopsService(client: client()).fetchPage(
      search: '  kahve ',
      filter: 'pending',
      sort: 'earnings',
      offset: 20,
    );

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/rest/v1/rpc/admin_shops_page');
    expect(jsonDecode(requests.single.body), {
      'p_search': 'kahve',
      'p_filter': 'pending',
      'p_sort': 'earnings',
      'p_limit': AdminShopsService.pageSize,
      'p_offset': 20,
    });
    expect(page.total, 12);
  });

  test('"Tümü" filtresi ve boş arama sunucuya null gider', () async {
    await AdminShopsService(client: client()).fetchPage(search: '   ');

    expect(jsonDecode(requests.single.body), {
      'p_search': null,
      'p_filter': null,
      'p_sort': 'default',
      'p_limit': AdminShopsService.pageSize,
      'p_offset': 0,
    });
  });

  test('satırlar ve özet eşlenir; satır haritaları değiştirilebilir', () async {
    final page = await AdminShopsService(client: client()).fetchPage();

    expect(page.rows.single['name'], 'Dükkan 1');
    expect((page.rows.single['profiles'] as Map)['email'], 'sahip@example.com');
    expect((page.rows.single['total_earnings'] as num).toDouble(), 1250.5);
    // Kart işlemleri satırı yerinde günceller (ör. bakiye sıfırlama).
    page.rows.single['admin_credit'] = 0.0;
    expect(page.rows.single['admin_credit'], 0.0);

    expect(page.count('total'), 12);
    expect(page.count('pending'), 2);
    expect(page.count('admin_courier'), 5);
    expect(page.count('bilinmeyen'), 0);
    expect(page.amount('revenue'), 1250.5);
    expect(page.amount('commission'), 125.0);
  });

  test('boş yanıt güvenle eşlenir', () async {
    respond = (_) => {'total': 0, 'rows': <Object>[], 'summary': <String, Object>{}};

    final page = await AdminShopsService(client: client()).fetchPage();

    expect(page.rows, isEmpty);
    expect(page.total, 0);
    expect(page.count('total'), 0);
  });
}
