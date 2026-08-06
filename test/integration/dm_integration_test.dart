// =============================================================================
// DM Integration Test - Gerçek Supabase'e bağlanır
// CizreApp - 1'e 1 mesaj gönderme/alma akışını test eder
// =============================================================================
// Kullanım:
//   flutter test test/integration/dm_integration_test.dart
//
// Bu test Supabase'e gerçek HTTP istek gönderir. Hata varsa tam hata
// mesajını gösterir (RLS, auth, network, vb. sorunlar).
// =============================================================================

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/constants/app_constants.dart';

class DmTestResult {
  final String name;
  final bool success;
  final String? error;
  final String? details;
  final int statusCode;
  final Duration duration;

  DmTestResult({
    required this.name,
    required this.success,
    this.error,
    this.details,
    required this.statusCode,
    required this.duration,
  });
}

final List<DmTestResult> _results = [];

Future<void> _runTest(
  String name,
  int expectedStatus,
  Future<int> Function() testFn,
) async {
  final stopwatch = Stopwatch()..start();
  try {
    final statusCode = await testFn();
    stopwatch.stop();
    final success = statusCode == expectedStatus ||
        (expectedStatus == 200 &&
            (statusCode == 200 || statusCode == 201));
    _results.add(DmTestResult(
      name: name,
      success: success,
      statusCode: statusCode,
      duration: stopwatch.elapsed,
    ));
  } catch (e) {
    stopwatch.stop();
    _results.add(DmTestResult(
      name: name,
      success: false,
      error: e.toString(),
      statusCode: 0,
      duration: stopwatch.elapsed,
    ));
  }
}

Future<int> _httpGet(String path) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  final request = await client.getUrl(Uri.parse('${AppConstants.supabaseUrl}$path'));
  request.headers.set('apikey', AppConstants.supabaseAnonKey);
  request.headers.set('Authorization', 'Bearer ${AppConstants.supabaseAnonKey}');
  final response = await request.close();
  final statusCode = response.statusCode;
  // Body'yi tüket (connection temizliği için)
  final body = await response.transform(utf8.decoder).join();
  client.close();
  print('   📥 Yanıt (${body.length} bytes): ${body.length > 300 ? "${body.substring(0, 300)}..." : body}');
  return statusCode;
}

void main() {
  // ===========================================================================
  // 1. MESSAGES TABLOSU ERİŞİMİ
  // ===========================================================================
  group('📨 Messages Tablosu Erişimi', () {
    test('messages tablosundan SELECT yapılabiliyor mu?', () async {
      // 5 mesaj çekmeyi dene
      final status = await _httpGet('/rest/v1/messages?select=id,sender_id,content&limit=5');
      print('   📊 Status: $status');

      if (status == 200) {
        print('   ✅ Messages tablosuna erişim var');
      } else if (status == 401) {
        print('   🔒 401 Unauthorized - RLS engelliyor olabilir');
      } else if (status == 403) {
        print('   🚫 403 Forbidden - RLS politikası reddediyor');
      } else {
        print('   ⚠️ Beklenmeyen durum: $status');
      }

      // 200 veya 401 kabul edilir (401 = RLS var, anon'a kapalı)
      expect(status, anyOf(200, 401));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('messages_insert_merged policy var mı?', () async {
      // INSERT denemesi - yeni mesaj eklemek istiyoruz
      // Geçersiz sender_id ile deneyelim (policy kontrolü için)
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(
        Uri.parse('${AppConstants.supabaseUrl}/rest/v1/messages'),
      );
      request.headers.set('apikey', AppConstants.supabaseAnonKey);
      request.headers.set('Authorization', 'Bearer ${AppConstants.supabaseAnonKey}');
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({
        'sender_id': '00000000-0000-0000-0000-000000000000',
        'content': 'test',
      }));

      try {
        final response = await request.close();
        final status = response.statusCode;
        final body = await response.transform(utf8.decoder).join();
        print('   📝 INSERT Status: $status');
        print('   📝 Yanıt: ${body.length > 300 ? "${body.substring(0, 300)}..." : body}');

        if (status == 401) {
          print('   🔒 INSERT için authentication gerekiyor (normal)');
        } else if (status == 403) {
          print('   🚫 INSERT reddedildi - RLS policy mesaj yazmanı engelliyor');
          print('   💡 Çözüm: messages_insert_merged policy kontrol edilmeli');
        } else if (status == 400) {
          print('   ⚠️ 400 Bad Request - foreign key veya schema hatası');
        }
        client.close();
      } on SocketException catch (e) {
        print('   ❌ Network hatası: $e');
        rethrow;
      } finally {
        client.close();
      }
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ===========================================================================
  // 2. CONVERSATIONS TABLOSU
  // ===========================================================================
  group('💬 Conversations Tablosu', () {
    test('conversations tablosuna SELECT', () async {
      final status = await _httpGet('/rest/v1/conversations?select=id,user_id,other_user_id&limit=5');
      print('   💬 Status: $status');
      expect(status, anyOf(200, 401));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ===========================================================================
  // 3. RLS DURUMU
  // ===========================================================================
  group('🔒 RLS (Row Level Security) Durumu', () {
    test('Anon key ile messages SELECT', () async {
      // Anon olarak mesaj çekmeyi dene
      final status = await _httpGet('/rest/v1/messages?select=id&limit=1');
      print('   🔑 Anon SELECT status: $status');

      if (status == 200) {
        print('   ⚠️ RLS yok veya herkese açık - güvenlik riski olabilir');
      } else if (status == 401) {
        print('   ✅ RLS aktif ve korunuyor (anon erişimi kapalı)');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('Anon key ile messages INSERT', () async {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(
        Uri.parse('${AppConstants.supabaseUrl}/rest/v1/messages'),
      );
      request.headers.set('apikey', AppConstants.supabaseAnonKey);
      request.headers.set('Authorization', 'Bearer ${AppConstants.supabaseAnonKey}');
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({
        'sender_id': 'test',
        'content': 'test',
      }));

      final response = await request.close();
      final status = response.statusCode;
      final body = await response.transform(utf8.decoder).join();
      client.close();

      print('   🔑 Anon INSERT status: $status');
      print('   📋 Yanıt: ${body.length > 200 ? "${body.substring(0, 200)}..." : body}');

      // INSERT için 401 beklenir (anon authenticated değil)
      if (status == 401) {
        print('   ✅ INSERT authenticated kullanıcı gerektiriyor (güvenli)');
      } else if (status == 403) {
        print('   🚫 INSERT reddedildi');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ===========================================================================
  // 4. AUTH DURUMU
  // ===========================================================================
  group('🔐 Auth Durumu', () {
    test('Mevcut auth session var mı?', () async {
      final status = await _httpGet('/auth/v1/user');
      print('   👤 Auth user status: $status');
      if (status == 200) {
        print('   ✅ Aktif session var');
      } else {
        print('   ℹ️ Aktif session yok (login olmamış olabilirsin)');
      }
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ===========================================================================
  // 5. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 70}');
    print('🔍 DM INTEGRATION TEST SONUÇ RAPORU');
    print('=' * 70);
    print('Bu test gerçek Supabase bağlantısı kurar. Çıktıları incele:');
    print('  • 200 = ✅ Erişim var');
    print('  • 401 = 🔒 Auth/RLS engeli (login gerekli veya RLS aktif)');
    print('  • 403 = 🚫 RLS reddi (policy kontrolü gerekli)');
    print('  • 400 = ⚠️ Schema/foreign key hatası');
    print('=' * 70);
  });
}
