import 'dart:async';

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
import '../../music/models/attached_music.dart';

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
      // feed_posts_with_profiles = posts_with_profiles − sessize alınanlar −
      // gizlenen gönderiler (sunucuda süzülür; sayfalama bozulmaz).
      final response = await _supabase
          .from('feed_posts_with_profiles')
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

      // Analytics tracking — beklenmez: kayıt ağa gider ve akışı bir tur
      // geciktiriyordu (trackEvent hatayı kendi yutar).
      unawaited(_analyticsService.trackEvent(
        eventType: 'feed_load',
        metadata: {'count': posts.length, 'offset': offset},
      ));

      return posts;
    } catch (e) {
      AppLogger.error('❌ Feed loading error: $e');
      unawaited(
        _analyticsService.trackError('feed_load_error', details: e.toString()),
      );
      // Hataları merkezi işleyiciden geçir: ağ hatası ("Failed host lookup" /
      // SocketException) → "İnternet bağlantınızı kontrol edin", izin hatası →
      // "yetkiniz bulunmuyor" gibi kullanıcı dostu mesaj. FriendlyException'ın
      // toString() sadece temiz mesajı döndürür; UI'da Tekrar Dene ile gösterilir.
      throw FriendlyException.from(e);
    }
  }

  // Kullanıcının gönderilerini getir
  // ✅ OPTİMİZE: posts_with_profiles view'ını kullanır (yazar bilgisi dahil)
  // Sayfalı: profil ızgarası ilk [limit] gönderiyle açılır, kaydırdıkça devamı
  // gelir (eskiden tüm gönderiler + hepsinin beğeni durumu tek seferde).
  static const int userPostsPageSize = 24;

  Future<List<Post>> getUserPosts(
    String userId, {
    int limit = userPostsPageSize,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('posts_with_profiles')
          .select()
          .eq('user_id', userId)
          // Profilde sabitlenen gönderi başta (eskiden yalnız tarihe göre
          // sıralanıyordu, sabitleme yalnız bir rozet olarak kalıyordu).
          .order('is_pinned', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + limit - 1);

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
    String? background,
    AttachedMusic? music,
    double? imageAspectRatio,
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
        // Fotoğrafların çerçeve oranı (Görev 2.8): akış kartı fotoğrafı bu
        // oranda çizer. Yalnızca fotoğraflı gönderide anlamlı.
        if (cleanImages.isNotEmpty && imageAspectRatio != null)
          'image_aspect_ratio': imageAspectRatio,
        // Arka plan yalnızca görselsiz metin gönderilerinde anlamlı; görsel
        // varsa DB'ye yazılmaz (feed/ızgara tutarlılığı model tarafında da
        // aynı kuralla korunuyor).
        'background': cleanImages.isEmpty ? background : null,
        // İliştirilmiş müzik. Sunucudaki `music_attach_guard` tetikleyicisi
        // admin anahtarı kapalıyken bu alanı sessizce düşürür — yani
        // istemcinin göndermesi tek başına yayınlanacağı anlamına gelmez.
        if (music != null) 'music': music.toJson(),
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'is_active': true,
      }).select().maybeSingle();

      if (response == null) return null;
      return Post.fromJson(response);
    } catch (e) {
      throw Exception('Gönderi oluşturulurken hata: $e');
    }
  }

  /// Gönderi metnini düzenler. Sunucu `edited_at`'i damgalar
  /// (b_posts_mark_edited); dönen alanlar mevcut gönderiye birleştirilir.
  /// RLS yalnız sahibine izin verir: satır dönmezse yetki yoktur.
  Future<Post> updatePostContent(Post post, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty && post.images.isEmpty) {
      throw Exception('Gönderi metni boş olamaz');
    }
    final row = await _supabase
        .from('posts')
        .update({'content': trimmed})
        .eq('id', post.id)
        .select('id, content, edited_at, updated_at')
        .maybeSingle();
    if (row == null) throw Exception('Bu gönderiyi düzenleme yetkiniz yok');
    return post.copyWith(
      content: row['content'] as String? ?? trimmed,
      editedAt: DateTime.tryParse('${row['edited_at'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse('${row['updated_at'] ?? ''}')?.toUtc(),
    );
  }

  /// `#etiket` içeren gönderiler (yeniden eskiye; gizli hesap / engel RLS'te süzülür).
  Future<List<Post>> getPostsByHashtag(String tag, {int limit = 20, int offset = 0}) async {
    final res = await _supabase.rpc(
      'posts_by_hashtag',
      params: {'p_tag': tag, 'p_limit': limit, 'p_offset': offset},
    );
    if (res is! List) return const [];
    final posts = <Post>[];
    for (final row in res.whereType<Map>()) {
      try {
        posts.add(Post.fromJson(Map<String, dynamic>.from(row)));
      } catch (_) {
        // Bozuk satır tüm listeyi boşaltmasın.
      }
    }
    return posts;
  }

  /// "Gönderiyi gizle" / "İlgilenmiyorum": yalnız benim akışımdan çıkar
  /// ([reason]: 'hidden' | 'not_interested').
  Future<void> hidePost(String postId, {String reason = 'hidden'}) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Giriş yapmalısınız');
    await _supabase.from('hidden_posts').upsert(
      {'user_id': uid, 'post_id': postId, 'reason': reason},
      onConflict: 'user_id,post_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> unhidePost(String postId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    await _supabase.from('hidden_posts').delete().eq('user_id', uid).eq('post_id', postId);
  }

  /// Gönderi metninde arama (Türkçe katlamalı, en yeni önce, en çok 30).
  Future<List<Post>> searchPosts(String query, {int limit = 20}) async {
    if (query.trim().length < 2) return const [];
    final res = await _supabase.rpc(
      'search_posts',
      params: {'p_q': query.trim(), 'p_limit': limit},
    );
    if (res is! List) return const [];
    final posts = <Post>[];
    for (final row in res.whereType<Map>()) {
      try {
        posts.add(Post.fromJson(Map<String, dynamic>.from(row)));
      } catch (_) {}
    }
    return posts;
  }

  /// Son [days] günün en çok kullanılan etiketleri: (etiket, gönderi sayısı).
  Future<List<MapEntry<String, int>>> getTrendingHashtags({int days = 7, int limit = 10}) async {
    try {
      final res = await _supabase.rpc(
        'trending_hashtags',
        params: {'p_days': days, 'p_limit': limit},
      );
      if (res is! List) return const [];
      return [
        for (final e in res.whereType<Map>())
          if (e['tag'] is String)
            MapEntry(e['tag'] as String, (e['posts'] as num?)?.toInt() ?? 0),
      ];
    } catch (e) {
      debugPrint('Gündem etiketleri yüklenemedi: $e');
      return const [];
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
  // Zaten beğenilmişse (iki cihaz, eski durum, çift dokunuş) sessizce başarılı
  // sayılır: düz INSERT tekil kısıta çarpıp hata veriyor, ekran da kalbi geri
  // söndürüyordu. ON CONFLICT DO NOTHING'de tetikleyici çalışmaz → sayaç ve
  // bildirim de tekrarlanmaz.
  Future<void> likePost(String postId, String userId) async {
    try {
      await _supabase.from('post_likes').upsert(
        {'post_id': postId, 'user_id': userId},
        onConflict: 'post_id,user_id',
        ignoreDuplicates: true,
      );

      // NOT: Beğeni bildirimi SQL trigger tarafından otomatik gönderiliyor
      // (notify_post_like; aynı kişinin 24 saat içindeki tekrar beğenisi
      // yeni bildirim üretmez — 20261023000001).

      unawaited(_analyticsService.trackPostLike(postId));
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
  // [parentCommentId] verilirse bu yorum başka bir yoruma yanıt olarak
  // kaydedilir; yanıtlanan yorumun sahibine notify_comment_reply DB
  // trigger'ı otomatik bildirim gönderir (post_service.dart bunu tetiklemez).
  Future<PostComment?> addComment(
    String postId,
    String userId,
    String content, {
    String? parentCommentId,
  }) async {
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
            if (parentCommentId != null) 'parent_comment_id': parentCommentId,
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

      unawaited(_analyticsService.trackComment(postId));

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
          .order('created_at', ascending: false)
          // Üst sınır: çok yorumlu gönderide ekran tüm geçmişi indirmesin.
          .limit(300);

      return (response as List)
          .map((json) => PostComment.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Yorumlar yüklenirken hata: $e');
    }
  }

  /// Kullanıcının beğendiği yorumlar (gönderinin yorum listesi için tek istek).
  Future<Set<String>> getLikedCommentIds(String userId, List<String> commentIds) async {
    if (commentIds.isEmpty) return {};
    try {
      final response = await _supabase
          .from('post_comment_likes')
          .select('comment_id')
          .eq('user_id', userId)
          .inFilter('comment_id', commentIds);
      return (response as List).map((j) => j['comment_id'] as String).toSet();
    } catch (e) {
      debugPrint('Beğenilen yorumlar yüklenemedi: $e');
      return {};
    }
  }

  /// Yorum beğen (zaten beğenildiyse sessizce başarılı; sayaç/bildirim sunucuda).
  Future<void> likeComment(String commentId, String userId) async {
    await _supabase.from('post_comment_likes').upsert(
      {'comment_id': commentId, 'user_id': userId},
      onConflict: 'comment_id,user_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> unlikeComment(String commentId, String userId) async {
    await _supabase
        .from('post_comment_likes')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId);
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

  // Takip et. Tek RPC (social_follow — Görev 3.5): herkese açık hesabı takip
  // eder, gizli hesaba istek gönderir (onaylanınca takip olur), engelli hesabı
  // reddeder. [followerId] her zaman oturumdaki kullanıcıdır (sunucu auth.uid()).
  Future<void> followUser(String followerId, String followingId) async {
    try {
      await _supabase.rpc('social_follow', params: {'p_user_id': followingId, 'p_follow': true});
      // NOT: Takip / istek bildirimi SQL tetikleyicileri tarafından gönderiliyor.
    } catch (e) {
      throw Exception('Takip eklenirken hata: $e');
    }
  }

  // Takipten çık (bekleyen takip isteğini de geri alır).
  Future<void> unfollowUser(String followerId, String followingId) async {
    try {
      await _supabase.rpc('social_follow', params: {'p_user_id': followingId, 'p_follow': false});
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

  /// Gönderinin kayıt durumunu [saved] yapar; ikisi de tekrar edilebilir
  /// (idempotent). Ekran bildiği durumun tersini ister: "önce oku, sonra
  /// ekle/sil" yarışı (çift dokunuşta tekil kısıt hatası, ekranın "kaydedilmedi"
  /// göstermesi) böylece oluşmaz.
  Future<void> setPostSaved(String postId, bool saved) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Kaydetmek için giriş yapmalısınız');
    }

    if (saved) {
      await _supabase.from('post_favorites').upsert(
        {'post_id': postId, 'user_id': userId},
        onConflict: 'user_id,post_id',
        ignoreDuplicates: true,
      );
    } else {
      await _supabase
          .from('post_favorites')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
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

    final saved = existing == null;
    await setPostSaved(postId, saved);
    return saved;
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
