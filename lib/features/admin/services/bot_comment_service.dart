import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin > Bot Hesapları > Yorumlar (Görev 4.7).
///
/// Manuel yorum (şimdi ya da zamanlı), otomatik yorum ayarları, kuyruk ve yorum
/// kitaplığı. Yazmalar yönetici RPC'leriyle (`admin_bot_comment*`); ayarlar
/// diğer bot ayarları gibi `app_settings`e düz metin yazılır.
class BotCommentSettings {
  const BotCommentSettings({
    this.enabled = false,
    this.probability = 25,
    this.minCount = 1,
    this.maxCount = 1,
    this.minHours = 0,
    this.maxHours = 6,
    this.lookbackDays = 2,
  });

  final bool enabled;

  /// Uygun gönderinin otomatik yorum alma olasılığı (%).
  final int probability;
  final int minCount;
  final int maxCount;
  final int minHours;
  final int maxHours;
  final int lookbackDays;

  BotCommentSettings copyWith({
    bool? enabled,
    int? probability,
    int? minCount,
    int? maxCount,
    int? minHours,
    int? maxHours,
    int? lookbackDays,
  }) => BotCommentSettings(
    enabled: enabled ?? this.enabled,
    probability: probability ?? this.probability,
    minCount: minCount ?? this.minCount,
    maxCount: maxCount ?? this.maxCount,
    minHours: minHours ?? this.minHours,
    maxHours: maxHours ?? this.maxHours,
    lookbackDays: lookbackDays ?? this.lookbackDays,
  );
}

String? _text(Object? value) {
  final t = value?.toString().trim();
  return t == null || t.isEmpty ? null : t;
}

DateTime? _time(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

/// Kuyruktaki (ya da yazılmış) bot yorumu.
class BotCommentJob {
  const BotCommentJob({
    required this.id,
    required this.body,
    required this.source,
    required this.status,
    required this.createdAt,
    this.dueAt,
    this.processedAt,
    this.errorMessage,
    this.commentId,
    this.botName,
    this.botUsername,
    this.botAvatarUrl,
    this.postId,
    this.postPreview,
    this.postAuthorName,
  });

  final String id;
  final String body;

  /// 'auto' | 'manual'
  final String source;

  /// 'pending' | 'done' | 'skipped' | 'failed' | 'cancelled'
  final String status;
  final DateTime createdAt;
  final DateTime? dueAt;
  final DateTime? processedAt;
  final String? errorMessage;
  final String? commentId;
  final String? botName;
  final String? botUsername;
  final String? botAvatarUrl;
  final String? postId;
  final String? postPreview;
  final String? postAuthorName;

  bool get isPending => status == 'pending';

  bool get isDone => status == 'done';

  String get statusLabel => switch (status) {
    'pending' => 'Bekliyor',
    'done' => 'Yazıldı',
    'skipped' => 'Atlandı',
    'failed' => 'Hata',
    'cancelled' => 'İptal',
    _ => status,
  };

  factory BotCommentJob.fromJson(Map<String, dynamic> json) {
    final bot = json['bot'];
    final post = json['post'];
    return BotCommentJob(
      id: json['id'].toString(),
      body: _text(json['body']) ?? '',
      source: json['source'] == 'manual' ? 'manual' : 'auto',
      status: _text(json['status']) ?? 'pending',
      createdAt: _time(json['created_at']) ?? DateTime.now(),
      dueAt: _time(json['due_at']),
      processedAt: _time(json['processed_at']),
      errorMessage: _text(json['error_message']),
      commentId: _text(json['comment_id']),
      botName: bot is Map ? _text(bot['name']) : null,
      botUsername: bot is Map ? _text(bot['username']) : null,
      botAvatarUrl: bot is Map ? _text(bot['avatar_url']) : null,
      postId: post is Map ? _text(post['id']) : null,
      postPreview: post is Map ? _text(post['preview']) : null,
      postAuthorName: post is Map ? _text(post['author_name']) : null,
    );
  }
}

class BotCommentJobsPage {
  const BotCommentJobsPage({
    this.rows = const [],
    this.total = 0,
    this.pending = 0,
    this.done24h = 0,
    this.failed24h = 0,
    this.libraryActive = 0,
  });

  final List<BotCommentJob> rows;
  final int total;
  final int pending;
  final int done24h;
  final int failed24h;
  final int libraryActive;

  factory BotCommentJobsPage.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map?) ?? const {};
    return BotCommentJobsPage(
      rows: [
        for (final raw in (json['rows'] as List? ?? const []).whereType<Map>())
          BotCommentJob.fromJson(Map<String, dynamic>.from(raw)),
      ],
      total: _int(json['total']),
      pending: _int(summary['pending']),
      done24h: _int(summary['done_24h']),
      failed24h: _int(summary['failed_24h']),
      libraryActive: _int(summary['library_active']),
    );
  }
}

