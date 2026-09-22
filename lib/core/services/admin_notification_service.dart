import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_notification_model.dart';

/// Admin bildirim merkezi.
///
/// Admin başkasının `notifications` satırına RLS ile dokunamaz; bu yüzden her
/// şey SECURITY DEFINER RPC'lerle yapılır (admin kontrolü sunucuda). Bir
/// gönderim "kampanya"dır: toplu (herkes/müşteri/satıcı/kurye) ya da kişiye
/// özel (bir ya da birkaç kişi); hemen ya da zamanlı gönderilir.
class AdminNotificationService {
  AdminNotificationService([SupabaseClient? client]) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic res) => (res as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  /// Son gönderimler (zamanlanmışlar dahil), en yeni üstte.
  Future<List<AdminNotification>> history({int limit = 300}) async {
    final res = await _db.rpc('admin_notification_history', params: {'p_limit': limit});
    return _rows(res).map(AdminNotification.fromJson).toList();
  }

  /// Alıcılar ve okuma durumu. [filter]: null (hepsi) | 'read' | 'unread'.
  Future<List<AdminNotificationRecipient>> recipients(
    String campaignId, {
    String? filter,
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _db.rpc('admin_notification_recipients', params: {
      'p_campaign_id': campaignId,
      'p_filter': filter,
      'p_limit': limit,
      'p_offset': offset,
    });
    return _rows(res).map(AdminNotificationRecipient.fromJson).toList();
  }

  /// Gönderim öncesi "≈ N kişiye ulaşacak" sayısı (bot ve gönderen hariç).
  Future<int> audienceCount(
    AdminNotifAudience audience, {
    List<String> userIds = const [],
  }) async {
    final res = await _db.rpc('admin_notification_audience_count', params: {
      'p_audience': audience.key,
      'p_user_ids': audience == AdminNotifAudience.personal ? userIds : null,
    });
    return (res as num).toInt();
  }

  /// Gönderir. [scheduledFor] gelecekteyse zamanlar, yoksa hemen gönderir.
  Future<AdminNotifSendResult> send({
    required AdminNotifAudience audience,
    required String title,
    required String content,
    required String iconType,
    List<String> userIds = const [],
    DateTime? scheduledFor,
  }) async {
    final res = await _db.rpc('admin_send_notification', params: {
      'p_audience': audience.key,
      'p_title': title.trim(),
      'p_content': content.trim(),
      'p_icon_type': iconType,
      'p_user_ids': audience == AdminNotifAudience.personal ? userIds : null,
      'p_scheduled_for': scheduledFor?.toUtc().toIso8601String(),
    });
    return AdminNotifSendResult.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Metni/ikonu düzeltir. Gönderilmişse alıcıların bildirim kutusundaki metin
  /// de güncellenir (giden push geri alınamaz). [renotify]: okunmadı yapıp en
  /// üste alır ve push'u yeniden gönderir. Zamanlanmışsa [scheduledFor] yeni zaman.
  Future<void> update(
    String campaignId, {
    required String title,
    required String content,
    required String iconType,
    DateTime? scheduledFor,
    bool renotify = false,
  }) async {
    await _db.rpc('admin_update_notification_campaign', params: {
      'p_campaign_id': campaignId,
      'p_title': title.trim(),
      'p_content': content.trim(),
      'p_icon_type': iconType,
      'p_scheduled_for': scheduledFor?.toUtc().toIso8601String(),
      'p_renotify': renotify,
    });
  }

  /// Alıcıların bildirim kutusundan ve "Duyurular"dan da kaldırır. Döner: silinen sayısı.
  Future<int> delete(List<String> campaignIds) async {
    final res = await _db.rpc('admin_delete_notification_campaigns', params: {
      'p_ids': campaignIds,
    });
    return (res as num).toInt();
  }

  /// Zamanlanmış bildirimi hemen gönderir.
  Future<AdminNotifSendResult> sendNow(String campaignId) async {
    final res = await _db.rpc('admin_send_notification_campaign_now', params: {
      'p_campaign_id': campaignId,
    });
    return AdminNotifSendResult.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Kişiye özel alıcı seçicisi için kullanıcı arama (ad, soyad, kullanıcı adı).
  Future<List<AdminNotifUser>> searchUsers(String query, {int limit = 30}) async {
    final q = query.trim();
    final res = await _db.rpc('admin_list_users', params: {
      'p_search': q.isEmpty ? null : q,
      'p_limit': limit,
    });
    return _rows(res).map(AdminNotifUser.fromJson).toList();
  }
}
