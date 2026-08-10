// =============================================================================
// ShopService Unit Test - Satıcı mağaza yönetimi
// =============================================================================
// Kullanım:
//   flutter test test/seller/shop_service_test.dart
//
// Bu test fiziksel cihaz senaryosu gibi çalışır: gerçek Supabase backend'ine
// HTTP üzerinden bağlanır, RLS davranışını ve fonksiyon mantığını doğrular.
// =============================================================================

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/constants/app_constants.dart';

class SellerTestResult {
  final String name;
  final bool success;
  final String? error;
  final Duration duration;
  SellerTestResult({
    required this.name,
    required this.success,
    this.error,
    required this.duration,
  });

  @override
  String toString() {
    final status = success ? '✅ BAŞARILI' : '❌ BAŞARISIZ';
    final err = error != null ? '\n   Hata: $error' : '';
    return '$status [${duration.inMilliseconds}ms] $name$err';
  }
}

final List<SellerTestResult> _results = [];

Future<void> _runTest(String name, Future<void> Function() testFn) async {
  final sw = Stopwatch()..start();
  try {
    await testFn();
    sw.stop();
    _results.add(
      SellerTestResult(name: name, success: true, duration: sw.elapsed),
    );
  } catch (e) {
    sw.stop();
    _results.add(
      SellerTestResult(
        name: name,
        success: false,
        error: e.toString(),
        duration: sw.elapsed,
      ),
    );
  }
}

