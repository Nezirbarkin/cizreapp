import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_model.dart';
import 'notification_preferences_service.dart';

class NotificationService {
  final NotificationPreferencesService _preferencesService = NotificationPreferencesService();
  
  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      return null;
    }
  }
  
  /// Supabase başlatılmış mı?
  bool get isSupabaseReady {
    try {
      Supabase.instance.client;
      return true;
    } catch (e) {
      return false;
    }
  }

  // Kullanıcının bildirimlerini getir
  Future<List<NotificationModel>> getNotifications(String userId, {int limit = 50}) async {
    final client = _supabase;
    if (client == null) return [];
    
    try {
      final response = await client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      // Mesaj/chat bildirimlerini hariç tut (ayrı chat sistemi var)
      final notifications = (response as List)
          .map((json) => NotificationModel.fromJson(json))
          .where((notification) =>
              notification.type != 'message' &&
              notification.type != 'chat')
          .toList();
      
      // Duplike sipariş bildirimlerini temizle
      // Aynı sipariş + aynı durum + kısa süre içinde oluşmuş bildirimler duplike sayılır
      // Farklı durumlar (onaylandı, yolda, teslim edildi) ayrı ayrı gösterilmeli
      final deduplicatedNotifications = <NotificationModel>[];
      final seenOrderKeys = <String>{};
      
      for (var notification in notifications) {
        final isOrderRelated = ['order_status', 'order_update', 'new_order', 'review_request', 'review_pending']
            .contains(notification.type);
        
        if (isOrderRelated && notification.entityId != null) {
          // Her sipariş bildirimi için benzersiz key: entityId + title (durum mesajı)
          // Böylece aynı siparişin farklı durum bildirimleri (onaylandı, yolda, teslim edildi) korunur
          // Ama aynı durum için birden fazla bildirim varsa sadece en yenisi gösterilir
          final titleKey = notification.title ?? notification.type;
          final groupKey = '${notification.entityId}_$titleKey';
          if (seenOrderKeys.contains(groupKey)) {
            continue; // Aynı sipariş + aynı başlık = duplike, atla
          }
          seenOrderKeys.add(groupKey);
        }
        deduplicatedNotifications.add(notification);
      }
      
      return deduplicatedNotifications;
    } catch (e) {
      return [];
    }
  }

  // Okunmamış bildirim sayısını getir
  // Not: Pending reviews ayrıca PendingReviewChecker ile gösteriliyor, buraya dahil edilmiyor
  Future<int> getUnreadCount(String userId) async {
    final client = _supabase;
    if (client == null) return 0;
    
    try {
      // Mesaj/chat bildirimlerini hariç tutarak okunmamış sayısını al
      // review_pending hariç (PendingReviewChecker'da ayrı gösteriliyor)
      final response = await client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false)
          .not('type', 'in', '(message,chat,review_pending)')
          .count(CountOption.exact);

      return response.count;
    } catch (e) {
      debugPrint('⚠️ Bildirim sayısı alınırken hata: $e');
      return 0;
    }
  }

  // Bildirimi okundu olarak işaretle
  Future<void> markAsRead(String notificationId) async {
    final client = _supabase;
    if (client == null) {
      throw Exception('Supabase başlatılmadı');
    }
    
    try {
      await client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      throw Exception('Bildirim okundu işaretlenirken hata: $e');
    }
  }

  // Tüm bildirimleri okundu olarak işaretle
  Future<void> markAllAsRead(String userId) async {
    final client = _supabase;
    if (client == null) {
      throw Exception('Supabase başlatılmadı');
    }
    
    try {
      await client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      throw Exception('Bildirimler okundu işaretlenirken hata: $e');
    }
  }

  // Bildirim sil
  Future<void> deleteNotification(String notificationId) async {
    final client = _supabase;
    if (client == null) {
      throw Exception('Supabase başlatılmadı');
    }
    
    try {
      await client
          .from('notifications')
          .delete()
          .eq('id', notificationId);
    } catch (e) {
      throw Exception('Bildirim silinirken hata: $e');
    }
  }

  // Yeni bildirim oluştur (tercihleri kontrol eder)
  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String content,
    String? actorId,
    String? actorName,
    String? actorAvatar,
    String? entityId,
    String? entityImage,
  }) async {
    final client = _supabase;
    if (client == null) {
      debugPrint('⚠️ Supabase başlatılmadı, bildirim oluşturulamıyor');
      return;
    }
    
    try {
      debugPrint('🔔 BİLDİRİM OLUŞTURULUYOR:');
      debugPrint('  - Kullanıcı: $userId');
      debugPrint('  - Tip: $type');
      debugPrint('  - Başlık: $title');
      debugPrint('  - İçerik: $content');
      
      // Kullanıcının FCM token'ını kontrol et (DEBUG)
      try {
        final profile = await client
            .from('profiles')
            .select('fcm_token, username')
            .eq('id', userId)
            .maybeSingle();
        if (profile != null) {
          final fcmToken = profile['fcm_token'] as String?;
          if (fcmToken == null || fcmToken.isEmpty) {
            debugPrint('⚠️⚠️⚠️ KRİTİK: Kullanıcının FCM TOKEN YOK! Push bildirim GELMEYECEK!');
            debugPrint('⚠️ Kullanıcı: ${profile['username']}');
          } else {
            debugPrint('✅ Kullanıcının FCM token var: ${fcmToken.substring(0, 30)}...');
          }
        } else {
          debugPrint('⚠️ Kullanıcı profili bulunamadı!');
        }
      } catch (e) {
        debugPrint('⚠️ FCM token kontrol hatası: $e');
      }
      
      // Kullanıcının bu bildirim türü için tercihini kontrol et
      final isEnabled = await _preferencesService.isNotificationEnabled(userId, type);
      if (!isEnabled) {
        debugPrint('⚠️ Bildirim kapalı, gönderilmiyor: $type');
        return;
      }
      
      debugPrint('✅ Bildirim tercihi açık, veritabanına ekleniyor...');
      
      final response = await client.from('notifications').insert({
        'user_id': userId,
        'type': type,
        'title': title,
        'content': content,
        'actor_id': actorId,
        'actor_name': actorName,
        'actor_avatar': actorAvatar,
        'entity_id': entityId,
        'entity_image': entityImage,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      }).select('id');
      
      debugPrint('✅ BİLDİRİM BAŞARIYLA OLUŞTURULDU! ID: ${response.first['id']}');
      debugPrint('🔔 Database Trigger tetiklenmeli (push_notification_trigger.sql)');
    } catch (e) {
      // Bildirim oluşturma hatası sessizce geçilebilir
      // Ana işlemi engellememek için
      debugPrint('❌ BİLDİRİM HATASI: $e');
      debugPrint('❌ HATA DETAYI: ${e.toString()}');
    }
  }

  // Beğeni bildirimi oluştur
  Future<void> createLikeNotification({
    required String userId,
    required String actorId,
    required String actorName,
    required String actorAvatar,
    required String entityType,
    required String entityId,
    String? entityImage,
    String? entityTitle,
  }) async {
    final type = entityType == 'post' ? 'like' : 'like';
    final title = '$actorName senin gönderini beğendi';
    final content = entityTitle ?? 'Gönderi';

    await createNotification(
      userId: userId,
      type: type,
      title: title,
      content: content,
      actorId: actorId,
      actorName: actorName,
      actorAvatar: actorAvatar,
      entityId: entityId,
      entityImage: entityImage,
    );
  }

  // Yorum bildirimi oluştur
  Future<void> createCommentNotification({
    required String userId,
    required String actorId,
    required String actorName,
    required String actorAvatar,
    required String postId,
    String? postImage,
    String? commentText,
  }) async {
    await createNotification(
      userId: userId,
      type: 'comment',
      title: '$actorName yorum yaptı',
      content: commentText ?? 'Yorum',
      actorId: actorId,
      actorName: actorName,
      actorAvatar: actorAvatar,
      entityId: postId,
      entityImage: postImage,
    );
  }

  // Takip bildirimi oluştur
  Future<void> createFollowNotification({
    required String userId,
    required String actorId,
    required String actorName,
    required String actorAvatar,
  }) async {
    await createNotification(
      userId: userId,
      type: 'follow',
      title: '$actorName seni takip etti',
      content: 'Takip isteği',
      actorId: actorId,
      actorName: actorName,
      actorAvatar: actorAvatar,
    );
  }

  // Mention bildirimi oluştur
  Future<void> createMentionNotification({
    required String userId,
    required String actorId,
    required String actorName,
    required String actorAvatar,
    required String postId,
    String? postImage,
  }) async {
    await createNotification(
      userId: userId,
      type: 'mention',
      title: '$actorName seni bahsetti',
      content: 'Yorum',
      actorId: actorId,
      actorName: actorName,
      actorAvatar: actorAvatar,
      entityId: postId,
      entityImage: postImage,
    );
  }

  // Grup katılma isteği bildirimi oluştur (grup kurucusuna gönderilir)
  Future<void> createGroupJoinRequestNotification({
    required String groupOwnerId,
    required String actorId,
    required String actorName,
    required String actorAvatar,
    required String groupId,
    required String groupName,
  }) async {
    await createNotification(
      userId: groupOwnerId,
      type: 'group_join_request',
      title: '$actorName "$groupName" grubuna katılmak istiyor',
      content: 'Katılma isteğini onaylayın veya reddedin',
      actorId: actorId,
      actorName: actorName,
      actorAvatar: actorAvatar,
      entityId: groupId,
    );
  }

  // Gruba katılım onay bildirimi (grup kurucusuna gönderilir)
  Future<void> createGroupMemberJoinedNotification({
    required String groupOwnerId,
    required String actorId,
    required String actorName,
    required String actorAvatar,
    required String groupId,
    required String groupName,
  }) async {
    await createNotification(
      userId: groupOwnerId,
      type: 'group_member_joined',
      title: '$actorName "$groupName" grubuna katıldı',
      content: 'Yeni üye gruba katıldı',
      actorId: actorId,
      actorName: actorName,
      actorAvatar: actorAvatar,
      entityId: groupId,
    );
  }

  // Değerlendirme bildirimi oluştur
  Future<void> createReviewNotification({
    required String userId,
    required String orderId,
    required String shopName,
    String? productId,
    String? productName,
  }) async {
    final content = productName != null
        ? '$productName için değerlendirme yapın'
        : '$shopName için değerlendirme yapın';
    
    await createNotification(
      userId: userId,
      type: 'review_pending',
      title: '$shopName siparişiniz teslim edildi',
      content: content,
      entityId: orderId,
    );
  }
}
