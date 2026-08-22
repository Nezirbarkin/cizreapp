import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/models/news_model.dart';

/// Haber servisi - Haber CRUD ve diğer haber işlemleri
class NewsService {
  final StorageService _storageService = StorageService();

  /// Supabase client'ı güvenli şekilde al
  static SupabaseClient get _client => Supabase.instance.client;

  // ============================================
  // HABER LİSTELEME
  // ============================================

  /// Yayınlanmış haberleri getir (anasayfa için)
  Future<List<NewsModel>> getPublishedNews({
    int limit = 20,
    int offset = 0,
    String? categoryId,
    bool featuredOnly = false,
    bool breakingOnly = false,
  }) async {
    try {
      List<Map<String, dynamic>> data;

      // Farklı query senaryoları
      if (featuredOnly) {
        data = await _client
            .from('news')
            .select('''
              *,
              news_categories(name, slug, color, icon),
              institutions(name, slug, logo_url, is_verified)
            ''')
            .eq('is_published', true)
            .eq('is_featured', true)
            .order('published_at', ascending: false)
            .range(offset, offset + limit - 1);
      } else if (breakingOnly) {
        data = await _client
            .from('news')
            .select('''
              *,
              news_categories(name, slug, color, icon),
              institutions(name, slug, logo_url, is_verified)
            ''')
            .eq('is_published', true)
            .eq('is_breaking', true)
            .order('published_at', ascending: false)
            .range(offset, offset + limit - 1);
      } else if (categoryId != null) {
        data = await _client
            .from('news')
            .select('''
              *,
              news_categories(name, slug, color, icon),
              institutions(name, slug, logo_url, is_verified)
            ''')
            .eq('is_published', true)
            .eq('category_id', categoryId)
            .order('published_at', ascending: false)
            .range(offset, offset + limit - 1);
      } else {
        data = await _client
            .from('news')
            .select('''
              *,
              news_categories(name, slug, color, icon),
              institutions(name, slug, logo_url, is_verified)
            ''')
            .eq('is_published', true)
            .order('published_at', ascending: false)
            .range(offset, offset + limit - 1);
      }

      return data.map((e) => NewsModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Haber listeleme hatası: $e');
      return [];
    }
  }

  /// Tek bir haber getir
  Future<NewsModel?> getNewsById(String id) async {
    try {
      final userId = _client.auth.currentUser?.id;

      final response = await _client
          .from('news')
          .select('''
            *,
            news_categories(name, slug, color, icon),
            institutions(name, slug, logo_url, is_verified),
            news_images(*)
          ''')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;

      final data = Map<String, dynamic>.from(response);

      // Kullanıcının beğeni durumunu kontrol et
      if (userId != null) {
        final likeResponse = await _client
            .from('news_likes')
            .select()
            .eq('news_id', id)
            .eq('user_id', userId)
            .maybeSingle();

        data['is_liked_by_user'] = likeResponse != null;
      }

      return NewsModel.fromJson(data);
    } catch (e) {
      debugPrint('Haber getirme hatası: $e');
      return null;
    }
  }

  /// Slug ile haber getir
  Future<NewsModel?> getNewsBySlug(String slug) async {
    try {
      final userId = _client.auth.currentUser?.id;

      final response = await _client
          .from('news')
          .select('''
            *,
            news_categories(name, slug, color, icon),
            institutions(name, slug, logo_url, is_verified),
            news_images(*)
          ''')
          .eq('slug', slug)
          .eq('is_published', true)
          .maybeSingle();

      if (response == null) return null;

      final data = Map<String, dynamic>.from(response);

      if (userId != null) {
        final likeResponse = await _client
            .from('news_likes')
            .select()
            .eq('news_id', data['id'])
            .eq('user_id', userId)
            .maybeSingle();

        data['is_liked_by_user'] = likeResponse != null;
      }

      return NewsModel.fromJson(data);
    } catch (e) {
      debugPrint('Haber getirme hatası: $e');
      return null;
    }
  }

  /// Kullanıcının haberlerini getir (haber rolü için)
  Future<List<NewsModel>> getMyNews({int limit = 20, int offset = 0}) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final data = await _client
          .from('news')
          .select('''
            *,
            news_categories(name, slug, color, icon),
            institutions(name, slug, logo_url, is_verified)
          ''')
          .eq('author_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (data).map((e) => NewsModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Kullanıcı haberleri getirme hatası: $e');
      return [];
    }
  }

  // ============================================
  // HABER OLUŞTURMA
  // ============================================

  /// Yeni haber oluştur
  Future<NewsModel?> createNews({
    required String title,
    required String content,
    String? summary,
    String? thumbnailUrl,
    String? videoUrl,
    String? categoryId,
    String? institutionId,
    bool isFeatured = false,
    bool isPublished = false,
    bool isBreaking = false,
    String? locationName,
    double? latitude,
    double? longitude,
    DateTime? publishedAt,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      // Slug oluştur
      final slug = _generateSlug(title);

      // Kullanıcı bilgilerini al
      final profile = await _client
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      // Önce insert yap
      final insertResponse = await _client
          .from('news')
          .insert({
            'title': title,
            'slug': slug,
            'content': content,
            'summary': summary,
            'thumbnail_url': thumbnailUrl,
            'video_url': videoUrl,
            'category_id': categoryId,
            'institution_id': institutionId,
            'author_id': user.id,
            'author_name': profile?['full_name'] ?? user.email,
            'author_avatar_url': profile?['avatar_url'],
            'is_featured': isFeatured,
            'is_published': isPublished,
            'is_breaking': isBreaking,
            'location_name': locationName,
            'latitude': latitude,
            'longitude': longitude,
            'published_at': publishedAt?.toIso8601String(),
          })
          .select('id')
          .single();

      final newsId = insertResponse['id'] as String;

      // Sonra joined data ile select yap
      final data = await _client
          .from('news')
          .select('''
            *,
            news_categories(name, slug, color, icon),
            institutions(name, slug, logo_url, is_verified)
          ''')
          .eq('id', newsId)
          .single();

      return NewsModel.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('Haber oluşturma hatası: $e');
      return null;
    }
  }

  /// Haber güncelle
  Future<bool> updateNews({
    required String id,
    String? title,
    String? content,
    String? summary,
    String? thumbnailUrl,
    String? videoUrl,
    String? categoryId,
    String? institutionId,
    bool? isFeatured,
    bool? isPublished,
    bool? isBreaking,
    String? locationName,
    double? latitude,
    double? longitude,
    DateTime? publishedAt,
    bool clearThumbnail = false,
    bool clearVideo = false,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (title != null) updateData['title'] = title;
      if (content != null) updateData['content'] = content;
      if (summary != null) updateData['summary'] = summary;
      if (clearThumbnail) {
        updateData['thumbnail_url'] = null;
      } else if (thumbnailUrl != null) {
        updateData['thumbnail_url'] = thumbnailUrl;
      }
      if (clearVideo) {
        updateData['video_url'] = null;
      } else if (videoUrl != null) {
        updateData['video_url'] = videoUrl;
      }
      if (categoryId != null) updateData['category_id'] = categoryId;
      if (institutionId != null) updateData['institution_id'] = institutionId;
      if (isFeatured != null) updateData['is_featured'] = isFeatured;
      if (isPublished != null) updateData['is_published'] = isPublished;
      if (isBreaking != null) updateData['is_breaking'] = isBreaking;
      if (locationName != null) updateData['location_name'] = locationName;
      if (latitude != null) updateData['latitude'] = latitude;
      if (longitude != null) updateData['longitude'] = longitude;
      if (publishedAt != null) {
        updateData['published_at'] = publishedAt.toIso8601String();
      }

      await _client.from('news').update(updateData).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Haber güncelleme hatası: $e');
      return false;
    }
  }

  /// Haber sil
  Future<bool> deleteNews(String id) async {
    try {
      await _client.from('news').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Haber silme hatası: $e');
      return false;
    }
  }

  // ============================================
  // GÖRSEL YÜKLEME
  // ============================================

  /// Haber görseli yükle
  Future<NewsImageModel?> uploadNewsImage({
    required String newsId,
    required File imageFile,
    String? caption,
    int sortOrder = 0,
  }) async {
    try {
      // Benzersiz dosya adı oluştur
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'news-images/$newsId-$timestamp.jpg';

      // Storage'a yükle
      final imageUrl = await _storageService.uploadFile(
        filePath: imageFile.path,
        bucket: 'news-images',
        path: path,
      );

      if (imageUrl == null) return null;

      // Veritabanına kaydet
      final data = await _client
          .from('news_images')
          .insert({
            'news_id': newsId,
            'image_url': imageUrl,
            'caption': caption,
            'sort_order': sortOrder,
          })
          .select()
          .single();

      return NewsImageModel.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('Haber görseli yükleme hatası: $e');
      return null;
    }
  }

  /// Web ve mobilde seçilen byte verisini haber galerisine yükler.
  Future<NewsImageModel?> uploadNewsImageBytes({
    required String newsId,
    required Uint8List bytes,
    required String extension,
    String? caption,
    int sortOrder = 0,
  }) async {
    try {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final normalizedExtension = extension.toLowerCase();
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;
      final path = '$userId/galleries/$newsId/$timestamp.$normalizedExtension';
      final imageUrl = await _storageService.uploadBytes(
        bytes: bytes,
        bucket: 'news-images',
        path: path,
        metadata: {'contentType': _imageContentType(normalizedExtension)},
      );
      if (imageUrl == null) return null;

      final data = await _client
          .from('news_images')
          .insert({
            'news_id': newsId,
            'image_url': imageUrl,
            'caption': caption,
            'sort_order': sortOrder,
            'file_size': bytes.length,
          })
          .select()
          .single();
      return NewsImageModel.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('Haber galeri görseli yükleme hatası: $e');
      return null;
    }
  }

  String _imageContentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// Birden fazla görsel yükle
  Future<List<NewsImageModel>> uploadMultipleImages({
    required String newsId,
    required List<File> imageFiles,
  }) async {
    final uploadedImages = <NewsImageModel>[];

    for (var i = 0; i < imageFiles.length; i++) {
      final image = await uploadNewsImage(
        newsId: newsId,
        imageFile: imageFiles[i],
        sortOrder: i,
      );
      if (image != null) {
        uploadedImages.add(image);
      }
    }

    return uploadedImages;
  }

  /// Haber görseli sil
  Future<bool> deleteNewsImage(String imageId) async {
    try {
      // Önce görsel URL'sini al
      final image = await _client
          .from('news_images')
          .select('image_url')
          .eq('id', imageId)
          .maybeSingle();

      if (image != null) {
        // Storage'dan sil
        await _deleteFromStorage(image['image_url'] as String);
      }

      // Veritabanından sil
      await _client.from('news_images').delete().eq('id', imageId);
      return true;
    } catch (e) {
      debugPrint('Haber görseli silme hatası: $e');
      return false;
    }
  }

  /// Storage'dan dosya sil
  Future<void> _deleteFromStorage(String url) async {
    try {
      // Hem Supabase hem de S3 URL'lerinde nesne yolu bu klasörden başlar.
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final newsImagesIndex = segments.indexOf('news-images');
      if (newsImagesIndex < 0 || newsImagesIndex == segments.length - 1) {
        debugPrint('Storage yolu çözümlenemedi: $url');
        return;
      }
      final path = segments.sublist(newsImagesIndex + 1).join('/');

      await _storageService.deleteFile(bucket: 'news-images', path: path);
    } catch (e) {
      debugPrint('Storage silme hatası: $e');
    }
  }

  // ============================================
  // BEĞENİ VE GÖRÜNTÜLEME
  // ============================================

  /// Haber beğeni toggle
  Future<bool> toggleLike(String newsId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint(
          '[NEWS_DIAG] toggleLike skipped: unauthenticated news=$newsId',
        );
        return false;
      }

      debugPrint('[NEWS_DIAG] toggleLike start news=$newsId actor=$userId');

      // Mevcut beğeni durumunu kontrol et
      final existing = await _client
          .from('news_likes')
          .select()
          .eq('news_id', newsId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // Beğeniyi kaldır
        await _client.from('news_likes').delete().eq('id', existing['id']);
        debugPrint(
          '[NEWS_DIAG] toggleLike success action=removed news=$newsId actor=$userId',
        );
        return false;
      } else {
        // Beğeni ekle
        await _client.from('news_likes').insert({
          'news_id': newsId,
          'user_id': userId,
        });
        debugPrint(
          '[NEWS_DIAG] toggleLike success action=inserted news=$newsId actor=$userId',
        );
        return true;
      }
    } catch (e) {
      debugPrint('[NEWS_DIAG] toggleLike failed news=$newsId error=$e');
      return false;
    }
  }

  /// Haber görüntüleme kaydet
  Future<void> recordView(String newsId) async {
    try {
      final userId = _client.auth.currentUser?.id;

      debugPrint(
        '[NEWS_DIAG] recordView start news=$newsId authenticated=${userId != null}',
      );

      await _client.from('news_views').insert({
        'news_id': newsId,
        'user_id': userId,
        'device_info': {'platform': Platform.operatingSystem},
      });
      debugPrint(
        '[NEWS_DIAG] recordView success news=$newsId viewer=${userId ?? 'anonymous'}',
      );
    } catch (e) {
      debugPrint('[NEWS_DIAG] recordView failed news=$newsId error=$e');
    }
  }

  /// Haber yazarı/admin için görüntüleyen, beğenen ve yorum yapanları getirir.
  Future<Map<String, List<Map<String, dynamic>>>> getEngagementDetails(
    String newsId,
  ) async {
    try {
      debugPrint('[NEWS_DIAG] getEngagementDetails start news=$newsId');
      final response = await _client.rpc(
        'get_news_engagement_details',
        params: {'p_news_id': newsId},
      );
      final data = Map<String, dynamic>.from(response as Map);

      List<Map<String, dynamic>> rows(String key) =>
          ((data[key] as List?) ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();

      final result = <String, List<Map<String, dynamic>>>{
        'viewers': rows('viewers'),
        'likes': rows('likes'),
        'comments': rows('comments'),
      };
      debugPrint(
        '[NEWS_DIAG] getEngagementDetails success news=$newsId '
        'viewers=${result['viewers']!.length} likes=${result['likes']!.length} '
        'comments=${result['comments']!.length}',
      );
      return result;
    } catch (e) {
      debugPrint(
        '[NEWS_DIAG] getEngagementDetails failed news=$newsId error=$e',
      );
      rethrow;
    }
  }

  // ============================================
  // YORUMLAR
  // ============================================

  /// Haber yorumlarını getir
  Future<List<NewsCommentModel>> getComments(String newsId) async {
    try {
      final userId = _client.auth.currentUser?.id;

      // Ana yorumları getir (parent_id null olanlar - yani üst yorumlar)
      final response = await _client
          .from('news_comments')
          .select()
          .eq('news_id', newsId)
          .eq('is_hidden', false)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      // Dart'ta parent_id == null olanları filtrele
      final data = (response as List)
          .where((c) => c['parent_id'] == null)
          .toList();

      // Kullanıcının beğeni durumlarını al
      final comments = <NewsCommentModel>[];
      for (final item in data) {
        final itemMap = Map<String, dynamic>.from(item);
        final isLiked = userId != null
            ? await _client
                      .from('news_comment_likes')
                      .select()
                      .eq('comment_id', item['id'])
                      .eq('user_id', userId)
                      .maybeSingle() !=
                  null
            : false;

        // Alt yorumları getir
        final replies = await _getReplies(item['id'] as String);

        itemMap['is_liked_by_user'] = isLiked;
        itemMap['replies'] = replies;

        comments.add(NewsCommentModel.fromJson(itemMap));
      }

      return comments;
    } catch (e) {
      debugPrint('Yorum getirme hatası: $e');
      return [];
    }
  }

  /// Alt yorumları getir
  Future<List<NewsCommentModel>> _getReplies(String parentId) async {
    try {
      final response = await _client
          .from('news_comments')
          .select()
          .eq('parent_id', parentId)
          .order('created_at', ascending: true);

      final data = response as List;
      return data
          .map((e) => NewsCommentModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('Alt yorum getirme hatası: $e');
      return [];
    }
  }

  /// Yorum ekle
  Future<NewsCommentModel?> addComment({
    required String newsId,
    required String content,
    String? parentId,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        debugPrint(
          '[NEWS_DIAG] addComment skipped: unauthenticated news=$newsId',
        );
        return null;
      }

      debugPrint(
        '[NEWS_DIAG] addComment start news=$newsId actor=${user.id} parent=${parentId ?? 'root'}',
      );

      // Kullanıcı bilgilerini al
      final profile = await _client
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      final data = await _client
          .from('news_comments')
          .insert({
            'news_id': newsId,
            'parent_id': parentId,
            'user_id': user.id,
            'user_name': profile?['full_name'] ?? user.email,
            'user_avatar_url': profile?['avatar_url'],
            'content': content,
          })
          .select()
          .single();

      debugPrint(
        '[NEWS_DIAG] addComment success news=$newsId comment=${data['id']} parent=${parentId ?? 'root'}',
      );
      return NewsCommentModel.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint(
        '[NEWS_DIAG] addComment failed news=$newsId parent=${parentId ?? 'root'} error=$e',
      );
      return null;
    }
  }

  /// Yorum güncelle
  Future<bool> updateComment(String commentId, String content) async {
    try {
      await _client
          .from('news_comments')
          .update({'content': content, 'is_edited': true})
          .eq('id', commentId);
      return true;
    } catch (e) {
      debugPrint('Yorum güncelleme hatası: $e');
      return false;
    }
  }

  /// Yorum sil
  Future<bool> deleteComment(String commentId) async {
    try {
      await _client.from('news_comments').delete().eq('id', commentId);
      return true;
    } catch (e) {
      debugPrint('Yorum silme hatası: $e');
      return false;
    }
  }

  /// Yorum beğeni toggle
  Future<bool> toggleCommentLike(String commentId) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint(
          '[NEWS_DIAG] toggleCommentLike skipped: unauthenticated comment=$commentId',
        );
        return false;
      }

      debugPrint(
        '[NEWS_DIAG] toggleCommentLike start comment=$commentId actor=$userId',
      );

      final existing = await _client
          .from('news_comment_likes')
          .select()
          .eq('comment_id', commentId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        await _client
            .from('news_comment_likes')
            .delete()
            .eq('id', existing['id']);
        debugPrint(
          '[NEWS_DIAG] toggleCommentLike success action=removed comment=$commentId',
        );
        return false;
      } else {
        await _client.from('news_comment_likes').insert({
          'comment_id': commentId,
          'user_id': userId,
        });
        debugPrint(
          '[NEWS_DIAG] toggleCommentLike success action=inserted comment=$commentId',
        );
        return true;
      }
    } catch (e) {
      debugPrint(
        '[NEWS_DIAG] toggleCommentLike failed comment=$commentId error=$e',
      );
      return false;
    }
  }

  // ============================================
  // KATEGORİLER VE KURUMLAR
  // ============================================

  /// Kategorileri getir
  Future<List<NewsCategoryModel>> getCategories() async {
    try {
      final response = await _client
          .from('news_categories')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final data = response as List;
      return data
          .map((e) => NewsCategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Kategori getirme hatası: $e');
      return [];
    }
  }

  /// Kurumları getir
  Future<List<InstitutionModel>> getInstitutions() async {
    try {
      final response = await _client
          .from('institutions')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true);

      final data = response as List;
      return data
          .map((e) => InstitutionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Kurum getirme hatası: $e');
      return [];
    }
  }

  // ============================================
  // YARDIMCI FONKSİYONLAR
  // ============================================

  /// Slug oluştur
  String _generateSlug(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[çÇ]'), 'c')
        .replaceAll(RegExp(r'[ğĞ]'), 'g')
        .replaceAll(RegExp(r'[ıİ]'), 'i')
        .replaceAll(RegExp(r'[öÖ]'), 'o')
        .replaceAll(RegExp(r'[şŞ]'), 's')
        .replaceAll(RegExp(r'[üÜ]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();

    // Benzersiz slug için timestamp ekle
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$slug-$timestamp';
  }

  /// Haberleri ara
  Future<List<NewsModel>> searchNews(String query, {int limit = 20}) async {
    try {
      final response = await _client
          .from('news')
          .select('''
            *,
            news_categories(name, slug, color, icon),
            institutions(name, slug, logo_url, is_verified)
          ''')
          .eq('is_published', true)
          .or('title.ilike.%$query%,content.ilike.%$query%')
          .order('published_at', ascending: false)
          .limit(limit);

      final data = response as List;
      return data
          .map((e) => NewsModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Haber arama hatası: $e');
      return [];
    }
  }

  /// Son haberleri getir (belirli sayıda)
  Future<List<NewsModel>> getLatestNews({int limit = 10}) async {
    return getPublishedNews(limit: limit);
  }

  /// Öne çıkan haberleri getir
  Future<List<NewsModel>> getFeaturedNews({int limit = 5}) async {
    return getPublishedNews(limit: limit, featuredOnly: true);
  }

  /// Son dakika haberlerini getir
  Future<List<NewsModel>> getBreakingNews({int limit = 5}) async {
    return getPublishedNews(limit: limit, breakingOnly: true);
  }

  /// Admin: Tüm haberleri getir (yayınlanmış ve yayınlanmamış)
  Future<List<NewsModel>> getAllNewsForAdmin({
    int limit = 50,
    int offset = 0,
    String? searchQuery,
    String? categoryId,
    bool? isPublished,
  }) async {
    try {
      List<Map<String, dynamic>> data;

      if (searchQuery != null && searchQuery.isNotEmpty) {
        // Arama ile birlikte filtreleme
        if (categoryId != null && isPublished != null) {
          data = await _client
              .from('news')
              .select('''
                *,
                news_categories(name, slug, color, icon),
                institutions(name, slug, logo_url, is_verified)
              ''')
              .or('title.ilike.%$searchQuery%,content.ilike.%$searchQuery%')
              .eq('category_id', categoryId)
              .eq('is_published', isPublished)
              .order('created_at', ascending: false)
              .range(offset, offset + limit - 1);
        } else if (categoryId != null) {
          data = await _client
              .from('news')
              .select('''
                *,
                news_categories(name, slug, color, icon),
                institutions(name, slug, logo_url, is_verified)
              ''')
              .or('title.ilike.%$searchQuery%,content.ilike.%$searchQuery%')
              .eq('category_id', categoryId)
              .order('created_at', ascending: false)
              .range(offset, offset + limit - 1);
        } else if (isPublished != null) {
          data = await _client
              .from('news')
              .select('''
                *,
                news_categories(name, slug, color, icon),
                institutions(name, slug, logo_url, is_verified)
              ''')
              .or('title.ilike.%$searchQuery%,content.ilike.%$searchQuery%')
              .eq('is_published', isPublished)
              .order('created_at', ascending: false)
              .range(offset, offset + limit - 1);
        } else {
          data = await _client
              .from('news')
              .select('''
                *,
                news_categories(name, slug, color, icon),
                institutions(name, slug, logo_url, is_verified)
              ''')
              .or('title.ilike.%$searchQuery%,content.ilike.%$searchQuery%')
              .order('created_at', ascending: false)
              .range(offset, offset + limit - 1);
        }
      } else if (categoryId != null && isPublished != null) {
        data = await _client
            .from('news')
            .select('''
              *,
              news_categories(name, slug, color, icon),
              institutions(name, slug, logo_url, is_verified)
            ''')
            .eq('category_id', categoryId)
            .eq('is_published', isPublished)
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
      } else if (categoryId != null) {
        data = await _client
            .from('news')
            .select('''
              *,
              news_categories(name, slug, color, icon),
              institutions(name, slug, logo_url, is_verified)
            ''')
            .eq('category_id', categoryId)
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
      } else if (isPublished != null) {
        data = await _client
            .from('news')
            .select('''
              *,
              news_categories(name, slug, color, icon),
              institutions(name, slug, logo_url, is_verified)
            ''')
            .eq('is_published', isPublished)
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
      } else {
        data = await _client
            .from('news')
            .select('''
              *,
              news_categories(name, slug, color, icon),
              institutions(name, slug, logo_url, is_verified)
            ''')
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
      }

      return data.map((e) => NewsModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Admin haber listesi hatası: $e');
      return [];
    }
  }

  /// Admin: İstatistikleri getir
  Future<Map<String, int>> getNewsStats() async {
    try {
      final totalResponse = await _client.from('news').select('id').count();
      final publishedResponse = await _client
          .from('news')
          .select('id')
          .eq('is_published', true)
          .count();
      final draftResponse = await _client
          .from('news')
          .select('id')
          .eq('is_published', false)
          .count();
      final featuredResponse = await _client
          .from('news')
          .select('id')
          .eq('is_featured', true)
          .count();
      final breakingResponse = await _client
          .from('news')
          .select('id')
          .eq('is_breaking', true)
          .count();

      return {
        'total': totalResponse.count,
        'published': publishedResponse.count,
        'draft': draftResponse.count,
        'featured': featuredResponse.count,
        'breaking': breakingResponse.count,
      };
    } catch (e) {
      debugPrint('İstatistik getirme hatası: $e');
      return {
        'total': 0,
        'published': 0,
        'draft': 0,
        'featured': 0,
        'breaking': 0,
      };
    }
  }
}