/// Kitaplıktaki hazır yorum.
class BotCommentTemplate {
  const BotCommentTemplate({
    required this.id,
    required this.body,
    this.tone = 'genel',
    this.isActive = true,
    this.useCount = 0,
  });

  final String id;
  final String body;
  final String tone;
  final bool isActive;
  final int useCount;

  factory BotCommentTemplate.fromJson(Map<String, dynamic> json) => BotCommentTemplate(
    id: json['id'].toString(),
    body: _text(json['body']) ?? '',
    tone: _text(json['tone']) ?? 'genel',
    isActive: json['is_active'] != false,
    useCount: _int(json['use_count']),
  );
}

/// Manuel yorum için seçilebilir gönderi.
class BotPostOption {
  const BotPostOption({
    required this.id,
    required this.preview,
    this.createdAt,
    this.commentsCount = 0,
    this.authorName,
    this.authorIsBot = false,
  });

  final String id;
  final String preview;
  final DateTime? createdAt;
  final int commentsCount;
  final String? authorName;
  final bool authorIsBot;

  factory BotPostOption.fromJson(Map<String, dynamic> json) => BotPostOption(
    id: json['id'].toString(),
    preview: _text(json['preview']) ?? 'Gönderi',
    createdAt: _time(json['created_at']),
    commentsCount: _int(json['comments_count']),
    authorName: _text(json['author_name']),
    authorIsBot: json['author_is_bot'] == true,
  );
}

class BotCommentService {
  BotCommentService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  /// Sunucudaki CHECK listesiyle aynı sıra.
  static const tones = ['genel', 'tebrik', 'soru', 'mizah', 'yerel', 'destek'];

  static String toneLabel(String tone) => switch (tone) {
    'genel' => 'Genel',
    'tebrik' => 'Tebrik',
    'soru' => 'Soru',
    'mizah' => 'Mizah',
    'yerel' => 'Yerel',
    'destek' => 'Destek',
    _ => tone,
  };

  static const _settingKeys = [
    'bot_auto_comment_enabled',
    'bot_comment_probability',
    'bot_comment_min_count',
    'bot_comment_max_count',
    'bot_comment_min_hours',
    'bot_comment_max_hours',
    'bot_comment_lookback_days',
  ];

  Future<BotCommentSettings> loadSettings() async {
    try {
      final rows = await _client.from('app_settings').select('key,value').inFilter('key', _settingKeys);
      final map = <String, String>{};
      for (final row in (rows as List).whereType<Map>()) {
        map[row['key'].toString()] = row['value']?.toString().replaceAll('"', '').trim() ?? '';
      }
      int number(String key, int fallback) => int.tryParse(map[key] ?? '') ?? fallback;
      const d = BotCommentSettings();
      final minCount = number('bot_comment_min_count', d.minCount);
      final maxCount = number('bot_comment_max_count', d.maxCount);
      final minHours = number('bot_comment_min_hours', d.minHours);
      final maxHours = number('bot_comment_max_hours', d.maxHours);
      return BotCommentSettings(
        enabled: (map['bot_auto_comment_enabled'] ?? 'false').toLowerCase() == 'true',
        probability: number('bot_comment_probability', d.probability).clamp(0, 100),
        minCount: minCount,
        maxCount: maxCount < minCount ? minCount : maxCount,
        minHours: minHours,
        maxHours: maxHours < minHours ? minHours : maxHours,
        lookbackDays: number('bot_comment_lookback_days', d.lookbackDays),
      );
    } catch (e) {
      debugPrint('⚠️ Bot yorum ayarları okunamadı: $e');
      return const BotCommentSettings();
    }
  }

