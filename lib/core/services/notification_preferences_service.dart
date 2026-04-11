import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_preferences_model.dart';

class NotificationPreferencesService {
  final _supabase = Supabase.instance.client;

  /// Kullanıcının bildirim tercihlerini getir
  Future<NotificationPreferences?> getUserPreferences(String userId) async {
    try {
      final response = await _supabase
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        // Eğer tercih yoksa, varsayılan tercihleri oluştur
        return await _createDefaultPreferences(userId);
      }

      return NotificationPreferences.fromJson(response);
    } catch (e) {
      throw Exception('Bildirim tercihleri yüklenirken hata: $e');
    }
  }

  /// Varsayılan bildirim tercihlerini oluştur
  Future<NotificationPreferences> _createDefaultPreferences(String userId) async {
    try {
      final data = {
        'user_id': userId,
        'likes_enabled': true,
        'comments_enabled': true,
        'followers_enabled': true,
        'order_updates_enabled': true,
        'order_ready_enabled': true,
        'delivery_enabled': true,
        'promotional_enabled': false,
        'mentions': true,
        'group_join_requests_enabled': true,
        'group_member_joined_enabled': true,
      };

      final response = await _supabase
          .from('notification_preferences')
          .insert(data)
          .select()
          .single();

      return NotificationPreferences.fromJson(response);
    } catch (e) {
      throw Exception('Varsayılan tercihler oluşturulurken hata: $e');
    }
  }

  /// Bildirim tercihlerini güncelle
  Future<void> updatePreferences({
    required String userId,
    bool? likesEnabled,
    bool? commentsEnabled,
    bool? followersEnabled,
    bool? orderUpdatesEnabled,
    bool? orderReadyEnabled,
    bool? deliveryEnabled,
    bool? promotionalEnabled,
    bool? mentionsEnabled,
    bool? groupJoinRequestsEnabled,
    bool? groupMemberJoinedEnabled,
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (likesEnabled != null) updates['likes_enabled'] = likesEnabled;
      if (commentsEnabled != null) updates['comments_enabled'] = commentsEnabled;
      if (followersEnabled != null) updates['followers_enabled'] = followersEnabled;
      if (orderUpdatesEnabled != null) updates['order_updates_enabled'] = orderUpdatesEnabled;
      if (orderReadyEnabled != null) updates['order_ready_enabled'] = orderReadyEnabled;
      if (deliveryEnabled != null) updates['delivery_enabled'] = deliveryEnabled;
      if (promotionalEnabled != null) updates['promotional_enabled'] = promotionalEnabled;
      if (mentionsEnabled != null) updates['mentions'] = mentionsEnabled;
      if (groupJoinRequestsEnabled != null) updates['group_join_requests_enabled'] = groupJoinRequestsEnabled;
      if (groupMemberJoinedEnabled != null) updates['group_member_joined_enabled'] = groupMemberJoinedEnabled;

      await _supabase
          .from('notification_preferences')
          .update(updates)
          .eq('user_id', userId);
    } catch (e) {
      throw Exception('Tercihler güncellenirken hata: $e');
    }
  }

  /// Belirli bir bildirim türü için tercihi kontrol et
  Future<bool> isNotificationEnabled(String userId, String notificationType) async {
    try {
      final prefs = await getUserPreferences(userId);
      if (prefs == null) return true; // Varsayılan olarak aktif

      switch (notificationType) {
        case 'like':
          return prefs.likesEnabled;
        case 'comment':
          return prefs.commentsEnabled;
        case 'follow':
        case 'follow_accepted': // Takip isteği kabul edildi
        case 'follow_request':  // Takip isteği alındı
          return prefs.followersEnabled;
        case 'mention':
          return prefs.mentionsEnabled;
        case 'order_update':
        case 'order_status':    // Sipariş durumu güncellemesi
        case 'order_confirmed': // Sipariş onaylandı
          return prefs.orderUpdatesEnabled;
        case 'order_ready':
          return prefs.orderReadyEnabled;
        case 'delivery':
        case 'delivered':       // Sipariş teslim edildi
          return prefs.deliveryEnabled;
        case 'new_order':       // Yeni sipariş (satıcı için)
          return prefs.orderUpdatesEnabled;
        case 'promotional':
          return prefs.promotionalEnabled;
        case 'group_join_request':
          return prefs.groupJoinRequestsEnabled;
        case 'group_member_joined':
          return prefs.groupMemberJoinedEnabled;
        case 'review_request':  // Değerlendirme isteği
        case 'review_pending':  // Bekleyen değerlendirme
          return prefs.orderUpdatesEnabled;
        default:
          return true; // Tanımlanmamış tipler için varsayılan açık
      }
    } catch (e) {
      return true; // Hata durumunda bildirimleri aktif bırak
    }
  }

  /// Tüm bildirimleri aç/kapat
  Future<void> toggleAllNotifications(String userId, bool enabled) async {
    try {
      await updatePreferences(
        userId: userId,
        likesEnabled: enabled,
        commentsEnabled: enabled,
        followersEnabled: enabled,
        mentionsEnabled: enabled,
        orderUpdatesEnabled: enabled,
        orderReadyEnabled: enabled,
        deliveryEnabled: enabled,
        promotionalEnabled: enabled,
        groupJoinRequestsEnabled: enabled,
        groupMemberJoinedEnabled: enabled,
      );
    } catch (e) {
      throw Exception('Bildirimler güncellenirken hata: $e');
    }
  }
}
