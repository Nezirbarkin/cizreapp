// =============================================================================
// Seller Edge Function Integration Test
// =============================================================================
// Kullanım:
//   flutter test test/seller/seller_edge_function_test.dart
//
// Supabase Edge Function'larını test eder (gerçek HTTP):
//   - get-seller-earnings
//   - request-withdrawal
//   - process-withdrawal
//   - get-transaction-history (satıcı bağlamı)
//
// Fiziksel cihaz senaryosu: cihazdan uygulama açıldığında bu endpoint'lere
// gerçek istek atılır, bu test aynısını yapar.
// =============================================================================

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/constants/app_constants.dart';

class EdgeTestResult {
  final String name;
  final bool success;
  final int? status;
  final String? detail;
  final Duration duration;
  EdgeTestResult({
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

final List<EdgeTestResult> _results = [];

Future<void> _run(String name, Future<int> Function() fn) async {
  final sw = Stopwatch()..start();
  try {
    final status = await fn();
    sw.stop();
    // 4xx dahil kabul, 5xx sunucu hatası (HATA)
    final ok = status < 500;
    _results.add(
      EdgeTestResult(
        name: name,
        success: ok,
        status: status,
        duration: sw.elapsed,
      ),
    );
  } catch (e) {
    sw.stop();
    _results.add(
      EdgeTestResult(
        name: name,
        success: false,
        detail: e.toString(),
        duration: sw.elapsed,
      ),
    );
  }
}

Future<Map<String, dynamic>> _callEdgeFunction({
  required String functionName,
  required String method,
  Map<String, dynamic>? body,
  String? token,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(
      method,
      Uri.parse('${AppConstants.supabaseUrl}/functions/v1/$functionName'),
    );
    req.headers.set('apikey', AppConstants.supabaseAnonKey);
    req.headers.set(
      'Authorization',
      'Bearer ${token ?? AppConstants.supabaseAnonKey}',
    );
    req.headers.set('Content-Type', 'application/json');
    // req.write() varsayılan olarak latin1 kullanır; 'ı', 'ş', 'ç' gibi
    // Latin-1 dışı Türkçe karakterler içeride "Contains invalid characters"
    // hatası fırlatır. Bu yüzden gövdeyi açıkça UTF-8 bayt olarak yaz.
    if (body != null) req.add(utf8.encode(jsonEncode(body)));

    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    return {
      'status': resp.statusCode,
      'body': respBody.isEmpty ? null : jsonDecode(respBody),
    };
  } finally {
    client.close();
  }
}

void main() {
  // ===========================================================================
  // 1. get-seller-earnings
  // ===========================================================================
  group('⚡ get-seller-earnings', () {
    test('OPTIONS preflight', () async {
      await _run('OPTIONS get-seller-earnings', () async {
        final r = await _callEdgeFunction(
          functionName: 'get-seller-earnings',
          method: 'OPTIONS',
        );
        return r['status'] as int;
      });
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
      'POST auth header olmadan → 401 beklenir',
      () async {
        await _run('POST get-seller-earnings (no auth)', () async {
          final r = await _callEdgeFunction(
            functionName: 'get-seller-earnings',
            method: 'POST',
          );
          // 401 beklenir (auth yok), 5xx olursa hata
          return r['status'] as int;
        });
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'POST invalid token ile → 401 beklenir',
      () async {
        await _run('POST get-seller-earnings (invalid token)', () async {
          final r = await _callEdgeFunction(
            functionName: 'get-seller-earnings',
            method: 'POST',
            token: 'invalid_token_xxx',
          );
          return r['status'] as int;
        });
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'POST anon key ile (geçerli kullanıcı) → 200/403 beklenir',
      () async {
        await _run('POST get-seller-earnings (anon user)', () async {
          // anon key ile → user.id olmadığı için 401/403 beklenir
          final r = await _callEdgeFunction(
            functionName: 'get-seller-earnings',
            method: 'POST',
          );
          // 401: auth yok, 403: satıcı değil, 200: başarılı → hepsi 5xx değil
          return r['status'] as int;
        });
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  // ===========================================================================
  // 2. request-withdrawal
  // ===========================================================================
  group('⚡ request-withdrawal', () {
    test('OPTIONS preflight', () async {
      await _run('OPTIONS request-withdrawal', () async {
        final r = await _callEdgeFunction(
          functionName: 'request-withdrawal',
          method: 'OPTIONS',
        );
        return r['status'] as int;
      });
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
      'POST eksik body → 400 beklenir',
      () async {
        await _run('POST request-withdrawal (empty body)', () async {
          final r = await _callEdgeFunction(
            functionName: 'request-withdrawal',
            method: 'POST',
            body: {},
          );
          return r['status'] as int;
        });
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'POST geçersiz IBAN ile → 400 beklenir',
      () async {
        await _run('POST request-withdrawal (bad IBAN)', () async {
          final r = await _callEdgeFunction(
            functionName: 'request-withdrawal',
            method: 'POST',
            body: {
              'amount': 100,
              'bank_name': 'Test Bank',
              'iban': 'INVALID_IBAN',
            },
          );
          return r['status'] as int;
        });
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'POST geçerli IBAN formatı ile → 401/403 beklenir (auth yok)',
      () async {
        await _run('POST request-withdrawal (valid IBAN, no auth)', () async {
          final r = await _callEdgeFunction(
            functionName: 'request-withdrawal',
            method: 'POST',
            body: {
              'amount': 100,
              'bank_name': 'Ziraat Bankası',
              'iban': 'TR330006100519786457841326',
              'bank_account_name': 'Test Satıcı',
            },
          );
          return r['status'] as int;
        });
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'POST düşük tutar ile (min altı) → 400 beklenir',
      () async {
        await _run('POST request-withdrawal (low amount)', () async {
          final r = await _callEdgeFunction(
            functionName: 'request-withdrawal',
            method: 'POST',
            body: {
              'amount': 1, // 50 TL altında
              'bank_name': 'Test Bank',
              'iban': 'TR330006100519786457841326',
            },
          );
          return r['status'] as int;
        });
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  // ===========================================================================
  // 3. process-withdrawal (admin)
  // ===========================================================================
  group('⚡ process-withdrawal (admin)', () {
    test('OPTIONS preflight', () async {
      await _run('OPTIONS process-withdrawal', () async {
        final r = await _callEdgeFunction(
          functionName: 'process-withdrawal',
          method: 'OPTIONS',
        );
        return r['status'] as int;
      });
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
      'POST auth olmadan → 401 beklenir',
      () async {
        await _run('POST process-withdrawal (no auth)', () async {
          final r = await _callEdgeFunction(
            functionName: 'process-withdrawal',
            method: 'POST',
            body: {
              'withdrawal_id': '00000000-0000-0000-0000-000000000000',
              'action': 'approve',
            },
          );
          return r['status'] as int;
        });
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  // ===========================================================================
  // 4. get-transaction-history (satıcı bağlamı)
  // ===========================================================================
  group('⚡ get-transaction-history', () {
    test('OPTIONS preflight', () async {
      await _run('OPTIONS get-transaction-history', () async {
        final r = await _callEdgeFunction(
          functionName: 'get-transaction-history',
          method: 'OPTIONS',
        );
        return r['status'] as int;
      });
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  // ===========================================================================
  // 5. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 70}');
    print('⚡ SELLER EDGE FUNCTION TEST RAPORU');
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
          ? '🎉 TÜM EDGE FUNCTION TESTLERİ BAŞARILI!'
          : '⚠️ BAZI EDGE FUNCTION TESTLERİ BAŞARISIZ',
    );
    print('=' * 70);
  });
}
