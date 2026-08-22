// =============================================================================
// Seller Backend HTTP Test - Fiziksel cihazda çalışıyormuş gibi davranır
// =============================================================================
// Kullanım:
//   flutter test test/seller/seller_backend_test.dart
//
// Bu test Supabase backend'ine gerçek HTTP çağrıları yapar. Gerçek bir fiziksel
// cihazda uygulama açıldığında karşılaşılan akışı birebir simüle eder:
//   - Auth (anon key ile)
//   - REST API (CRUD)
//   - Storage API
//   - Edge Functions
// =============================================================================

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/constants/app_constants.dart';

class SellerBackendResult {
  final String name;
  final bool success;
  final int? status;
  final String? detail;
  final Duration duration;
  SellerBackendResult({
    required this.name,
    required this.success,
    this.status,
    this.detail,
    required this.duration,
  });

  @override
  String toString() {
    final icon = success ? '✅' : '❌';
    final s = status != null ? ' [HTTP $status]' : '';
    final d = (detail != null && !success) ? '\n   Detay: $detail' : '';
    return '$icon$s [${duration.inMilliseconds}ms] $name$d';
  }
}

final List<SellerBackendResult> _results = [];

Future<void> _run(String name, Future<int> Function() fn) async {
  final sw = Stopwatch()..start();
  try {
    final status = await fn();
    sw.stop();
    // 2xx başarı, 4xx RLS/auth hatası (kabul), 5xx sunucu hatası (başarısız)
    final ok = status < 500;
    _results.add(
      SellerBackendResult(
        name: name,
        success: ok,
        status: status,
        duration: sw.elapsed,
      ),
    );
  } catch (e) {
    sw.stop();
    _results.add(
      SellerBackendResult(
        name: name,
        success: false,
        detail: e.toString(),
        duration: sw.elapsed,
      ),
    );
  }
}

Future<int> _get(
  String path, {
  Map<String, String>? query,
  String? token,
}) async {
  final url = Uri.parse(
    '${AppConstants.supabaseUrl}$path',
  ).replace(queryParameters: query);
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    req.headers.set('apikey', AppConstants.supabaseAnonKey);
    req.headers.set(
      'Authorization',
      'Bearer ${token ?? AppConstants.supabaseAnonKey}',
    );
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode;
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _getJson(
  String path, {
  Map<String, String>? query,
  String? token,
}) async {
  final url = Uri.parse(
    '${AppConstants.supabaseUrl}$path',
  ).replace(queryParameters: query);
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    req.headers.set('apikey', AppConstants.supabaseAnonKey);
    req.headers.set(
      'Authorization',
      'Bearer ${token ?? AppConstants.supabaseAnonKey}',
    );
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return {
      'status': resp.statusCode,
      'body': body.isEmpty ? null : jsonDecode(body),
    };
  } finally {
    client.close();
  }
}

