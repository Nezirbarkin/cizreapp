import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mağaza Servisi - Satıcı mağaza ayarları yönetimi
class ShopService {
  final SupabaseClient _supabase;

  ShopService(this._supabase);

  /// Satıcının mağaza bilgilerini getir
  Future<Map<String, dynamic>?> getShop(String sellerId) async {
    try {
      final response = await _supabase
          .from('shops')
          .select('*')
          .eq('owner_id', sellerId)
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      throw Exception('Mağaza bilgileri alınamadı: $e');
    }
  }

  /// Mağaza bilgilerini güncelle
  Future<void> updateShop({
    required String shopId,
    String? name,
    String? description,
    String? phone,
    String? address,
    String? logoUrl,
    String? coverImage,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (name != null) updateData['name'] = name;
      if (description != null) updateData['description'] = description;
      if (phone != null) updateData['phone'] = phone;
      if (address != null) updateData['address'] = address;
      if (logoUrl != null) updateData['logo_url'] = logoUrl;
      if (coverImage != null) updateData['cover_image'] = coverImage; // banner_url -> cover_image

      if (updateData.isEmpty) return;

      await _supabase
          .from('shops')
          .update(updateData)
          .eq('id', shopId);
    } catch (e) {
      throw Exception('Mağaza bilgileri güncellenemedi: $e');
    }
  }

  /// Çalışma saatlerini güncelle
  Future<void> updateWorkingHours({
    required String shopId,
    required Map<String, dynamic> workingHours,
  }) async {
    try {
      await _supabase
          .from('shops')
          .update({'working_hours': workingHours})
          .eq('id', shopId);
    } catch (e) {
      throw Exception('Çalışma saatleri güncellenemedi: $e');
    }
  }

  /// Teslimat ayarlarını güncelle
  Future<void> updateDeliverySettings({
    required String shopId,
    double? minOrderAmount,
    double? freeDeliveryMinAmount,
    String? deliveryTime,
    double? deliveryFee,
    bool? hasOwnCourier,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (minOrderAmount != null) updateData['min_order_amount'] = minOrderAmount;
      if (freeDeliveryMinAmount != null) updateData['free_delivery_min_amount'] = freeDeliveryMinAmount;
      if (deliveryTime != null) updateData['delivery_time'] = deliveryTime;
      if (deliveryFee != null) updateData['delivery_fee'] = deliveryFee;
      if (hasOwnCourier != null) updateData['has_own_courier'] = hasOwnCourier;

      // Debug log: Güncellenecek veriyi yazdır
      // ignore: avoid_print
      print('🔧 SHOP SERVICE: Updating shop $shopId with data: $updateData');

      await _supabase
          .from('shops')
          .update(updateData)
          .eq('id', shopId);
      
      // ignore: avoid_print
      print('✅ SHOP SERVICE: Update successful');
    } catch (e) {
      // ignore: avoid_print
      print('❌ SHOP SERVICE: Update failed: $e');
      throw Exception('Teslimat ayarları güncellenemedi: $e');
    }
  }

  /// Logo yükle (XFile ile - Web ve Mobile uyumlu)
  Future<String> uploadLogo(String shopId, XFile file) async {
    try {
      final extension = file.name.split('.').last.toLowerCase();
      final fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final filePath = 'shops/$shopId/$fileName';

      final bytes = await file.readAsBytes();
      await _supabase.storage.from('shop-images').uploadBinary(filePath, bytes);

      final url = _supabase.storage.from('shop-images').getPublicUrl(filePath);
      return url;
    } catch (e) {
      throw Exception('Logo yüklenemedi: $e');
    }
  }

  /// Kapak resmi yükle (XFile ile - Web ve Mobile uyumlu)
  Future<String> uploadCoverImage(String shopId, XFile file) async {
    try {
      final extension = file.name.split('.').last.toLowerCase();
      final fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final filePath = 'shops/$shopId/$fileName';

      final bytes = await file.readAsBytes();
      await _supabase.storage.from('shop-images').uploadBinary(filePath, bytes);

      final url = _supabase.storage.from('shop-images').getPublicUrl(filePath);
      return url;
    } catch (e) {
      throw Exception('Kapak resmi yüklenemedi: $e');
    }
  }

