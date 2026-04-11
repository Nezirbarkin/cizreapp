import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/cached_post_model.dart';
import '../models/post_model.dart';
import '../utils/app_logger.dart';

/// Stale-while-revalidate cache sonucu
class StaleCacheResult<T> {
  final T? data;
  final bool isStale;
  final bool isFromCache;
  
  const StaleCacheResult({
    this.data,
    this.isStale = false,
    this.isFromCache = false,
  });
}

class CacheService {
  static const String _boxName = 'posts_cache';
  static Box<CachedPost>? _box;

  // Singleton pattern
  static final CacheService _instance = CacheService._internal();

  factory CacheService() {
    return _instance;
  }

  CacheService._internal();

  /// Cache hizmetini başlat
  static Future<void> initialize() async {
    // Web'de Hive kullanmıyoruz - IndexedDB problemi
    if (kIsWeb) {
      AppLogger.info('ℹ️ Cache service skipped on web platform');
      return;
    }

    try {
      _box = await Hive.openBox<CachedPost>(_boxName);
      AppLogger.info('🔄 Cache service initialized. Box size: ${_box?.length ?? 0}');
    } catch (e) {
      AppLogger.error('❌ Cache initialization error: $e');
      // Hata olsa bile devam et - cache olmadan işleyelim
      _box = null;
    }
  }

  /// Postları cache'e kaydet
  Future<void> cachePost(Post post) async {
    if (_box == null) return;
    try {
      final cachedPost = CachedPost.fromPost(post);
      await _box!.put(post.id, cachedPost);
      AppLogger.debug('💾 Post cached: ${post.id}');
    } catch (e) {
      AppLogger.error('Cache post error: $e');
    }
  }

  /// Birden fazla postu cache'e kaydet
  Future<void> cachePosts(List<Post> posts) async {
    if (_box == null) return;
    try {
      final Map<String, CachedPost> postsMap = {
        for (var post in posts)
          post.id: CachedPost.fromPost(post)
      };
      await _box!.putAll(postsMap);
      AppLogger.debug('💾 ${posts.length} posts cached');
    } catch (e) {
      AppLogger.error('Cache posts error: $e');
    }
  }

  /// Cache'den post al
  Post? getCachedPost(String postId) {
    if (_box == null) return null;
    try {
      final cachedPost = _box!.get(postId);
      if (cachedPost != null && !cachedPost.isExpired()) {
        AppLogger.debug('✅ Post retrieved from cache: $postId');
        return cachedPost.toPost();
      }
      return null;
    } catch (e) {
      AppLogger.error('Get cached post error: $e');
      return null;
    }
  }

  /// Cache'den tüm postları al (süresi dolmayan)
  List<Post> getCachedPosts() {
    if (_box == null) return [];
    try {
      final posts = _box!.values
          .where((cachedPost) => !cachedPost.isExpired())
          .map((cachedPost) => cachedPost.toPost())
          .toList();
      AppLogger.debug('✅ Retrieved ${posts.length} posts from cache');
      return posts;
    } catch (e) {
      AppLogger.error('Get cached posts error: $e');
      return [];
    }
  }

  /// Sayfalanmış postları cache'den al
  List<Post> getCachedPostsPaginated({
    required int page,
    required int pageSize,
  }) {
    if (_box == null) return [];
    try {
      final allPosts = getCachedPosts();
      final startIndex = page * pageSize;
      final endIndex = (startIndex + pageSize).clamp(0, allPosts.length);

      if (startIndex >= allPosts.length) {
        return [];
      }

      final paginatedPosts = allPosts.sublist(startIndex, endIndex);
      AppLogger.debug('✅ Retrieved ${paginatedPosts.length} paginated posts from cache (page: $page)');
      return paginatedPosts;
    } catch (e) {
      AppLogger.error('Get paginated cached posts error: $e');
      return [];
    }
  }

  /// Belirli bir postu cache'den sil
  Future<void> deletePost(String postId) async {
    if (_box == null) return;
    try {
      await _box!.delete(postId);
      AppLogger.debug('🗑️ Post deleted from cache: $postId');
    } catch (e) {
      AppLogger.error('Delete post error: $e');
    }
  }

