import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/category_model.dart';
import '../../../core/models/daily_deal_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/shop_model.dart';

/// Ana sayfanın son başarılı verisinin cihazdaki kopyası.
///
/// Soğuk açılışta ana sayfa yedi sorgunun hepsini bekleyip saniyelerce
/// yükleme halkası gösteriyordu (cihaz ölçümü 2026-10-06: ilk bağlantılar
/// kurulurken 2–8 sn). Artık son görülen kategoriler, dükkânlar, indirimli
/// ürünler, kategori sayıları ve fırsat kartları ANINDA çizilir; taze veri
/// gelince yerine konur (stale-while-revalidate).
///
/// Hikâyeler bilerek saklanmaz (süreleri dolar). Veri herkese açık bölümlerdir;
/// yine de kullanıcıya göre ayrı dosyada tutulur. Web'de devre dışıdır.
class HomeSnapshot {
  const HomeSnapshot({
    required this.categories,
    required this.shops,
    required this.discountedProducts,
    required this.categoryShopCounts,
    required this.deals,
    required this.settings,
    required this.savedAt,
  });

  final List<Category> categories;
  final List<Shop> shops;
  final List<Product> discountedProducts;
  final Map<String, int> categoryShopCounts;
  final List<DailyDeal> deals;

  /// Ana sayfanın kullandığı birkaç uygulama ayarı (limitler, slogan,
  /// animasyon süreleri, global sipariş durumu) — düzen taze veriyle
  /// zıplamasın diye.
  final Map<String, dynamic> settings;
  final DateTime savedAt;
}

class HomeSnapshotCache {
  HomeSnapshotCache._();

  static const _version = 1;

  /// Bundan eski kopya gösterilmez (fiyat/stok çok bayatlamasın).
  static const maxAge = Duration(days: 3);

  static Future<File?> _file(String? userId) async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    final owner = (userId == null || userId.isEmpty) ? 'guest' : userId;
    return File('${dir.path}/home_snapshot_$owner.json');
  }

  /// Saklı kopya; yoksa, bozuksa ya da [maxAge]'den eskiyse `null`.
  static Future<HomeSnapshot?> read(String? userId) async {
    try {
      final file = await _file(userId);
      if (file == null || !await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['v'] != _version) return null;
      final savedAt = DateTime.tryParse(raw['saved_at']?.toString() ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt) > maxAge) {
        return null;
      }
      List<Map<String, dynamic>> rows(String key) => (raw[key] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return HomeSnapshot(
        categories: rows('categories').map(Category.fromJson).toList(),
        shops: rows('shops').map(Shop.fromJson).toList(),
        discountedProducts: rows('products').map(Product.fromJson).toList(),
        categoryShopCounts: (raw['category_counts'] as Map? ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
        deals: rows('deals').map(DailyDeal.fromJson).toList(),
        settings: Map<String, dynamic>.from(raw['settings'] as Map? ?? {}),
        savedAt: savedAt,
      );
    } catch (e) {
      debugPrint('HomeSnapshotCache.read: $e');
      return null;
    }
  }

  /// Son başarılı yüklemeyi saklar. Hata sessizce yutulur.
  static Future<void> write(String? userId, HomeSnapshot snapshot) async {
    try {
      final file = await _file(userId);
      if (file == null) return;
      final json = jsonEncode({
        'v': _version,
        'saved_at': snapshot.savedAt.toIso8601String(),
        'categories': snapshot.categories.map((c) => c.toJson()).toList(),
        'shops': snapshot.shops.map(shopToJson).toList(),
        'products': snapshot.discountedProducts.map(productToJson).toList(),
        'category_counts': snapshot.categoryShopCounts,
        'deals': snapshot.deals.map((d) => d.toJson()).toList(),
        'settings': snapshot.settings,
      });
      // Önce geçici dosyaya yaz, sonra taşı: yarım yazılmış dosya okunmasın.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('HomeSnapshotCache.write: $e');
    }
  }

  /// `Shop.toJson` sunucuya yazmak için kullanıldığından sponsor süresi
  /// sütunlarını içermez (satıcı kaydı onları ezmesin); önbellekte sponsor
  /// sırası doğru kalsın diye burada eklenir.
  @visibleForTesting
  static Map<String, dynamic> shopToJson(Shop shop) => {
    ...shop.toJson(),
    'sponsored_list_until': shop.sponsoredListUntil?.toIso8601String(),
    'sponsored_category_until': shop.sponsoredCategoryUntil?.toIso8601String(),
  };

  /// Bkz. [shopToJson]: `Product.toJson`'da olmayan alanlar eklenir.
  @visibleForTesting
  static Map<String, dynamic> productToJson(Product product) => {
    ...product.toJson(),
    'sponsored_category_until': product.sponsoredCategoryUntil
        ?.toIso8601String(),
    'sponsored_discount_until': product.sponsoredDiscountUntil
        ?.toIso8601String(),
    'smm_disabled_reason': product.smmDisabledReason,
    'smm_disabled_kind': product.smmDisabledKind,
  };
}
