import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/product_image_preset_model.dart';
import '../../../core/models/product_model.dart';
import '../../market/services/product_image_preset_service.dart';
import '../../market/services/product_image_scrape_service.dart';
import '../models/bulk_product_draft.dart';
import '../utils/spreadsheet_io.dart';

/// Toplu yüklemenin ihtiyaç duyduğu mağaza bilgisi.
class BulkShopContext {
  const BulkShopContext({
    required this.shopId,
    required this.shopName,
    required this.categories,
    required this.products,
    required this.digitalCommissionRate,
    required this.ownStoragePrefix,
  });

  final String shopId;
  final String shopName;
  final List<String> categories;

  /// Mağazanın TÜM ürünleri (satışa kapalılar dahil).
  final List<Product> products;
  final double digitalCommissionRate;
  final String ownStoragePrefix;
}

/// `seller_bulk_upsert_products` satır sonucu.
class BulkRowResult {
  const BulkRowResult({required this.index, required this.ok, this.action, this.productId, this.error});

  final int index;
  final bool ok;

  /// 'created' | 'updated'
  final String? action;
  final String? productId;
  final String? error;

  factory BulkRowResult.fromJson(Map<String, dynamic> json) => BulkRowResult(
    index: (json['i'] as num).toInt(),
    ok: json['ok'] == true,
    action: json['action'] as String?,
    productId: json['id'] as String?,
    error: json['error'] as String?,
  );
}

class BulkUpsertResult {
  const BulkUpsertResult({
    required this.created,
    required this.updated,
    required this.failed,
    required this.addedCategories,
    required this.rows,
  });

  final int created;
  final int updated;
  final int failed;
  final List<String> addedCategories;
  final List<BulkRowResult> rows;

  factory BulkUpsertResult.fromJson(Map<String, dynamic> json) => BulkUpsertResult(
    created: (json['created'] as num?)?.toInt() ?? 0,
    updated: (json['updated'] as num?)?.toInt() ?? 0,
    failed: (json['failed'] as num?)?.toInt() ?? 0,
    addedCategories: [
      for (final c in (json['added_categories'] as List? ?? const [])) c.toString(),
    ],
    rows: [
      for (final r in (json['results'] as List? ?? const []))
        BulkRowResult.fromJson(Map<String, dynamic>.from(r as Map)),
    ],
  );
}

/// İndirilmiş/okunmuş, yüklenmeye hazır görsel.
class BulkImageBytes {
  const BulkImageBytes(this.bytes, this.extension, this.mimeType);

  final Uint8List bytes;

  /// jpg | png | webp
  final String extension;
  final String mimeType;
}

