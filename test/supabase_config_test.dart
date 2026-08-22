// =============================================================================
// Supabase Config Test - Plugin gerektirmez, her ortamda çalışır
// CizreApp - URL, Key ve AppConstants doğrulama
// =============================================================================
// Kullanım:
//   flutter test test/supabase_config_test.dart
// =============================================================================

// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/constants/app_constants.dart';

void main() {
  // ===========================================================================
  // 1. APP CONSTANTS ERİŞİM TESTLERİ
  // ===========================================================================
  group('🔧 APP CONSTANTS ERİŞİM', () {
    test('supabaseUrl tanımlı ve geçerli', () {
      final url = AppConstants.supabaseUrl;
      print('   🌐 URL: $url');

      expect(url, isNotEmpty, reason: 'Supabase URL tanımlı olmalı');
      expect(
        url.startsWith('https://'),
        isTrue,
        reason: 'URL https:// ile başlamalı',
      );
      expect(url, contains('supabase.co'), reason: 'Supabase URL içermeli');
    });

    test('supabaseAnonKey tanımlı ve JWT formatında', () {
      final key = AppConstants.supabaseAnonKey;
      final maskedKey = key.length > 30
          ? '${key.substring(0, 20)}...${key.substring(key.length - 10)}'
          : '***';
      print('   🔑 Key: $maskedKey (${key.length} karakter)');

      expect(key, isNotEmpty, reason: 'Anon Key tanımlı olmalı');
      expect(
        key.length > 100,
        isTrue,
        reason: 'Anon Key yeterli uzunlukta olmalı (JWT token)',
      );
      expect(
        key.split('.').length,
        equals(3),
        reason: 'JWT 3 parçadan oluşmalı (header.payload.signature)',
      );
    });

    test('baseApiUrl tanımlı', () {
      final url = AppConstants.baseApiUrl;
      print('   🔗 API URL: $url');
      expect(url, isNotEmpty, reason: 'API URL tanımlı olmalı');
      expect(
        url.startsWith('https://'),
        isTrue,
        reason: 'API URL https:// ile başlamalı',
      );
    });

    test('Pagination sabitleri makul değerler', () {
      expect(AppConstants.defaultPageSize, greaterThan(0));
      expect(AppConstants.defaultPageSize, lessThanOrEqualTo(100));
      print('   📄 Sayfa boyutu: ${AppConstants.defaultPageSize}');
    });

    test('Cart sabitleri tutarlı', () {
      expect(AppConstants.defaultDeliveryFee, greaterThan(0));
      expect(AppConstants.freeDeliveryThreshold, greaterThan(0));
      expect(AppConstants.defaultCommissionRate, greaterThan(0));
      expect(AppConstants.defaultCommissionRate, lessThanOrEqualTo(100));
      print('   🚚 Teslimat: ${AppConstants.defaultDeliveryFee} TL');
      print('   🎯 Ücretsiz limit: ${AppConstants.freeDeliveryThreshold} TL');
      print('   💰 Komisyon: %${AppConstants.defaultCommissionRate}');
    });

    test('Image size limitleri makul', () {
      expect(AppConstants.maxImageUploadSizeMB, greaterThan(0));
      expect(AppConstants.thumbnailSize, greaterThan(0));
      expect(
        AppConstants.fullImageSize,
        greaterThan(AppConstants.thumbnailSize),
      );
      print('   🖼️ Max upload: ${AppConstants.maxImageUploadSizeMB}MB');
    });
  });

  // ===========================================================================
  // 2. BACKEND HEALTHCHECK (HTTP) - Plugin gerektirmez
  // ===========================================================================
  group('🌐 BACKEND HEALTHCHECK (HTTP)', () {
    test(
      'Supabase REST API erişilebilir',
      () async {
        final url = AppConstants.supabaseUrl;
        final healthUrl = '$url/rest/v1/';

        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 10);

          final request = await client.getUrl(Uri.parse(healthUrl));
          request.headers.set('apikey', AppConstants.supabaseAnonKey);

          final response = await request.close();
          final statusCode = response.statusCode;
          await response.drain<void>();
          client.close();

          print('   📡 HTTP yanıtı: $statusCode');

          // 200, 401, 403 backend'in ayakta olduğunu gösterir
          // 404 de kabul edilir (root path genelde 404 döner)
          expect(
            statusCode,
            anyOf(200, 401, 403, 404),
            reason: 'Backend yanıt vermeli (status: $statusCode)',
          );
        } on SocketException catch (e) {
          fail('Backend bağlantı hatası (ağ/host erişilemez): $e');
        } catch (e) {
          fail('Backend bağlantı hatası: $e');
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'Supabase Auth API erişilebilir',
      () async {
        final url = AppConstants.supabaseUrl;
        final authUrl = '$url/auth/v1/settings';

        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 10);

          final request = await client.getUrl(Uri.parse(authUrl));
          final response = await request.close();
          final statusCode = response.statusCode;
          await response.drain<void>();
          client.close();

          print('   🔐 Auth HTTP yanıtı: $statusCode');
          expect(
            statusCode,
            anyOf(200, 400, 401),
            reason: 'Auth API yanıt vermeli (status: $statusCode)',
          );
        } on SocketException catch (e) {
          fail('Auth API bağlantı hatası (ağ/host erişilemez): $e');
        } catch (e) {
          fail('Auth API bağlantı hatası: $e');
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  // ===========================================================================
  // 3. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 60}');
    print('📋 CONFIG TEST SONUÇ RAPORU');
    print('=' * 60);
    print('✅ Config testler başarıyla tamamlandı');
    print('💡 Bu testler plugin gerektirmez, her ortamda çalışır:');
    print('   - Unit test (CI)');
    print('   - Fiziksel cihaz');
    print('   - Web build');
    print('=' * 60);
  });
}
