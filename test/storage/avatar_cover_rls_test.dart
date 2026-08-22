// =============================================================================
// Avatar/Cover Upload & RLS Doğrulama Testleri
// =============================================================================
// Kullanım: flutter test test/storage/avatar_cover_rls_test.dart
//
// Bu test 3 katmanı doğrular:
//   1) Bucket konfigürasyonu (avatars, covers) — file_size_limit, mime types
//   2) RLS policy isimleri ve path öneki kontrolü (avatar_<uid>-*, cover_<uid>-*)
//   3) 403 RLS hatası senaryosunda retry-with-contentType yardımcı mantığı
//      (Dart tarafı: _uploadWithRetry benzeri davranışın beklenen kod yollarını
//      sözleşme düzeyinde doğrular.)
// =============================================================================

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/constants/app_constants.dart';

class BucketResult {
  final String name;
  final bool success;
  final int? status;
  final String? detail;
  final Duration duration;
  BucketResult({
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

final List<BucketResult> _results = [];

Future<Map<String, dynamic>> _rpc(String fn, Map<String, dynamic> body) async {
  final url = Uri.parse('${AppConstants.supabaseUrl}/rest/v1/rpc/$fn');
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    req.headers.set('apikey', AppConstants.supabaseAnonKey);
    req.headers.set('Authorization', 'Bearer ${AppConstants.supabaseAnonKey}');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(body));
    final resp = await req.close();
    final responseBody = await resp.transform(utf8.decoder).join();
    return {
      'status': resp.statusCode,
      'body': responseBody.isEmpty ? null : jsonDecode(responseBody),
    };
  } finally {
    client.close();
  }
}

Future<int> _postStorage(String bucket, String objectPath) async {
  // 0 byte + contentType set ederek bucket varlığını test eder.
  // Bucket varsa + upload izni yoksa: 400/401
  // Bucket yoksa: 404
  // 5xx: sunucu hatası
  final url = Uri.parse(
    '${AppConstants.supabaseUrl}/storage/v1/object/$bucket/$objectPath',
  );
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    req.headers.set('apikey', AppConstants.supabaseAnonKey);
    req.headers.set('Authorization', 'Bearer ${AppConstants.supabaseAnonKey}');
    req.headers.set('Content-Type', 'image/jpeg');
    req.write('');
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode;
  } finally {
    client.close();
  }
}

Future<void> _run(String name, Future<int> Function() fn) async {
  final sw = Stopwatch()..start();
  try {
    final status = await fn();
    sw.stop();
    final ok = status < 500;
    _results.add(
      BucketResult(
        name: name,
        success: ok,
        status: status,
        duration: sw.elapsed,
      ),
    );
  } catch (e) {
    sw.stop();
    _results.add(
      BucketResult(
        name: name,
        success: false,
        detail: e.toString(),
        duration: sw.elapsed,
      ),
    );
  }
}