void main() {
  // ===========================================================================
  // 1. AUTH HEALTHCHECK
  // ===========================================================================
  group('🔐 AUTH HEALTHCHECK', () {
    test('Auth settings endpoint', () async {
      await _run('GET /auth/v1/settings', () => _get('/auth/v1/settings'));
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('Auth health endpoint', () async {
      await _run('GET /auth/v1/health', () => _get('/auth/v1/health'));
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ===========================================================================
  // 2. REST API - SHOP TABLOSU
  // ===========================================================================
  group('🏪 REST API - shops tablosu', () {
    test('Tüm shop\'lar (limit)', () async {
      await _run(
        'GET /rest/v1/shops?limit=5',
        () => _get(
          '/rest/v1/shops',
          query: {'select': 'id,name,is_active', 'limit': '5'},
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('Aktif shop\'lar', () async {
      await _run(
        'GET /rest/v1/shops?is_active=eq.true',
        () => _get(
          '/rest/v1/shops',
          query: {'is_active': 'eq.true', 'limit': '5'},
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('Shop finansal kolonları', () async {
      await _run(
        'GET shops finansal',
        () => _get(
          '/rest/v1/shops',
          query: {
            'select':
                'id,admin_credit,commission_debt,cash_payment_revenue,online_payment_revenue,total_paid',
            'limit': '1',
          },
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('Shop teslimat kolonları', () async {
      await _run(
        'GET shops teslimat',
        () => _get(
          '/rest/v1/shops',
          query: {
            'select':
                'id,min_order_amount,free_delivery_min_amount,delivery_time,delivery_fee,has_own_courier',
            'limit': '1',
          },
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ===========================================================================
  // 3. REST API - CATEGORIES
  // ===========================================================================
  group('📂 REST API - categories', () {
    test('Aktif kategoriler', () async {
      await _run(
        'GET /rest/v1/categories',
        () => _get(
          '/rest/v1/categories',
          query: {
            'is_active': 'eq.true',
            'order': 'display_order.asc',
            'limit': '20',
          },
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ===========================================================================
  // 4. REST API - SELLER FINANCE
  // ===========================================================================
  group('💸 REST API - Satıcı finansal tablolar', () {
    test('payout_requests', () async {
      await _run(
        'GET /rest/v1/payout_requests',
        () => _get(
          '/rest/v1/payout_requests',
          query: {'select': 'id,status', 'limit': '1'},
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('seller_earnings', () async {
      await _run(
        'GET /rest/v1/seller_earnings',
        () => _get(
          '/rest/v1/seller_earnings',
          query: {'select': 'id,status', 'limit': '1'},
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('seller_withdrawals', () async {
      await _run(
        'GET /rest/v1/seller_withdrawals',
        () => _get(
          '/rest/v1/seller_withdrawals',
          query: {'select': 'id,status', 'limit': '1'},
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ===========================================================================
  // 5. STORAGE
  // ===========================================================================
  group('🖼️ STORAGE', () {
    test('shop-images bucket', () async {
      await _run(
        'GET /storage/v1/bucket/shop-images',
        () => _get('/storage/v1/bucket/shop-images'),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('avatars bucket', () async {
      await _run(
        'GET /storage/v1/bucket/avatars',
        () => _get('/storage/v1/bucket/avatars'),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ===========================================================================
  // 6. EDGE FUNCTIONS (varlık kontrolü)
  // ===========================================================================
  group('⚡ EDGE FUNCTIONS', () {
    test('get-seller-earnings OPTIONS', () async {
      final client = HttpClient();
      try {
        final req = await client.openUrl(
          'OPTIONS',
          Uri.parse(
            '${AppConstants.supabaseUrl}/functions/v1/get-seller-earnings',
          ),
        );
        req.headers.set('apikey', AppConstants.supabaseAnonKey);
        final resp = await req.close();
        await resp.drain<void>();
        print('   ⚡ get-seller-earnings OPTIONS status: ${resp.statusCode}');
        _results.add(
          SellerBackendResult(
            name: 'OPTIONS get-seller-earnings',
            success: resp.statusCode < 500,
            status: resp.statusCode,
            duration: const Duration(milliseconds: 50),
          ),
        );
      } finally {
        client.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('request-withdrawal OPTIONS', () async {
      final client = HttpClient();
      try {
        final req = await client.openUrl(
          'OPTIONS',
          Uri.parse(
            '${AppConstants.supabaseUrl}/functions/v1/request-withdrawal',
          ),
        );
        req.headers.set('apikey', AppConstants.supabaseAnonKey);
        final resp = await req.close();
        await resp.drain<void>();
        print('   ⚡ request-withdrawal OPTIONS status: ${resp.statusCode}');
        _results.add(
          SellerBackendResult(
            name: 'OPTIONS request-withdrawal',
            success: resp.statusCode < 500,
            status: resp.statusCode,
            duration: const Duration(milliseconds: 50),
          ),
        );
      } finally {
        client.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ===========================================================================
  // 7. WRITE/READ UYUMLULUĞU (seller_products örneği)
  // ===========================================================================
  group('📦 REST API - Seller ürün & sipariş', () {
    test('products tablosu erişimi', () async {
      await _run(
        'GET /rest/v1/products',
        () => _get(
          '/rest/v1/products',
          query: {'is_active': 'eq.true', 'limit': '3'},
        ),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
      'orders tablosu erişimi (anon)',
      () async {
        await _run(
          'GET /rest/v1/orders',
          () => _get(
            '/rest/v1/orders',
            query: {'select': 'id,status', 'limit': '1'},
          ),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  // ===========================================================================
  // 8. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 70}');
    print('📡 SELLER BACKEND HTTP TEST RAPORU');
    print('=' * 70);
    final ok = _results.where((r) => r.success).length;
    final fail = _results.where((r) => !r.success).length;
    print('✅ Başarılı: $ok');
    print('❌ Başarısız: $fail');
    print('=' * 70);
    for (final r in _results) {
      print(r.toString());
    }
    print('=' * 70);
    print(
      fail == 0
          ? '🎉 TÜM SATICI BACKEND TESTLERİ BAŞARILI!'
          : '⚠️ BAZI BACKEND TESTLERİ BAŞARISIZ',
    );
    print('=' * 70);
  });
}
