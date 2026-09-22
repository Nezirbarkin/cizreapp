import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/seller_announcement_model.dart';

/// Satıcı duyuru kartları.
///
/// Satıcı tarafı (fetchMine / markSeen / dismiss) yalnızca RPC kullanır:
/// hedef kitle ve "kapattı" süzgeci sunucuda uygulanır, tablo satıcıya
/// kapalıdır. Admin tarafı tabloyu RLS (auth_is_admin) ile yazar, istatistikli
/// listeyi admin_list_seller_announcements ile okur.
class SellerAnnouncementService {
  SellerAnnouncementService([SupabaseClient? client]) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------
  // Satıcı
  // ---------------------------------------------------------------------

  Future<List<SellerAnnouncement>> fetchMine() async {
    final res = await _db.rpc('get_my_seller_announcements');
    return (res as List)
        .map((e) => SellerAnnouncement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Kartlar çizildikten sonra çağrılır; hatası satıcıya yansıtılmaz.
  Future<void> markSeen(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _db.rpc('mark_seller_announcements_seen', params: {'p_ids': ids});
    } catch (e) {
      debugPrint('⚠️ duyuru görüldü işaretlenemedi: $e');
    }
  }

  Future<void> dismiss(String id) async {
    await _db.rpc('dismiss_seller_announcement', params: {'p_id': id});
  }

  // ---------------------------------------------------------------------
  // Admin
  // ---------------------------------------------------------------------

  Future<List<SellerAnnouncement>> fetchAllForAdmin() async {
    final res = await _db.rpc('admin_list_seller_announcements');
    return (res as List)
        .map((e) => SellerAnnouncement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// [item.id] varsa günceller, yoksa yeni satır ekler.
  Future<void> save(SellerAnnouncement item) async {
    final payload = item.toDbPayload();
    if (item.id == null) {
      payload['created_by'] = _db.auth.currentUser?.id;
      await _db.from('seller_announcements').insert(payload);
    } else {
      await _db.from('seller_announcements').update(payload).eq('id', item.id!);
    }
  }

  Future<void> setPublished(String id, bool published) async {
    await _db
        .from('seller_announcements')
        .update({'is_published': published}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _db.from('seller_announcements').delete().eq('id', id);
  }

  /// "Belirli mağazalar" seçicisi için mağaza listesi.
  Future<List<({String id, String name})>> fetchShopsForPicker() async {
    final res = await _db.from('shops').select('id, name').order('name');
    return (res as List)
        .map((e) => (
              id: e['id'] as String,
              name: ((e['name'] as String?) ?? 'Adsız mağaza').trim(),
            ))
        .toList();
  }
}
