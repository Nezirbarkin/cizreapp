import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/post_model.dart';
// ignore: unused_import
import '../../../core/models/user_model.dart' as user_model;
import '../../../core/services/notification_service.dart';
import '../../../core/services/mention_service.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/performance_monitoring_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/utils/app_logger.dart';

class PostService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();
  final MentionService _mentionService = MentionService();
  final CacheService _cacheService = CacheService();
  final PerformanceMonitoringService _performanceMonitoringService = PerformanceMonitoringService();
  final AnalyticsService _analyticsService = AnalyticsService();

  // Tüm aktif gönderileri getir (feed) - with stale-while-revalidate cache & performance monitoring
  // ✅ OPTİMİZE: N+1 query problemi düzeltildi - likes_count ve comments_count posts tablosundan doğrudan okunuyor
  // ✅ CACHE: Stale-while-revalidate pattern - cache'ten hemen göster, arka planda güncelle
  Future<List<Post>> getFeed({int limit = 20, int offset = 0, bool useCache = false}) async {
    return await _performanceMonitoringService.measureApiCall(
      endpoint: 'posts.getFeed',
      apiCall: () async {
        // Cache devre dışı - her zaman ağdan taze veri çek (keşfet sayfası için sıralama önemli)
        // Stale-while-revalidate sıralamayı bozabiliyor, bu yüzden kullanmıyoruz
        return await _fetchFeedFromNetwork(limit: limit, offset: offset);
      },
    );
  }

  /// Network'ten feed verilerini çek (cache'ten bağımsız)
  Future<List<Post>> _fetchFeedFromNetwork({required int limit, required int offset}) async {
    try {
      final response = await _supabase
          .from('posts')
          .select()
          .eq('is_active', true)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // ✅ PERFORMANS: Posts tablosunda likes_count ve comments_count zaten mevcut
      final posts = (response as List).map((json) => Post.fromJson(json)).toList();

      // Cache'e kaydet
      if (posts.isNotEmpty) {
        await _cacheService.cachePosts(posts);
        AppLogger.info('📦 ${posts.length} posts cached successfully');
      }

      // Analytics tracking
      await _analyticsService.trackEvent(
        eventType: 'feed_load',
        metadata: {'count': posts.length, 'offset': offset},
      );

      return posts;
    } catch (e) {
      AppLogger.error('❌ Feed loading error: $e');
      await _analyticsService.trackError('feed_load_error', details: e.toString());
      throw Exception('Feed yüklenirken hata: $e');
    }
  }

  // Kullanıcının gönderilerini getir
  // ✅ OPTİMİZE: N+1 query problemi düzeltildi
  Future<List<Post>> getUserPosts(String userId) async {
    try {
      final response = await _supabase
          .from('posts')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      // ✅ PERFORMANS: likes_count ve comments_count posts tablosundan doğrudan okunuyor
      return (response as List).map((json) => Post.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Kullanıcı gönderileri yüklenirken hata: $e');
    }
  }

  // ID'ye göre gönderi getir
  Future<Post?> getPostById(String id) async {
    try {
      final response =
          await _supabase.from('posts').select().eq('id', id).maybeSingle();

      if (response == null) return null;
      return Post.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  // Gönderi oluştur
  Future<Post?> createPost({
    required String userId,
    required String content,
    List<String>? images,
    String? location,
    double? latitude,
    double? longitude,
  }) async {
    // Görsel listesini temizle - boş string'leri çıkar
    final cleanImages = images
        ?.where((url) => url.isNotEmpty)
        .toList() ?? [];

    try {
      final response = await _supabase.from('posts').insert({
        'user_id': userId,
        'content': content,
        'images': cleanImages,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      }).select().maybeSingle();

      if (response == null) return null;
      return Post.fromJson(response);
    } catch (e) {
      throw Exception('Gönderi oluşturulurken hata: $e');
    }
  }

  // Gönderi güncelle
  Future<Post?> updatePost(String postId, Map<String, dynamic> updates) async {
    try {
      final response = await _supabase
          .from('posts')
          .update(updates)
          .eq('id', postId)
          .select()
          .maybeSingle();

      if (response == null) return null;
      return Post.fromJson(response);
    } catch (e) {
      throw Exception('Gönderi güncellenirken hata: $e');
    }
  }

  // Gönderi sil
  Future<void> deletePost(String postId) async {
    try {
      await _supabase.from('posts').delete().eq('id', postId);
    } catch (e) {
      throw Exception('Gönderi silinirken hata: $e');
    }
  }

  // Beğeni ekle
  Future<void> likePost(String postId, String userId) async {
    try {
      await _supabase.from('post_likes').insert({
        'post_id': postId,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // NOT: Beğeni bildirimi SQL trigger tarafından otomatik gönderiliyor
      // notify_post_like_trigger - duplicatesiz single notification
    } catch (e) {
      throw Exception('Beğeni eklenirken hata: $e');
    }
  }

  // Beğeni bildirimi oluştur
  Future<void> _createLikeNotification(String postId, String actorId) async {
    try {
      debugPrint('🔵 BİLDİRİM: Beğeni bildirimi oluşturuluyor - Post: $postId, Actor: $actorId');
      
      // Gönderiyi getir
      final post = await getPostById(postId);
      if (post == null) {
        debugPrint('⚠️ BİLDİRİM: Gönderi bulunamadı');
        return;
      }
      if (post.userId == actorId) {
        debugPrint('⚠️ BİLDİRİM: Kendi gönderisine beğendi, bildirim gönderilmiyor');
        return; // Kendi gönderisine beğendiğinde bildirim verme
      }
      
      debugPrint('🔵 BİLDİRİM: Gönderi sahibi: ${post.userId}');

      // Gönderi sahibi ve beğenen kullanıcı bilgilerini getir
      final response = await _supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', [post.userId, actorId]);

      final profiles = response;
      Map<String, dynamic>? postOwner;
      Map<String, dynamic>? actor;
      
      try {
        postOwner = profiles.firstWhere((p) => p['id'] == post.userId);
      } catch (e) {
        debugPrint('⚠️ BİLDİRİM: Post owner profili bulunamadı');
      }
      
      try {
        actor = profiles.firstWhere((p) => p['id'] == actorId);
      } catch (e) {
        debugPrint('⚠️ BİLDİRİM: Actor profili bulunamadı');
      }

      if (postOwner == null || actor == null) {
        debugPrint('⚠️ BİLDİRİM: Profil bulunamadı - postOwner: $postOwner, actor: $actor');
        return;
      }
      
      debugPrint('🔵 BİLDİRİM: Actor: ${actor['username']}, PostOwner: ${postOwner['username']}');

      await _notificationService.createLikeNotification(
        userId: postOwner['id'],
        actorId: actor['id'],
        actorName: actor['username'] ?? 'Bir kullanıcı',
        actorAvatar: actor['avatar_url'],
        entityType: 'post',
        entityId: postId,
        entityImage: post.images.isNotEmpty ? post.images.first : null,
        entityTitle: (post.content?.length ?? 0) > 50 ? '${post.content!.substring(0, 50)}...' : (post.content ?? 'Gönderi'),
      );
      
      debugPrint('✅ BİLDİRİM: Beğeni bildirimi gönderildi');
    } catch (e) {
      // Bildirim hatası ana işlemi engellememesin
      debugPrint('❌ BİLDİRİM HATASI: Beğeni bildirimi oluşturulurken hata: $e');
    }
  }

  // Beğeniyi kaldır
  Future<void> unlikePost(String postId, String userId) async {
    try {
      await _supabase
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    } catch (e) {
      throw Exception('Beğeni kaldırılırken hata: $e');
    }
  }

  // Beğeni sayısını getir
  Future<int> getLikesCount(String postId) async {
    try {
      final response = await _supabase
          .from('post_likes')
          .select('id')
          .eq('post_id', postId);

      return response.length;
    } catch (e) {
      return 0;
    }
  }

  // Yorum sayısını getir
  Future<int> getCommentsCount(String postId) async {
    try {
      final response = await _supabase
          .from('post_comments')
          .select('id')
          .eq('post_id', postId);

      return response.length;
    } catch (e) {
      return 0;
    }
  }

  // Kullanıcının beğenip beğenmediğini kontrol et
  Future<bool> hasUserLiked(String postId, String userId) async {
    try {
      final response = await _supabase
          .from('post_likes')
          .select()
          .eq('post_id', postId)
          .eq('user_id', userId);

      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // ⚡ OPTİMİZE: Kullanıcının beğendiği tüm post'ları getir (Batch query)
  // Bu, N+1 query problemini çözer
  Future<Set<String>> getLikedPostIds(String userId, List<String> postIds) async {
    if (postIds.isEmpty) return {};
    
    try {
      final response = await _supabase
          .from('post_likes')
          .select('post_id')
          .eq('user_id', userId)
          .inFilter('post_id', postIds);

      return (response as List)
          .map((json) => json['post_id'] as String)
          .toSet();
    } catch (e) {
      debugPrint('Beğenilen post\'lar yüklenirken hata: $e');
      return {};
    }
  }

  // Yorum ekle
  Future<PostComment?> addComment(
    String postId,
    String userId,
    String content,
  ) async {
    try {
      final response = await _supabase.from('post_comments').insert({
        'post_id': postId,
        'user_id': userId,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
      }).select().maybeSingle();

      if (response == null) return null;

      final commentId = response['id'];

      // Mention'ları kaydet (@kullaniciadi'leri parse edip database'e kaydet)
      debugPrint('📝 Mention\'lar kaydediliyor - Comment: $commentId');
      await _mentionService.saveMentionsForComment(
        commentId: commentId,
        commentText: content,
      );

      // NOT: Yorum bildirimi SQL trigger tarafından otomatik gönderiliyor
      // notify_post_comment_trigger - duplicatesiz single notification

      return PostComment.fromJson(response);
    } catch (e) {
      throw Exception('Yorum eklenirken hata: $e');
    }
  }

  // Yorum bildirimi oluştur
  Future<void> _createCommentNotification(String postId, String actorId, String commentText) async {
    try {
      debugPrint('🟢 BİLDİRİM: Yorum bildirimi oluşturuluyor - Post: $postId, Actor: $actorId');
      
      // Gönderiyi getir
      final post = await getPostById(postId);
      if (post == null) {
        debugPrint('⚠️ BİLDİRİM: Gönderi bulunamadı');
        return;
      }
      if (post.userId == actorId) {
        debugPrint('⚠️ BİLDİRİM: Kendi gönderisine yorum yaptı, bildirim gönderilmiyor');
        return; // Kendi gönderisine yorumduğunda bildirim verme
      }
      
      debugPrint('🟢 BİLDİRİM: Gönderi sahibi: ${post.userId}');

      // Gönderi sahibi ve yorum yapan kullanıcı bilgilerini getir
      final response = await _supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', [post.userId, actorId]);

      final profiles = response;
      Map<String, dynamic>? postOwner;
      Map<String, dynamic>? actor;
      
      try {
        postOwner = profiles.firstWhere((p) => p['id'] == post.userId);
      } catch (e) {
        debugPrint('⚠️ BİLDİRİM: Post owner profili bulunamadı');
      }
      
      try {
        actor = profiles.firstWhere((p) => p['id'] == actorId);
      } catch (e) {
        debugPrint('⚠️ BİLDİRİM: Actor profili bulunamadı');
      }

      if (postOwner == null || actor == null) {
        debugPrint('⚠️ BİLDİRİM: Profil bulunamadı');
        return;
      }
      
      debugPrint('🟢 BİLDİRİM: Actor: ${actor['username']}, PostOwner: ${postOwner['username']}');

      await _notificationService.createCommentNotification(
        userId: postOwner['id'],
        actorId: actor['id'],
        actorName: actor['username'] ?? 'Bir kullanıcı',
        actorAvatar: actor['avatar_url'],
        postId: postId,
        postImage: post.images.isNotEmpty ? post.images.first : null,
        commentText: commentText.length > 50 ? '${commentText.substring(0, 50)}...' : commentText,
      );
      
      debugPrint('✅ BİLDİRİM: Yorum bildirimi gönderildi');
    } catch (e) {
      // Bildirim hatası ana işlemi engellememesin
      debugPrint('❌ BİLDİRİM HATASI: Yorum bildirimi oluşturulurken hata: $e');
    }
  }

  // Yorumları getir
  Future<List<PostComment>> getComments(String postId) async {
    try {
      final response = await _supabase
          .from('post_comments')
          .select()
          .eq('post_id', postId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => PostComment.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Yorumlar yüklenirken hata: $e');
    }
  }

  // Yorum sil
  Future<void> deleteComment(String commentId) async {
    try {
      await _supabase.from('post_comments').delete().eq('id', commentId);
    } catch (e) {
      throw Exception('Yorum silinirken hata: $e');
    }
  }

  // Takip et
  Future<void> followUser(String followerId, String followingId) async {
    try {
      // Önce zaten takip ediliyor mu kontrol et
      final existing = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', followerId)
          .eq('following_id', followingId)
          .maybeSingle();

      if (existing != null) {
        // Zaten takip ediliyor, hiçbir şey yapma
        return;
      }

      await _supabase.from('follows').insert({
        'follower_id': followerId,
        'following_id': followingId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // NOT: Takip bildirimi SQL trigger tarafından otomatik gönderiliyor
      // notify_new_follower_trigger - duplicatesiz single notification
    } catch (e) {
      throw Exception('Takip eklenirken hata: $e');
    }
  }

  // Takip bildirimi oluştur
  Future<void> _createFollowNotification(String followerId, String followingId) async {
    try {
      debugPrint('🟣 BİLDİRİM: Takip bildirimi oluşturuluyor - Follower: $followerId, Following: $followingId');
      
      // Takip eden ve takip edilen kullanıcı bilgilerini getir
      final response = await _supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', [followerId, followingId]);

      final profiles = response;
      Map<String, dynamic>? follower;
      Map<String, dynamic>? following;
      
      try {
        follower = profiles.firstWhere((p) => p['id'] == followerId);
      } catch (e) {
        debugPrint('⚠️ BİLDİRİM: Follower profili bulunamadı');
      }
      
      try {
        following = profiles.firstWhere((p) => p['id'] == followingId);
      } catch (e) {
        debugPrint('⚠️ BİLDİRİM: Following profili bulunamadı');
      }

      if (follower == null || following == null) {
        debugPrint('⚠️ BİLDİRİM: Profil bulunamadı');
        return;
      }
      
      debugPrint('🟣 BİLDİRİM: Follower: ${follower['username']}, Following: ${following['username']}');

      await _notificationService.createFollowNotification(
        userId: following['id'],
        actorId: follower['id'],
        actorName: follower['username'] ?? 'Bir kullanıcı',
        actorAvatar: follower['avatar_url'],
      );
      
      debugPrint('✅ BİLDİRİM: Takip bildirimi gönderildi');
    } catch (e) {
      // Bildirim hatası ana işlemi engellememesin
      debugPrint('❌ BİLDİRİM HATASI: Takip bildirimi oluşturulurken hata: $e');
    }
  }

  // Takipten çık
  Future<void> unfollowUser(String followerId, String followingId) async {
    try {
      await _supabase
          .from('follows')
          .delete()
          .eq('follower_id', followerId)
          .eq('following_id', followingId);
    } catch (e) {
      throw Exception('Takip kaldırılırken hata: $e');
    }
  }

  // Takip edip etmediğini kontrol et
  Future<bool> isFollowing(String followerId, String followingId) async {
    try {
      final response = await _supabase
          .from('follows')
          .select()
          .eq('follower_id', followerId)
          .eq('following_id', followingId);

      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Gönderiyi sabitle/sabitleme kaldır (toggle)
  Future<bool> togglePinPost(String postId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Mevcut gönderiyi al
      final postResponse = await _supabase
          .from('posts')
          .select('is_pinned, user_id')
          .eq('id', postId)
          .maybeSingle();

      if (postResponse == null) {
        throw Exception('Gönderi bulunamadı');
      }

      // Gönderinin sahibi mi kontrol et
      if (postResponse['user_id'] != userId) {
        throw Exception('Bu gönderi size ait değil');
      }

      final currentPinStatus = postResponse['is_pinned'] as bool? ?? false;
      final newPinStatus = !currentPinStatus;

      // Pin durumunu güncelle
      await _supabase
          .from('posts')
          .update({'is_pinned': newPinStatus})
          .eq('id', postId);

      debugPrint('📌 Gönderi ${newPinStatus ? "sabitlendi" : "sabitleme kaldırıldı"}: $postId');
      return newPinStatus;
    } catch (e) {
      debugPrint('❌ Gönderi sabitleme hatası: $e');
      throw Exception('Gönderi sabitleme işleminde hata: $e');
    }
  }
}
