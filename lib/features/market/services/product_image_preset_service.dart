import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../core/models/product_image_preset_model.dart';

class ProductImagePresetService {
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  /// Görsel satırının istemcinin kullandığı sütunları (arama sütunları hariç).
  static const String _presetColumns =
      'id,name,description,image_url,is_active,display_order,created_at,folder_id';

  /// Satıcı seçim ekranının bir sayfası.
  static const int pageSize = 60;

  // -------------------------------------------------------------------------
  // Satıcı: arama (search_product_image_presets RPC'si)
  // -------------------------------------------------------------------------

  /// Yayındaki görseller, açık klasörlerden. [query] boşsa sıra numarasına
  /// göre listeler; doluysa Türkçe/aksan duyarsız arar ve alakaya göre
  /// sıralar ("domtes" gibi yazım hatalarını da bulur). [folderId] null ise
  /// tüm klasörler.
  ///
  /// Varsayılan olarak sorgunun HER kelimesi eşleşmeli. [matchAny] true ise
  /// biri yeter; rakamlar ve 3 harften kısa kelimeler (1, kg, ml) yok sayılır,
  /// en çok kelimesi tutan önce gelir — "Salkım Domates 1 kg" gibi ürün
  /// adından öneri için.
  Future<List<ProductImagePreset>> searchPresets(
    String query, {
    String? folderId,
    int limit = pageSize,
    int offset = 0,
    bool matchAny = false,
  }) async {
    try {
      final response = await _supabase.rpc(
        'search_product_image_presets',
        params: {
          'p_query': query.trim(),
          'p_folder_id': folderId,
          'p_limit': limit,
          'p_offset': offset,
          'p_match_any': matchAny,
        },
      );
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

  /// Aramasız liste (satıcı seçim ekranının varsayılanı).
  Future<List<ProductImagePreset>> getPresets({
    String? folderId,
    int limit = pageSize,
    int offset = 0,
  }) => searchPresets('', folderId: folderId, limit: limit, offset: offset);

  /// Klasörler ve çağıranın görebildiği görsel sayıları. Satıcıda yalnız açık
  /// klasörler ve yayındaki görseller sayılır (RLS); adminde hepsi.
  Future<List<ProductImageFolder>> getFolders() async {
    try {
      final response = await _supabase.rpc('product_image_folder_summary');
      return (response as List)
          .map(
            (json) =>
                ProductImageFolder.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList();
    } catch (e) {
      throw Exception('Klasörler yüklenirken hata: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Admin: görseller
  // -------------------------------------------------------------------------

  /// Admin yönetim ekranı için pasifler dahil TÜM görseller.
  ///
  /// PostgREST tek istekte en fazla ~1000 satır döndürür (sunucu ayarı);
  /// kütüphane binlerce görsele çıkacağı için boş sayfa gelene kadar sayfa
  /// sayfa okunur. Sabit sıralama (display_order, id) sayfaların çakışmamasını
  /// sağlar.
  Future<List<ProductImagePreset>> getAllPresetsForAdmin() async {
    const chunk = 1000;
    final all = <ProductImagePreset>[];
    try {
      while (true) {
        final response = await _supabase
            .from('product_image_presets')
            .select(_presetColumns)
            .order('display_order', ascending: true)
            .order('id', ascending: true)
            .range(all.length, all.length + chunk - 1);
        final rows = response as List;
        if (rows.isEmpty) break;
        all.addAll(
          rows.map(
            (json) =>
                ProductImagePreset.fromJson(Map<String, dynamic>.from(json)),
          ),
        );
      }
      return all;
    } catch (e) {
      throw Exception('Görsel kütüphanesi yüklenirken hata: $e');
    }
  }

  Future<ProductImagePreset> addPreset({
    required String name,
    String? description,
    required String imageUrl,
    int displayOrder = 0,
    bool isActive = true,
    String? folderId,
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
            'folder_id': folderId,
          })
          .select(_presetColumns)
          .single();

      return ProductImagePreset.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw Exception('Görsel eklenirken hata: $e');
    }
  }

  /// [setFolder] true ise klasör [folderId]'ye yazılır (null = klasörsüz);
  /// false ise klasöre dokunulmaz.
  Future<ProductImagePreset> updatePreset({
    required String id,
    String? name,
    String? description,
    String? imageUrl,
    int? displayOrder,
    bool? isActive,
    bool setFolder = false,
    String? folderId,
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
      if (setFolder) updates['folder_id'] = folderId;

      final response = await _supabase
          .from('product_image_presets')
          .update(updates)
          .eq('id', id)
          .select(_presetColumns)
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

  /// Görselleri bir klasöre taşır; [folderId] null ise klasörsüz yapar.
  Future<void> moveToFolder(List<String> ids, String? folderId) async {
    if (ids.isEmpty) return;
    try {
      await _supabase
          .from('product_image_presets')
          .update({'folder_id': folderId})
          .inFilter('id', ids);
    } catch (e) {
      throw Exception('Görseller taşınırken hata: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Admin: klasörler
  // -------------------------------------------------------------------------

  /// Aynı adlı klasör (büyük/küçük harf ve Türkçe karakter farkı gözetmeden)
  /// veritabanında benzersiz; çakışma anlaşılır bir mesaja çevrilir.
  Exception _folderError(String action, Object e) {
    if (e is PostgrestException && e.code == '23505') {
      return Exception('Bu adda bir klasör zaten var');
    }
    return Exception('Klasör $action hata: $e');
  }

  Future<ProductImageFolder> addFolder({
    required String name,
    int displayOrder = 0,
  }) async {
    try {
      final response = await _supabase
          .from('product_image_folders')
          .insert({'name': name.trim(), 'display_order': displayOrder})
          .select()
          .single();
      return ProductImageFolder.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw _folderError('eklenirken', e);
    }
  }

  Future<void> updateFolder({
    required String id,
    String? name,
    int? displayOrder,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name.trim();
    if (displayOrder != null) updates['display_order'] = displayOrder;
    if (isActive != null) updates['is_active'] = isActive;
    if (updates.isEmpty) return;
    try {
      await _supabase
          .from('product_image_folders')
          .update(updates)
          .eq('id', id);
    } catch (e) {
      throw _folderError('güncellenirken', e);
    }
  }

  /// Klasörleri verilen sıraya göre 1, 2, 3… diye numaralar.
  Future<void> reorderFolders(List<String> idsInOrder) async {
    try {
      await Future.wait([
        for (var i = 0; i < idsInOrder.length; i++)
          _supabase
              .from('product_image_folders')
              .update({'display_order': i + 1})
              .eq('id', idsInOrder[i]),
      ]);
    } catch (e) {
      throw _folderError('sıralanırken', e);
    }
  }

  /// Klasörü siler; içindeki görseller SİLİNMEZ, klasörsüz kalır
  /// (folder_id ON DELETE SET NULL).
  Future<void> deleteFolder(String id) async {
    try {
      await _supabase.from('product_image_folders').delete().eq('id', id);
    } catch (e) {
      throw _folderError('silinirken', e);
    }
  }

  // -------------------------------------------------------------------------
  // Storage
  // -------------------------------------------------------------------------

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
