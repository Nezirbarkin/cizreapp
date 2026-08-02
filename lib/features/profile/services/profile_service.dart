import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/utils/image_compression_helper.dart';

class ProfileService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

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

      // Sadece profil satırını döndür. Gönderi/takipçi/takip sayıları
      // çağıran ekranlar tarafından zaten ayrı yükleniyor
      // (PostService.getUserPosts + loadFollowCounts); burada ekstra count
      // sorgusu yapmıyoruz — her profil açılışında 3 israf sorguyu önler.
      return response;
    } catch (e) {
      debugPrint('Profil bilgileri alınamadı: $e');
      rethrow;
    }
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

      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

      // .select() ile dönen satırı kontrol et: RLS bir UPDATE'i engellediğinde
      // Supabase hata fırlatmaz, sadece 0 satır günceller.
      final result = await _supabase
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select();

      if (result.isNotEmpty) return true;

      // 0 satır döndü: profil satırı yok (trigger ile otomatik oluşturulmamış).
      // auth metadata ile profili oluştur, böylece düzenleme kaybolmasın.
      final user = _supabase.auth.currentUser;
      final meta = user?.userMetadata ?? {};
      final now = DateTime.now().toUtc().toIso8601String();

      final created = await _supabase
          .from('profiles')
          .upsert({
            'id': userId,
            'email': user?.email ?? '',
            'username': (meta['username'] as String?) ?? '',
            'full_name': updates['full_name'] ?? (meta['full_name'] as String?) ?? '',
            ...updates,
            'created_at': now,
          }, onConflict: 'id')
          .select();

      if (created.isEmpty) {
        // Hem UPDATE hem INSERT 0 satır döndü -> RLS engelliyor.
        throw Exception(
            'Profil güncellenemedi: yetki hatası veya kayıt bulunamadı.');
      }

      return true;
    } catch (e) {
      debugPrint('Profil güncellenemedi: $e');
      rethrow; // Gerçek hatayı ekrana taşı ki kullanıcı sessizce "başarılı" görmesin
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
  // USERNAME LOOKUP METHODS
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