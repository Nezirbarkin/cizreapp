import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/utils/image_compression_helper.dart';

/// Profil sayaçları (get_follow_counts RPC'si).
class FollowCounts {
  final int followers;
  final int following;
  final int friends;
  final int posts;

  const FollowCounts({
    this.followers = 0,
    this.following = 0,
    this.friends = 0,
    this.posts = 0,
  });

  factory FollowCounts.fromJson(Map<String, dynamic> json) {
    int read(String key) {
      final v = json[key];
      return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    }

    return FollowCounts(
      followers: read('followers'),
      following: read('following'),
      friends: read('friends'),
      posts: read('posts'),
    );
  }
}

/// Ortak takipçiler (get_mutual_followers RPC'si): toplam sayı + ilk birkaç kişi.
class MutualFollowers {
  final int count;
  final List<Map<String, dynamic>> users;

  const MutualFollowers({this.count = 0, this.users = const []});

  factory MutualFollowers.fromJson(Map<String, dynamic> json) {
    final raw = json['count'];
    final list = json['users'];
    return MutualFollowers(
      count: raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0,
      users: list is List
          ? [
              for (final u in list)
                if (u is Map) Map<String, dynamic>.from(u),
            ]
          : const [],
    );
  }

  /// Kişinin görünen adı: kullanıcı adı (kısa; satırda yer kaplamasın).
  static String nameOf(Map<String, dynamic> user) {
    final username = user['username']?.toString().trim() ?? '';
    if (username.isNotEmpty) return username;
    return user['full_name']?.toString().trim() ?? 'kullanıcı';
  }

  /// "ali takip ediyor" / "ali ve veli takip ediyor" /
  /// "ali, veli ve 3 kişi daha takip ediyor".
  String get summary {
    if (count <= 0 || users.isEmpty) return '';
    final names = users.take(2).map(nameOf).toList();
    final rest = count - names.length;
    if (rest <= 0) {
      return names.length == 1
          ? '${names[0]} takip ediyor'
          : '${names[0]} ve ${names[1]} takip ediyor';
    }
    return '${names.join(', ')} ve $rest kişi daha takip ediyor';
  }
}

class ProfileService {
  /// Bu oturumda engellenen kullanıcıların kimlikleri yayınlanır. Açık
  /// listeler (Keşfet akışı, hikâye şeridi) o kişinin ekrandaki eski
  /// içeriğini elle yenilemeyi beklemeden çıkarır; sunucu zaten süzüyor.
  static final StreamController<String> _blockedController =
      StreamController<String>.broadcast();
  static Stream<String> get onUserBlocked => _blockedController.stream;

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
  // Not: Bu fonksiyon başka kullanıcıların public yüzeyini döner.
  // Hassas alanlar (email, telefon, fatura, role, is_admin, is_suspicious,
  // delete_confirmation_code, last_known_lat/lng) base profiles tablosundan
  // anon/authenticated'a REVOKE edildi. public_profiles_safe view'ı yalnız
  // güvenli sütunları döner; burada onu kullanıyoruz.
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('public_profiles_safe')
          .select()
          .eq('id', userId)
          .maybeSingle();

