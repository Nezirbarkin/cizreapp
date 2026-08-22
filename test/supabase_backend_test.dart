// =============================================================================
// Supabase Backend Smoke Test - Plugin gerektirmez
// CizreApp - Backend'in ayakta olduğunu doğrular
// =============================================================================
// Kullanım:
//   flutter test test/supabase_backend_test.dart
//
// NOT: Bu test plugin gerektirmez, sadece HTTP üzerinden backend'i kontrol eder.
// Detaylı DB/Auth testleri için integration_test/ klasörünü kullanın.
// =============================================================================

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/constants/app_constants.dart';

// Test sonuçlarını tutacak yapı
class TestResult {
  final String name;
  final bool success;
  final String? error;
  final Duration duration;

  TestResult({
    required this.name,
    required this.success,
    this.error,
    required this.duration,
  });

  @override
  String toString() {
    final status = success ? '✅ BAŞARILI' : '❌ BAŞARISIZ';
    final errorMsg = error != null ? '\n   Hata: $error' : '';
    return '$status [${duration.inMilliseconds}ms] $name$errorMsg';
  }
}

final List<TestResult> _results = [];

Future<void> _runTest(String name, Future<void> Function() testFn) async {
  final stopwatch = Stopwatch()..start();
  try {
    await testFn();
    stopwatch.stop();
    _results.add(
      TestResult(name: name, success: true, duration: stopwatch.elapsed),
    );
  } catch (e) {
    stopwatch.stop();
    _results.add(
      TestResult(
        name: name,
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsed,
      ),
    );
  }
}

