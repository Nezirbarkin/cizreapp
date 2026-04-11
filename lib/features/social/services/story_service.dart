import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import '../../../core/models/post_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/image_compression_helper.dart';

class StoryService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  // Tüm aktif hikayeleri getir (son 24 saat) - kullanıcının görüntüleme durumunu ve profil bilgilerini dahil eder
  Future<List<Story>> getStories() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final now = DateTime.now().toUtc();
      debugPrint('📱 getStories() çağrıldı - şu an: ${now.toIso8601String()}');
      
      // Kullanıcının görüntülediği story'leri getir (retry ile)
      List<String> viewedStoryIds = [];
      List<String> likedStoryIds = [];
      if (userId != null) {
        try {
          final viewedResponse = await _supabase
              .from('story_views')
              .select('story_id')
              .eq('viewer_id', userId);
          viewedStoryIds = (viewedResponse as List)
              .map((row) => row['story_id'] as String)
              .toList();
          debugPrint('📱 Kullanıcı ${viewedStoryIds.length} story görüntülemiş');
        } catch (e) {
          debugPrint('⚠️ Story views yüklenirken hata (yoksayıldı): $e');
        }
        
        // Kullanıcının beğendiği story'leri getir (retry ile)
        try {
          final likedResponse = await _supabase
              .from('story_likes')
              .select('story_id')
              .eq('user_id', userId);
          likedStoryIds = (likedResponse as List)
              .map((row) => row['story_id'] as String)
              .toList();
          debugPrint('📱 Kullanıcı ${likedStoryIds.length} story beğenmiş');
        } catch (e) {
          debugPrint('⚠️ Story likes yüklenirken hata (yoksayıldı): $e');
        }
      }
      
      // Stories ile birlikte profil bilgilerini de çek (TEK SORGU) - retry ile
      List? response;
      int retryCount = 0;
      while (retryCount < 2) {
        try {
          response = await _supabase
              .from('stories')
              .select('*, profiles!stories_user_id_fkey(username, full_name, avatar_url)')
              .gt('expires_at', now.toIso8601String())
              .order('is_pinned', ascending: false)
              .order('created_at', ascending: false);
          break; // Başarılı olursa döngüden çık
        } catch (e) {
          retryCount++;
          if (retryCount >= 2) {
            debugPrint('❌ Stories yüklenirken hata (2 deneme sonra başarısız): $e');
            throw Exception('Hikayeler yüklenirken hata: $e');
          }
          debugPrint('⚠️ Stories yüklenirken hata, tekrar deneniyor ($retryCount/2): $e');
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
      
      if (response == null) {
        throw Exception('Hikayeler yüklenemedi');
      }

      debugPrint('📱 getStories() - ${response.length} adet story bulundu');

      final stories = response.map((json) {
        final storyId = json['id'] as String;
        final isViewed = viewedStoryIds.contains(storyId);
        final isLiked = likedStoryIds.contains(storyId);
        json['is_viewed_by_current_user'] = isViewed;
        json['is_liked_by_current_user'] = isLiked;
        
        // Profil bilgilerini doğrudan story json'ına ekle
        final profiles = json['profiles'] as Map<String, dynamic>?;
        if (profiles != null) {
          json['username'] = profiles['username'];
          json['full_name'] = profiles['full_name'];
          json['avatar_url'] = profiles['avatar_url'];
        }
        
        return Story.fromJson(json);
      }).toList();

      // Sıralama önceliği:
      // 1. Sabitlenenler (is_pinned = true) her zaman en başta
      // 2. İzlenmeyen story'ler önce, izlenenler sonra
      // 3. Her grup içinde created_at desc (yeniden eskiye)
      stories.sort((a, b) {
        // 1. Önce pin durumuna göre sırala - SABİTLENEN HER ZAMAN BAŞTA
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1; // true (pinned) önce, false sonra
        }
        
        // 2. Pin durumu aynıysa, görüntüleme durumuna göre sırala
        if (a.isViewedByCurrentUser != b.isViewedByCurrentUser) {
          return a.isViewedByCurrentUser ? 1 : -1; // false (izlenmemiş) önce, true (izlenmiş) sonra
        }
        
        // 3. Her ikisi de aynı pin/view durumunda ise created_at desc (yeniden eskiye)
        return b.createdAt.compareTo(a.createdAt);
      });

      final pinnedCount = stories.where((s) => s.isPinned).length;
      final unwatchedCount = stories.where((s) => !s.isViewedByCurrentUser && !s.isPinned).length;
      final watchedCount = stories.where((s) => s.isViewedByCurrentUser && !s.isPinned).length;
      debugPrint('📱 Story sıralama tamamlandı - Sabitlenmiş: $pinnedCount, İzlenmeyen: $unwatchedCount, İzlenen: $watchedCount');

      return stories;
    } catch (e) {
      debugPrint('❌ getStories() HATA: $e');
      
      // Kullanıcı dostu hata mesajı
      String userMessage = 'Hikayeler yüklenirken bir hata oluştu';
      
      if (e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
        userMessage = 'İnternet bağlantınızı kontrol edin';
      } else if (e.toString().contains('TimeoutException')) {
        userMessage = 'Bağlantı zaman aşımı. Lütfen tekrar deneyin';
      }
      
      throw Exception(userMessage);
    }
  }

  // Kullanıcının hikayelerini getir
  Future<List<Story>> getUserStories(String userId) async {
    try {
      final now = DateTime.now().toUtc();
      debugPrint('📱 getUserStories($userId) çağrıldı');
      
      final response = await _supabase
          .from('stories')
          .select()
          .eq('user_id', userId)
          .gt('expires_at', now.toIso8601String())
          .order('created_at', ascending: false);

      debugPrint('📱 getUserStories() - ${response.length} adet story bulundu');

      return (response as List).map((json) => Story.fromJson(json)).toList();
    } catch (e) {
      debugPrint('❌ getUserStories() HATA: $e');
      throw Exception('Kullanıcı hikayeleri yüklenirken hata: $e');
    }
  }

  // Story image yükle (ORİJİNAL ASPECT RATIO KORUNARAK YÜKSEK KALİTE)
  // Web ve Mobile uyumlu
  Future<String?> uploadStoryImage({
    required String imagePath,
    XFile? xFile,
  }) async {
    try {
      debugPrint('🖼️ Story image yükleniyor...');
      
      Uint8List imageBytes;
      String fileExtension;
      
      if (kIsWeb && xFile != null) {
        // Web platformu - XFile kullan
        debugPrint('📱 Web platform - XFile kullanılıyor');
        
        // Sıkıştır
        final compressedBytes = await ImageCompressionHelper.compressXFile(
          xFile: xFile,
          quality: 92,
          maxWidth: 1080,
          maxHeight: 1920,
        );
        
        imageBytes = compressedBytes ?? await xFile.readAsBytes();
        fileExtension = path.extension(xFile.name).replaceFirst('.', '');
        
        debugPrint('📏 Yüklenecek boyut: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      } else {
        // Mobile platformu - XFile kullan (dart:io bağımlılığı yok)
        debugPrint('📱 Mobile platform - XFile kullanılıyor');
        
        final mobileXFile = xFile ?? XFile(imagePath);
        
        // XFile üzerinden sıkıştır
        final compressedBytes = await ImageCompressionHelper.compressXFile(
          xFile: mobileXFile,
          quality: 92,
          maxWidth: 1080,
          maxHeight: 1920,
        );
        
        imageBytes = compressedBytes ?? await mobileXFile.readAsBytes();
        fileExtension = path.extension(mobileXFile.name.isNotEmpty ? mobileXFile.name : imagePath).replaceFirst('.', '');
        
        debugPrint('📏 Yüklenecek boyut: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      }
      
      final fileName = 'story_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = 'stories/$fileName';
      
      await _supabase.storage.from('stories').uploadBinary(
        filePath,
        imageBytes,
        fileOptions: FileOptions(
          contentType: 'image/$fileExtension',
          upsert: false,
        ),
      );
      
      final imageUrl = _supabase.storage.from('stories').getPublicUrl(filePath);
      debugPrint('✅ Story image yüklendi: $imageUrl');
      
      return imageUrl;
    } catch (e) {
      debugPrint('❌ Story image yükleme hatası: $e');
      return null;
    }
  }

  // Video'dan thumbnail oluştur
  Future<String?> generateVideoThumbnail(String videoPath) async {
    try {
      debugPrint('📹 Video thumbnail oluşturuluyor: $videoPath');
      
      final uint8list = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 75,
      );
      
      if (uint8list == null) {
        debugPrint('❌ Thumbnail oluşturulamadı');
        return null;
      }
      
      // Thumbnail'ı Storage'a yükle
      final fileName = 'thumbnail_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = 'stories/thumbnails/$fileName';
      
      await _supabase.storage.from('stories').uploadBinary(
        filePath,
        uint8list,
      );
      
      final thumbnailUrl = _supabase.storage.from('stories').getPublicUrl(filePath);
      debugPrint('✅ Thumbnail yüklendi: $thumbnailUrl');
      
      return thumbnailUrl;
    } catch (e) {
      debugPrint('❌ Video thumbnail oluşturma hatası: $e');
      return null;
    }
  }

  // Hikaye oluştur (thumbnail desteği ile)
  Future<Story?> createStory({
    required String userId,
    required String imageUrl,
    String mediaType = 'image',
    String? thumbnailUrl,
    bool isPinned = false,
  }) async {
    try {
      final now = DateTime.now().toUtc(); // UTC'ye çevir
      final expiresAt = now.add(const Duration(hours: 24));

      debugPrint('Story oluşturuluyor - userId: $userId');
      debugPrint('Story oluşturuluyor - mediaType: $mediaType');
      debugPrint('Story oluşturuluyor - thumbnailUrl: $thumbnailUrl');
      debugPrint('Story oluşturuluyor - isPinned: $isPinned');
      debugPrint('Story oluşturuluyor - created_at: ${now.toIso8601String()}');
      debugPrint('Story oluşturuluyor - expires_at: ${expiresAt.toIso8601String()}');

      final insertData = {
        'user_id': userId,
        'image_url': imageUrl,
        'media_type': mediaType,
        'views_count': 0,
        'is_pinned': isPinned,
        'created_at': now.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };
      
      // Video ise thumbnail URL'ini ekle
      if (mediaType == 'video' && thumbnailUrl != null) {
        insertData['thumbnail_url'] = thumbnailUrl;
      }

      final response = await _supabase.from('stories').insert(insertData).select().maybeSingle();

      if (response == null) return null;

      debugPrint('Story başarıyla oluşturuldu: ${response['id']}');

      return Story.fromJson(response);
    } catch (e) {
      debugPrint('Story oluşturma HATASI: $e');
      throw Exception('Hikaye oluşturulurken hata: $e');
    }
  }

  // Videoyu yükle ve thumbnail oluştur (tüm işlem bir arada)
  // Hem video URL'sini hem thumbnail URL'sini döndürür
  // Web ve Mobile uyumlu
  // onProgress: Upload progress callback (0.0 - 1.0)
  Future<Map<String, String>?> uploadVideoWithThumbnail({
    required String videoPath,
    XFile? xFile,
    Function(double)? onProgress,
  }) async {
    try {
      debugPrint('📹 Video yükleniyor ve thumbnail oluşturuluyor...');
      
      Uint8List videoBytes;
      String fileExtension;
      
      // 1. Thumbnail oluştur (ilerleme: %0-%30)
      if (onProgress != null) onProgress(0.10);
      
      String? thumbnailUrl;
      if (!kIsWeb) {
        // Sadece mobile'da thumbnail oluştur (video_thumbnail web'de çalışmaz)
        thumbnailUrl = await generateVideoThumbnail(videoPath);
        if (thumbnailUrl == null) {
          debugPrint('⚠️ Thumbnail oluşturulamadı');
        } else {
          debugPrint('✅ Thumbnail oluşturuldu: $thumbnailUrl');
        }
      } else {
        debugPrint('⚠️ Web platformunda thumbnail oluşturma desteklenmiyor');
      }
      if (onProgress != null) onProgress(0.30);
      
      // 2. Videoyu yükle (ilerleme: %30-%100)
      if (kIsWeb && xFile != null) {
        // Web platformu
        videoBytes = await xFile.readAsBytes();
        fileExtension = path.extension(xFile.name).replaceFirst('.', '');
      } else {
        // Mobile platformu - XFile kullan (dart:io bağımlılığı yok)
        final mobileXFile = xFile ?? XFile(videoPath);
        videoBytes = await mobileXFile.readAsBytes();
        fileExtension = path.extension(mobileXFile.name.isNotEmpty ? mobileXFile.name : videoPath).replaceFirst('.', '');
      }
      
      debugPrint('📹 Video boyutu: ${(videoBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = 'stories/$fileName';
      
      if (onProgress != null) onProgress(0.50);
      
      await _supabase.storage.from('stories').uploadBinary(
        filePath,
        videoBytes,
        fileOptions: FileOptions(
          contentType: 'video/$fileExtension',
          upsert: false,
        ),
      );
      
      if (onProgress != null) onProgress(0.90);
      
      final videoUrl = _supabase.storage.from('stories').getPublicUrl(filePath);
      debugPrint('✅ Video yüklendi: $videoUrl');
      
      if (onProgress != null) onProgress(1.0);
      
      // Her iki URL'yi de döndür
      return {
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl ?? '', // Thumbnail yoksa boş string
      };
    } catch (e) {
      debugPrint('❌ Video yükleme hatası: $e');
      return null;
    }
  }

  // Hikaye görüntüleme ekle
  Future<void> viewStory(String storyId, String viewerId) async {
    try {
      // Önce kontrol et, daha önce görüntülendi mi
      final existingView = await _supabase
          .from('story_views')
          .select()
          .eq('story_id', storyId)
          .eq('viewer_id', viewerId);

      if (existingView.isEmpty) {
        await _supabase.from('story_views').insert({
          'story_id': storyId,
          'viewer_id': viewerId,
        });
        debugPrint('📱 Story görüntüleme kaydı oluşturuldu: $storyId');
      }
    } catch (e) {
      debugPrint('❌ Story görüntüleme hatası: $e');
    }
  }

  // Hikaye görüntülenme sayısını getir
  Future<int> getViewsCount(String storyId) async {
    try {
      final response = await _supabase
          .from('story_views')
          .select('id')
          .eq('story_id', storyId);

      return response.length;
    } catch (e) {
      return 0;
    }
  }

  // Hikayeyi görüntüleyenlerin listesini getir (profil bilgileri ile birlikte)
  Future<List<Map<String, dynamic>>> getViewers(String storyId) async {
    try {
      debugPrint('📱 getViewers($storyId) çağrıldı');
      
      // 1. Önce story_views tablosundan viewer_id ve created_at bilgilerini al
      final viewsResponse = await _supabase
          .from('story_views')
          .select('viewer_id, created_at')
          .eq('story_id', storyId)
          .order('created_at', ascending: false);

      debugPrint('📱 getViewers() - ${viewsResponse.length} adet görüntüleyen bulundu');
      
      if (viewsResponse.isEmpty) {
        return [];
      }

      // 2. Tüm viewer_id'leri topla
      final viewerIds = (viewsResponse as List)
          .map((v) => v['viewer_id'] as String)
          .toSet()
          .toList();

      debugPrint('📱 Viewer IDs: $viewerIds');

      // 3. Bu kullanıcıların profillerini ayrı sorgu ile al
      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, full_name, username, avatar_url')
          .inFilter('id', viewerIds);

      debugPrint('📱 Profil sayısı: ${profilesResponse.length}');

      // 4. Profile'leri map'e koy (hızlı erişim için)
      final profilesMap = <String, Map<String, dynamic>>{};
      for (var profile in profilesResponse) {
        profilesMap[profile['id']] = profile;
      }

      // 5. View verileriyle profile'leri birleştir
      final result = <Map<String, dynamic>>[];
      for (var view in viewsResponse) {
        final viewerId = view['viewer_id'] as String;
        result.add({
          'viewer_id': viewerId,
          'created_at': view['created_at'],
          'profiles': profilesMap[viewerId],
        });
      }

      debugPrint('📱 Sonuç sayısı: ${result.length}');
      if (result.isNotEmpty) {
        debugPrint('📱 İlk görüntüleyen: ${result.first}');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Görüntüleyenler yüklenirken hata: $e');
      return [];
    }
  }

  // Kullanıcı hikayeyi görüntüledi mi kontrol et
  Future<bool> hasUserViewed(String storyId, String viewerId) async {
    try {
      final response = await _supabase
          .from('story_views')
          .select('id')
          .eq('story_id', storyId)
          .eq('viewer_id', viewerId);

      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Hikaye sil
  Future<void> deleteStory(String storyId) async {
    try {
      await _supabase.from('stories').delete().eq('id', storyId);
    } catch (e) {
      throw Exception('Hikaye silinirken hata: $e');
    }
  }

  // Süresi dolmuş hikayeleri temizle
  Future<void> deleteExpiredStories() async {
    try {
      await _supabase
          .from('stories')
          .delete()
          .lt('expires_at', DateTime.now().toIso8601String());
    } catch (e) {
      throw Exception('Süresi dolmuş hikayeler silinirken hata: $e');
    }
  }

  // Story beğen
  Future<void> likeStory(String storyId) async {
    try {
      debugPrint('🔔 STORY LİKE BAŞLADI - storyId: $storyId');
      
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Kullanıcı giriş yapmamış');
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Önce beğenilmiş mi kontrol et - retry ile
      dynamic existingLike;
      int retryCount = 0;
      while (retryCount < 2) {
        try {
          existingLike = await _supabase
              .from('story_likes')
              .select('id')
              .eq('story_id', storyId)
              .eq('user_id', userId)
              .maybeSingle();
          break;
        } catch (e) {
          retryCount++;
          if (retryCount >= 2) rethrow;
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      if (existingLike == null) {
        // Beğeni ekle
        await _supabase.from('story_likes').insert({
          'story_id': storyId,
          'user_id': userId,
        });

        // Beğeni sayısını artır
        await _supabase.rpc('increment_story_likes', params: {'story_id': storyId});
        debugPrint('❤️ Story beğenildi: $storyId');

        // Hikaye sahibine bildirim gönder
        await _createStoryLikeNotification(storyId, userId);
      }
    } catch (e) {
      debugPrint('❌ Story beğenme hatası: $e');
      throw Exception('Story beğenilirken hata: $e');
    }
  }

  // Hikaye beğeni bildirimi oluştur
  Future<void> _createStoryLikeNotification(String storyId, String actorId) async {
    try {
      debugPrint('🔔🔔🔔 STORY BEĞENİ BİLDİRİMİ BAŞLADI 🔔🔔🔔');
      debugPrint('📱 Story ID: $storyId');
      debugPrint('📱 Actor ID: $actorId');
      
      // Hikayeyi getir - retry ile
      dynamic storyResponse;
      int retryCount = 0;
      while (retryCount < 2) {
        try {
          storyResponse = await _supabase
              .from('stories')
              .select('user_id, image_url, thumbnail_url')
              .eq('id', storyId)
              .maybeSingle();
          break;
        } catch (e) {
          retryCount++;
          if (retryCount >= 2) {
            debugPrint('❌ Story getirme hatası: $e');
            return;
          }
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      if (storyResponse == null) {
        debugPrint('❌ Story bulunamadı');
        return;
      }
      final storyOwnerId = storyResponse['user_id'] as String;
      debugPrint('👤 Story Owner ID: $storyOwnerId');
      
      // Kendi hikayesine beğendiğinde bildirim verme
      if (storyOwnerId == actorId) {
        debugPrint('⚠️ Kendi hikayesini beğendi, bildirim gönderilmiyor');
        return;
      }

      // Hikaye sahibi ve beğenen kullanıcı bilgilerini getir - retry ile
      dynamic profilesResponse;
      retryCount = 0;
      while (retryCount < 2) {
        try {
          profilesResponse = await _supabase
              .from('profiles')
              .select('id, username, avatar_url')
              .inFilter('id', [storyOwnerId, actorId]);
          break;
        } catch (e) {
          retryCount++;
          if (retryCount >= 2) {
            debugPrint('❌ Profil getirme hatası: $e');
            return;
          }
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      Map<String, dynamic>? storyOwner;
      Map<String, dynamic>? actor;
      
      // ignore: unnecessary_type_check
      if (profilesResponse is List) {
        for (var p in profilesResponse) {
          if (p['id'] == storyOwnerId) storyOwner = p;
          if (p['id'] == actorId) actor = p;
        }
      }

      if (storyOwner == null || actor == null) {
        debugPrint('❌ Kullanıcı profilleri bulunamadı');
        return;
      }

      // Thumbnail veya image URL'ini kullan
      final storyImage = storyResponse['thumbnail_url'] ?? storyResponse['image_url'];
      final actorName = actor['username'] ?? 'Bir kullanıcı';
      
      debugPrint('📢 BİLDİRİM GÖNDERİLİYOR:');
      debugPrint('  - Alıcı: ${storyOwner['username']} ($storyOwnerId)');
      debugPrint('  - Gönderen: $actorName ($actorId)');
      debugPrint('  - Tip: like (story)');
      debugPrint('  - Title: $actorName hikayeni beğendi');

      // Story beğenisi için özel bildirim oluştur
      await _notificationService.createNotification(
        userId: storyOwner['id'],
        type: 'like',
        title: '$actorName hikayeni beğendi',
        content: 'Hikayeni beğendi',
        actorId: actor['id'],
        actorName: actorName,
        actorAvatar: actor['avatar_url'],
        entityId: storyId,
        entityImage: storyImage,
      );
      
      debugPrint('✅✅✅ STORY BEĞENİ BİLDİRİMİ GÖNDERİLDİ ✅✅✅');
    } catch (e) {
      // Bildirim hatası ana işlemi engellemesin
      debugPrint('❌❌❌ Story beğeni bildirim HATASI: $e');
    }
  }

  // Story beğenisini kaldır
  Future<void> unlikeStory(String storyId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Beğeniyi sil
      await _supabase
          .from('story_likes')
          .delete()
          .eq('story_id', storyId)
          .eq('user_id', userId);

      // Beğeni sayısını azalt
      await _supabase.rpc('decrement_story_likes', params: {'story_id': storyId});
      debugPrint('💔 Story beğenisi kaldırıldı: $storyId');
    } catch (e) {
      debugPrint('❌ Story beğeni kaldırma hatası: $e');
      throw Exception('Story beğenisi kaldırılırken hata: $e');
    }
  }

  // Story beğenisi toggle (beğenili değilse beğen, beğeniliyse kaldır)
  Future<bool> toggleStoryLike(String storyId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Mevcut beğeniyi kontrol et - retry ile
      dynamic existingLike;
      int retryCount = 0;
      while (retryCount < 2) {
        try {
          existingLike = await _supabase
              .from('story_likes')
              .select('id')
              .eq('story_id', storyId)
              .eq('user_id', userId)
              .maybeSingle();
          break;
        } catch (e) {
          retryCount++;
          if (retryCount >= 2) rethrow;
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      if (existingLike != null) {
        // Beğeni varsa kaldır
        await unlikeStory(storyId);
        return false;
      } else {
        // Beğeni yoksa ekle
        await likeStory(storyId);
        return true;
      }
    } catch (e) {
      debugPrint('❌ Story beğeni toggle hatası: $e');
      throw Exception('Story beğeni işleminde hata: $e');
    }
  }

  // Kullanıcının story'yi beğenip beğenmediğini kontrol et
  Future<bool> isStoryLiked(String storyId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      // Beğeni kontrolü - retry ile
      dynamic response;
      int retryCount = 0;
      while (retryCount < 2) {
        try {
          response = await _supabase
              .from('story_likes')
              .select('id')
              .eq('story_id', storyId)
              .eq('user_id', userId)
              .maybeSingle();
          break;
        } catch (e) {
          retryCount++;
          if (retryCount >= 2) {
            debugPrint('❌ Story beğeni kontrol hatası: $e');
            return false;
          }
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      return response != null;
    } catch (e) {
      debugPrint('❌ Story beğeni kontrol hatası: $e');
      return false;
    }
  }

  // Story'yi sabitle/sabitleme kaldır (toggle)
  Future<bool> togglePinStory(String storyId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Mevcut story'yi al - retry ile
      dynamic storyResponse;
      int retryCount = 0;
      while (retryCount < 2) {
        try {
          storyResponse = await _supabase
              .from('stories')
              .select('is_pinned, user_id')
              .eq('id', storyId)
              .maybeSingle();
          break;
        } catch (e) {
          retryCount++;
          if (retryCount >= 2) rethrow;
          await Future.delayed(Duration(milliseconds: 300));
        }
      }

      if (storyResponse == null) {
        throw Exception('Story bulunamadı');
      }

      // Story'nin sahibi mi kontrol et
      if (storyResponse['user_id'] != userId) {
        throw Exception('Bu story size ait değil');
      }

      final currentPinStatus = storyResponse['is_pinned'] as bool? ?? false;
      final newPinStatus = !currentPinStatus;

      // Pin durumunu güncelle
      await _supabase
          .from('stories')
          .update({'is_pinned': newPinStatus})
          .eq('id', storyId);

      debugPrint('📌 Story ${newPinStatus ? "sabitlendi" : "sabitleme kaldırıldı"}: $storyId');
      return newPinStatus;
    } catch (e) {
      debugPrint('❌ Story sabitleme hatası: $e');
      throw Exception('Story sabitleme işleminde hata: $e');
    }
  }
}