  Future<void> saveSettings(BotCommentSettings s) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('app_settings').upsert([
      {'key': 'bot_auto_comment_enabled', 'value': s.enabled ? 'true' : 'false', 'updated_at': now},
      {'key': 'bot_comment_probability', 'value': '${s.probability}', 'updated_at': now},
      {'key': 'bot_comment_min_count', 'value': '${s.minCount}', 'updated_at': now},
      {'key': 'bot_comment_max_count', 'value': '${s.maxCount}', 'updated_at': now},
      {'key': 'bot_comment_min_hours', 'value': '${s.minHours}', 'updated_at': now},
      {'key': 'bot_comment_max_hours', 'value': '${s.maxHours}', 'updated_at': now},
      {'key': 'bot_comment_lookback_days', 'value': '${s.lookbackDays}', 'updated_at': now},
    ], onConflict: 'key');
  }

  /// [dueAt] null ya da geçmiş = hemen yazılır ('done'); ileri tarih = kuyruğa
  /// ('pending').
  Future<({String status, String jobId, String? commentId})> comment({
    required String botId,
    required String postId,
    required String body,
    DateTime? dueAt,
  }) async {
    final data = await _client.rpc(
      'admin_bot_comment',
      params: {
        'p_bot_id': botId,
        'p_post_id': postId,
        'p_body': body.trim(),
        'p_due_at': dueAt?.toUtc().toIso8601String(),
      },
    );
    final json = data is Map ? data : const {};
    return (
      status: json['status']?.toString() ?? 'pending',
      jobId: json['job_id']?.toString() ?? '',
      commentId: _text(json['comment_id']),
    );
  }

  /// status: 'pending' | 'done' | 'failed' | 'all'
  Future<BotCommentJobsPage> jobs({String status = 'pending', int limit = 30, int offset = 0}) async {
    final data = await _client.rpc(
      'admin_bot_comment_jobs',
      params: {'p_status': status, 'p_limit': limit, 'p_offset': offset},
    );
    return BotCommentJobsPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Bekleyeni iptal eder ('cancelled') ya da yazılmış yorumu siler ('deleted').
  Future<String> cancel(String jobId) async {
    final data = await _client.rpc('admin_bot_comment_cancel', params: {'p_job_id': jobId});
    return (data is Map ? data['status']?.toString() : null) ?? 'cancelled';
  }

  Future<List<BotCommentTemplate>> library() async {
    final data = await _client.rpc('admin_bot_comment_library');
    return [
      for (final raw in (data as List? ?? const []).whereType<Map>())
        BotCommentTemplate.fromJson(Map<String, dynamic>.from(raw)),
    ];
  }

  Future<String> upsertTemplate({String? id, required String body, required String tone, required bool isActive}) async {
    final data = await _client.rpc(
      'admin_bot_comment_library_upsert',
      params: {'p_id': id, 'p_body': body.trim(), 'p_tone': tone, 'p_is_active': isActive},
    );
    return data.toString();
  }

  Future<void> deleteTemplate(String id) async {
    await _client.rpc('admin_bot_comment_library_delete', params: {'p_id': id});
  }

  Future<List<BotPostOption>> recentPosts({String? search, int limit = 20}) async {
    final text = search?.trim();
    final data = await _client.rpc(
      'admin_bot_recent_posts',
      params: {'p_search': text == null || text.isEmpty ? null : text, 'p_limit': limit},
    );
    return [
      for (final raw in (data as List? ?? const []).whereType<Map>())
        BotPostOption.fromJson(Map<String, dynamic>.from(raw)),
    ];
  }

  Future<({int scheduled, int processed})> runQueue() async {
    final data = await _client.rpc('admin_bot_run_comment_queue');
    final json = data is Map ? data : const {};
    return (scheduled: _int(json['scheduled']), processed: _int(json['processed']));
  }

  static String errorMessage(Object error) {
    if (error is PostgrestException) {
      switch (error.hint) {
        case 'BOT_COMMENT_INVALID':
          return 'Yorum metni boş ya da çok uzun.';
        case 'BOT_INACTIVE':
          return 'Bot bulunamadı ya da pasif.';
        case 'BOT_POST_UNAVAILABLE':
          return 'Gönderi bulunamadı ya da gizli.';
        case 'BOT_COMMENT_TOO_LATE':
          return 'En çok 30 gün sonrasına zamanlanabilir.';
        case 'BOT_COMMENT_FAILED':
          return 'Yorum yazılamadı; gönderi ya da bot uygun değil.';
        case 'BOT_JOB_NOT_FOUND':
          return 'Kayıt bulunamadı.';
        case 'BOT_JOB_CLOSED':
          return 'Bu kayıt artık değiştirilemez.';
        case 'BOT_COMMENT_DUPLICATE':
          return 'Bu yorum kitaplıkta zaten var.';
        case 'BOT_COMMENT_TONE_INVALID':
          return 'Geçersiz ton.';
      }
      if (error.code == '42501') return 'Bu işlem için yönetici yetkisi gerekli.';
      return error.message;
    }
    return 'İşlem tamamlanamadı: $error';
  }
}
