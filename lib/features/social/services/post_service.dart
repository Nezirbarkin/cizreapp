import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/post_model.dart';
// ignore: unused_import
import '../../../core/models/user_model.dart' as user_model;
import '../../../core/services/mention_service.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/performance_monitoring_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/app_logger.dart';

class PostService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }
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
  /// ✅ OPTİMİZE: posts_with_profiles view'ını kullanır.
  /// Tek sorguda post + yazar profil bilgisi (username, full_name, avatar_url,
  /// role, is_verified) gelir — N+1 problemi yok.
  /// View LEFT JOIN kullandığı için profil kaydı olmayan postlar da görünür
  /// (author_profile_exists=false olarak işaretlenir).
  Future<List<Post>> _fetchFeedFromNetwork({required int limit, required int offset}) async {
    try {
      // Feed'de sadece admin sabitlediği gönderiler üstte gösterilir
      // Kullanıcının kendi sabitlediği gönderiler normal olarak tarihe göre sıralanır
      final response = await _supabase
          .from('posts_with_profiles')
          .select()
          .order('admin_pinned', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // Debug: Sabitlenmiş gönderileri logla
      for (var post in response) {
        final isAdminPinned = post['admin_pinned'] == true;
        final isPinned = post['is_pinned'] == true;
        if (isAdminPinned || isPinned) {
          debugPrint('📌 FEED DEBUG: id=${post['id']}, admin_pinned=$isAdminPinned, is_pinned=$isPinned, user_id=${post['user_id']}');
        }
      }

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
      // Hataları merkezi işleyiciden geçir: ağ hatası ("Failed host lookup" /
      // SocketException) → "İnternet bağlantınızı kontrol edin", izin hatası →
      // "yetkiniz bulunmuyor" gibi kullanıcı dostu mesaj. FriendlyException'ın
      // toString() sadece temiz mesajı döndürür; UI'da Tekrar Dene ile gösterilir.
      throw FriendlyException.from(e);
    }
  }

  // Kullanıcının gönderilerini getir
  // ✅ OPTİMİZE: posts_with_profiles view'ını kullanır (yazar bilgisi dahil)
  Future<List<Post>> getUserPosts(String userId) async {
    try {
      final response = await _supabase
          .from('posts_with_profiles')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Post.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Kullanıcı gönderileri yüklenirken hata: $e');
    }
  }

  // ID'ye göre gönderi getir
  // ✅ OPTİMİZE: posts_with_profiles view'ını kullanır (yazar bilgisi dahil)
  Future<Post?> getPostById(String id) async {
    try {
      final response = await _supabase
          .from('posts_with_profiles')
          .select()
          .eq('id', id)
          .maybeSingle();

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

      await _analyticsService.trackPostLike(postId);
    } catch (e) {
      throw Exception('Beğeni eklenirken hata: $e');
    }
  }

  // NOT (2026-09-06): Kullanılmayan bildirim yardımcıları kaldırıldı.
  // Beğeni / yorum / takip bildirimleri DB trigger'ları tarafından
  // (notify_post_like, notify_post_comment, notify_new_follower)
  // üretiliyor. Ayrıca notifications tablosunun INSERT politikası
  // yalnızca 'kendine bildirim' yazmaya izin veriyor; bu yüzden istemci
  // tarafından başka bir kullanıcıya bildirim yazmak zaten mümkün değil.

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
    // Yalnızca boşluktan oluşan yorumlar DB'ye yazılmasın (content NOT NULL
    // ama boş string'i engellemiyor; feed'de boş balon görünüyordu).
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw Exception('Yorum boş olamaz');
    }

    try {
      // Yazar bilgisini de aynı sorguda geri al; böylece yeni yorum listeye
      // eklenirken ikinci bir profil isteği gerekmiyor.
      final response = await _supabase
          .from('post_comments')
          .insert({
            'post_id': postId,
            'user_id': userId,
            'content': trimmed,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select(
            '*, profiles!post_comments_user_id_fkey(id, username, full_name, avatar_url)',
          )
          .maybeSingle();

      if (response == null) return null;

      final commentId = response['id'];
      content = trimmed;

      // Mention'ları kaydet (@kullaniciadi'leri parse edip database'e kaydet)
      debugPrint('📝 Mention\'lar kaydediliyor - Comment: $commentId');
      await _mentionService.saveMentionsForComment(
        commentId: commentId,
        commentText: content,
      );

      // NOT: Yorum bildirimi SQL trigger tarafından otomatik gönderiliyor
      // notify_post_comment_trigger - duplicatesiz single notification

      await _analyticsService.trackComment(postId);

      return PostComment.fromJson(response);
    } catch (e) {
      throw Exception('Yorum eklenirken hata: $e');
    }
  }

  // Yorumları getir
  // ✅ OPTİMİZE: Yazar profilleri aynı sorguda JOIN'leniyor. Eskiden ekran
  // katmanı her yorum için ayrı bir getUserProfile çağrısı yapıyordu (N+1).
  Future<List<PostComment>> getComments(String postId) async {
    try {
      final response = await _supabase
          .from('post_comments')
          .select(
            '*, profiles!post_comments_user_id_fkey(id, username, full_name, avatar_url)',
          )
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
  // Yetki DB'de: yorumu yazan, gönderi sahibi veya admin silebilir
  // (post_comments_delete_allowed politikası).
  Future<void> deleteComment(String commentId) async {
    try {
      final deleted = await _supabase
          .from('post_comments')
          .delete()
          .eq('id', commentId)
          .select('id');

      if ((deleted as List).isEmpty) {
        // RLS engelledi: satır silinmedi ama Postgrest hata da fırlatmadı.
        throw Exception('Bu yorumu silme yetkiniz yok');
      }
    } catch (e) {
      throw Exception('Yorum silinirken hata: $e');
    }
  }

  /// Yorumu silebilir miyiz? (yorum sahibi veya gönderi sahibi)
  bool canDeleteComment({
    required String commentUserId,
    required String postOwnerId,
  }) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    return userId == commentUserId || userId == postOwnerId;
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

  // ==========================================================================
  // KAYDEDİLEN GÖNDERİLER (post_favorites)
  // ==========================================================================
  // ÖNCEKİ DURUM — üç ayrı depo aynı anda kullanılıyordu:
  //   * Keşfet feed'indeki yer imi butonu SharedPreferences('saved_posts')
  //     yazıyordu (cihaz yerel; uygulama silinince kaybolur),
  //   * Profil ekranlarındaki buton toggle_post_favorite RPC'siyle
  //     post_favorites tablosuna yazıyordu,
  //   * ama profil ekranları kayıtlı DURUMUNU yine SharedPreferences'tan
  //     okuyordu.
  // Sonuç: feed'den kaydedilen gönderi "Favorilerim" ekranında hiç görünmüyor,
  // profilden kaydedilen gönderinin ikonu dolu görünmüyordu.
  //
  // Tek kaynak artık post_favorites (Favoriler ekranının da okuduğu tablo).

  /// Kullanıcının kaydettiği gönderi id'leri.
  Future<Set<String>> getSavedPostIds() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return {};

      final response = await _supabase
          .from('post_favorites')
          .select('post_id')
          .eq('user_id', userId);

      return (response as List)
          .map((row) => row['post_id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (e) {
      debugPrint('Kaydedilen gönderiler yüklenirken hata: $e');
      return {};
    }
  }

  /// Gönderiyi kaydet / kaydı kaldır. Dönen değer: işlem sonrası kayıtlı mı.
  Future<bool> toggleSavePost(String postId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Kaydetmek için giriş yapmalısınız');
    }

    final existing = await _supabase
        .from('post_favorites')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('post_favorites')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
      return false;
    }

    await _supabase.from('post_favorites').insert({
      'post_id': postId,
      'user_id': userId,
    });
    return true;
  }

  /// Eski sürümde SharedPreferences'ta tutulan yerel kayıtları bir kereliğine
  /// post_favorites tablosuna taşır. Taşıma sonrası yerel anahtar silinir,
  /// böylece her açılışta tekrar çalışmaz.
  Future<void> migrateLegacyLocalSaves() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getStringList('saved_posts');
      if (legacy == null) return;

      final ids = legacy.where((id) => id.isNotEmpty).toSet();
      if (ids.isNotEmpty) {
        await _supabase.from('post_favorites').upsert(
          [
            for (final postId in ids) {'post_id': postId, 'user_id': userId},
          ],
          onConflict: 'user_id,post_id',
          ignoreDuplicates: true,
        );
        debugPrint('📌 ${ids.length} yerel kayıt post_favorites tablosuna taşındı');
      }

      await prefs.remove('saved_posts');
    } catch (e) {
      // Taşıma başarısız olursa kullanıcıyı engellemeyelim; yerel anahtar
      // duruyorsa bir sonraki açılışta tekrar denenir.
      debugPrint('Yerel kayıt taşıma hatası (yoksayıldı): $e');
    }
  }

  /// Kaydedilen gönderilerin tamamını (içerikleriyle) getirir.
  Future<List<Post>> getSavedPosts() async {
    try {
      final ids = await getSavedPostIds();
      if (ids.isEmpty) return [];

      final response = await _supabase
          .from('posts_with_profiles')
          .select()
          .inFilter('id', ids.toList())
          .order('created_at', ascending: false);

      return (response as List).map((json) => Post.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Kaydedilen gönderiler getirilemedi: $e');
      return [];
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