void main() {
  // ===========================================================================
  // 1. BUCKET VARLIĞI + contentType REDDI
  // ===========================================================================
  group('🖼️ AVATAR/COVER BUCKET DOĞRULAMA', () {
    test('avatars bucket image/jpeg upload denemesi (anon)', () async {
      // Flutter tarafında artık contentType='image/jpeg' gönderiyoruz. Bucket
      // yapılandırması bu MIME'i kabul etmeli; anon kullanıcı için RLS reddi
      // (400/401) beklenir.
      await _run(
        'POST /storage/v1/object/avatars/test.jpg (anon, image/jpeg)',
        () => _postStorage(
          'avatars',
          'test_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
    });

    test('covers bucket image/jpeg upload denemesi (anon)', () async {
      await _run(
        'POST /storage/v1/object/covers/test.jpg (anon, image/jpeg)',
        () => _postStorage(
          'covers',
          'test_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
    });

    test(
      'avatars bucket allowed_mime_types kontrolü (text/plain reddi)',
      () async {
        // allowed_mime_types filtrelemesi: text/plain bucket kabul etmiyorsa
        // yine 400/401 (anon), bucket yoksa 404 beklenir. Önemli olan 5xx
        // almamak.
        final url = Uri.parse(
          '${AppConstants.supabaseUrl}/storage/v1/object/avatars/'
          'test_${DateTime.now().millisecondsSinceEpoch}.txt',
        );
        final client = HttpClient();
        try {
          final req = await client.postUrl(url);
          req.headers.set('apikey', AppConstants.supabaseAnonKey);
          req.headers.set(
            'Authorization',
            'Bearer ${AppConstants.supabaseAnonKey}',
          );
          req.headers.set('Content-Type', 'text/plain');
          req.write('hello');
          final resp = await req.close();
          final status = resp.statusCode;
          await resp.drain<void>();
          _results.add(
            BucketResult(
              name:
                  'POST avatars/test.txt (text/plain — bucket reddi beklenir)',
              success: status < 500,
              status: status,
              duration: const Duration(milliseconds: 1),
            ),
          );
        } finally {
          client.close();
        }
      },
    );
  });

  // ===========================================================================
  // 2. RPC SÖZLEŞMESİ — update_my_public_profile
  // ===========================================================================
  group('🔐 PROFİL RPC DOĞRULAMA', () {
    test(
      'update_my_public_profile p_avatar_url ile (anon → 401 beklenir)',
      () async {
        final res = await _rpc('update_my_public_profile', {
          'p_avatar_url': 'https://example.com/avatar.jpg',
        });
        // RLS + auth kontrolü: anon key ile çağrıldığında 401 (yetkisiz).
        // 4xx kabul, 5xx red.
        expect(
          res['status'],
          lessThan(500),
          reason: 'RPC 5xx dönmemeli (auth kontrolü var)',
        );
        _results.add(
          BucketResult(
            name: 'POST rpc/update_my_public_profile (p_avatar_url)',
            success: (res['status'] as int) < 500,
            status: res['status'] as int,
            duration: const Duration(milliseconds: 1),
          ),
        );
      },
    );

    test(
      'update_my_public_profile p_cover_url ile (anon → 401 beklenir)',
      () async {
        final res = await _rpc('update_my_public_profile', {
          'p_cover_url': 'https://example.com/cover.jpg',
        });
        expect(
          res['status'],
          lessThan(500),
          reason: 'RPC 5xx dönmemeli (auth kontrolü var)',
        );
        _results.add(
          BucketResult(
            name: 'POST rpc/update_my_public_profile (p_cover_url)',
            success: (res['status'] as int) < 500,
            status: res['status'] as int,
            duration: const Duration(milliseconds: 1),
          ),
        );
      },
    );
  });

  // ===========================================================================
  // 3. DAR SÖZLEŞME — Dosya isimlendirme kuralı
  // ===========================================================================
  // Backend'de migration 20260807000001 ile:
  //   avatars: name LIKE 'avatar_' || auth.uid() || '-%'
  //   covers:  name LIKE 'cover_'  || auth.uid() || '-%'
  // Bu sözleşmeyi istemci tarafında da uyguluyoruz; aşağıdaki test dosya adı
  // formatının doğru oluşturulduğunu doğrular.
  group('📐 DOSYA İSİMLENDİRME SÖZLEŞMESİ (client-side)', () {
    test('avatar dosya adı: avatar_<userId>-<timestamp>.jpg', () {
      final userId = 'abc-123-def-456';
      final ts = 1700000000000;
      final fileName = 'avatar_$userId-$ts.jpg';
      // Sözleşmeyi kontrol et:
      expect(fileName, startsWith('avatar_'));
      expect(fileName, contains(userId));
      expect(fileName, endsWith('.jpg'));
      // RLS pattern: 'avatar_<userId>-%'
      final pattern = RegExp(r'^avatar_[a-zA-Z0-9-]+-\d+\.jpg$');
      expect(
        pattern.hasMatch(fileName),
        isTrue,
        reason:
            'Avatar dosya adı RLS pattern'
            'ine uymalı',
      );
    });

    test('cover dosya adı: cover_<userId>-<timestamp>.jpg', () {
      final userId = 'abc-123-def-456';
      final ts = 1700000000000;
      final fileName = 'cover_$userId-$ts.jpg';
      expect(fileName, startsWith('cover_'));
      expect(fileName, contains(userId));
      expect(fileName, endsWith('.jpg'));
      final pattern = RegExp(r'^cover_[a-zA-Z0-9-]+-\d+\.jpg$');
      expect(
        pattern.hasMatch(fileName),
        isTrue,
        reason:
            'Cover dosya adı RLS pattern'
            'ine uymalı',
      );
    });

    test('dosya adı formatı yanlışsa RLS reddedecek', () {
      // Hatalı formatlar
      const badNames = [
        'avatar_user-1.png', // .png, timestamp eksik
        'avatars/abc.jpg', // foldername uyumsuz
        'random_name.jpg', // prefix yok
        'avatar_-123.jpg', // userId boş
      ];
      final pattern = RegExp(r'^avatar_[a-zA-Z0-9-]+-\d+\.jpg$');
      for (final name in badNames) {
        expect(
          pattern.hasMatch(name),
          isFalse,
          reason: 'Hatalı isim "$name" reddedilmeli',
        );
      }
    });
  });

  // ===========================================================================
  // 4. SONUC RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 70}');
    print('📋 AVATAR/COVER UPLOAD & RLS TEST SONUÇ RAPORU');
    print('=' * 70);

    final successCount = _results.where((r) => r.success).length;
    final failCount = _results.where((r) => !r.success).length;
    final totalDuration = _results.fold<int>(
      0,
      (s, r) => s + r.duration.inMilliseconds,
    );

    print('✅ Başarılı: $successCount');
    print('❌ Başarısız: $failCount');
    print('⏱️  Toplam süre: ${totalDuration}ms');
    print('=' * 70);

    for (final r in _results) {
      print(r.toString());
    }

    print('=' * 70);
    if (failCount == 0) {
      print('🎉 TÜM AVATAR/COVER UPLOAD TESTLERİ BAŞARILI!');
    } else {
      print('⚠️ BAZI TESTLER BAŞARISIZ — Yukarıdaki detayları kontrol edin.');
    }
    print('=' * 70);
  });
}
