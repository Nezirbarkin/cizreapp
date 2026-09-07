import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import '../../../core/models/post_model.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/image_compression_helper.dart';

class StoryService {
  /// Klasik begeni tepkisi. story_likes.emoji sutununun DB varsayilani da ayni.
  static const String defaultReaction = '\u2764\uFE0F';

  /// Hikaye ekranindaki hizli tepki cubugunda gosterilen emojiler.
  static const List<String> quickReactions = <String>[
    '\u2764\uFE0F',
    '\u{1F602}',
    '\u{1F62E}',
    '\u{1F622}',
    '\u{1F44F}',
    '\u{1F525}',
  ];

  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }
  final StorageService _storageService = StorageService();

  // Tüm aktif hikayeleri getir (son 24 saat) - kullanıcının görüntüleme durumunu ve profil bilgilerini dahil eder
  Future<List<Story>> getStories() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final now = DateTime.now().toUtc();
      debugPrint('📱 getStories() çağrıldı - şu an: ${now.toIso8601String()}');
      
      // ⚡ AÇILIŞ OPTİMİZASYONU (2026-08-14): Görüntüleme/beğeni listeleri ile
      // aktif stories sorgusu birbirinden bağımsız. Eskiden 3 gidiş-dönüş
      // sırayla bekleniyordu (3× RTT); şimdi üçü paralel (≈ 1× RTT).
      // Sorguların kendisi ve filtreleri DEĞİŞMEDİ.
      final viewsFuture = userId == null
          ? Future.value(<String>[])
          : _supabase
              .from('story_views')
              .select('story_id')
              .eq('viewer_id', userId)
              .then((r) {
                final ids = (r as List)
                    .map((row) => row['story_id'] as String)
                    .toList();
                debugPrint('📱 Kullanıcı ${ids.length} story görüntülemiş');
                return ids;
              })
              .catchError((e) {
                debugPrint('⚠️ Story views yüklenirken hata (yoksayıldı): $e');
                return <String>[];
              });
      // Beğeni + tepki emojisi (story_id -> emoji) tek sorguda gelir.
      final likesFuture = userId == null
          ? Future.value(<String, String>{})
          : _supabase
              .from('story_likes')
              .select('story_id, emoji')
              .eq('user_id', userId)
              .then((r) {
                final map = <String, String>{};
                for (final row in (r as List)) {
                  final sid = row['story_id'] as String?;
                  if (sid == null) continue;
                  final emoji = row['emoji'] as String?;
                  map[sid] = (emoji == null || emoji.isEmpty)
                      ? defaultReaction
                      : emoji;
                }
                debugPrint('📱 Kullanıcı ${map.length} story beğenmiş');
                return map;
              })
              .catchError((e) {
                debugPrint('⚠️ Story likes yüklenirken hata (yoksayıldı): $e');
                return <String, String>{};
              });

      // Stories ile birlikte profil bilgilerini de çek (TEK SORGU) - retry ile
      Future<List?> fetchStories() async {
        int retryCount = 0;
        while (retryCount < 2) {
          try {
            debugPrint('📱 Sorgulanıyor: admin_pinned desc, is_pinned desc, created_at desc, expires_at > ${now.toIso8601String()}');
            return await _supabase
                .from('stories')
                .select('*, profiles!stories_user_id_fkey(username, full_name, avatar_url)')
                .gt('expires_at', now.toIso8601String())
                .order('admin_pinned', ascending: false, nullsFirst: false)
                .order('is_pinned', ascending: false, nullsFirst: false)
                .order('created_at', ascending: false);
          } catch (e) {
            retryCount++;
            if (retryCount >= 2) {
              debugPrint('❌ Stories yüklenirken hata (2 deneme sonra başarısız): $e');
              throw Exception('Hikayeler yüklenirken hata: $e');
            }
            debugPrint('⚠️ Stories yüklenirken hata, tekrar deneniyor ($retryCount/2): $e');
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        // Buraya normalde ulaşılamaz (retryCount >= 2 üstte fırlatıyor);
        // analiz memnuniyeti için koruyucu hata.
        throw Exception('Hikayeler yüklenemedi');
      }

      final results = await Future.wait([
        viewsFuture,
        likesFuture,
        fetchStories(),
      ]);
      final viewedStoryIds = results[0] as List<String>;
      final myReactions = results[1] as Map<String, String>;
      final response = results[2] as List?;

      if (response == null) {
        throw Exception('Hikayeler yüklenemedi');
      }

      debugPrint('📱 getStories() - ${response.length} adet story bulundu');

      // İlk 5 hikayenin sabitleme durumunu logla
      for (int i = 0; i < 5 && i < response.length; i++) {
        final s = response[i];
        debugPrint('📱  Hikayeler[$i]: id=${s['id']}, is_pinned=${s['is_pinned']}, admin_pinned=${s['admin_pinned']}');
      }

      final stories = response.map((json) {
        final storyId = json['id'] as String;
        final isViewed = viewedStoryIds.contains(storyId);
        final myReaction = myReactions[storyId];
        json['is_viewed_by_current_user'] = isViewed;
        json['is_liked_by_current_user'] = myReaction != null;
        json['my_reaction'] = myReaction;
        
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
      // 1. Admin sabitlenenler (adminPinned = true) her zaman en başta
      // 2. Kullanıcı sabitlenenler (isPinned = true) ikinci sıra
      // 3. İzlenmeyen story'ler önce, izlenenler sonra
      // 4. Her grup içinde created_at desc (yeniden eskiye)
      stories.sort((a, b) {
        // 1. Önce adminPinned durumuna göre sırala - ADMIN SABİTLENEN HER ZAMAN BAŞTA
        if (a.adminPinned != b.adminPinned) {
          return a.adminPinned ? -1 : 1;
        }
        // 2. Sonra isPinned durumuna göre sırala
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        
        // 2. Pin durumu aynıysa, görüntüleme durumuna göre sırala
        if (a.isViewedByCurrentUser != b.isViewedByCurrentUser) {
          return a.isViewedByCurrentUser ? 1 : -1;
        }
        
        // 3. Her ikisi de aynı pin/view durumunda ise created_at desc (yeniden eskiye)
        return b.createdAt.compareTo(a.createdAt);
      });

      final adminPinnedCount = stories.where((s) => s.adminPinned).length;
      final userPinnedCount = stories.where((s) => !s.adminPinned && s.isPinned).length;
      final unwatchedCount = stories.where((s) => !s.isViewedByCurrentUser && !s.isPinned && !s.adminPinned).length;
      final watchedCount = stories.where((s) => s.isViewedByCurrentUser && !s.isPinned && !s.adminPinned).length;
      debugPrint('📱 Story sıralama - Admin Sabitlenmiş: $adminPinnedCount, Kullanıcı Sabitlenmiş: $userPinnedCount, İzlenmeyen: $unwatchedCount, İzlenen: $watchedCount');

      return stories;
    } catch (e) {
      debugPrint('❌ getStories() HATA: $e');
      // Hataları merkezi işleyiciden geçir: ağ hatası → "İnternet bağlantınızı
      // kontrol edin", vs. FriendlyException.toString() sadece temiz mesajı döndürür.
      throw FriendlyException.from(e);
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
      throw FriendlyException.from(e);
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
      
      final imageUrl = await _storageService.uploadBytes(
        bucket: 'stories',
        path: filePath,
        bytes: imageBytes,
        metadata: {'Content-Type': 'image/$fileExtension'},
      );

      if (imageUrl == null) return null;
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
      
      final thumbnailUrl = await _storageService.uploadBytes(
        bucket: 'stories',
        path: filePath,
        bytes: uint8list,
        metadata: const {'Content-Type': 'image/jpeg'},
      );

      if (thumbnailUrl == null) return null;
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
      
      final videoUrl = await _storageService.uploadBytes(
        bucket: 'stories',
        path: filePath,
        bytes: videoBytes,
        metadata: {'Content-Type': 'video/$fileExtension'},
      );

      if (videoUrl == null) return null;
      if (onProgress != null) onProgress(0.90);
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

      // 3. Profilleri ve bu hikayeye verilen tepkileri paralel çek
      final extras = await Future.wait([
        _supabase
            .from('profiles')
            .select('id, full_name, username, avatar_url')
            .inFilter('id', viewerIds),
        _supabase
            .from('story_likes')
            .select('user_id, emoji')
            .eq('story_id', storyId)
            .catchError((e) {
              debugPrint('⚠️ Story tepkileri yüklenemedi (yoksayıldı): $e');
              return <Map<String, dynamic>>[];
            }),
      ]);

      final profilesResponse = extras[0] as List;
      final reactionsResponse = extras[1] as List;

      debugPrint('📱 Profil sayısı: ${profilesResponse.length}');

      // 4. Profile'leri map'e koy (hızlı erişim için)
      final profilesMap = <String, Map<String, dynamic>>{};
      for (var profile in profilesResponse) {
        profilesMap[profile['id']] = profile;
      }

      // 4b. Tepkileri map'e koy (viewer_id -> emoji)
      final reactionsMap = <String, String>{};
      for (var row in reactionsResponse) {
        final uid = row['user_id'] as String?;
        if (uid == null) continue;
        final emoji = row['emoji'] as String?;
        reactionsMap[uid] = (emoji == null || emoji.isEmpty)
            ? defaultReaction
            : emoji;
      }

      // 5. View verileriyle profile'leri birleştir
      final result = <Map<String, dynamic>>[];
      for (var view in viewsResponse) {
        final viewerId = view['viewer_id'] as String;
        result.add({
          'viewer_id': viewerId,
          'created_at': view['created_at'],
          'profiles': profilesMap[viewerId],
          'reaction': reactionsMap[viewerId],
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
  // NOT: stories.likes_count senkronizasyonu PostgreSQL trigger'ı
  // (increment_story_likes_count) tarafından otomatik yapılır.
  // Burada RPC çağırmak çift sayıma yol açar.
  /// Hikayeye tepki ver (klasik begeni = kalp emojisi).
  ///
  /// NOT (2026-09-06): Bildirim ARTIK Dart'tan gonderilmiyor. DB'deki
  /// notify_story_like_trigger zaten hikaye sahibine bildirim yaziyor;
  /// Dart tarafindaki _createStoryLikeNotification ikinci bir bildirim
  /// uretme riski tasiyordu. Sayac da trigger_increment_story_likes_count
  /// tarafindan yonetiliyor (increment_story_likes RPC'si no-op).
  Future<void> likeStory(String storyId, {String emoji = defaultReaction}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanici giris yapmamis');
      }

      // Upsert ile race condition'dan korunuyoruz (unique constraint).
      // Kayit zaten varsa yalnizca emoji guncellenir (tepki degistirme).
      await _supabase.from('story_likes').upsert(
        {'story_id': storyId, 'user_id': userId, 'emoji': emoji},
        onConflict: 'story_id,user_id',
      );

      debugPrint('Story tepkisi kaydedildi: $storyId -> $emoji');
    } catch (e) {
      debugPrint('Story tepki hatasi: $e');
      throw Exception('Story begenilirken hata: $e');
    }
  }

  /// Mevcut kullanicinin bu hikayeye verdigi tepkiyi dondurur (yoksa null).
  Future<String?> getMyReaction(String storyId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('story_likes')
          .select('emoji')
          .eq('story_id', storyId)
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;
      final emoji = response['emoji'] as String?;
      return (emoji == null || emoji.isEmpty) ? defaultReaction : emoji;
    } catch (e) {
      debugPrint('Story tepki okuma hatasi: $e');
      return null;
    }
  }

  // NOT (2026-09-06): _createStoryLikeNotification kaldirildi.
  // Hikaye tepkisi bildirimi tek noktadan, DB'deki notify_story_like_trigger
  // tarafindan uretiliyor. Dart tarafinda ikinci bir bildirim yazmak ayni
  // olay icin cift bildirim riski dogruyordu.

  // Story beğenisini kaldır
  // NOT: decrement_story_likes RPC no-op'dır (20260528000001_trigger).
  // DELETE trigger (decrement_story_likes_count) otomatik azaltır.
  Future<void> unlikeStory(String storyId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı giriş yapmamış');
      }

      // Önce mevcut beğeni var mı kontrol et
      final existing = await _supabase
          .from('story_likes')
          .select('id')
          .eq('story_id', storyId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing == null) {
        debugPrint('ℹ️ Story beğenisi zaten yok: $storyId');
        return;
      }

      // Beğeniyi sil
      await _supabase
          .from('story_likes')
          .delete()
          .eq('story_id', storyId)
          .eq('user_id', userId);

      // DELETE trigger otomatik decrement yapar
      debugPrint('💔 Story beğenisi kaldırıldı: $storyId');
    } catch (e) {
      debugPrint('❌ Story beğeni kaldırma hatası: $e');
      throw Exception('Story beğenisi kaldırılırken hata: $e');
    }
  }

  /// Hikaye tepkisini degistir.
  ///
  /// Kullanicinin mevcut tepkisi [emoji] ile ayniysa tepki KALDIRILIR
  /// (Instagram davranisi: ayni emojiye tekrar basmak geri alir), farkliysa
  /// yeni emoji ile guncellenir.
  ///
  /// Donen deger: islem sonrasindaki tepki (kaldirildiysa null).
  Future<String?> setStoryReaction(
    String storyId, {
    String emoji = defaultReaction,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Kullanici giris yapmamis');
    }

    final current = await getMyReaction(storyId);
    if (current == emoji) {
      await unlikeStory(storyId);
      return null;
    }

    await likeStory(storyId, emoji: emoji);
    return emoji;
  }

  /// Klasik begeni toggle (kalp). Geriye donuk uyumluluk icin korunuyor.
  Future<bool> toggleStoryLike(String storyId) async {
    try {
      final result = await setStoryReaction(storyId);
      return result != null;
    } catch (e) {
      debugPrint('Story begeni toggle hatasi: $e');
      throw Exception('Story begeni isleminde hata: $e');
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
