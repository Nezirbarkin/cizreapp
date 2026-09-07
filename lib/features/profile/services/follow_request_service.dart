import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/notification_service.dart';

/// Gizli hesaplar için takip isteği yönetim servisi.
/// profile_is_public = false olan hesaplara takip isteği gönderir.
/// İstek onaylanınca otomatik olarak follows tablosuna eklenir (SQL trigger ile).
class FollowRequestService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }
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

  /// Takip isteği kabul et.
  ///
  /// Yalnızca follow_requests.status'u 'accepted' yapar; follows kaydını ve
  /// bildirimi DB trigger'ları üstlenir (tek kaynak, çift bildirim yok).
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

      // 2. İsteği 'accepted' yap.
      //
      // follows kaydını ARTIK Dart eklemiyor: DB'deki SECURITY DEFINER
      // trigger'ı (handle_follow_request_status_change) status 'accepted'
      // olunca follows satırını kendisi oluşturuyor. Eskiden Dart da doğrudan
      // insert ettiği için follows INSERT politikasının
      // "auth.uid() = following_id" gibi gevşek bir kural içermesi
      // gerekiyordu; bu da bir kullanıcının başkasını kendisini takip ediyor
      // göstermesine izin veriyordu (20260906100002 migration'ı ile kapatıldı).
      await _supabase
          .from('follow_requests')
          .update({'status': 'accepted'})
          .eq('id', requestId);

      debugPrint('✅ Takip isteği kabul edildi: $requestId (follower: $followerId)');

      // 3. Bildirim: DB trigger'ı (notify_follow_request_accepted) zaten
      //    'follow_request_accepted' tipinde bildirim yazıyor. Burada ikinci
      //    kez 'follow_accepted' yazmak kullanıcıya AYNI olay için iki
      //    bildirim gösteriyordu; bu yüzden Dart tarafı kaldırıldı.
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