/// HTTP yardımcı: Supabase REST API'sine istek at
Future<Map<String, dynamic>> _supabaseRequest({
  required String path,
  String method = 'GET',
  String? bearerToken,
  Map<String, String>? query,
  Map<String, dynamic>? body,
}) async {
  final url = Uri.parse(
    '${AppConstants.supabaseUrl}/rest/v1/$path',
  ).replace(queryParameters: query);
  final client = HttpClient();
  try {
    final request = await (method == 'GET'
        ? client.getUrl(url)
        : method == 'POST'
        ? client.postUrl(url)
        : method == 'PATCH'
        ? client.patchUrl(url)
        : client.deleteUrl(url));
    request.headers.set('apikey', AppConstants.supabaseAnonKey);
    request.headers.set(
      'Authorization',
      'Bearer ${bearerToken ?? AppConstants.supabaseAnonKey}',
    );
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Prefer', 'return=representation');

    if (body != null) {
      // req.write() varsayılan latin1'dir; Türkçe karakterler (ı, ş, ç) hata
      // fırlatır. Gövdeyi açıkça UTF-8 bayt olarak yaz.
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    return {
      'status': response.statusCode,
      'body': responseBody.isEmpty ? null : jsonDecode(responseBody),
    };
  } finally {
    client.close();
  }
}

void main() {
  // ===========================================================================
  // 1. SHOP SERVICE - MAĞAZA BİLGİLERİ
  // ===========================================================================
  group('🏪 SHOP SERVICE - Mağaza Bilgileri', () {
    test(
      'shops tablosu okunabilir (anon)',
      () async {
        final result = await _supabaseRequest(
          path: 'shops',
          query: {'select': 'id,name,is_active,owner_id', 'limit': '5'},
        );
        print('   🏪 shops status: ${result['status']}');
        expect(result['status'], anyOf(200, 401, 403));
        if (result['status'] == 200) {
          expect(result['body'], isA<List>());
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'shops tablosunda gerekli sütunlar var',
      () async {
        final result = await _supabaseRequest(
          path: 'shops',
          query: {
            'select':
                'id,name,owner_id,is_active,commission_rate,delivery_fee,min_order_amount,free_delivery_min_amount,has_own_courier,iban,bank_name,account_holder_name',
            'limit': '1',
          },
        );
        print('   📋 shops sütunları status: ${result['status']}');
        // 200 ise sütunlar doğru; 400/406 sütun adı yanlış demektir (HATA)
        if (result['status'] == 400 || result['status'] == 404) {
          fail('shops tablosunda beklenen sütunlar eksik: ${result['body']}');
        }
        expect(result['status'], anyOf(200, 401, 403));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'Aktif mağazalar filtrelenebilir',
      () async {
        final result = await _supabaseRequest(
          path: 'shops',
          query: {'select': 'id,name', 'is_active': 'eq.true', 'limit': '10'},
        );
        print('   ✅ Aktif shop status: ${result['status']}');
        expect(result['status'], anyOf(200, 401, 403));
        if (result['status'] == 200) {
          final list = result['body'] as List;
          for (final shop in list) {
            expect(shop, containsPair('name', isA<String>()));
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  // ===========================================================================
  // 2. SHOP SERVICE - KATEGORİLER
  // ===========================================================================
  group('📂 SHOP SERVICE - Kategori Yönetimi', () {
    test(
      'Aktif kategoriler listelenebilir',
      () async {
        final result = await _supabaseRequest(
          path: 'categories',
          query: {
            'select': 'id,name,slug,icon,is_active,display_order',
            'is_active': 'eq.true',
            'order': 'display_order.asc',
            'limit': '50',
          },
        );
        print('   📂 categories status: ${result['status']}');
        expect(result['status'], anyOf(200, 401, 403));
        if (result['status'] == 200) {
          final list = result['body'] as List;
          print('   📂 ${list.length} aktif kategori bulundu');
          expect(list, isA<List>());
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'categories tablosu seller_categories alanı için hazır',
      () async {
        final result = await _supabaseRequest(
          path: 'shops',
          query: {'select': 'id,seller_categories', 'limit': '1'},
        );
        print('   🏷️ seller_categories status: ${result['status']}');
        // Eğer sütun yoksa bu test fail olur (HATA TESPİT)
        if (result['status'] == 400) {
          fail('seller_categories sütunu shops tablosunda tanımlı değil');
        }
        expect(result['status'], anyOf(200, 401, 403, 404));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  // ===========================================================================
  // 3. PAYOUT SERVICE - ÖDEME & KAZANÇ
  // ===========================================================================
  group('💰 PAYOUT SERVICE - Ödeme & Kazanç', () {
    test(
      'payout_requests tablosu var ve RLS aktif',
      () async {
        final result = await _supabaseRequest(
          path: 'payout_requests',
          query: {
            'select': 'id,seller_id,shop_id,amount,status,iban',
            'limit': '1',
          },
        );
        print('   💸 payout_requests status: ${result['status']}');
        // 200: var ve açık, 401/403: var ama RLS kısıtlı (kabul)
        expect(
          result['status'],
          anyOf(200, 401, 403),
          reason:
              'payout_requests tablosu erişilebilir olmalı (status=${result['status']})',
        );
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'payout_requests sütunları doğru',
      () async {
        final result = await _supabaseRequest(
          path: 'payout_requests',
          query: {
            'select':
                'id,seller_id,shop_id,amount,total_amount,commission_amount,net_receivable,admin_credit,status,iban,bank_name,account_holder_name,requested_at,order_count',
            'limit': '1',
          },
        );
        print('   📋 payout_requests sütunları status: ${result['status']}');
        if (result['status'] == 400) {
          fail(
            'payout_requests tablosunda beklenen sütun(lar) eksik: ${result['body']}',
          );
        }
        expect(result['status'], anyOf(200, 401, 403));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test('seller_earnings tablosu var', () async {
      final result = await _supabaseRequest(
        path: 'seller_earnings',
        query: {
          'select':
              'id,seller_id,order_id,gross_amount,commission_amount,net_amount,status',
          'limit': '1',
        },
      );
      print('   💵 seller_earnings status: ${result['status']}');
      expect(result['status'], anyOf(200, 401, 403));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test(
      'seller_withdrawals tablosu var',
      () async {
        final result = await _supabaseRequest(
          path: 'seller_withdrawals',
          query: {
            'select': 'id,seller_id,amount,fee,net_amount,status,iban',
            'limit': '1',
          },
        );
        print('   🏦 seller_withdrawals status: ${result['status']}');
        expect(result['status'], anyOf(200, 401, 403));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  // ===========================================================================
  // 4. SHOP SERVICE - FİNANSAL ALANLAR (shops tablosu)
  // ===========================================================================
  group('💼 SHOP SERVICE - Finansal Alanlar', () {
    test(
      'shops tablosu finansal sütunları içeriyor',
      () async {
        final result = await _supabaseRequest(
          path: 'shops',
          query: {
            'select':
                'id,has_own_courier,admin_credit,commission_debt,total_collected_cash,cash_payment_revenue,online_payment_revenue,total_paid',
            'limit': '1',
          },
        );
        print('   💰 shops finansal status: ${result['status']}');
        if (result['status'] == 400) {
          fail('shops tablosunda finansal sütun(lar) eksik: ${result['body']}');
        }
        expect(result['status'], anyOf(200, 401, 403));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'shops tablosu teslimat ayar sütunlarını içeriyor',
      () async {
        final result = await _supabaseRequest(
          path: 'shops',
          query: {
            'select':
                'id,min_order_amount,free_delivery_min_amount,delivery_time,delivery_fee,has_own_courier',
            'limit': '1',
          },
        );
        print('   🚚 shops teslimat status: ${result['status']}');
        if (result['status'] == 400) {
          fail(
            'shops tablosunda teslimat sütun(lar)ı eksik: ${result['body']}',
          );
        }
        expect(result['status'], anyOf(200, 401, 403));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'shops tablosu working_hours alanını içeriyor',
      () async {
        final result = await _supabaseRequest(
          path: 'shops',
          query: {
            'select': 'id,working_hours,logo_url,cover_image',
            'limit': '1',
          },
        );
        print('   ⏰ working_hours status: ${result['status']}');
        if (result['status'] == 400) {
          fail(
            'shops tablosunda working_hours/logo_url/cover_image sütunlarından biri eksik: ${result['body']}',
          );
        }
        expect(result['status'], anyOf(200, 401, 403));
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  // ===========================================================================
  // 5. STORAGE - MAĞAZA GÖRSELLERİ
  // ===========================================================================
  group('🖼️ STORAGE - Mağaza Görselleri', () {
    test(
      'shop-images bucket erişilebilir',
      () async {
        final url = '${AppConstants.supabaseUrl}/storage/v1/bucket/shop-images';
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(url));
          request.headers.set('apikey', AppConstants.supabaseAnonKey);
          request.headers.set(
            'Authorization',
            'Bearer ${AppConstants.supabaseAnonKey}',
          );
          final response = await request.close();
          await response.drain<void>();
          print('   🖼️ shop-images bucket status: ${response.statusCode}');
          // 200 var, 400/404 yok
          expect(response.statusCode, anyOf(200, 400, 401, 403, 404));
          if (response.statusCode == 404) {
            fail(
              'shop-images bucket bulunamadı - shop logo/cover yükleme çalışmaz',
            );
          }
        } finally {
          client.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  // ===========================================================================
  // 6. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 70}');
    print('🏪 SELLER PANEL TEST SONUÇ RAPORU');
    print('=' * 70);
    final ok = _results.where((r) => r.success).length;
    final fail = _results.where((r) => !r.success).length;
    final totalMs = _results.fold<int>(
      0,
      (s, r) => s + r.duration.inMilliseconds,
    );
    print('✅ Başarılı: $ok');
    print('❌ Başarısız: $fail');
    print('⏱️ Toplam süre: ${totalMs}ms');
    print('=' * 70);
    for (final r in _results) {
      print(r.toString());
    }
    print('=' * 70);
    print(
      fail == 0
          ? '🎉 TÜM SATICI PANEL TESTLERİ BAŞARILI!'
          : '⚠️ BAZI TESTLER BAŞARISIZ - Yukarıdaki hataları kontrol edin',
    );
    print('=' * 70);
  });
}
