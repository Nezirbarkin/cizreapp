import 'dart:io' if (dart.library.html) '';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/image_compression_helper.dart';
import 'follow_request_service.dart';

class ProfileService {
  final _supabase = Supabase.instance.client;

  // Profil bilgilerini çek
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .maybeSingle();
      
      // Profil bulunamadıysa hata fırlat
      if (response == null) {
        throw Exception('Profil bulunamadı. Lütfen FIX_FOREIGN_KEY.sql script\'ini çalıştırın.');
      }

      // Gönderileri say
      final postsCount = await _supabase
          .from('posts')
          .select('id')
          .eq('user_id', userId);

      // Takipçileri say
      final followersCount = await _supabase
          .from('follows')
          .select('id')
          .eq('following_id', userId);

      // Takip edilenleri say
      final followingCount = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', userId);

      return {
        ...response,
        'posts_count': postsCount.length,
        'followers_count': followersCount.length,
        'following_count': followingCount.length,
      };
    } catch (e) {
      debugPrint('Profil bilgileri alınamadı: $e');
      rethrow;
    }
  }

  // Kullanıcının gönderilerini çek (optimize edilmiş)
  Future<List<Map<String, dynamic>>> getUserPosts(String userId) async {
    try {
      debugPrint('🔍 Gönderiler çekiliyor - User ID: $userId');
      
      // Limit ile pagination (ilk 20 post)
      final response = await _supabase
          .from('posts')
          .select('''
            id,
            content,
            image_url,
            created_at,
            user_id,
            user:profiles!posts_user_id_fkey(
              id,
              username,
              full_name,
              avatar_url
            ),
            likes:post_likes(count),
            comments:post_comments(count)
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(20);

      debugPrint('✅ ${response.length} gönderi bulundu');
      
      // Basit mapping
      final postsWithData = <Map<String, dynamic>>[];
      
      for (var post in response) {
        final likesCount = (post['likes'] as List?)?.length ?? 0;
        final commentsCount = (post['comments'] as List?)?.length ?? 0;
        
        postsWithData.add({
          'id': post['id'],
          'content': post['content'],
          'image_url': post['image_url'],
          'created_at': post['created_at'],
          'user_id': post['user_id'],
          'user': post['user'],
          'likes': [{'count': likesCount}],
          'comments': [{'count': commentsCount}],
        });
      }

      return postsWithData;
    } catch (e) {
      debugPrint('❌ Gönderiler alınamadı: $e');
      return [];
    }
  }

  // Kullanıcının kaydettiği gönderileri çek
  Future<List<Map<String, dynamic>>> getSavedPosts(String userId) async {
    try {
      final response = await _supabase
          .from('post_saves')
          .select('''
            post:posts(
              *,
              user:profiles!posts_user_id_fkey(id, username, full_name, avatar_url),
              likes:post_likes(count),
              comments:post_comments(count),
              saved:post_saves(count)
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(
        response.map((item) => item['post']).where((post) => post != null),
      );
    } catch (e) {
      debugPrint('Kaydedilen gönderiler alınamadı: $e');
      return [];
    }
  }

  // Takip et/takipten çık
  // Gizli hesaplar için takip isteği gönderir
  // Dönüş değerleri: true = takip edildi/istek gönderildi, false = takipten çıkıldı
  Future<bool> toggleFollow(String targetUserId) async {
    try {
      debugPrint('🔔 TOGGLE FOLLOW BAŞLADI - targetUserId: $targetUserId');
      
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        debugPrint('❌ Kullanıcı giriş yapmamış');
        return false;
      }

      // Zaten takip ediyor mu kontrol et
      final existing = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', currentUserId)
          .eq('following_id', targetUserId)
          .maybeSingle();

      if (existing != null) {
        // Takipten çık
        await _supabase
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', targetUserId);
        debugPrint('🔕 Takipten çıkıldı');
        return false;
      } else {
        // Hedef kullanıcının profili gizli mi kontrol et
        final followRequestService = FollowRequestService();
        final isPrivate = await followRequestService.isProfilePrivate(targetUserId);
        
        if (isPrivate) {
          // Gizli hesap - takip isteği gönder
          // Önce zaten bekleyen bir istek var mı kontrol et
          final existingRequest = await followRequestService.getFollowRequestStatus(targetUserId);
          if (existingRequest == 'pending') {
            // Zaten bekleyen istek var - iptal et
            await followRequestService.cancelFollowRequest(targetUserId);
            debugPrint('🗑️ Bekleyen takip isteği iptal edildi');
            return false;
          } else {
            // Yeni takip isteği gönder
            await followRequestService.sendFollowRequest(targetUserId);
            debugPrint('📩 Gizli hesaba takip isteği gönderildi');
            return true;
          }
        } else {
          // Public hesap - doğrudan takip et
          await _supabase.from('follows').insert({
            'follower_id': currentUserId,
            'following_id': targetUserId,
          });
          
          debugPrint('✅ Public hesap takip edildi');
          // NOT: Takip bildirimi SQL trigger tarafından otomatik gönderiliyor
          // notify_new_follower_trigger - duplicatesiz single notification
          
          return true;
        }
      }
    } catch (e) {
      debugPrint('Takip işlemi başarısız: $e');
      return false;
    }
  }
  
  // Takip bildirimi gönder
  Future<void> _sendFollowNotification(String followerId, String followingId) async {
    try {
      // Takip eden kullanıcının profil bilgilerini al
      final followerResponse = await _supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .eq('id', followerId)
          .maybeSingle();
          
      if (followerResponse == null) return;
      
      // NotificationService'i kullanarak bildirim oluştur
      final notificationService = NotificationService();
      await notificationService.createFollowNotification(
        userId: followingId,
        actorId: followerResponse['id'],
        actorName: followerResponse['username'] ?? 'Bir kullanıcı',
        actorAvatar: followerResponse['avatar_url'],
      );
      
      debugPrint('✅ Takip bildirimi gönderildi: $followerId -> $followingId');
    } catch (e) {
      debugPrint('❌ Takip bildirim hatası: $e');
    }
  }

  // Takip durumunu kontrol et
  Future<bool> isFollowing(String targetUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final response = await _supabase
          .from('follows')
          .select('id')
          .eq('follower_id', currentUserId)
          .eq('following_id', targetUserId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Takip durumu kontrol edilemedi: $e');
      return false;
    }
  }

  // Gönderiyi beğen/beğenmekten vazgeç
  Future<bool> toggleLike(String postId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final existing = await _supabase
          .from('post_likes')
          .select('id')
          .eq('user_id', userId)
          .eq('post_id', postId)
          .maybeSingle();

      if (existing != null) {
        // Beğeniyi kaldır
        await _supabase
            .from('post_likes')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', postId);
        return false;
      } else {
        // Beğen
        await _supabase.from('post_likes').insert({
          'user_id': userId,
          'post_id': postId,
        });
        return true;
      }
    } catch (e) {
      debugPrint('Beğeni işlemi başarısız: $e');
      return false;
    }
  }

  // Gönderiyi kaydet/kaydı kaldır
  Future<bool> toggleSave(String postId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final existing = await _supabase
          .from('post_saves')
          .select('id')
          .eq('user_id', userId)
          .eq('post_id', postId)
          .maybeSingle();

      if (existing != null) {
        // Kaydı kaldır
        await _supabase
            .from('post_saves')
            .delete()
            .eq('user_id', userId)
            .eq('post_id', postId);
        return false;
      } else {
        // Kaydet
        await _supabase.from('post_saves').insert({
          'user_id': userId,
          'post_id': postId,
        });
        return true;
      }
    } catch (e) {
      debugPrint('Kaydetme işlemi başarısız: $e');
      return false;
    }
  }

  // Gönderinin beğenilme durumunu kontrol et
  Future<bool> isPostLiked(String postId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _supabase
          .from('post_likes')
          .select('id')
          .eq('user_id', userId)
          .eq('post_id', postId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  // Gönderinin kaydedilme durumunu kontrol et
  Future<bool> isPostSaved(String postId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _supabase
          .from('post_saves')
          .select('id')
          .eq('user_id', userId)
          .eq('post_id', postId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  // Profil fotoğrafı yükle (dosya yolu ile - XFile üzerinden)
  Future<String?> uploadProfilePhoto(String filePath) async {
    // XFile'a dönüştür ve XFile metodu ile yükle
    final xFile = XFile(filePath);
    return uploadProfilePhotoXFile(xFile);
  }

  // Kapak fotoğrafı yükle (dosya yolu ile - XFile üzerinden)
  Future<String?> uploadCoverPhoto(String filePath) async {
    // XFile'a dönüştür ve XFile metodu ile yükle
    final xFile = XFile(filePath);
    return uploadCoverPhotoXFile(xFile);
  }

  // Web için profil fotoğrafı yükle (bytes ile)
  Future<String?> uploadProfilePhotoBytes(Uint8List bytes) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Avatar - Kullanıcı ID boş');
        return null;
      }

      debugPrint('📤 Avatar yükleniyor (web): ${bytes.length} bytes');
      
      final fileName = 'avatar_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Dosyayı yükle
      final uploadResponse = await _supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      debugPrint('✅ Dosya yüklendi: $uploadResponse');

      // Public URL al
      final url = _supabase.storage
          .from('avatars')
          .getPublicUrl(fileName);

      debugPrint('🔗 Public URL: $url');

      // Profili güncelle
      final updateResponse = await _supabase
          .from('profiles')
          .update({'avatar_url': url, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userId)
          .select();

      debugPrint('✅ Profil güncellendi: $updateResponse');

      return url;
    } catch (e) {
      debugPrint('❌ Profil fotoğrafı yüklenemedi (web): $e');
      return null;
    }
  }

  // Web için kapak fotoğrafı yükle (bytes ile)
  Future<String?> uploadCoverPhotoBytes(Uint8List bytes) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Kapak - Kullanıcı ID boş');
        return null;
      }

      debugPrint('📤 Kapak fotoğrafı yükleniyor (web): ${bytes.length} bytes');
      
      final fileName = 'cover_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Dosyayı yükle
      final uploadResponse = await _supabase.storage
          .from('covers')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      debugPrint('✅ Dosya yüklendi: $uploadResponse');

      // Public URL al
      final url = _supabase.storage
          .from('covers')
          .getPublicUrl(fileName);

      debugPrint('🔗 Public URL: $url');

      // Profili güncelle
      final updateResponse = await _supabase
          .from('profiles')
          .update({'cover_url': url, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userId)
          .select();

      debugPrint('✅ Profil güncellendi: $updateResponse');

      return url;
    } catch (e) {
      debugPrint('❌ Kapak fotoğrafı yüklenemedi (web): $e');
      return null;
    }
  }

  // Profili güncelle
  Future<bool> updateProfile({
    String? fullName,
    String? bio,
    String? website,
    String? location,
    String? gender,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (bio != null) updates['bio'] = bio;
      if (website != null) updates['website'] = website;
      if (location != null) updates['location'] = location;
      if (gender != null) updates['gender'] = gender;

      if (updates.isEmpty) return false;

      await _supabase
          .from('profiles')
          .update(updates)
          .eq('id', userId);

      return true;
    } catch (e) {
      debugPrint('Profil güncellenemedi: $e');
      return false;
    }
  }

  // Kullanıcının hikayelerini çek
  Future<List<Map<String, dynamic>>> getUserStories(String userId) async {
    try {
      final response = await _supabase
          .from('stories')
          .select('''
            *,
            user:profiles!stories_user_id_fkey(id, username, full_name, avatar_url),
            views:story_views(count)
          ''')
          .eq('user_id', userId)
          .gte('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Hikayeler alınamadı: $e');
      return [];
    }
  }

  // Story görüntüleme kaydet
  Future<void> viewStory(String storyId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('story_views').insert({
        'story_id': storyId,
        'user_id': userId,
      });
    } catch (e) {
      debugPrint('Story görüntüleme kaydedilemedi: $e');
    }
  }

  // Kullanıcı ara (isim veya kullanıcı adı ile)
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (query.trim().isEmpty) return [];

      final response = await _supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url, bio')
          .or('username.ilike.%$query%,full_name.ilike.%$query%')
          .limit(20);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Kullanıcı araması başarısız: $e');
      return [];
    }
  }

  // Kullanıcıyı şikayet et
  // Dönüş değerleri:
  // - 'success': Şikayet başarıyla oluşturuldu
  // - 'duplicate': Bu kullanıcıyı daha önce şikayet etmişsiniz
  // - 'error': Genel hata (izin yok, vb.)
  // - 'not_logged_in': Kullanıcı giriş yapmamış
  Future<String> reportUser({
    required String reportedUserId,
    required String reason,
    String? description,
    List<String>? images,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        debugPrint('❌ Şikayet: Kullanıcı giriş yapmamış');
        return 'not_logged_in';
      }

      debugPrint('🔍 Şikayet kontrolü: reporter=$currentUserId, reported=$reportedUserId');

      // Zaten şikayet edilmiş mi kontrol et
      final existing = await _supabase
          .from('user_reports')
          .select('id, status')
          .eq('reporter_id', currentUserId)
          .eq('reported_user_id', reportedUserId)
          .maybeSingle();

      debugPrint('🔍 Mevcut şikayet: $existing');

      if (existing != null) {
        debugPrint('⚠️ Bu kullanıcıyı daha önce şikayet etmişsiniz (ID: ${existing['id']}, Status: ${existing['status']})');
        return 'duplicate';
      }

      debugPrint('✅ Yeni şikayet oluşturuluyor...');
      
      final Map<String, dynamic> reportData = {
        'reporter_id': currentUserId,
        'reported_user_id': reportedUserId,
        'reason': reason,
        'description': description,
        'status': 'pending',
      };

      // Görsel URL'leri varsa ekle
      if (images != null && images.isNotEmpty) {
        reportData['images'] = images;
      }

      await _supabase.from('user_reports').insert(reportData);

      debugPrint('✅ Şikayet başarıyla oluşturuldu');
      return 'success';
    } catch (e) {
      debugPrint('❌ Şikayet işlemi başarısız: $e');
      return 'error';
    }
  }

  // Kullanıcıyı engelle
  Future<bool> blockUser(String blockedUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      // Zaten engellenmiş mi kontrol et
      final existing = await _supabase
          .from('blocked_users')
          .select('id')
          .eq('blocker_id', currentUserId)
          .eq('blocked_id', blockedUserId)
          .maybeSingle();

      if (existing != null) {
        // Zaten engellenmiş, engeli kaldır
        await _supabase
            .from('blocked_users')
            .delete()
            .eq('blocker_id', currentUserId)
            .eq('blocked_id', blockedUserId);
        return false;
      }

      // Engelle
      await _supabase.from('blocked_users').insert({
        'blocker_id': currentUserId,
        'blocked_id': blockedUserId,
      });

      return true;
    } catch (e) {
      debugPrint('Engelleme işlemi başarısız: $e');
      return false;
    }
  }

  // Kullanıcının engelli olup olmadığını kontrol et
  Future<bool> isUserBlocked(String userId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final response = await _supabase
          .from('blocked_users')
          .select('id')
          .eq('blocker_id', currentUserId)
          .eq('blocked_id', userId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Engelleme durumu kontrol edilemedi: $e');
      return false;
    }
  }

  // Destek talebi oluştur
  Future<bool> createSupportTicket({
    required String subject,
    required String category,
    required String message,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      debugPrint('📝 Destek talebi oluşturuluyor - userId: $currentUserId');
      
      if (currentUserId == null) {
        debugPrint('❌ Kullanıcı oturumu açık değil');
        throw Exception('Oturum açmanız gerekiyor');
      }

      debugPrint('📤 Veri gönderiliyor: subject=$subject, category=$category');
      
      final response = await _supabase.from('support_tickets').insert({
        'user_id': currentUserId,
        'subject': subject,
        'category': category,
        'message': message,
        'status': 'open',
      }).select();

      debugPrint('✅ Destek talebi oluşturuldu: $response');
      return true;
    } catch (e) {
      debugPrint('❌ Destek talebi oluşturulamadı: $e');
      rethrow; // Hatayı üst katmana ilet
    }
  }

  // Kullanıcının destek taleplerini getir
  Future<List<Map<String, dynamic>>> getUserSupportTickets() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('support_tickets')
          .select('*')
          .eq('user_id', currentUserId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Destek talepleri alınamadı: $e');
      return [];
    }
  }

  // SSS (Sıkça Sorulan Sorular) getir
  Future<List<Map<String, dynamic>>> getFAQs() async {
    try {
      final response = await _supabase
          .from('faqs')
          .select('*')
          .order('order', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('SSS getirilemedi: $e');
      return [];
    }
  }

  // Engellediğim kullanıcıları getir
  Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('blocked_users')
          .select('id, blocked_id, created_at')
          .eq('blocker_id', currentUserId)
          .order('created_at', ascending: false);

      // Profil bilgilerini ayrıca çek
      final blockedUsers = <Map<String, dynamic>>[];
      for (var block in response) {
        try {
          final userProfile = await _supabase
              .from('profiles')
              .select('id, username, full_name, avatar_url')
              .eq('id', block['blocked_id'])
              .maybeSingle();
          
          if (userProfile != null) {
            blockedUsers.add({
              ...block,
              'blocked_user': userProfile,
            });
          }
        } catch (e) {
          debugPrint('Profil alınamadı: $e');
        }
      }

      return blockedUsers;
    } catch (e) {
      debugPrint('Engellenen kullanıcılar getirilemedi: $e');
      return [];
    }
  }

  // Şikayet ettiğim kullanıcıları getir
  Future<List<Map<String, dynamic>>> getMyReports() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('user_reports')
          .select('id, reported_user_id, reason, description, status, created_at')
          .eq('reporter_id', currentUserId)
          .order('created_at', ascending: false);

      // Profil bilgilerini ayrıca çek
      final reports = <Map<String, dynamic>>[];
      for (var report in response) {
        try {
          final userProfile = await _supabase
              .from('profiles')
              .select('id, username, full_name, avatar_url')
              .eq('id', report['reported_user_id'])
              .maybeSingle();
          
          if (userProfile != null) {
            reports.add({
              ...report,
              'reported_user': userProfile,
            });
          }
        } catch (e) {
          debugPrint('Profil alınamadı: $e');
        }
      }

      return reports;
    } catch (e) {
      debugPrint('Şikayetler getirilemedi: $e');
      return [];
    }
  }

  // ============================================
  // USERNAME LOOKUP METHODS (NEW)
  // ============================================

  /// Username'den kullanıcı bilgilerini getir
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('id, email, username, full_name, avatar_url')
          .eq('username', username.trim().toLowerCase())
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('❌ Username ile kullanıcı bulunamadı: $e');
      return null;
    }
  }

  /// Email veya username'den email'i al
  Future<String?> getEmailByIdentifier(String identifier) async {
    try {
      // Email ise direkt döndür
      if (identifier.contains('@')) {
        return identifier.trim();
      }

      // Username ise lookup yap
      final user = await getUserByUsername(identifier);
      return user?['email'] as String?;
    } catch (e) {
      debugPrint('❌ Email lookup hatası: $e');
      return null;
    }
  }

  /// Kullanıcı adının kullanılabilir olup olmadığını kontrol et
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('id')
          .eq('username', username.trim().toLowerCase())
          .maybeSingle();

      // Eğer kullanıcı bulunduysa username alınmış demektir
      return response == null;
    } catch (e) {
      debugPrint('❌ Username kontrolü hatası: $e');
      // Hata durumunda false dön (kullanıcılamaz gibi davran)
      return false;
    }
  }

  // ============================================
  // XFILE UPLOAD METHODS (Web ve Mobile uyumlu)
  // ============================================

  /// XFile'dan profil fotoğrafı yükle (Web ve Mobile uyumlu)
  /// Bu metod hem web hem mobile'da çalışır
  Future<String?> uploadProfilePhotoXFile(XFile xFile) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Avatar - Kullanıcı ID boş');
        return null;
      }

      debugPrint('📤 Avatar XFile yükleniyor...');
      
      // Resmi sıkıştır
      final compressedBytes = await ImageCompressionHelper.compressProfilePhotoXFile(xFile);
      final imageBytes = compressedBytes ?? await xFile.readAsBytes();
      
      final fileSize = imageBytes.length;
      debugPrint('📏 Yüklenecek boyut: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      final fileName = 'avatar_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Dosyayı yükle (byte array ile)
      final uploadResponse = await _supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      debugPrint('✅ Dosya yüklendi: $uploadResponse');

      // Public URL al
      final url = _supabase.storage
          .from('avatars')
          .getPublicUrl(fileName);

      debugPrint('🔗 Public URL: $url');

      // Profili güncelle
      final updateResponse = await _supabase
          .from('profiles')
          .update({'avatar_url': url, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userId)
          .select();

      debugPrint('✅ Profil güncellendi: $updateResponse');

      return url;
    } catch (e) {
      debugPrint('❌ Profil fotoğrafı yüklenemedi (XFile): $e');
      return null;
    }
  }

  /// XFile'dan kapak fotoğrafı yükle (Web ve Mobile uyumlu)
  /// Bu metod hem web hem mobile'da çalışır
  Future<String?> uploadCoverPhotoXFile(XFile xFile) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Kapak - Kullanıcı ID boş');
        return null;
      }

      debugPrint('📤 Kapak XFile yükleniyor...');
      
      // Resmi sıkıştır
      final compressedBytes = await ImageCompressionHelper.compressCoverPhotoXFile(xFile);
      final imageBytes = compressedBytes ?? await xFile.readAsBytes();
      
      final fileSize = imageBytes.length;
      debugPrint('📏 Yüklenecek boyut: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      final fileName = 'cover_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Dosyayı yükle (byte array ile)
      final uploadResponse = await _supabase.storage
          .from('covers')
          .uploadBinary(
            fileName,
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      debugPrint('✅ Dosya yüklendi: $uploadResponse');

      // Public URL al
      final url = _supabase.storage
          .from('covers')
          .getPublicUrl(fileName);

      debugPrint('🔗 Public URL: $url');

      // Profili güncelle
      final updateResponse = await _supabase
          .from('profiles')
          .update({'cover_url': url, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userId)
          .select();

      debugPrint('✅ Profil güncellendi: $updateResponse');

      return url;
    } catch (e) {
      debugPrint('❌ Kapak fotoğrafı yüklenemedi (XFile): $e');
      return null;
    }
  }
}