  /// Tüm cache'i temizle
  Future<void> clearCache() async {
    if (_box == null) return;
    try {
      await _box!.clear();
      AppLogger.info('🧹 Cache cleared');
    } catch (e) {
      AppLogger.error('Clear cache error: $e');
    }
  }

  /// Süresi dolan postları sil
  Future<void> clearExpiredPosts() async {
    if (_box == null) return;
    try {
      final keysToDelete = <String>[];
      for (var entry in _box!.toMap().entries) {
        if (entry.value.isExpired()) {
          keysToDelete.add(entry.key as String);
        }
      }

      for (var key in keysToDelete) {
        await _box!.delete(key);
      }

      AppLogger.debug('🧹 ${keysToDelete.length} expired posts deleted from cache');
    } catch (e) {
      AppLogger.error('Clear expired posts error: $e');
    }
  }

  /// Cache'deki post sayısı
  int get cacheSize => _box?.length ?? 0;

  /// Cache boş mu?
  bool get isEmpty => _box?.isEmpty ?? true;

  /// Belirli bir postu cache'te kontrol et
  bool containsPost(String postId) {
    if (_box == null) return false;
    return _box!.containsKey(postId);
  }

  /// Cache'deki son güncelleme zamanı
  DateTime? getLastCacheTime() {
    if (_box == null) return null;
    try {
      if (_box!.isEmpty) return null;

      final posts = _box!.values.toList();
      posts.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
      return posts.first.cachedAt;
    } catch (e) {
      AppLogger.error('Get last cache time error: $e');
      return null;
    }
  }

  // ==================== STALE-WHILE-REVALIDATE ====================
  
  /// Stale-while-revalidate pattern: Cache'ten hemen döndür, arka planda güncelle
  ///
  /// Bu metod cache'teki veriyi hemen döndürür (stale kabul edilerek),
  /// ardından arka planda yeni veriyi çeker ve cache'i günceller.
  ///
  /// Kullanım:
  /// ```dart
  /// final result = await CacheService().getWithStaleWhileRevalidate(
  ///   cacheKey: 'posts_page_0',
  ///   fetcher: () => postService.getFeedPosts(page: 0),
  ///   fromJson: (json) => Post.fromJson(json),
  ///   cacheDuration: const Duration(minutes: 5),
  /// );
  ///
  /// if (result.data != null) {
  ///   // Veriyi göster (cache'ten gelse bile)
  ///   showPosts(result.data);
  /// }
  ///
  /// if (result.isStale) {
  ///   // Arka planda güncelleniyor - kullanıcıya bildirim verebilirsiniz
  ///   showIndicator('Güncelleniyor...');
  /// }
  /// ```

  /// Posts için özel stale-while-revalidate
  Future<StaleCacheResult<List<Post>>> getPostsPaginatedWithStaleWhileRevalidate({
    required int page,
    required int pageSize,
    required Future<List<Post>> Function() fetcher,
    Duration cacheDuration = const Duration(minutes: 5),
  }) async {
    // Önce cache'ten kontrol et
    final cachedPosts = getCachedPostsPaginated(page: page, pageSize: pageSize);
    
    if (cachedPosts.isNotEmpty) {
      // Cache'ten döndür, arka planda güncelle
      fetcher().then((freshPosts) {
        if (freshPosts.isNotEmpty) {
          cachePosts(freshPosts);
          AppLogger.debug('🔄 Posts cache revalidated for page $page');
        }
      }).catchError((e) {
        AppLogger.error('Posts revalidate error: $e');
      });
      
      return StaleCacheResult(
        data: cachedPosts,
        isStale: true,
        isFromCache: true,
      );
    }
    
    // Cache boşsa, fetch'in bitmesini bekle
    try {
      final freshPosts = await fetcher();
      if (freshPosts.isNotEmpty) {
        await cachePosts(freshPosts);
      }
      
      return StaleCacheResult(
        data: freshPosts,
        isStale: false,
        isFromCache: false,
      );
    } catch (e) {
      AppLogger.error('Posts fetch error: $e');
      return const StaleCacheResult();
    }
  }
}
