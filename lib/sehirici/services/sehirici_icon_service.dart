import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sehirici_icon_models.dart';
import 'sehirici_errors.dart';

/// Şehiriçi harita ikon kütüphanesi: okuma (herkes) + yönetim (admin).
///
/// Yazma işlemleri `admin_*_sehirici_marker_icon` RPC'leriyle yapılır (tabloya
/// doğrudan yazma kapalı); görseller herkese açık `sehirici-icons` kovasına
/// yüklenir.
class SehiriciIconService {
  SehiriciIconService({SupabaseClient? client, http.Client? httpClient})
      : _clientOverride = client,
        _http = httpClient;

  final SupabaseClient? _clientOverride;
  final http.Client? _http;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  static const String bucket = 'sehirici-icons';

  /// Kova sınırıyla aynı (1 MB). İstemci baştan reddeder ki admin yüklemeden
  /// sonra değil, seçer seçmez uyarılsın.
  static const int maxImageBytes = 1024 * 1024;

  static const Map<String, String> _mimeByExt = {
    'png': 'image/png',
    'webp': 'image/webp',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
  };

  /// Katalogdaki tüm ikonlar (araç + durak, pasifler dahil). Hata olursa
  /// istisna fırlatır; çağıran ([SehiriciIconCatalog]) yerleşik listeye düşer.
  Future<List<SehiriciMarkerIcon>> fetchAll() async {
    final response = await _client
        .from('sehirici_marker_icons')
        .select()
        .order('kind', ascending: true)
        .order('sort_order', ascending: true)
        .order('label', ascending: true);
    return (response as List)
        .map((e) =>
            SehiriciMarkerIcon.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Bir ikon görselini yükler. Dönen `url` herkese açık adrestir; `path`
  /// kova içindeki yoldur (sonradan silmek için kaydedilir).
  Future<({String url, String path})> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String key,
  }) async {
    if (bytes.isEmpty) {
      throw const SehiriciAdminException('Görsel boş görünüyor.');
    }
    if (bytes.length > maxImageBytes) {
      throw const SehiriciAdminException('Görsel çok büyük (en fazla 1 MB).');
    }
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    final mime = _mimeByExt[ext];
    if (mime == null) {
      throw const SehiriciAdminException(
        'Yalnızca PNG, WebP veya JPEG görsel yüklenebilir.',
      );
    }
    final safeKey = key.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final path =
        'icons/${safeKey.isEmpty ? 'icon' : safeKey}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '31536000',
              upsert: false,
              contentType: mime,
            ),
          );
      return (
        url: _client.storage.from(bucket).getPublicUrl(path),
        path: path,
      );
    } catch (e) {
      debugPrint('SehiriciIconService.uploadImage hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  /// İkonu oluşturur / günceller. Kaydedilen ikonun id'sini döner.
  Future<String> saveIcon(SehiriciMarkerIconDraft draft) async {
    try {
      final id = await _client.rpc('admin_upsert_sehirici_marker_icon', params: {
        'p_id': draft.id,
        'p_kind': draft.kind.dbValue,
        'p_key': draft.key,
        'p_label': draft.label,
        'p_builtin_shape': draft.builtinShape,
        'p_image_url': draft.imageUrl,
        'p_image_path': draft.imagePath,
        'p_image_rotation': draft.imageRotation,
        'p_tint_with_line_color': draft.tintWithLineColor,
        'p_scale': draft.scale,
        'p_anchor_bottom': draft.anchorBottom,
        'p_is_active': draft.isActive,
        'p_sort_order': draft.sortOrder,
      });
      return id as String;
    } catch (e) {
      debugPrint('SehiriciIconService.saveIcon hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  /// İkonu siler (yerleşik / varsayılan / kullanımda olan silinemez — sunucu
  /// nedenini söyler) ve yüklenmiş görselini kovadan temizler.
  Future<void> deleteIcon(SehiriciMarkerIcon icon) async {
    try {
      final path = await _client.rpc('admin_delete_sehirici_marker_icon',
          params: {'p_id': icon.id});
      await removeFile(path as String? ?? icon.imagePath);
    } catch (e) {
      debugPrint('SehiriciIconService.deleteIcon hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  /// Bu ikonu türünün varsayılanı yapar (haritada kullanılan durak ikonu,
  /// bilinmeyen türler için yedek araç ikonu).
  Future<void> setDefault(String id) async {
    try {
      await _client
          .rpc('admin_set_default_sehirici_marker_icon', params: {'p_id': id});
    } catch (e) {
      debugPrint('SehiriciIconService.setDefault hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  /// Kovadan dosya siler; başarısızlık kayıt akışını bozmaz (yetim dosya
  /// zararsızdır).
  Future<void> removeFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      debugPrint('SehiriciIconService.removeFile hata (yoksayıldı): $e');
    }
  }

  /// Bir ikon görselinin baytları (harita bitmap'i için).
  Future<Uint8List> downloadBytes(String url) async {
    final client = _http ?? http.Client();
    try {
      final response =
          await client.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw SehiriciAdminException('Görsel indirilemedi (${response.statusCode}).');
      }
      return response.bodyBytes;
    } finally {
      if (_http == null) client.close();
    }
  }
}