      // Profil bulunamadıysa hata fırlat
      if (response == null) {
        throw Exception('Profil bulunamadı. userId=$userId');
      }
      return response;
    } catch (e) {
      debugPrint('Profil bilgileri alınamadı: $e');
      rethrow;
    }
  }

  // Web için profil fotoğrafı yükle (bytes ile)
  // [fileExtension]/[contentType]: hazır avatar assetleri PNG olarak
  // yüklenir, kamera/galeri akışı JPEG kalır.
  Future<String?> uploadProfilePhotoBytes(
    Uint8List bytes, {
    String fileExtension = 'jpg',
    String contentType = 'image/jpeg',
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Avatar - Kullanıcı ID boş');
        return null;
      }

      debugPrint('📤 Avatar yükleniyor (web): ${bytes.length} bytes');

      final fileName =
          'avatar_$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      // Dosyayı yükle
      final uploadResponse = await _supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: contentType,
            ),
          );

      debugPrint('✅ Dosya yüklendi: $uploadResponse');

      // Public URL al
      final url = _supabase.storage.from('avatars').getPublicUrl(fileName);

      // Hassas URL debug log'a yazılmaz.

      // Profili güncelle: doğrudan UPDATE yerine dar RPC.
      await _supabase.rpc(
        'update_my_public_profile',
        params: {'p_avatar_url': url},
      );

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

      final fileName =
          'cover_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Dosyayı yükle
      final uploadResponse = await _supabase.storage
          .from('covers')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      debugPrint('✅ Dosya yüklendi: $uploadResponse');

      // Public URL al
      final url = _supabase.storage.from('covers').getPublicUrl(fileName);

      // Hassas URL debug log'a yazılmaz.

      // Profili güncelle: doğrudan UPDATE yerine dar RPC.
      await _supabase.rpc(
        'update_my_public_profile',
        params: {'p_cover_url': url},
      );

      return url;
    } catch (e) {
      debugPrint('❌ Kapak fotoğrafı yüklenemedi (web): $e');
      return null;
    }
  }

  // Profili güncelle
  // Not: Bu fonksiyon doğrudan profiles UPDATE yapmaz; onun yerine
  // update_my_public_profile RPC'sini çağırır. RPC yalnız izinli sütunları
  // günceller ve server timestamp yazar.
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

      if (fullName == null &&
          bio == null &&
          website == null &&
          location == null &&
          gender == null) {
        return false;
      }

      // Profil satırı yoksa ensure_my_profile ile güvenli varsayılanlarla
      // oluştur (idempotent).
      try {
        await _supabase.rpc('ensure_my_profile');
      } catch (e) {
        debugPrint('ℹ️ ensure_my_profile atlandı: $e');
      }

      // update_my_public_profile: username burada değiştirilmez; rename
      // akışı farklı bir RPC'de yapılır (priv_rpc_rename_username vb.).
      await _supabase.rpc(
        'update_my_public_profile',
        params: {
          if (fullName != null) 'p_full_name': fullName,
          if (bio != null) 'p_bio': bio,
          if (website != null) 'p_website': website,
          if (location != null) 'p_location': location,
          if (gender != null) 'p_gender': gender,
        },
      );
      return true;
    } catch (e) {
      debugPrint('Profil güncellenemedi: $e');
      rethrow;
    }
  }

  // Kullanıcı ara (isim veya kullanıcı adı ile)
  // Not: profiles tablosu RLS nedeniyle yalnız kendi satırınızı döndürür.
  // public_profiles_safe SECURITY DEFINER modda olduğu için tüm public
  // profiller buradan okunabilir.
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (query.trim().isEmpty) return [];

      // Değer çift tırnakla sarılır: virgül/parantez/nokta içeren arama
      // (ör. "ali, veli") PostgREST mantık ağacını bozup boş dönüyordu.
      final safe = query
          .trim()
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"');
      final response = await _supabase
          .from('public_profiles_safe')
          .select('id, username, full_name, avatar_url, bio')
          .or('username.ilike."%$safe%",full_name.ilike."%$safe%"')
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

      debugPrint(
        '🔍 Şikayet kontrolü: reporter=$currentUserId, reported=$reportedUserId',
      );

      // Zaten şikayet edilmiş mi kontrol et
      final existing = await _supabase
          .from('user_reports')
          .select('id, status')
          .eq('reporter_id', currentUserId)
          .eq('reported_user_id', reportedUserId)
          .maybeSingle();

      debugPrint('🔍 Mevcut şikayet: $existing');

      if (existing != null) {
        debugPrint(
          '⚠️ Bu kullanıcıyı daha önce şikayet etmişsiniz (ID: ${existing['id']}, Status: ${existing['status']})',
        );
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

  // Kullanıcıyı engelle / engeli kaldır. Eskiden tek bir "toggle" vardı ve
  // hata durumunda false dönüyordu; ekran bunu "engel kaldırıldı" diye
  // gösteriyordu (ağ hatası = sahte engel kaldırma). Artık niyet açık,
  // ikisi de tekrar edilebilir ve hata fırlatır.
  //
  // Engellemede iki yöndeki takip ve takip istekleri sunucuda silinir
  // (social_cleanup_follows_on_block, 20261023000001).
  Future<void> block(String blockedUserId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      throw Exception('Engellemek için giriş yapmalısınız');
    }
    await _supabase.from('blocked_users').upsert(
      {'blocker_id': currentUserId, 'blocked_id': blockedUserId},
      onConflict: 'blocker_id,blocked_id',
      ignoreDuplicates: true,
    );
    _blockedController.add(blockedUserId);
  }

  Future<void> unblock(String blockedUserId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    await _supabase
        .from('blocked_users')
        .delete()
        .eq('blocker_id', currentUserId)
        .eq('blocked_id', blockedUserId);
  }

  /// "X, Y ve N kişi daha takip ediyor": benim takip ettiklerimden [targetId]'yi
  /// takip edenler (engelli/hayalet/silinmiş hariç). Misafirde boş.
  Future<MutualFollowers> getMutualFollowers(
    String targetId, {
    int limit = 3,
  }) async {
    if (_supabase.auth.currentUser == null) return const MutualFollowers();
    final data = await _supabase.rpc(
      'get_mutual_followers',
      params: {'p_target': targetId, 'p_limit': limit},
    );
    if (data is! Map) return const MutualFollowers();
    return MutualFollowers.fromJson(Map<String, dynamic>.from(data));
  }

  /// Takipçi / takip / arkadaş / gönderi sayıları tek istekte. Eskiden tüm
  /// takip satırları indirilip telefonda sayılıyordu (1000 satır tavanı).
  Future<FollowCounts> getFollowCounts(String userId) async {
    final data = await _supabase.rpc(
      'get_follow_counts',
      params: {'p_user_id': userId},
    );
    if (data is! Map) return const FollowCounts();
    return FollowCounts.fromJson(Map<String, dynamic>.from(data));
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

  /// Liste ekranları için profilleri `id → satır` olarak tek istekte çeker.
  Future<Map<String, Map<String, dynamic>>> _profilesById(
    Iterable<String> ids,
  ) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return {};
    final rows = await _supabase
        .from('profiles')
        .select('id, username, full_name, avatar_url')
        .inFilter('id', unique);
    return {
      for (final row in rows) row['id'] as String: Map<String, dynamic>.from(row),
    };
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

      // Profil bilgilerini ayrıca, tek istekte çek (eskiden satır başına).
      final profiles = await _profilesById(
        response.map((b) => b['blocked_id']).whereType<String>(),
      );
      return [
        for (final block in response)
          if (profiles[block['blocked_id']] != null)
            {...block, 'blocked_user': profiles[block['blocked_id']]},
      ];
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
          .select(
            'id, reported_user_id, reason, description, status, created_at',
          )
          .eq('reporter_id', currentUserId)
          .order('created_at', ascending: false);

      // Profil bilgilerini ayrıca, tek istekte çek (eskiden satır başına).
      final profiles = await _profilesById(
        response.map((r) => r['reported_user_id']).whereType<String>(),
      );
      return [
        for (final report in response)
          if (profiles[report['reported_user_id']] != null)
            {...report, 'reported_user': profiles[report['reported_user_id']]},
      ];
    } catch (e) {
      debugPrint('Şikayetler getirilemedi: $e');
      return [];
    }
  }

  // ============================================
  // USERNAME LOOKUP METHODS
  // ============================================

  /// Username'den kullanıcı bilgilerini getir
  /// Not: Email PII sızıntısını önlemek için yalnız public sütunlar seçilir
  /// ve public_profiles_safe view'i kullanılır.
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    try {
      final response = await _supabase
          .from('public_profiles_safe')
          .select()
          .eq('username', username.trim().toLowerCase())
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('❌ Username ile kullanıcı bulunamadı: $e');
      return null;
    }
  }

  /// Email veya username'den email'i al
  /// Not: Username → email eşlemesi artık profiles tablosundan SELECT ile
  /// değil; yalnız RPC üzerinden yapılır. RPC SECURITY DEFINER + SET
  /// search_path='' ile çalışır; e-posta adresi dışında hiçbir sütun
  /// sızdırmaz. Production'da bu RPC'nin Supabase Edge Function üzerinden
  /// rate-limit edilmesi gerekir.
  Future<String?> getEmailByIdentifier(String identifier) async {
    try {
      // Email ise direkt döndür
      if (identifier.contains('@')) {
        return identifier.trim();
      }

      // Username ise server-side RPC ile email'i al
      final email = await _supabase.rpc<String>(
        'lookup_email_by_username',
        params: {'p_username': identifier.trim().toLowerCase()},
      );
      final normalizedEmail = email.trim().toLowerCase();
      return normalizedEmail.isEmpty ? null : normalizedEmail;
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
  /// Bu metod hem web hem mobile'da çalışır.
  ///
  /// RLS davranışı: bucket_id = 'avatars' ise authenticated INSERT kabul edilir
  /// (20260206000001_create_avatar_cover_buckets.sql). Bucket MİMARİSİ:
  /// dosya adı `avatar_<userId>-<ts>.jpg` → kullanıcı kendi klasörüne yazar;
  /// Supabase storage allowed_mime_types `image/jpeg|image/png|image/webp`
  /// kabul eder. contentType burada açıkça set edilmezse storage bazı
  /// bucket konfiglerinde "0 byte / mime uyumsuz" olarak reddedebilir.
  Future<String?> uploadProfilePhotoXFile(XFile xFile) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ Avatar - Kullanıcı ID boş (auth.currentUser null)');
        return null;
      }

      debugPrint('📤 Avatar XFile yükleniyor... userId=$userId');

      // Resmi sıkıştır
      final compressedBytes =
          await ImageCompressionHelper.compressProfilePhotoXFile(xFile);
      final imageBytes = compressedBytes ?? await xFile.readAsBytes();

      final fileSize = imageBytes.length;
      debugPrint(
        '📏 Yüklenecek boyut: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
      );

      final fileName =
          'avatar_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';

      // contentType ve upsert birlikte; storage RLS'in bucket-level kontrolü
      // için yeterli. allowed_mime_types filtrelemesini de geçer.
      await _uploadWithRetry(
        bucket: 'avatars',
        objectPath: fileName,
        bytes: imageBytes,
        contentType: 'image/jpeg',
      );

      // Public URL al
      final url = _supabase.storage.from('avatars').getPublicUrl(fileName);

      // Hassas URL debug log'a yazılmaz.

      // Profili güncelle: doğrudan UPDATE yerine dar RPC.
      await _supabase.rpc(
        'update_my_public_profile',
        params: {'p_avatar_url': url},
      );

      debugPrint('✅ Avatar yüklendi ve profile bağlandı');
      return url;
    } on StorageException catch (e) {
      debugPrint(
        '❌ Profil fotoğrafı StorageException: '
        'status=${e.statusCode} msg=${e.message}',
      );
      return null;
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
        debugPrint('❌ Kapak - Kullanıcı ID boş (auth.currentUser null)');
        return null;
      }

      debugPrint('📤 Kapak XFile yükleniyor... userId=$userId');

      // Resmi sıkıştır
      final compressedBytes =
          await ImageCompressionHelper.compressCoverPhotoXFile(xFile);
      final imageBytes = compressedBytes ?? await xFile.readAsBytes();

      final fileSize = imageBytes.length;
      debugPrint(
        '📏 Yüklenecek boyut: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
      );

      final fileName =
          'cover_$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';

      await _uploadWithRetry(
        bucket: 'covers',
        objectPath: fileName,
        bytes: imageBytes,
        contentType: 'image/jpeg',
      );

      // Public URL al
      final url = _supabase.storage.from('covers').getPublicUrl(fileName);

      // Hassas URL debug log'a yazılmaz.

      // Profili güncelle: doğrudan UPDATE yerine dar RPC.
      await _supabase.rpc(
        'update_my_public_profile',
        params: {'p_cover_url': url},
      );

      debugPrint('✅ Kapak yüklendi ve profile bağlandı');
      return url;
    } on StorageException catch (e) {
      debugPrint(
        '❌ Kapak fotoğrafı StorageException: '
        'status=${e.statusCode} msg=${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint('❌ Kapak fotoğrafı yüklenemedi (XFile): $e');
      return null;
    }
  }

  /// Storage yükleme yardımcısı:
  /// - contentType açıkça set edilir (bucket allowed_mime_types uyumu için)
  /// - 403 RLS hatası alındığında 1 kez upsert:false ile tekrar denenir
  ///   (mevcut dosya varken RLS UPDATE'i reddediyor olabilir; INSERT ile yeni
  ///   nesne oluşturmak çoğu zaman çözümdür).
  /// - Hâlâ başarısızsa StorageException fırlatır, üst katman loglayıp
  ///   kullanıcıya hata mesajı gösterir.
  Future<void> _uploadWithRetry({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    Future<void> attempt({required bool upsert}) async {
      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: upsert,
              contentType: contentType,
            ),
          );
    }

    try {
      await attempt(upsert: true);
    } on StorageException catch (e) {
      // 403 (RLS) veya 409 (Conflict) durumlarında upsert=false ile dene
      if (e.statusCode == '403' || e.statusCode == '409') {
        debugPrint(
          '⚠️ Storage upload RLS/Conflict (${e.statusCode}), upsert=false ile tekrar deneniyor...',
        );
        await attempt(upsert: false);
      } else {
        rethrow;
      }
    }
  }
}