void main() {
  // ===========================================================================
  // 1. BAĞLANTI TESTLERİ (Plugin gerektirmez)
  // ===========================================================================
  group('🔌 BAĞLANTI TESTLERİ', () {
    test('Supabase URL ve Key doğrulama', () {
      final url = AppConstants.supabaseUrl;
      final key = AppConstants.supabaseAnonKey;

      expect(url.isNotEmpty, true, reason: 'Supabase URL tanımlı olmalı');
      expect(
        url.startsWith('https://'),
        true,
        reason: 'URL https:// ile başlamalı',
      );
      expect(key.isNotEmpty, true, reason: 'Anon Key tanımlı olmalı');
      expect(
        key.length > 100,
        true,
        reason: 'Anon Key yeterli uzunlukta olmalı (JWT)',
      );
    });
  });

  // ===========================================================================
  // 2. HTTP BACKEND TESTLERİ (Plugin gerektirmez)
  // ===========================================================================
  group('🌐 HTTP BACKEND TESTLERİ', () {
    late HttpClient client;

    setUpAll(() {
      client = HttpClient();
    });

    tearDownAll(() {
      client.close();
    });

    test('REST API health check', () async {
      final url = '${AppConstants.supabaseUrl}/rest/v1/';
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('apikey', AppConstants.supabaseAnonKey);

      final response = await request.close();
      final statusCode = response.statusCode;
      await response.drain<void>();

      print('   📡 REST API status: $statusCode');
      // 200, 401, 403, 404 → backend ayakta
      expect(statusCode, anyOf(200, 401, 403, 404));
    });

    test('Auth API health check', () async {
      final url = '${AppConstants.supabaseUrl}/auth/v1/settings';
      final request = await client.getUrl(Uri.parse(url));

      final response = await request.close();
      final statusCode = response.statusCode;
      await response.drain<void>();

      print('   🔐 Auth API status: $statusCode');
      expect(statusCode, anyOf(200, 400, 401, 404));
    });

    test('Public tablo okuma - categories', () async {
      final url =
          '${AppConstants.supabaseUrl}/rest/v1/categories?select=id,name,icon&limit=5';
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('apikey', AppConstants.supabaseAnonKey);
      request.headers.set(
        'Authorization',
        'Bearer ${AppConstants.supabaseAnonKey}',
      );

      final response = await request.close();
      final statusCode = response.statusCode;
      final body = await response.transform(utf8.decoder).join();

      print('   📋 Categories status: $statusCode');

      if (statusCode == 200) {
        final data = jsonDecode(body) as List;
        print('   📋 ${data.length} kategori bulundu');
        expect(data, isA<List>());
      } else {
        final preview = body.length > 200 ? body.substring(0, 200) : body;
        print('   ⚠️ Yanıt: $preview');
        // 4xx kabul edilir (RLS/Tablo yok), 5xx sunucu hatası
        expect(statusCode, lessThan(500), reason: '5xx sunucu hatası var');
      }
    });

    test('Public tablo okuma - shops (active)', () async {
      final url =
          '${AppConstants.supabaseUrl}/rest/v1/shops?select=id,name,is_active&is_active=eq.true&limit=5';
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('apikey', AppConstants.supabaseAnonKey);
      request.headers.set(
        'Authorization',
        'Bearer ${AppConstants.supabaseAnonKey}',
      );

      final response = await request.close();
      final statusCode = response.statusCode;
      final body = await response.transform(utf8.decoder).join();

      print('   🏪 Shops status: $statusCode');

      if (statusCode == 200) {
        final data = jsonDecode(body) as List;
        print('   🏪 ${data.length} aktif mağaza bulundu');
        expect(data, isA<List>());
      } else {
        final preview = body.length > 200 ? body.substring(0, 200) : body;
        print('   ⚠️ Yanıt: $preview');
        expect(statusCode, lessThan(500));
      }
    });

    test('Public tablo okuma - products (active)', () async {
      final url =
          '${AppConstants.supabaseUrl}/rest/v1/products?select=id,name,price&is_active=eq.true&limit=5';
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('apikey', AppConstants.supabaseAnonKey);
      request.headers.set(
        'Authorization',
        'Bearer ${AppConstants.supabaseAnonKey}',
      );

      final response = await request.close();
      final statusCode = response.statusCode;
      final body = await response.transform(utf8.decoder).join();

      print('   📦 Products status: $statusCode');

      if (statusCode == 200) {
        final data = jsonDecode(body) as List;
        print('   📦 ${data.length} aktif ürün bulundu');
        expect(data, isA<List>());
      } else {
        final preview = body.length > 200 ? body.substring(0, 200) : body;
        print('   ⚠️ Yanıt: $preview');
        expect(statusCode, lessThan(500));
      }
    });

    test('Storage API - avatars bucket listeleme', () async {
      final url = '${AppConstants.supabaseUrl}/storage/v1/bucket/avatars';
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('apikey', AppConstants.supabaseAnonKey);
      request.headers.set(
        'Authorization',
        'Bearer ${AppConstants.supabaseAnonKey}',
      );

      final response = await request.close();
      final statusCode = response.statusCode;
      await response.drain<void>();

      print('   🖼️ Avatars bucket status: $statusCode');
      // 200 (var) veya 400/404 (yok) kabul edilir
      expect(statusCode, anyOf(200, 400, 401, 403, 404));
    });
  });

  // ===========================================================================
  // 3. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 70}');
    print('📋 BACKEND TEST SONUÇ RAPORU');
    print('=' * 70);

    final successCount = _results.where((r) => r.success).length;
    final failCount = _results.where((r) => !r.success).length;
    final totalDuration = _results.fold<int>(
      0,
      (sum, r) => sum + r.duration.inMilliseconds,
    );

    print('✅ Başarılı: $successCount');
    print('❌ Başarısız: $failCount');
    print('⏱️ Toplam süre: ${totalDuration}ms');
    print('=' * 70);

    for (final result in _results) {
      print(result.toString());
    }

    print('=' * 70);
    print(
      failCount == 0
          ? '🎉 TÜM BACKEND TESTLERİ BAŞARILI!'
          : '⚠️ BAZI TESTLER BAŞARISIZ - Yukarıdaki hataları kontrol edin',
    );
    print('=' * 70);
  });
}
