// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/ilan_models.dart';

class IlanService {
  IlanService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _detailSelect = '''
    *,
    ilan_categories(*),
    ilan_images(id,image_url,sort_order),
    profiles!ilanlar_owner_id_fkey(full_name,username,avatar_url)
  ''';

  // Misafir oturumunun profiles tablosuna doğrudan relation join yapması,
  // profiles PII güvenlik politikaları nedeniyle tüm ilan sorgusunu
  // başarısız kılabiliyor. Public akış yalnız ilan/kategori/görsel okur.
  // İlan sahibi adı admin ve kullanıcının kendi ilan ekranında yüklenir.
  static const String _publicSelect = '''
    *,
    ilan_categories(*),
    ilan_images(id,image_url,sort_order)
  ''';

  Future<IlanSettings> getSettings() async {
    final row = await _client
        .from('ilan_settings')
        .select()
        .eq('id', 1)
        .single();
    return IlanSettings.fromJson(row);
  }

  Future<void> updateSettings(IlanSettings settings) async {
    final userId = _requireUser();
    await _client
        .from('ilan_settings')
        .update({
          ...settings.toJson(),
          'updated_by': userId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', 1);
  }

  Future<List<IlanCategory>> getCategories({bool admin = false}) async {
    var query = _client.from('ilan_categories').select();
    if (!admin) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('name');
    return (rows as List)
        .map(
          (row) => IlanCategory.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> saveCategory(IlanCategory category) async {
    final data = category.toJson();
    if (category.id.isEmpty) {
      await _client.from('ilan_categories').insert(data);
    } else {
      await _client
          .from('ilan_categories')
          .update(data..remove('id'))
          .eq('id', category.id);
    }
  }

  Future<void> deleteCategory(String id) =>
      _client.from('ilan_categories').delete().eq('id', id);

  Future<List<Ilan>> getLatest({int limit = 8, String? categoryId}) async {
    var query = _client
        .from('ilanlar')
        .select(_publicSelect)
        .eq('status', 'published');
    if (categoryId != null) query = query.eq('category_id', categoryId);
    final rows = await query
        .order('published_at', ascending: false)
        .limit(limit);
    return _mapIlanlar(rows);
  }

  Future<List<Ilan>> search({
    String? categoryId,
    String? query,
    String? condition,
    double? minPrice,
    double? maxPrice,
    String sortBy = 'newest',
    int offset = 0,
    int limit = 20,
  }) async {
    var request = _client
        .from('ilanlar')
        .select(_publicSelect)
        .eq('status', 'published');
    if (categoryId != null) request = request.eq('category_id', categoryId);
    if (query != null && query.trim().isNotEmpty) {
      final safe = query.trim().replaceAll(',', ' ');
      request = request.or('title.ilike.%$safe%,description.ilike.%$safe%');
    }
    if (condition != null) request = request.eq('item_condition', condition);
    if (minPrice != null) request = request.gte('price', minPrice);
    if (maxPrice != null) request = request.lte('price', maxPrice);
    var ordered = switch (sortBy) {
      'price_asc' => request.order('price', ascending: true, nullsFirst: false),
      'price_desc' => request.order(
        'price',
        ascending: false,
        nullsFirst: false,
      ),
      _ => request.order('published_at', ascending: false),
    };
    if (sortBy == 'price_asc' || sortBy == 'price_desc') {
      ordered = ordered.order('published_at', ascending: false);
    }
    final rows = await ordered.range(offset, offset + limit - 1);
    return _mapIlanlar(rows);
  }

  Future<Ilan> getById(String id) async {
    final row = await _client
        .from('ilanlar')
        .select(_publicSelect)
        .eq('id', id)
        .single();
    final data = Map<String, dynamic>.from(row);

    // profiles tablosunu public ilan sorgusuna doğrudan join etmek PII/RLS
    // kısıtları nedeniyle özellikle misafirlerde tüm sorguyu bozabiliyor.
    // RPC yalnız ilanı görmeye yetkili kişilere güvenli profil alanlarını verir.
    try {
      final response = await _client.rpc(
        'get_ilan_owner_public_profile',
        params: {'p_ilan_id': id},
      );
      if (response is List && response.isNotEmpty) {
        data['profiles'] = Map<String, dynamic>.from(response.first as Map);
      } else if (response is Map) {
        data['profiles'] = Map<String, dynamic>.from(response);
      }
    } catch (_) {
      // Migration henüz uygulanmamış olsa bile ilan detayı açılmaya devam eder.
    }
    return Ilan.fromJson(data);
  }

  Future<List<Ilan>> getMine() async {
    final userId = _requireUser();
    final rows = await _client
        .from('ilanlar')
        .select(_detailSelect)
        .eq('owner_id', userId)
        .order('created_at', ascending: false);
    return _mapIlanlar(rows);
  }

  Future<List<Ilan>> getAdminIlanlar({String? status}) async {
    var request = _client.from('ilanlar').select(_detailSelect);
    if (status != null && status != 'all')
      request = request.eq('status', status);
    final rows = await request.order('created_at', ascending: false).limit(200);
    return _mapIlanlar(rows);
  }

  Future<String> createIlan(
    Map<String, dynamic> values,
    List<Uint8List> images,
  ) async {
    final userId = _requireUser();
    final inserted = await _client
        .from('ilanlar')
        .insert({...values, 'owner_id': userId})
        .select('id')
        .single();
    final ilanId = inserted['id'] as String;
    try {
      await _uploadImages(ilanId, userId, images);
      return ilanId;
    } catch (_) {
      await _client.from('ilanlar').delete().eq('id', ilanId);
      rethrow;
    }
  }

  Future<void> updateIlan(String id, Map<String, dynamic> values) =>
      _client.from('ilanlar').update(values).eq('id', id);

  Future<void> updateStatus(
    String id,
    IlanStatus status, {
    String? rejectionReason,
  }) async {
    await _client
        .from('ilanlar')
        .update({
          'status': status.name,
          'rejection_reason': rejectionReason?.trim().isEmpty == true
              ? null
              : rejectionReason?.trim(),
        })
        .eq('id', id);
  }

  Future<void> deleteIlan(String id) async {
    final images = await _client
        .from('ilan_images')
        .select('storage_path')
        .eq('ilan_id', id);
    final paths = (images as List)
        .map((row) => row['storage_path'] as String)
        .toList();
    final deleted = await _client
        .from('ilanlar')
        .delete()
        .eq('id', id)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw const PostgrestException(
        message: 'İlan silinemedi: bu işlem için yetkiniz yok.',
      );
    }
    if (paths.isEmpty) return;
    try {
      await _client.storage.from('ilan-images').remove(paths);
    } catch (_) {
      // İlan zaten silindi; depolamadaki görsel temizliği kritik değildir.
    }
  }

  Future<void> incrementView(String id) async {
    try {
      await _client.rpc('increment_ilan_view', params: {'p_ilan_id': id});
    } catch (_) {
      // Görüntülenme sayacı kritik değildir; detay ekranını bozmaz.
    }
  }

  Future<bool> isFavorite(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await _client
        .from('ilan_favorites')
        .select('ilan_id')
        .eq('ilan_id', id)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  Future<bool> toggleFavorite(String id, bool currentlyFavorite) async {
    final userId = _requireUser();
    if (currentlyFavorite) {
      await _client
          .from('ilan_favorites')
          .delete()
          .eq('ilan_id', id)
          .eq('user_id', userId);
      return false;
    }
    await _client.from('ilan_favorites').upsert({
      'ilan_id': id,
      'user_id': userId,
    });
    return true;
  }

  Future<void> _uploadImages(
    String ilanId,
    String userId,
    List<Uint8List> images,
  ) async {
    for (var index = 0; index < images.length; index++) {
      final path = '$userId/$ilanId/${const Uuid().v4()}.jpg';
      await _client.storage
          .from('ilan-images')
          .uploadBinary(
            path,
            images[index],
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      final url = _client.storage.from('ilan-images').getPublicUrl(path);
      await _client.from('ilan_images').insert({
        'ilan_id': ilanId,
        'owner_id': userId,
        'image_url': url,
        'storage_path': path,
        'sort_order': index,
      });
      if (index == 0)
        await _client
            .from('ilanlar')
            .update({'cover_image_url': url})
            .eq('id', ilanId);
    }
  }

  String _requireUser() {
    final id = _client.auth.currentUser?.id;
    if (id == null)
      throw const AuthException('Bu işlem için giriş yapmalısınız.');
    return id;
  }

  List<Ilan> _mapIlanlar(dynamic rows) => (rows as List)
      .map((row) => Ilan.fromJson(Map<String, dynamic>.from(row as Map)))
      .toList();
}
