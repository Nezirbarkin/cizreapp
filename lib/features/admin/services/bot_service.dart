import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin panelindeki bot (vitrin) hesaplarının veri katmanı.
///
/// Tüm yazma işlemleri `admin_bot_*` SECURITY DEFINER RPC'lerinden geçer;
/// istemcinin `profiles` veya `bot_*` tabloları üzerinde doğrudan yazma hakkı
/// yoktur. RPC'ler kendi içlerinde `private.current_user_is_admin()` kontrolü
/// yapar, yani yetki kararı sunucuda verilir.
class BotAccount {
  final String id;
  final String? username;
  final String? fullName;
  final String? bio;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? location;
  final String? website;
  final String? persona;
  final bool isActive;
  final bool autoFollowEnabled;
  final int followWeight;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final int pendingJobs;
  final DateTime? createdAt;

  const BotAccount({
    required this.id,
    this.username,
    this.fullName,
    this.bio,
    this.avatarUrl,
    this.bannerUrl,
    this.location,
    this.website,
    this.persona,
    this.isActive = true,
    this.autoFollowEnabled = true,
    this.followWeight = 100,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.pendingJobs = 0,
    this.createdAt,
  });

  String get displayName =>
      (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : (username ?? 'Bot');

  factory BotAccount.fromMap(Map<String, dynamic> map) {
    int asInt(dynamic v) => (v as num?)?.toInt() ?? 0;
    return BotAccount(
      id: map['id'] as String,
      username: map['username'] as String?,
      fullName: map['full_name'] as String?,
      bio: map['bio'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      bannerUrl: map['banner_url'] as String?,
      location: map['location'] as String?,
      website: map['website'] as String?,
      persona: map['persona'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      autoFollowEnabled: map['auto_follow_enabled'] as bool? ?? true,
      followWeight: asInt(map['follow_weight']),
      followersCount: asInt(map['followers_count']),
      followingCount: asInt(map['following_count']),
      postsCount: asInt(map['posts_count']),
      pendingJobs: asInt(map['pending_jobs']),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

class BotQueuedPost {
  final String id;
  final String? botId;
  final String? botUsername;
  final String? botFullName;
  final String? botAvatarUrl;
  final String? content;
  final List<String> images;
  final String? location;
  final DateTime scheduledAt;
  final String status;
  final String? postId;
  final DateTime? publishedAt;
  final String? errorMessage;

  const BotQueuedPost({
    required this.id,
    this.botId,
    this.botUsername,
    this.botFullName,
    this.botAvatarUrl,
    this.content,
    this.images = const [],
    this.location,
    required this.scheduledAt,
    required this.status,
    this.postId,
    this.publishedAt,
    this.errorMessage,
  });

  bool get isPending => status == 'pending';

  factory BotQueuedPost.fromMap(Map<String, dynamic> map) {
    return BotQueuedPost(
      id: map['id'] as String,
      botId: map['bot_id'] as String?,
      botUsername: map['bot_username'] as String?,
      botFullName: map['bot_full_name'] as String?,
      botAvatarUrl: map['bot_avatar_url'] as String?,
      content: map['content'] as String?,
      images: ((map['images'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      location: map['location'] as String?,
      scheduledAt:
          DateTime.tryParse(map['scheduled_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      status: map['status'] as String? ?? 'pending',
      postId: map['post_id'] as String?,
      publishedAt:
          DateTime.tryParse(map['published_at']?.toString() ?? '')?.toLocal(),
      errorMessage: map['error_message'] as String?,
    );
  }
}

class BotStats {
  final int botCount;
  final int activeBotCount;
  final int realUserCount;
  final int pendingFollowJobs;
  final int doneFollowJobs;
  final int queuedPosts;
  final int publishedPosts;
  final int botPostCount;
  final int pendingLikeJobs;
  final int doneLikeJobs;
  final int libraryTextCount;
  final int libraryImageCount;

  const BotStats({
    this.botCount = 0,
    this.activeBotCount = 0,
    this.realUserCount = 0,
    this.pendingFollowJobs = 0,
    this.doneFollowJobs = 0,
    this.queuedPosts = 0,
    this.publishedPosts = 0,
    this.botPostCount = 0,
    this.pendingLikeJobs = 0,
    this.doneLikeJobs = 0,
    this.libraryTextCount = 0,
    this.libraryImageCount = 0,
  });

  factory BotStats.fromMap(Map<String, dynamic> map) {
    int v(String k) => (map[k] as num?)?.toInt() ?? 0;
    return BotStats(
      botCount: v('bot_count'),
      activeBotCount: v('active_bot_count'),
      realUserCount: v('real_user_count'),
      pendingFollowJobs: v('pending_follow_jobs'),
      doneFollowJobs: v('done_follow_jobs'),
      queuedPosts: v('queued_posts'),
      publishedPosts: v('published_posts'),
      botPostCount: v('bot_post_count'),
      pendingLikeJobs: v('pending_like_jobs'),
      doneLikeJobs: v('done_like_jobs'),
      libraryTextCount: v('library_text_count'),
      libraryImageCount: v('library_image_count'),
    );
  }
}

/// Otomatik takip davranışının ayarları (`app_settings` key/value satırları).
class BotFollowSettings {
  final bool enabled;
  final int minHours;
  final int maxHours;
  final int minCount;
  final int maxCount;

  const BotFollowSettings({
    this.enabled = true,
    this.minHours = 0,
    this.maxHours = 72,
    this.minCount = 3,
    this.maxCount = 8,
  });

  BotFollowSettings copyWith({
    bool? enabled,
    int? minHours,
    int? maxHours,
    int? minCount,
    int? maxCount,
  }) {
    return BotFollowSettings(
      enabled: enabled ?? this.enabled,
      minHours: minHours ?? this.minHours,
      maxHours: maxHours ?? this.maxHours,
      minCount: minCount ?? this.minCount,
      maxCount: maxCount ?? this.maxCount,
    );
  }
}

/// Bot beğeni davranışının ayarları.
class BotLikeSettings {
  final bool enabled;
  final int minHours;
  final int maxHours;
  final int minCount;
  final int maxCount;
  final int lookbackDays;

  const BotLikeSettings({
    this.enabled = true,
    this.minHours = 1,
    this.maxHours = 48,
    this.minCount = 1,
    this.maxCount = 7,
    this.lookbackDays = 10,
  });

  BotLikeSettings copyWith({
    bool? enabled,
    int? minHours,
    int? maxHours,
    int? minCount,
    int? maxCount,
    int? lookbackDays,
  }) {
    return BotLikeSettings(
      enabled: enabled ?? this.enabled,
      minHours: minHours ?? this.minHours,
      maxHours: maxHours ?? this.maxHours,
      minCount: minCount ?? this.minCount,
      maxCount: maxCount ?? this.maxCount,
      lookbackDays: lookbackDays ?? this.lookbackDays,
    );
  }
}

/// Kitaplıktaki hazır gönderi metni.
class BotLibraryText {
  final String id;
  final String body;
  final String tone;
  final bool isActive;
  final int usedCount;

  const BotLibraryText({
    required this.id,
    required this.body,
    required this.tone,
    this.isActive = true,
    this.usedCount = 0,
  });

  factory BotLibraryText.fromMap(Map<String, dynamic> m) => BotLibraryText(
        id: m['id'] as String,
        body: m['body'] as String? ?? '',
        tone: m['tone'] as String? ?? 'gunluk',
        isActive: m['is_active'] as bool? ?? true,
        usedCount: (m['used_count'] as num?)?.toInt() ?? 0,
      );
}

/// Kitaplıktaki hazır gönderi görseli.
class BotLibraryImage {
  final String id;
  final String url;
  final String? caption;
  final String tone;
  final bool isActive;
  final int usedCount;

  const BotLibraryImage({
    required this.id,
    required this.url,
    this.caption,
    required this.tone,
    this.isActive = true,
    this.usedCount = 0,
  });

  factory BotLibraryImage.fromMap(Map<String, dynamic> m) => BotLibraryImage(
        id: m['id'] as String,
        url: m['url'] as String? ?? '',
        caption: m['caption'] as String?,
        tone: m['tone'] as String? ?? 'gunluk',
        isActive: m['is_active'] as bool? ?? true,
        usedCount: (m['used_count'] as num?)?.toInt() ?? 0,
      );
}

/// Kitaplık içeriğinin ton etiketleri. Anahtar DB'de saklanan değer,
/// değer arayüzde gösterilen Türkçe etikettir.
const Map<String, String> kBotContentTones = {
  'gunluk': 'Günlük',
  'mutlu': 'Mutlu',
  'sitem': 'Sitem',
  'kaygi': 'Kaygı',
  'sikayet': 'Şikâyet',
  'sevimli': 'Sevimli',
  'nostalji': 'Nostalji',
  'esnaf': 'Esnaf',
  'yemek': 'Yemek',
  'dayanisma': 'Dayanışma',
  'spor': 'Spor',
  'tesekkur': 'Teşekkür',
  'soru': 'Soru',
  'sehir': 'Şehir',
  'doga': 'Doğa',
  'hava': 'Hava',
  'motivasyon': 'Motivasyon',
};

class BotService {
  static const String _avatarBucket = 'avatars';
  static const String _postBucket = 'posts';

  final SupabaseClient _client;

  BotService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Botlar
  // ---------------------------------------------------------------------------
  Future<List<BotAccount>> listBots() async {
    final rows = await _client.rpc<List<dynamic>>('admin_bot_list');
    return rows
        .map((e) => BotAccount.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<BotStats> loadStats() async {
    final rows = await _client.rpc<List<dynamic>>('admin_bot_stats');
    if (rows.isEmpty) return const BotStats();
    return BotStats.fromMap((rows.first as Map).cast<String, dynamic>());
  }

  Future<String> createBot({
    required String fullName,
    required String username,
    String? bio,
    String? avatarUrl,
    String? location,
    String? website,
    String? persona,
  }) async {
    final id = await _client.rpc<String>('admin_bot_create', params: {
      'p_full_name': fullName,
      'p_username': username,
      'p_bio': bio,
      'p_avatar_url': avatarUrl,
      'p_location': location,
      'p_website': website,
      'p_persona': persona,
    });
    return id;
  }

  /// NULL geçilen alanlar sunucuda DEĞİŞTİRİLMEZ; boş string geçmek alanı
  /// temizler. Bu yüzden çağıran yalnız gerçekten değiştirdiği alanları
  /// göndermelidir.
  Future<void> updateBot({
    required String id,
    String? fullName,
    String? username,
    String? bio,
    String? avatarUrl,
    String? bannerUrl,
    String? location,
    String? website,
    String? persona,
    bool? isActive,
    bool? autoFollowEnabled,
    int? followWeight,
  }) async {
    await _client.rpc<void>('admin_bot_update', params: {
      'p_id': id,
      'p_full_name': fullName,
      'p_username': username,
      'p_bio': bio,
      'p_avatar_url': avatarUrl,
      'p_banner_url': bannerUrl,
      'p_location': location,
      'p_website': website,
      'p_persona': persona,
      'p_is_active': isActive,
      'p_auto_follow_enabled': autoFollowEnabled,
      'p_follow_weight': followWeight,
    });
  }

  Future<void> deleteBot(String id) async {
    await _client.rpc<void>('admin_bot_delete', params: {'p_id': id});
  }

  Future<int> seedDefaultBots() async {
    final created = await _client.rpc<int>('admin_bot_seed_defaults');
    return created;
  }

  /// Halihazırda kayıtlı üyeler için de takip planlar (yeni kurulumda
  /// mevcut üyelerin de takipçi kazanması için).
  Future<int> backfillFollows({int maxUsers = 500, int spreadHours = 72}) async {
    final affected = await _client.rpc<int>('admin_bot_backfill_follows', params: {
      'p_max_users': maxUsers,
      'p_spread_hours': spreadHours,
    });
    return affected;
  }

  /// Bekleyen takip/gönderi kuyruklarını hemen işler (cron'u beklemeden).
  Future<({int follows, int posts, int likesScheduled, int likes})>
      runQueuesNow() async {
    final rows = await _client.rpc<List<dynamic>>('admin_bot_run_queues');
    if (rows.isEmpty) {
      return (follows: 0, posts: 0, likesScheduled: 0, likes: 0);
    }
    final map = (rows.first as Map).cast<String, dynamic>();
    int v(String k) => (map[k] as num?)?.toInt() ?? 0;
    return (
      follows: v('follows_done'),
      posts: v('posts_published'),
      likesScheduled: v('likes_scheduled'),
      likes: v('likes_done'),
    );
  }

  // ---------------------------------------------------------------------------
  // Gönderi kuyruğu
  // ---------------------------------------------------------------------------
  Future<List<BotQueuedPost>> listQueue({String? status, int limit = 100}) async {
    final rows = await _client.rpc<List<dynamic>>('admin_bot_queue_list', params: {
      'p_status': status,
      'p_limit': limit,
    });
    return rows
        .map((e) => BotQueuedPost.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<String> upsertQueuedPost({
    String? id,
    String? botId,
    String? content,
    List<String> images = const [],
    String? location,
    DateTime? scheduledAt,
  }) async {
    final newId = await _client.rpc<String>('admin_bot_queue_upsert', params: {
      'p_id': id,
      'p_bot_id': botId,
      'p_content': content,
      'p_images': images,
      'p_location': location,
      'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
    });
    return newId;
  }

  Future<void> deleteQueuedPost(String id) async {
    await _client.rpc<void>('admin_bot_queue_delete', params: {'p_id': id});
  }

  // ---------------------------------------------------------------------------
  // Görsel yükleme
  // ---------------------------------------------------------------------------
  /// Bot profil fotoğrafı. `avatars` bucket'ında admin'in ALL yetkisi vardır
  /// (storage policy: `storage_admin_all_avatars_covers`).
  Future<String> uploadBotAvatar(String botId, XFile file) async {
    final bytes = await file.readAsBytes();
    final ext = _extensionOf(file.name, fallback: 'jpg');
    final path = 'avatar_$botId-${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _mimeOf(ext), upsert: true),
        );
    return _client.storage.from(_avatarBucket).getPublicUrl(path);
  }

  /// Bot gönderisi görseli. Uygulamanın normal gönderi akışıyla aynı bucket ve
  /// klasör düzenini kullanır (`posts/post_<botId>_<ts>_<i>.<ext>`).
  Future<String> uploadPostImage(String botId, XFile file, {int index = 0}) async {
    final bytes = await file.readAsBytes();
    final ext = _extensionOf(file.name, fallback: 'jpg');
    final path =
        'posts/post_${botId}_${DateTime.now().millisecondsSinceEpoch}_$index.$ext';

    await _client.storage.from(_postBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _mimeOf(ext), upsert: true),
        );
    return _client.storage.from(_postBucket).getPublicUrl(path);
  }

  Future<List<String>> uploadPostImages(String botId, List<XFile> files) async {
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      try {
        urls.add(await uploadPostImage(botId, files[i], index: i));
      } catch (e) {
        debugPrint('❌ Bot gönderi görseli yüklenemedi: $e');
        rethrow;
      }
    }
    return urls;
  }

  // ---------------------------------------------------------------------------
  // Otomatik takip ayarları
  // ---------------------------------------------------------------------------
  static const _settingKeys = <String>[
    'bot_auto_follow_enabled',
    'bot_follow_min_hours',
    'bot_follow_max_hours',
    'bot_follow_min_count',
    'bot_follow_max_count',
  ];

  static const _likeSettingKeys = <String>[
    'bot_auto_like_enabled',
    'bot_like_min_hours',
    'bot_like_max_hours',
    'bot_like_min_count',
    'bot_like_max_count',
    'bot_like_lookback_days',
  ];

  /// `app_settings` key/value satırlarını düz bir haritaya çevirir.
  /// Değerler jsonb kolonunda ya JSON string ("true") ya da JSON skaleri
  /// (true) olarak durabilir; iki biçimi de aynı şekilde okuyoruz.
  Future<Map<String, String>> _readSettings(List<String> keys) async {
    final rows = await _client
        .from('app_settings')
        .select('key,value')
        .inFilter('key', keys);

    final map = <String, String>{};
    for (final row in (rows as List)) {
      final m = (row as Map).cast<String, dynamic>();
      map[m['key'].toString()] =
          m['value']?.toString().replaceAll('"', '').trim() ?? '';
    }
    return map;
  }

  Future<BotFollowSettings> loadFollowSettings() async {
    try {
      final rows = await _client
          .from('app_settings')
          .select('key,value')
          .inFilter('key', _settingKeys);

      final map = <String, String>{};
      for (final row in (rows as List)) {
        final m = (row as Map).cast<String, dynamic>();
        map[m['key'].toString()] =
            m['value']?.toString().replaceAll('"', '').trim() ?? '';
      }

      int num(String key, int fallback) =>
          int.tryParse(map[key] ?? '') ?? fallback;

      const defaults = BotFollowSettings();
      final minH = num('bot_follow_min_hours', defaults.minHours);
      final maxH = num('bot_follow_max_hours', defaults.maxHours);
      final minC = num('bot_follow_min_count', defaults.minCount);
      final maxC = num('bot_follow_max_count', defaults.maxCount);

      return BotFollowSettings(
        enabled: (map['bot_auto_follow_enabled'] ?? 'true').toLowerCase() != 'false',
        minHours: minH,
        maxHours: maxH < minH ? minH : maxH,
        minCount: minC,
        maxCount: maxC < minC ? minC : maxC,
      );
    } catch (e) {
      debugPrint('⚠️ Bot takip ayarları okunamadı: $e');
      return const BotFollowSettings();
    }
  }

  Future<void> saveFollowSettings(BotFollowSettings settings) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = <Map<String, dynamic>>[
      {
        'key': 'bot_auto_follow_enabled',
        'value': settings.enabled ? 'true' : 'false',
        'updated_at': now,
      },
      {'key': 'bot_follow_min_hours', 'value': '${settings.minHours}', 'updated_at': now},
      {'key': 'bot_follow_max_hours', 'value': '${settings.maxHours}', 'updated_at': now},
      {'key': 'bot_follow_min_count', 'value': '${settings.minCount}', 'updated_at': now},
      {'key': 'bot_follow_max_count', 'value': '${settings.maxCount}', 'updated_at': now},
    ];
    await _client.from('app_settings').upsert(rows, onConflict: 'key');
  }

  Future<BotLikeSettings> loadLikeSettings() async {
    try {
      final map = await _readSettings(_likeSettingKeys);
      int num(String key, int fallback) =>
          int.tryParse(map[key] ?? '') ?? fallback;

      const d = BotLikeSettings();
      final minH = num('bot_like_min_hours', d.minHours);
      final maxH = num('bot_like_max_hours', d.maxHours);
      final minC = num('bot_like_min_count', d.minCount);
      final maxC = num('bot_like_max_count', d.maxCount);

      return BotLikeSettings(
        enabled:
            (map['bot_auto_like_enabled'] ?? 'true').toLowerCase() != 'false',
        minHours: minH,
        maxHours: maxH < minH ? minH : maxH,
        minCount: minC,
        maxCount: maxC < minC ? minC : maxC,
        lookbackDays: num('bot_like_lookback_days', d.lookbackDays),
      );
    } catch (e) {
      debugPrint('⚠️ Bot beğeni ayarları okunamadı: $e');
      return const BotLikeSettings();
    }
  }

  Future<void> saveLikeSettings(BotLikeSettings s) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('app_settings').upsert(<Map<String, dynamic>>[
      {
        'key': 'bot_auto_like_enabled',
        'value': s.enabled ? 'true' : 'false',
        'updated_at': now,
      },
      {'key': 'bot_like_min_hours', 'value': '${s.minHours}', 'updated_at': now},
      {'key': 'bot_like_max_hours', 'value': '${s.maxHours}', 'updated_at': now},
      {'key': 'bot_like_min_count', 'value': '${s.minCount}', 'updated_at': now},
      {'key': 'bot_like_max_count', 'value': '${s.maxCount}', 'updated_at': now},
      {
        'key': 'bot_like_lookback_days',
        'value': '${s.lookbackDays}',
        'updated_at': now,
      },
    ], onConflict: 'key');
  }

  // ---------------------------------------------------------------------------
  // İçerik kitaplığı
  // ---------------------------------------------------------------------------
  Future<List<BotLibraryText>> listLibraryTexts({String? tone, int limit = 500}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'admin_bot_library_texts',
      params: {'p_tone': tone, 'p_limit': limit},
    );
    return rows
        .map((e) => BotLibraryText.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<BotLibraryImage>> listLibraryImages({String? tone, int limit = 300}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'admin_bot_library_images',
      params: {'p_tone': tone, 'p_limit': limit},
    );
    return rows
        .map((e) => BotLibraryImage.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<String> upsertLibraryText({
    String? id,
    required String body,
    String tone = 'gunluk',
    bool isActive = true,
  }) async {
    return await _client.rpc<String>('admin_bot_library_text_upsert', params: {
      'p_id': id,
      'p_body': body,
      'p_tone': tone,
      'p_is_active': isActive,
    });
  }

  Future<String> upsertLibraryImage({
    String? id,
    String? url,
    String? caption,
    String tone = 'gunluk',
    bool isActive = true,
  }) async {
    return await _client.rpc<String>('admin_bot_library_image_upsert', params: {
      'p_id': id,
      'p_url': url,
      'p_caption': caption,
      'p_tone': tone,
      'p_is_active': isActive,
    });
  }

  Future<void> deleteLibraryEntry({required String kind, required String id}) async {
    await _client.rpc<void>('admin_bot_library_delete', params: {
      'p_kind': kind,
      'p_id': id,
    });
  }

  /// Yerel bir görseli `posts` bucket'ına yükleyip kitaplığa kaydeder.
  /// Dosya adı bir bota değil kitaplığa ait olduğu için `library` öneki alır.
  Future<BotLibraryImage> addLibraryImage(
    XFile file, {
    String? caption,
    String tone = 'gunluk',
  }) async {
    final bytes = await file.readAsBytes();
    final ext = _extensionOf(file.name, fallback: 'jpg');
    final path =
        'posts/library_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from(_postBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _mimeOf(ext), upsert: true),
        );
    final url = _client.storage.from(_postBucket).getPublicUrl(path);

    final id = await upsertLibraryImage(url: url, caption: caption, tone: tone);
    return BotLibraryImage(id: id, url: url, caption: caption, tone: tone);
  }

  /// Kitaplıktaki metinleri botlara DÜZENSİZ dağıtarak gönderiye çevirir.
  Future<int> publishFromLibrary({
    int total = 60,
    int spreadDays = 180,
    int imagePercent = 35,
  }) async {
    return await _client.rpc<int>('admin_bot_publish_from_library', params: {
      'p_total': total,
      'p_spread_days': spreadDays,
      'p_image_percent': imagePercent,
    });
  }

  // ---------------------------------------------------------------------------
  String _extensionOf(String name, {required String fallback}) {
    final parts = name.split('.');
    if (parts.length < 2) return fallback;
    final ext = parts.last.toLowerCase();
    const allowed = {'jpg', 'jpeg', 'png', 'webp'};
    return allowed.contains(ext) ? ext : fallback;
  }

  String _mimeOf(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
