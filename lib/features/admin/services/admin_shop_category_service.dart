import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin > Dükkanlar > "Ana kategori" (Görev 4.5).
///
/// Değişiklik sunucuda `admin_set_shop_category` ile yapılır: pasif kategoriye
/// taşımaz, denetim günlüğüne yazar, satıcıya bildirim gider. İsteğe bağlı
/// kilit satıcının kategoriyi geri değiştirmesini engeller (INVOKER tetikleyici).
class ShopCategoryOption {
  const ShopCategoryOption({
    required this.id,
    required this.name,
    this.icon,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? icon;
  final bool isActive;

  factory ShopCategoryOption.fromJson(Map<String, dynamic> json) => ShopCategoryOption(
    id: json['id'].toString(),
    name: (json['name'] as String?)?.trim() ?? 'Kategori',
    icon: json['icon'] as String?,
    isActive: json['is_active'] != false,
  );

  /// Satıcı ekranındaki eşlemeyle aynı emoji ('utensils' → 🍽️).
  String get emoji => categoryIconEmoji(icon);
}

/// Kategori ikon adı → emoji (satıcı mağaza ayarlarıyla aynı eşleme).
String categoryIconEmoji(String? icon) {
  const map = {
    'utensils': '🍽️',
    'shopping-bag': '🛍️',
    'zap': '⚡',
    'tshirt': '👕',
    'cake': '🍰',
    'car': '🚗',
    'phone': '📱',
    'book': '📚',
    'music': '🎵',
    'game': '🎮',
  };
  return map[icon] ?? '📁';
}

class ShopCategoryChange {
  const ShopCategoryChange({
    required this.categoryId,
    required this.categoryName,
    required this.locked,
    required this.changed,
  });

  final String categoryId;
  final String categoryName;
  final bool locked;
  final bool changed;

  factory ShopCategoryChange.fromJson(Map<String, dynamic> json) => ShopCategoryChange(
    categoryId: json['category_id'].toString(),
    categoryName: (json['category_name'] as String?) ?? '',
    locked: json['locked'] == true,
    changed: json['changed'] == true,
  );
}

class AdminShopCategoryService {
  AdminShopCategoryService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  /// Tüm kategoriler (pasifler dahil; seçicide pasifler seçilemez gösterilir).
  Future<List<ShopCategoryOption>> fetchCategories() async {
    final rows = await _client
        .from('categories')
        .select('id, name, icon, is_active, display_order')
        .order('display_order', ascending: true)
        .order('name', ascending: true);
    return [
      for (final row in (rows as List).whereType<Map>()) ShopCategoryOption.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<ShopCategoryChange> setShopCategory({
    required String shopId,
    required String categoryId,
    required bool lock,
    String? note,
  }) async {
    final text = note?.trim();
    final data = await _client.rpc(
      'admin_set_shop_category',
      params: {
        'p_shop_id': shopId,
        'p_category_id': categoryId,
        'p_lock': lock,
        'p_note': text == null || text.isEmpty ? null : text,
      },
    );
    return ShopCategoryChange.fromJson(Map<String, dynamic>.from(data as Map));
  }

  static String errorMessage(Object error) {
    if (error is PostgrestException) {
      switch (error.hint) {
        case 'CATEGORY_INACTIVE':
          return 'Bu kategori pasif. Önce Kategoriler menüsünden etkinleştirin.';
        case 'CATEGORY_NOT_FOUND':
          return 'Kategori bulunamadı (silinmiş olabilir).';
        case 'SHOP_NOT_FOUND':
          return 'Mağaza bulunamadı.';
      }
      if (error.code == '42501') return 'Bu işlem için yönetici yetkisi gerekli.';
      return error.message;
    }
    return 'İşlem tamamlanamadı: $error';
  }
}
