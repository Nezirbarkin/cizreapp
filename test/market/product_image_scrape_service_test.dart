import 'dart:convert';
import 'dart:typed_data';

import 'package:cizreapp/features/market/services/product_image_scrape_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `fetch-og-image` çağrısını taklit eden Supabase istemcisi.
SupabaseClient _client(
  http.Response Function(http.Request req) handler, {
  List<http.Request>? seen,
}) {
  return SupabaseClient(
    'https://example.supabase.co',
    'anon-key',
    httpClient: MockClient((req) async {
      seen?.add(req);
      return handler(req);
    }),
  );
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2, 3]);

  test('başarılı yanıt bayt, uzantı ve başlığı çözer', () async {
    final seen = <http.Request>[];
    final service = ProductImageScrapeService(
      client: _client(
        (_) => _json({
          'ok': true,
          'image_url': 'https://cdn.example.com/a.jpg',
          'title': '  Kırmızı   Domates ',
          'content_type': 'image/jpeg',
          'extension': 'jpg',
          'image_base64': base64Encode(jpeg),
        }),
        seen: seen,
      ),
    );

    final image = await service.fetchFromLink('  https://shop.example.com/u  ');

    expect(image.bytes, jpeg);
    expect(image.extension, 'jpg');
    expect(image.fileName, 'linkten.jpg');
    expect(image.title, 'Kırmızı Domates');
    expect(image.imageUrl, 'https://cdn.example.com/a.jpg');
    // Link kırpılarak gönderilir ve doğru fonksiyon çağrılır.
    expect(seen.single.url.path, endsWith('/functions/v1/fetch-og-image'));
    expect(jsonDecode(seen.single.body), {'url': 'https://shop.example.com/u'});
  });

  test('beklenen hata (ok:false) sunucunun Türkçe mesajıyla fırlar', () async {
    final service = ProductImageScrapeService(
      client: _client(
        (_) => _json({
          'ok': false,
          'error': 'NO_IMAGE',
          'message': 'Bu sayfada ürün görseli bulunamadı',
        }),
      ),
    );

    await expectLater(
      service.fetchFromLink('https://shop.example.com/u'),
      throwsA(
        isA<ProductImageScrapeException>().having(
          (e) => e.message,
          'message',
          'Bu sayfada ürün görseli bulunamadı',
        ),
      ),
    );
  });

  test('boş link sunucuya gitmeden reddedilir', () async {
    var called = false;
    final service = ProductImageScrapeService(
      client: _client((_) {
        called = true;
        return _json({'ok': true});
      }),
    );

    await expectLater(
      service.fetchFromLink('   '),
      throwsA(isA<ProductImageScrapeException>()),
    );
    expect(called, isFalse);
  });

  test('yetki ve hız sınırı durumları anlaşılır mesaj verir', () async {
    Future<String> messageFor(int status) async {
      final service = ProductImageScrapeService(
        client: _client((_) => _json({'error_code': 'X'}, status: status)),
      );
      try {
        await service.fetchFromLink('https://shop.example.com/u');
      } on ProductImageScrapeException catch (e) {
        return e.message;
      }
      return 'hata fırlamadı';
    }

    expect(await messageFor(403), contains('satıcılar ve yöneticiler'));
    expect(await messageFor(401), contains('yeniden giriş'));
    expect(await messageFor(500), contains('tekrar deneyin'));
  });

  test('429 yanıtındaki sunucu mesajı korunur', () async {
    final service = ProductImageScrapeService(
      client: _client(
        (_) => _json({
          'ok': false,
          'error': 'RATE_LIMITED',
          'message':
              'Çok fazla deneme yapıldı; bir dakika sonra tekrar deneyin',
        }, status: 429),
      ),
    );

    await expectLater(
      service.fetchFromLink('https://shop.example.com/u'),
      throwsA(
        isA<ProductImageScrapeException>().having(
          (e) => e.message,
          'message',
          contains('bir dakika'),
        ),
      ),
    );
  });

  test('bozuk base64 yanıtı kontrollü hataya çevrilir', () async {
    final service = ProductImageScrapeService(
      client: _client(
        (_) => _json({'ok': true, 'image_base64': '***bozuk***'}),
      ),
    );

    await expectLater(
      service.fetchFromLink('https://shop.example.com/u'),
      throwsA(isA<ProductImageScrapeException>()),
    );
  });
}