  /// Mevcut çalışma saatlerini getir
  Map<String, dynamic> getDefaultWorkingHours() {
    return {
      'monday': {'open': '09:00', 'close': '18:00', 'active': true},
      'tuesday': {'open': '09:00', 'close': '18:00', 'active': true},
      'wednesday': {'open': '09:00', 'close': '18:00', 'active': true},
      'thursday': {'open': '09:00', 'close': '18:00', 'active': true},
      'friday': {'open': '09:00', 'close': '18:00', 'active': true},
      'saturday': {'open': '09:00', 'close': '18:00', 'active': true},
      'sunday': {'open': null, 'close': null, 'active': false},
    };
  }

  /// Türkçe gün isimleri
  static const Map<String, String> dayNamesTurkish = {
    'monday': 'Pazartesi',
    'tuesday': 'Salı',
    'wednesday': 'Çarşamba',
    'thursday': 'Perşembe',
    'friday': 'Cuma',
    'saturday': 'Cumartesi',
    'sunday': 'Pazar',
  };

  /// Çalışma saatlerini formatla (gösterim için)
  String formatWorkingHours(Map<String, dynamic> workingHours, String day) {
    final dayData = workingHours[day] as Map<String, dynamic>?;
    if (dayData == null || !(dayData['active'] as bool)) {
      return 'Kapalı';
    }

    final open = dayData['open'] as String?;
    final close = dayData['close'] as String?;

    if (open == null || close == null) {
      return 'Kapalı';
    }

    return '$open - $close';
  }

  /// Aktif kategorileri getir
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final response = await _supabase
          .from('categories')
          .select('id, name, slug, icon, image_url')
          .eq('is_active', true)
          .order('display_order', ascending: true);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw Exception('Kategoriler alınamadı: $e');
    }
  }

  /// Mağaza kategorisini güncelle
  Future<void> updateShopCategory({
    required String shopId,
    required String categoryId,
  }) async {
    try {
      await _supabase
          .from('shops')
          .update({'category_id': categoryId})
          .eq('id', shopId);
    } catch (e) {
      throw Exception('Kategori güncellenemedi: $e');
    }
  }

  /// Satıcının kendi oluşturduğu kategorilerini getir
  Future<List<String>> getSellerCategories(String shopId) async {
    try {
      final response = await _supabase
          .from('shops')
          .select('seller_categories')
          .eq('id', shopId)
          .single();

      if (response['seller_categories'] == null) {
        return [];
      }

      return List<String>.from(response['seller_categories'] as List);
    } catch (e) {
      throw Exception('Satıcı kategorileri alınamadı: $e');
    }
  }

  /// Satıcının kendi kategorilerini güncelle
  Future<void> updateSellerCategories({
    required String shopId,
    required List<String> categories,
  }) async {
    try {
      await _supabase
          .from('shops')
          .update({'seller_categories': categories})
          .eq('id', shopId);
    } catch (e) {
      throw Exception('Satıcı kategorileri güncellenemedi: $e');
    }
  }

  /// Satıcıya yeni kategori ekle
  Future<void> addSellerCategory({
    required String shopId,
    required String categoryName,
  }) async {
    try {
      // Mevcut kategorileri al
      final currentCategories = await getSellerCategories(shopId);
      
      // Zaten var mı kontrol et
      if (currentCategories.contains(categoryName)) {
        throw Exception('Bu kategori zaten mevcut');
      }
      
      // Yeni kategoriyi ekle
      final updatedCategories = [...currentCategories, categoryName];
      
      await updateSellerCategories(
        shopId: shopId,
        categories: updatedCategories,
      );
    } catch (e) {
      throw Exception('Kategori eklenemedi: $e');
    }
  }

  /// Satıcıdan kategori sil
  Future<void> removeSellerCategory({
    required String shopId,
    required String categoryName,
  }) async {
    try {
      // Mevcut kategorileri al
      final currentCategories = await getSellerCategories(shopId);
      
      // Kategoriyi sil
      final updatedCategories = currentCategories.where((cat) => cat != categoryName).toList();
      
      await updateSellerCategories(
        shopId: shopId,
        categories: updatedCategories,
      );
    } catch (e) {
      throw Exception('Kategori silinemedi: $e');
    }
  }
}
