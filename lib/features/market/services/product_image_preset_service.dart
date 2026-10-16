import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, protected, visibleForTesting;
import '../../../core/models/product_image_preset_model.dart';

/// Önbellekteki bir istek: süren istek de paylaşılır (aynı anda iki ekran
/// aynı aramayı isterse tek istek gider).
class _CacheEntry<T> {
  _CacheEntry(this.value) : at = DateTime.now();

  final Future<T> value;
  final DateTime at;

  bool get fresh =>
      DateTime.now().difference(at) < ProductImagePresetService.cacheTtl;
}

class ProductImagePresetService {
  /// Satıcı seçicisi, ürün formundaki ad önerisi ve toplu yükleme bu örneği
  /// paylaşır; böylece önbellek ekranlar arasında korunur (art arda ürün
  /// eklerken seçici anında açılır).
  static final ProductImagePresetService shared = ProductImagePresetService();

  ProductImagePresetService({SupabaseClient? client}) : _client = client;

  /// Testlerde sahte istemci; verilmezse uygulamanın istemcisi.
  final SupabaseClient? _client;

  SupabaseClient get _supabase {
    final client = _client;
    if (client != null) return client;
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
  // Önbellek (satıcı tarafı)
  // -------------------------------------------------------------------------

  /// Arama sonuçları ve klasör özeti bu süre bellekte tutulur. Admin bu
  /// cihazda bir şey değiştirirse hemen boşaltılır; başka cihazdaki
  /// değişiklik en geç bu süre sonra görünür.
  static const Duration cacheTtl = Duration(minutes: 5);
  static const int _searchCacheMax = 80;

  final Map<String, _CacheEntry<List<ProductImagePreset>>> _searchCache = {};
  _CacheEntry<List<ProductImageFolder>>? _foldersCache;

  /// Bu örneğin önbelleğini boşaltır.
  void clearCache() {
    _searchCache.clear();
    _foldersCache = null;
  }

  /// Admin değişikliğinden sonra: bu örnek ve satıcı ekranlarının kullandığı
  /// [shared] örnek eski sonucu göstermesin.
  void _invalidate() {
    clearCache();
    if (!identical(this, shared)) shared.clearCache();
  }

  /// Başarısız istek önbellekte kalmasın (tekrar dene ağa gitsin).
  void _dropOnError<T>(_CacheEntry<T> entry, void Function() drop) {
    unawaited(entry.value.then((_) {}, onError: (Object _) => drop()));
  }

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
  ///
  /// Sonuçlar [cacheTtl] boyunca önbellekten döner (değiştirilemez liste).
  Future<List<ProductImagePreset>> searchPresets(
    String query, {
    String? folderId,
    int limit = pageSize,
    int offset = 0,
    bool matchAny = false,
  }) {
    final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    final key =
        '$q\u0001${folderId ?? ''}\u0001$limit\u0001$offset\u0001$matchAny';
    final hit = _searchCache.remove(key);
    if (hit != null && hit.fresh) {
      _searchCache[key] = hit; // en son kullanılan sona
      return hit.value;
    }
    final entry = _CacheEntry(
      fetchSearchPage(
        q,
        folderId: folderId,
        limit: limit,
        offset: offset,
        matchAny: matchAny,
      ).then(List<ProductImagePreset>.unmodifiable),
    );
    _searchCache[key] = entry;
    while (_searchCache.length > _searchCacheMax) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _dropOnError(entry, () {
      if (identical(_searchCache[key], entry)) _searchCache.remove(key);
    });
    return entry.value;
  }

  /// [searchPresets]'in önbelleksiz ağ isteği.
  @protected
  @visibleForTesting
  Future<List<ProductImagePreset>> fetchSearchPage(
    String query, {
    String? folderId,
    required int limit,
    required int offset,
    required bool matchAny,
  }) async {
    try {
      final response = await _supabase.rpc(
        'search_product_image_presets',
        params: {
          'p_query': query,
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

  /// Satıcı seçicisinin klasör çipleri: [getFolders], [cacheTtl] boyunca
  /// önbellekten.
  Future<List<ProductImageFolder>> getFoldersCached() {
    final hit = _foldersCache;
    if (hit != null && hit.fresh) return hit.value;
    final entry = _CacheEntry(getFolders());
    _foldersCache = entry;
    _dropOnError(entry, () {
      if (identical(_foldersCache, entry)) _foldersCache = null;
    });
    return entry.value;
  }

  /// Klasörler ve çağıranın görebildiği görsel sayıları. Satıcıda yalnız açık
  /// klasörler ve yayındaki görseller sayılır (RLS); adminde hepsi.
  /// Önbelleksiz (admin her yenilemede güncel sayıyı görür).
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

  /// Admin yönetim ekranının bir sayfası.
  static const int adminPageSize = 60;

  /// Toplu yazımlarda (taşı / yayına al / pasife al / sil) tek istekteki
  /// kimlik sayısı. Kimlikler tırnaklı olarak adrese yazılır (`id=in.(…)`);
  /// 150 kimlik ≈ 7 KB, ağ geçidinin adres sınırının altında. "Süzgece uyanların
  /// tümünü seç" binlerce kimlik seçebildiği için parçalanır.
  static const int idBatchSize = 150;

  Map<String, dynamic> _adminFilterParams(ProductImageAdminQuery query) => {
    'p_folder_id': query.folderId,
    'p_unfiled': query.unfiled,
    'p_status': query.status.name,
    'p_query': query.search,
  };

  /// Admin yönetim ekranı: [query]'ye uyan görsellerin (pasifler dahil) bir
  /// sayfası ve süzgece uyan toplam. Süzme, arama ve sıralama sunucuda
  /// (`admin_product_image_presets_page`); kütüphane istemciye inmez.
  ///
  /// [withSummary] true ise kütüphane özeti de gelir (klasörler ve klasör
  /// başına tüm/yayında sayaçları); [limit] 0 ile yalnız toplam + özet
  /// alınır. Sunucu [limit]'i en fazla 500'e indirir. Önbelleksiz.
  Future<ProductImageAdminPage> getAdminPage(
    ProductImageAdminQuery query, {
    int limit = adminPageSize,
    int offset = 0,
    bool withSummary = false,
  }) async {
    try {
      final response = await _supabase.rpc(
        'admin_product_image_presets_page',
        params: {
          ..._adminFilterParams(query),
          'p_sort': query.sort.name,
          'p_limit': limit,
          'p_offset': offset,
          'p_with_summary': withSummary,
        },
      );
      return ProductImageAdminPage.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    } catch (e) {
      throw Exception('Görsel kütüphanesi yüklenirken hata: $e');
    }
  }

  /// [query]'ye uyan TÜM görsellerin kimlikleri (sırasız; [query]'nin
  /// sıralaması yok sayılır) — "süzgece uyanların tümünü seç" için. Satır
  /// verisi gelmez (`admin_product_image_preset_ids`).
  Future<List<String>> getAdminPresetIds(ProductImageAdminQuery query) async {
    try {
      final response = await _supabase.rpc(
        'admin_product_image_preset_ids',
        params: _adminFilterParams(query),
      );
      return [for (final id in (response as List? ?? const [])) id as String];
    } catch (e) {
      throw Exception('Görseller seçilirken hata: $e');
    }
  }

  /// [ids]'i [idBatchSize]'lık parçalar halinde, en fazla 4'ü aynı anda,
  /// [run]'a verir. Parçalar ayrı istek olduğu için hata olursa bir kısmı
  /// uygulanmış olabilir; çağıran listeyi sunucudan tazelemeli.
  Future<void> _inBatches(
    List<String> ids,
    Future<void> Function(List<String> batch) run,
  ) async {
    final batches = [
      for (var i = 0; i < ids.length; i += idBatchSize)
        ids.sublist(i, math.min(i + idBatchSize, ids.length)),
    ];
    for (var i = 0; i < batches.length; i += 4) {
      await Future.wait([for (final b in batches.skip(i).take(4)) run(b)]);
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
    } finally {
      _invalidate();
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
    } finally {
      _invalidate();
    }
  }

  Future<void> deletePreset(String id) => deletePresets([id]);

  /// Satırları siler. Storage dosyasına DOKUNMAZ: ürünler seçilen görselin
  /// URL'sini kendi kayıtlarına kopyaladığı için dosya silinirse o ürünlerin
  /// görseli kırılır. Çok kimlik parça parça gönderilir ([idBatchSize]).
  Future<void> deletePresets(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _inBatches(
        ids,
        (batch) => _supabase
            .from('product_image_presets')
            .delete()
            .inFilter('id', batch),
      );
    } catch (e) {
      throw Exception('Görsel silinirken hata: $e');
    } finally {
      _invalidate();
    }
  }

  Future<void> setActive(List<String> ids, bool isActive) async {
    if (ids.isEmpty) return;
    try {
      await _inBatches(
        ids,
        (batch) => _supabase
            .from('product_image_presets')
            .update({'is_active': isActive})
            .inFilter('id', batch),
      );
    } catch (e) {
      throw Exception('Durum güncellenirken hata: $e');
    } finally {
      _invalidate();
    }
  }

  /// Görselleri bir klasöre taşır; [folderId] null ise klasörsüz yapar.
  Future<void> moveToFolder(List<String> ids, String? folderId) async {
    if (ids.isEmpty) return;
    try {
      await _inBatches(
        ids,
        (batch) => _supabase
            .from('product_image_presets')
            .update({'folder_id': folderId})
            .inFilter('id', batch),
      );
    } catch (e) {
      throw Exception('Görseller taşınırken hata: $e');
    } finally {
      _invalidate();
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
    } finally {
      _invalidate();
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
    } finally {
      _invalidate();
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
    } finally {
      _invalidate();
    }
  }

  /// Klasörü siler; içindeki görseller SİLİNMEZ, klasörsüz kalır
  /// (folder_id ON DELETE SET NULL).
  Future<void> deleteFolder(String id) async {
    try {
      await _supabase.from('product_image_folders').delete().eq('id', id);
    } catch (e) {
      throw _folderError('silinirken', e);
    } finally {
      _invalidate();
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
