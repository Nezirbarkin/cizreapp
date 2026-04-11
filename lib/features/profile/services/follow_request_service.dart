import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/notification_service.dart';

/// Gizli hesaplar için takip isteği yönetim servisi.
/// profile_is_public = false olan hesaplara takip isteği gönderir.
/// İstek onaylanınca otomatik olarak follows tablosuna eklenir (SQL trigger ile).
class FollowRequestService {
  final SupabaseClient _supabase = Supabase.instance.client;
  // ignore: unused_field
  final NotificationService _notificationService = NotificationService();

  /// Takip isteği gönder (duplicate key hatasını önler)
  Future<void> sendFollowRequest(String targetUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('Kullanıcı giriş yapmamış');

      debugPrint('🔍 Takip isteği gönderiliyor: $currentUserId -> $targetUserId');

      // upsert_follow_request fonksiyonunu kullan (duplicate'i önler)
      try {
        final result = await _supabase.rpc('upsert_follow_request', params: {
          'p_follower_id': currentUserId,
          'p_following_id': targetUserId,
        });

        debugPrint('🔍 RPC sonucu: $result');

        if (result != null && result['success'] == false) {
          throw Exception(result['message'] ?? 'Takip isteği gönderilemedi');
        }

        debugPrint('✅ Takip isteği başarıyla gönderildi: $currentUserId -> $targetUserId');
      } catch (rpcError) {
        debugPrint('❌ RPC hatası: $rpcError');
        // RPC fonksiyonu yoksa veya hata veriyorsa direkt insert deneyelim
        debugPrint('⚠️ Alternatif yöntem deneniyor: direkt insert');
        
        // Önce mevcut istek var mı kontrol et
        final existing = await _supabase
            .from('follow_requests')
            .select('id, status')
            .eq('follower_id', currentUserId)
            .eq('following_id', targetUserId)
            .maybeSingle();
        
        if (existing != null) {
          if (existing['status'] == 'pending') {
            debugPrint('⚠️ Zaten bekleyen bir istek var');
            return;
          } else {
            // Eski isteği güncelle
            await _supabase
                .from('follow_requests')
                .update({'status': 'pending', 'created_at': DateTime.now().toIso8601String()})
                .eq('id', existing['id']);
            debugPrint('✅ Mevcut istek güncellendi');
            return;
          }
        }
        
        // Yeni istek oluştur
        await _supabase.from('follow_requests').insert({
          'follower_id': currentUserId,
          'following_id': targetUserId,
          'status': 'pending',
        });
        
        debugPrint('✅ Yeni takip isteği oluşturuldu (alternatif yöntem)');
      }
    } catch (e) {
      debugPrint('❌ Takip isteği gönderme hatası: $e');
      rethrow;
    }
  }

  /// Takip isteği kabul et
  /// Hem follow_requests durumunu günceller hem de follows tablosuna ekler
  /// Ayrıca istek gönderen kullanıcıya bildirim gönderir
  Future<void> acceptFollowRequest(String requestId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('Kullanıcı giriş yapmamış');

      debugPrint('🔍 Takip isteği kabul ediliyor: requestId=$requestId');

      // 1. Önce istek gönderen kullanıcıyı bul (status güncellenmeden ÖNCE)
      final request = await _supabase
          .from('follow_requests')
          .select('follower_id, following_id, status')
          .eq('id', requestId)
          .maybeSingle();

      if (request == null) {
        debugPrint('❌ Takip isteği bulunamadı: $requestId');
        throw Exception('Takip isteği bulunamadı');
      }

      final followerId = request['follower_id'] as String;
      final requestStatus = request['status'] as String?;

      // Zaten kabul edilmişse tekrar işlem yapma
      if (requestStatus == 'accepted') {
        debugPrint('⚠️ Takip isteği zaten kabul edilmiş: $requestId');
        return;
      }

      debugPrint('🔍 İstek gönderen: $followerId, hedef: $currentUserId');

      // 2. follows tablosuna doğrudan ekle (önce follows'a ekle, sonra status güncelle)
      bool followAdded = false;
      try {
        await _supabase.from('follows').upsert({
          'follower_id': followerId,
          'following_id': currentUserId,
          'created_at': DateTime.now().toIso8601String(),
        }, onConflict: 'follower_id, following_id');
        followAdded = true;
        debugPrint('✅ follows tablosuna eklendi: $followerId -> $currentUserId');
      } catch (followError) {
        debugPrint('⚠️ follows tablosuna ekleme hatası (duplicate olabilir): $followError');
        // Duplicate ise devam et - zaten takip ediyor demektir
        followAdded = true;
      }

      // 3. İsteği kabul et (follows başarılı olduktan sonra)
      if (followAdded) {
        await _supabase
            .from('follow_requests')
            .update({'status': 'accepted'})
            .eq('id', requestId);
        debugPrint('✅ Takip isteği kabul edildi: $requestId');
      }

      // 4. İstek gönderen kullanıcıya bildirim gönder
      try {
        await _notificationService.createNotification(
          userId: followerId,
          type: 'follow_accepted',
          title: 'Takip İsteğiniz Kabul Edildi',
          content: 'Takip isteğiniz kabul edildi',
          actorId: currentUserId,
        );
        debugPrint('📩 Takip kabul bildirimi gönderildi: $followerId');
      } catch (notifError) {
        debugPrint('⚠️ Bildirim gönderilemedi: $notifError');
      }
    } catch (e) {
      debugPrint('❌ Takip isteği kabul hatası: $e');
      rethrow;
    }
  }

  /// Takip isteğini reddet
  Future<void> rejectFollowRequest(String requestId) async {
    try {
      await _supabase
          .from('follow_requests')
          .update({'status': 'rejected'})
          .eq('id', requestId);

      debugPrint('❌ Takip isteği reddedildi: $requestId');
    } catch (e) {
      debugPrint('❌ Takip isteği reddetme hatası: $e');
      rethrow;
    }
  }

  /// Takip isteğini sil (gönderen kişi iptal edebilir)
  Future<void> cancelFollowRequest(String targetUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('Kullanıcı giriş yapmamış');

      await _supabase
          .from('follow_requests')
          .delete()
          .eq('follower_id', currentUserId)
          .eq('following_id', targetUserId);

      debugPrint('🗑️ Takip isteği iptal edildi');
    } catch (e) {
      debugPrint('❌ Takip isteği iptal hatası: $e');
      rethrow;
    }
  }

  /// Bekleyen takip isteklerini getir (bana gelen istekler)
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('follow_requests')
          .select('*, profiles!follow_requests_follower_id_fkey(id, username, full_name, avatar_url)')
          .eq('following_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Bekleyen istekleri getirme hatası: $e');
      return [];
    }
  }

  /// Bekleyen takip isteği sayısını getir
  Future<int> getPendingRequestCount() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 0;

      final response = await _supabase
          .from('follow_requests')
          .select('id')
          .eq('following_id', currentUserId)
          .eq('status', 'pending');

      return response.length;
    } catch (e) {
      debugPrint('❌ Bekleyen istek sayısı hatası: $e');
      return 0;
    }
  }

  /// Kullanıcıya gönderilen isteğin durumunu kontrol et
  /// Döndürdüğü değerler: 'none', 'pending', 'accepted', 'rejected'
  Future<String> getFollowRequestStatus(String targetUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 'none';

      final response = await _supabase
          .from('follow_requests')
          .select('status')
          .eq('follower_id', currentUserId)
          .eq('following_id', targetUserId)
          .maybeSingle();

      if (response == null) return 'none';
      return response['status'] as String? ?? 'none';
    } catch (e) {
      debugPrint('❌ Takip isteği durumu kontrol hatası: $e');
      return 'none';
    }
  }

  /// Kullanıcının profili gizli mi kontrol et
  Future<bool> isProfilePrivate(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('profile_is_public')
          .eq('id', userId)
          .maybeSingle();

      if (response == null) return false;
      return !(response['profile_is_public'] as bool? ?? true);
    } catch (e) {
      debugPrint('❌ Profil gizlilik kontrol hatası: $e');
      return false;
    }
  }

  /// Belirli bir kullanıcının bize gönderdiği bekleyen takip isteğini getir
  /// Döndürdüğü değer: istek varsa request id, yoksa null
  Future<String?> getIncomingFollowRequestId(String fromUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return null;

      final response = await _supabase
          .from('follow_requests')
          .select('id')
          .eq('follower_id', fromUserId)
          .eq('following_id', currentUserId)
          .eq('status', 'pending')
          .maybeSingle();

      if (response == null) return null;
      return response['id'] as String?;
    } catch (e) {
      debugPrint('❌ Gelen takip isteği kontrol hatası: $e');
      return null;
    }
  }

  /// Kullanıcının onaylı takipçisi mi kontrol et (gizli hesaplar için)
  Future<bool> isApprovedFollower(String targetUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      // Önce follows tablosunda kontrol et
      final followResponse = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', currentUserId)
          .eq('following_id', targetUserId)
          .maybeSingle();

      return followResponse != null;
    } catch (e) {
      debugPrint('❌ Onaylı takipçi kontrol hatası: $e');
      return false;
    }
  }
}
