import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// `fetch-og-image` fonksiyonunun bulduğu ürün görseli.
class ScrapedProductImage {
  const ScrapedProductImage({
    required this.bytes,
    required this.mimeType,
    required this.extension,
    required this.imageUrl,
    this.title,
  });

  final Uint8List bytes;
  final String mimeType;

  /// Küçük harfli, noktasız: jpg / png / webp.
  final String extension;

  /// Görselin özgün (dış site) adresi; yalnızca bilgi amaçlı, kaydedilmez.
  final String imageUrl;

  /// Sayfanın başlığı (og:title); ad alanlarını önermek için.
  final String? title;

  /// Storage yükleme yolları uzantıyı dosya adından okur.
  String get fileName => 'linkten.$extension';
}

/// Kullanıcıya olduğu gibi gösterilebilecek Türkçe bir mesaj taşır.
class ProductImageScrapeException implements Exception {
  const ProductImageScrapeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Bir web sayfası linkinden ürün görselini (og:image) sunucu üzerinden alır.
///
/// Görseli tarayıcıdan/uygulamadan doğrudan indirmek yerine Edge Function
/// kullanılır: dış sitelerde CORS ve hotlink engeli vardır, ayrıca sunucu
/// tarafı iç ağa erişimi engelleyen doğrulamayı yapar. Baytlar döndüğü için
/// çağıran taraf görseli normal bir dosya gibi kendi bucket'ına yükler.
class ProductImageScrapeService {
  ProductImageScrapeService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<ScrapedProductImage> fetchFromLink(String link) async {
    final url = link.trim();
    if (url.isEmpty) {
      throw const ProductImageScrapeException('Bir bağlantı yapıştırın');
    }

    final dynamic data;
    try {
      final response = await _supabase.functions.invoke(
        'fetch-og-image',
        body: {'url': url},
      );
      data = response.data;
    } on FunctionException catch (e) {
      throw ProductImageScrapeException(_messageForFailure(e));
    } catch (e) {
      debugPrint('fetch-og-image bağlantı hatası: $e');
      throw const ProductImageScrapeException(
        'Sunucuya ulaşılamadı; internet bağlantınızı kontrol edin',
      );
    }

    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    if (map == null) {
      throw const ProductImageScrapeException('Beklenmeyen bir yanıt alındı');
    }
    if (map['ok'] != true) {
      throw ProductImageScrapeException(
        (map['message'] as String?) ?? 'Görsel alınamadı',
      );
    }

    final encoded = map['image_base64'];
    if (encoded is! String || encoded.isEmpty) {
      throw const ProductImageScrapeException('Görsel alınamadı');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      throw const ProductImageScrapeException('Görsel verisi bozuk geldi');
    }

    return ScrapedProductImage(
      bytes: bytes,
      mimeType: (map['content_type'] as String?) ?? 'image/jpeg',
      extension: (map['extension'] as String?) ?? 'jpg',
      imageUrl: (map['image_url'] as String?) ?? url,
      title: _cleanTitle(map['title']),
    );
  }

  static String? _cleanTitle(Object? raw) {
    if (raw is! String) return null;
    final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? null : t;
  }

  /// 200 dışı yanıtlar (yetki, hız sınırı, sunucu hatası).
  static String _messageForFailure(FunctionException e) {
    final details = e.details;
    if (details is Map && details['message'] is String) {
      return details['message'] as String;
    }
    switch (e.status) {
      case 401:
        return 'Oturumunuz sona ermiş; yeniden giriş yapın';
      case 403:
        return 'Bu özellik yalnızca satıcılar ve yöneticiler içindir';
      case 429:
        return 'Çok fazla deneme yapıldı; bir dakika sonra tekrar deneyin';
      default:
        debugPrint('fetch-og-image hatası: $e');
        return 'Görsel alınamadı; biraz sonra tekrar deneyin';
    }
  }
}
