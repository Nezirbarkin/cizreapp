import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../core/models/product_image_preset_model.dart';
import '../../../core/utils/search_query.dart';

class ProductImagePresetService {
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  // Aktif preset'leri getir (satıcı seçim ekranı için varsayılan liste)
  Future<List<ProductImagePreset>> getPresets({int limit = 60}) async {
    try {
      final response = await _supabase
          .from('product_image_presets')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .limit(limit);

      return (response as List)
          .map(
            (json) =>
                ProductImagePreset.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList();
    } catch (e) {
      throw Exception('Görsel kütüphanesi yüklenirken hata: $e');
    }
  }

  // Admin yönetim ekranı için pasifler dahil tüm preset'ler
  Future<List<ProductImagePreset>> getAllPresetsForAdmin({
    int limit = 1000,
  }) async {
    try {
      final response = await _supabase
          .from('product_image_presets')
          .select()
          .order('display_order', ascending: true)
          .limit(limit);

      return (response as List)
          .map(
            (json) =>
                ProductImagePreset.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList();
    } catch (e) {
      throw Exception('Görsel kütüphanesi yüklenirken hata: $e');
    }
  }

  Future<List<ProductImagePreset>> searchPresets(
    String query, {
    int limit = 60,
  }) async {
    try {
      final response = await _supabase
          .from('product_image_presets')
          .select()
          .eq('is_active', true)
          .or(buildIlikeOrFilter(const ['name', 'description'], query))
          .order('display_order', ascending: true)
          .limit(limit);

      return (response as List)
          .map(
            (json) =>
                ProductImagePreset.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<ProductImagePreset> addPreset({
    required String name,
    String? description,
    required String imageUrl,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    try {
      final response = await _supabase
          .from('product_image_presets')
          .insert({
            'name': name,
            'description': description,
            'image_url': imageUrl,
            'display_order': displayOrder,
            'is_active': isActive,
          })
          .select()
          .single();

      return ProductImagePreset.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw Exception('Görsel eklenirken hata: $e');
    }
  }

  Future<ProductImagePreset> updatePreset({
    required String id,
    String? name,
    String? description,
    String? imageUrl,
    int? displayOrder,
    bool? isActive,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      // Boş metin = arama kelimelerini temizle (null'a çevrilir).
      if (description != null) {
        updates['description'] = description.trim().isEmpty
            ? null
            : description.trim();
      }
      if (imageUrl != null) updates['image_url'] = imageUrl;
      if (displayOrder != null) updates['display_order'] = displayOrder;
      if (isActive != null) updates['is_active'] = isActive;

      final response = await _supabase
          .from('product_image_presets')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      return ProductImagePreset.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw Exception('Görsel güncellenirken hata: $e');
    }
  }

  Future<void> deletePreset(String id) => deletePresets([id]);

  /// Satırları siler. Storage dosyasına DOKUNMAZ: ürünler seçilen görselin
  /// URL'sini kendi kayıtlarına kopyaladığı için dosya silinirse o ürünlerin
  /// görseli kırılır.
  Future<void> deletePresets(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _supabase
          .from('product_image_presets')
          .delete()
          .inFilter('id', ids);
    } catch (e) {
      throw Exception('Görsel silinirken hata: $e');
    }
  }

  Future<void> setActive(List<String> ids, bool isActive) async {
    if (ids.isEmpty) return;
    try {
      await _supabase
          .from('product_image_presets')
          .update({'is_active': isActive})
          .inFilter('id', ids);
    } catch (e) {
      throw Exception('Durum güncellenirken hata: $e');
    }
  }

  static const String bucket = 'product-image-presets';

  /// Bucket'ın izin verdiği türler; başka uzantılar jpg olarak yüklenir.
  static const Map<String, String> _mimeByExt = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  /// Görseli storage'a yükleyip herkese açık URL'sini döner.
  ///
  /// [fileName] yalnızca uzantıyı belirlemek için kullanılır (web'de
  /// `XFile.path` bir blob URL'sidir, uzantı taşımaz; bu yüzden ad kullanılır).
  /// [uniqueTag] aynı milisaniyede paralel yüklemelerin çakışmasını önler.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String uniqueTag,
  }) async {
    final dot = fileName.lastIndexOf('.');
    var ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    if (!_mimeByExt.containsKey(ext)) ext = 'jpg';

    final path =
        'presets/preset_${DateTime.now().millisecondsSinceEpoch}_$uniqueTag.$ext';
    try {
      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: _mimeByExt[ext],
            ),
          );
      return _supabase.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      throw Exception('Görsel yüklenirken hata: $e');
    }
  }
}