/// Görsel indirilemedi/geçersiz: satıcıya gösterilecek kısa neden.
class BulkImageException implements Exception {
  const BulkImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BulkProductService {
  BulkProductService({
    SupabaseClient? client,
    http.Client? httpClient,
    ProductImagePresetService? presets,
    ProductImageScrapeService? scraper,
  }) : _client = client,
       _http = httpClient,
       _presets = presets ?? ProductImagePresetService.shared,
       _scraper = scraper;

  final SupabaseClient? _client;
  final http.Client? _http;
  final ProductImagePresetService _presets;
  final ProductImageScrapeService? _scraper;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  /// Sunucu tek çağrıda en fazla 100 satır kabul eder; ilerleme çubuğu daha
  /// sık ilerlesin diye daha küçük parçalar gönderilir.
  static const int rpcChunkSize = 25;

  /// Bucket sınırı 5 MB; bunun üstündeki görseller (mobilde) sıkıştırılır.
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const int _compressAbove = 1536 * 1024;

  /// Bir dosyada işlenecek en fazla satır.
  static const int maxRows = 2000;

  static const String _bucket = 'shop-images';

  // ── Mağaza ──────────────────────────────────────────────────────────────────

  Future<BulkShopContext> loadShopContext() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Oturum bulunamadı; yeniden giriş yapın');

    final shop = await _supabase
        .from('shops')
        .select('id, name, seller_categories, digital_commission_rate')
        .eq('owner_id', userId)
        .maybeSingle();
    if (shop == null) throw Exception('Mağaza bulunamadı');

    final shopId = shop['id'] as String;
    final rows = await _supabase
        .from('products')
        .select()
        .eq('shop_id', shopId)
        .order('created_at', ascending: false);

    final rawCategories = shop['seller_categories'];
    return BulkShopContext(
      shopId: shopId,
      shopName: (shop['name'] as String?) ?? 'Mağazam',
      categories: rawCategories is List ? rawCategories.map((e) => e.toString()).toList() : const [],
      products: [
        for (final r in rows as List) Product.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
      digitalCommissionRate: (shop['digital_commission_rate'] as num?)?.toDouble() ?? 10.0,
      ownStoragePrefix: ownStoragePrefix(),
    );
  }

  /// `https://<proje>.supabase.co/storage/v1/object/public/`
  String ownStoragePrefix() {
    const marker = '/object/public/';
    final probe = _supabase.storage.from(_bucket).getPublicUrl('x');
    final i = probe.indexOf(marker);
    return i < 0 ? '' : probe.substring(0, i + marker.length);
  }

  // ── Yükleme ─────────────────────────────────────────────────────────────────

  Future<BulkUpsertResult> upsert(String shopId, List<Map<String, dynamic>> items) async {
    final response = await _supabase.rpc(
      'seller_bulk_upsert_products',
      params: {'p_shop_id': shopId, 'p_items': items},
    );
    return BulkUpsertResult.fromJson(Map<String, dynamic>.from(response as Map));
  }

  /// Görseli mağaza klasörüne yükler, herkese açık adresini döner.
  Future<String> uploadImage(String shopId, BulkImageBytes image) async {
    final rand = Random().nextInt(0x7fffffff).toRadixString(36);
    final path = 'shops/$shopId/bulk_${DateTime.now().millisecondsSinceEpoch}_$rand.${image.extension}';
    await _supabase.storage
        .from(_bucket)
        .uploadBinary(
          path,
          image.bytes,
          fileOptions: FileOptions(cacheControl: '3600', upsert: false, contentType: image.mimeType),
        );
    return _supabase.storage.from(_bucket).getPublicUrl(path);
  }

  /// Satırın görsellerini hazır adreslere çevirir (gerekenleri indirip
  /// yükler). Başarısız görsel atlanır, nedeni [failures]'a yazılır.
  Future<List<String>> prepareImages(
    String shopId,
    List<BulkImage> images, {
    required List<String> failures,
  }) async {
    final urls = <String>[];
    for (final img in images) {
      try {
        switch (img.kind) {
          case BulkImageKind.ready:
          case BulkImageKind.library:
            urls.add(img.url!);
          case BulkImageKind.file:
            final bytes = await img.read!();
            urls.add(await uploadImage(shopId, await normalizeImage(bytes, name: img.fileName)));
          case BulkImageKind.remote:
            urls.add(await uploadImage(shopId, await downloadImage(img.url!)));
        }
      } on BulkImageException catch (e) {
        failures.add('${img.fileName ?? _shortUrl(img.url)}: ${e.message}');
      } catch (e) {
        debugPrint('Toplu yükleme görsel hatası: $e');
        failures.add('${img.fileName ?? _shortUrl(img.url)}: yüklenemedi');
      }
    }
    return urls;
  }

  static String _shortUrl(String? url) {
    if (url == null) return 'görsel';
    final u = Uri.tryParse(url);
    final last = u?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return last ?? u?.host ?? url;
  }

  /// Bayt türünü tanır; büyükse (mobilde) JPEG'e sıkıştırır.
  Future<BulkImageBytes> normalizeImage(Uint8List bytes, {String? name}) async {
    final detected = sniffImageType(bytes);
    if (detected == null) {
      final lower = (name ?? '').toLowerCase();
      if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
        throw const BulkImageException('HEIC desteklenmiyor (JPG/PNG/WEBP kullanın)');
      }
      throw const BulkImageException('JPG, PNG ya da WEBP değil');
    }
    String type = detected;
    var data = bytes;
    if (data.length > _compressAbove && !kIsWeb) {
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          data,
          minWidth: 1600,
          minHeight: 1600,
          quality: 85,
        );
        if (compressed.isNotEmpty && compressed.length < data.length) {
          data = compressed;
          type = 'jpg';
        }
      } catch (e) {
        debugPrint('Görsel sıkıştırılamadı: $e');
      }
    }
    if (data.length > maxImageBytes) {
      throw const BulkImageException('5 MB\'tan büyük');
    }
    return BulkImageBytes(data, type, _mimeFor(type));
  }

  static String? sniffImageType(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpg';
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'webp';
    }
    return null;
  }

  static String _mimeFor(String ext) => switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };

  DateTime? _lastScrape;

  /// Dış bağlantıdaki görseli indirir. Mobilde doğrudan; web'de (CORS) ya da
  /// bağlantı bir ürün SAYFASIYSA `fetch-og-image` üzerinden (sayfanın ana
  /// görselini bulur). O fonksiyon kullanıcı başına dakikada 20 istekle
  /// sınırlı; web'de istekler aralıklandırılır.
  Future<BulkImageBytes> downloadImage(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw const BulkImageException('Geçersiz bağlantı');
    }
    if (!kIsWeb) {
      final client = _http ?? http.Client();
      try {
        final res = await client
            .get(uri, headers: const {'Accept': 'image/jpeg,image/png,image/webp,image/*;q=0.8,*/*;q=0.5'})
            .timeout(const Duration(seconds: 25));
        if (res.statusCode == 200 && sniffImageType(res.bodyBytes) != null) {
          if (res.bodyBytes.length > 15 * 1024 * 1024) {
            throw const BulkImageException('Görsel çok büyük');
          }
          return await normalizeImage(res.bodyBytes);
        }
        if (res.statusCode != 200) {
          final type = res.headers['content-type'] ?? '';
          if (!type.contains('html')) throw BulkImageException('Bağlantı açılamadı (${res.statusCode})');
        }
        // HTML sayfa: aşağıda sunucu tarafında ana görseli bulunur.
      } on BulkImageException {
        rethrow;
      } catch (e) {
        debugPrint('Doğrudan görsel indirme başarısız ($url): $e');
      } finally {
        if (_http == null) client.close();
      }
    }

    final last = _lastScrape;
    if (last != null) {
      final wait = const Duration(milliseconds: 3200) - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastScrape = DateTime.now();
    try {
      final scraped = await (_scraper ?? ProductImageScrapeService()).fetchFromLink(url);
      return await normalizeImage(scraped.bytes);
    } on ProductImageScrapeException catch (e) {
      throw BulkImageException(e.message);
    }
  }

  /// Ürün adıyla kütüphanede TÜM kelimeleri tutan ilk görsel.
  Future<ProductImagePreset?> findLibraryImage(String name) async {
    final q = name.trim();
    if (q.length < 3) return null;
    final found = await _presets.searchPresets(q, limit: 1);
    return found.isEmpty ? null : found.first;
  }

  // ── Şablon / dışa aktarma ───────────────────────────────────────────────────

  static const List<BulkField> templateFields = [
    BulkField.code,
    BulkField.name,
    BulkField.description,
    BulkField.price,
    BulkField.oldPrice,
    BulkField.stock,
    BulkField.category,
    BulkField.images,
    BulkField.available,
    BulkField.shippingFee,
    BulkField.freeShipping,
    BulkField.minOrder,
    BulkField.maxOrder,
    BulkField.badges,
  ];

  static const List<double> _widths = [38, 34, 44, 11, 11, 9, 20, 46, 10, 12, 14, 12, 12, 24];

  static String fieldHelp(BulkField f) => switch (f) {
    BulkField.code => 'Yeni üründe BOŞ bırakın. Dışa aktarılan dosyada dolu gelir; o ürünü günceller.',
    BulkField.name => 'Zorunlu. 2–200 karakter. Mağazanda aynı adlı ürün varsa yüklerken atla/güncelle/yine de ekle seçilir.',
    BulkField.description => 'İsteğe bağlı.',
    BulkField.price => 'Zorunlu. Satış fiyatı (TL). 12,50 ya da 12.50 yazabilirsiniz.',
    BulkField.oldPrice => 'İsteğe bağlı. Üstü çizili fiyat; satış fiyatından büyük olmalı. Güncellemede kaldırmak için 0 yazın.',
    BulkField.stock => 'Zorunlu. Tam sayı.',
    BulkField.category => 'İsteğe bağlı. Mağazanda olmayan kategori otomatik eklenir.',
    BulkField.images =>
      'İsteğe bağlı. Görsel bağlantısı (https://…) ya da yüklerken seçeceğiniz dosyanın adı (domates.jpg). '
          'Birden çok görseli | ile ayırın (en fazla 5). Boşsa ürün adıyla adlandırılmış dosya ya da görsel kütüphanesi denenir.',
    BulkField.available => 'İsteğe bağlı: evet / hayır. Boşsa evet.',
    BulkField.shippingFee => 'İsteğe bağlı. Bu ürüne özel kargo ücreti; boşsa mağaza ücreti geçerli.',
    BulkField.freeShipping => 'İsteğe bağlı: evet / hayır.',
    BulkField.minOrder => 'İsteğe bağlı. Sepete eklenebilecek en az adet.',
    BulkField.maxOrder => 'İsteğe bağlı. Sepete eklenebilecek en fazla adet.',
    BulkField.badges => 'İsteğe bağlı, en fazla 3, virgülle: ${ProductBadge.all.map((b) => b.label).join(', ')}',
  };

  /// Boş şablon: "Ürünler" sayfası + "Nasıl Doldurulur" açıklaması.
  Uint8List buildTemplate() {
    return SpreadsheetIO.buildXlsx([
      SpreadsheetSheet(
        name: 'Ürünler',
        rows: [templateFields.map((f) => f.templateHeader).toList()],
        columnWidths: _widths,
      ),
      _helpSheet(),
    ]);
  }

  SpreadsheetSheet _helpSheet() => SpreadsheetSheet(
    name: 'Nasıl Doldurulur',
    columnWidths: const [24, 110],
    wrapText: true,
    rows: [
      ['Sütun', 'Açıklama'],
      for (final f in templateFields) [f.templateHeader, fieldHelp(f)],
      ['', ''],
      ['İpuçları', 'Sütun sırası ve fazladan sütunlar önemli değil; başlıklar tanınır. Bir dosyada en fazla $maxRows satır.'],
      ['', 'Kendi Excel dosyanızı da yükleyebilirsiniz: "Ürün Adı / Ad", "Fiyat", "Stok" gibi başlıklar otomatik eşleşir.'],
      ['', 'Toplu fiyat/stok güncellemesi: Ürünlerim → Toplu işlemler → "Ürünlerimi dışa aktar" ile dosyayı alın, değiştirip geri yükleyin. Boş hücre o alanı değiştirmez.'],
      ['Örnek', 'Ürün Adı: Salkım Domates 1 kg · Fiyat: 34,90 · Eski Fiyat: 39,90 · Stok: 25 · Kategori: Manav · Görsel: domates.jpg'],
    ],
  );

  /// Fiziksel ürünleri (dijitaller hariç) düzenlenip geri yüklenebilecek
  /// biçimde dışa aktarır.
  Uint8List buildExport(List<Product> products) {
    final rows = <List<Object?>>[templateFields.map((f) => f.templateHeader).toList()];
    for (final p in products.where((p) => !p.isDigital)) {
      rows.add([
        p.id,
        p.name,
        p.description ?? '',
        p.price,
        p.oldPrice,
        p.stockQuantity,
        p.category ?? '',
        p.images.join(' | '),
        p.isAvailable ? 'evet' : 'hayır',
        p.shippingFee,
        p.freeShipping ? 'evet' : 'hayır',
        p.minOrderQuantity,
        p.maxOrderQuantity,
        p.badgeDetails.map((b) => b.label).join(', '),
      ]);
    }
    return SpreadsheetIO.buildXlsx([
      SpreadsheetSheet(name: 'Ürünler', rows: rows, columnWidths: _widths),
      _helpSheet(),
    ]);
  }

  /// Dosyayı paylaşım sayfasıyla açar (web'de indirir).
  Future<void> shareSpreadsheet(Uint8List bytes, String fileName, {Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: SpreadsheetIO.xlsxMimeType, name: fileName)],
        fileNameOverrides: [fileName],
        sharePositionOrigin: origin,
      ),
    );
  }
}
