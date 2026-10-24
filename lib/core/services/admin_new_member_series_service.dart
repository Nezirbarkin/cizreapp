import 'package:supabase_flutter/supabase_flutter.dart';

/// Yeni üye karşılama serisinin bir adımı (`new_member_message_steps` +
/// teslim sayaçları). Sunucu: 20261024000001_new_member_messages.
class NewMemberStep {
  const NewMemberStep({
    required this.id,
    required this.stepKey,
    required this.sortOrder,
    required this.delayMinutes,
    required this.title,
    required this.body,
    required this.icon,
    required this.condition,
    required this.isActive,
    required this.respectQuietHours,
    this.voiceText,
    this.voiceGender,
    this.actionRoute,
    this.sent = 0,
    this.skipped = 0,
    this.failed = 0,
    this.read = 0,
    this.lastSentAt,
  });

  final String id;
  final String stepKey;
  final int sortOrder;
  final int delayMinutes;
  final String title;
  final String body;
  final String? voiceText;
  final String? voiceGender;
  final String icon;
  final String condition;
  final String? actionRoute;
  final bool isActive;
  final bool respectQuietHours;
  final int sent;
  final int skipped;
  final int failed;
  final int read;
  final DateTime? lastSentAt;

  /// Okunma oranı (yüzde); gönderim yoksa null.
  int? get readPercent => sent == 0 ? null : (read * 100 / sent).round();

  factory NewMemberStep.fromJson(Map<String, dynamic> j) {
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return NewMemberStep(
      id: j['id'] as String,
      stepKey: j['step_key'] as String? ?? '',
      sortOrder: i(j['sort_order']),
      delayMinutes: i(j['delay_minutes']),
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      voiceText: j['voice_text'] as String?,
      voiceGender: j['voice_gender'] as String?,
      icon: j['icon'] as String? ?? 'info',
      condition: j['condition'] as String? ?? 'always',
      actionRoute: j['action_route'] as String?,
      isActive: j['is_active'] as bool? ?? false,
      respectQuietHours: j['respect_quiet_hours'] as bool? ?? true,
      sent: i(j['sent']),
      skipped: i(j['skipped']),
      failed: i(j['failed']),
      read: i(j['read']),
      lastSentAt: DateTime.tryParse('${j['last_sent_at'] ?? ''}'),
    );
  }
}

class NewMemberSeries {
  const NewMemberSeries({required this.enabled, required this.steps});

  final bool enabled;
  final List<NewMemberStep> steps;

  factory NewMemberSeries.fromJson(Map<String, dynamic> j) {
    final raw = j['steps'];
    return NewMemberSeries(
      enabled: j['enabled'] == true,
      steps: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => NewMemberStep.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// Adımın gönderilme koşulu (sunucudaki `condition` değerleri).
const Map<String, String> kNewMemberConditions = {
  'always': 'Herkese',
  'no_avatar': 'Profil fotoğrafı yoksa',
  'no_post': 'Hiç gönderisi yoksa',
  'no_order': 'Hiç siparişi yoksa',
};

/// Bildirime dokununca açılacak ekran (sunucudaki `action_route` değerleri).
const Map<String, String> kNewMemberRoutes = {
  '': 'Yalnız bildirim detayı',
  'edit_profile': 'Profil düzenleme',
  'create_post': 'Gönderi oluşturma',
  'market': 'Dükkânlar (ana sayfa)',
  'okey': '101 Okey lobisi',
};

/// "Kayıttan 1 gün 3 sa sonra" gibi okunur gecikme.
String newMemberDelayLabel(int minutes) {
  if (minutes <= 0) return 'Hemen';
  final d = minutes ~/ 1440;
  final h = (minutes % 1440) ~/ 60;
  final m = minutes % 60;
  final parts = <String>[
    if (d > 0) '$d gün',
    if (h > 0) '$h sa',
    if (m > 0) '$m dk',
  ];
  return parts.join(' ');
}

/// Admin > Bildirim merkezi > Yeni üye serisi. Tüm çağrılar admin RPC'leri
/// (tablolar istemciye kapalı).
class AdminNewMemberSeriesService {
  AdminNewMemberSeriesService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  Future<NewMemberSeries> load() async {
    final res = await _db.rpc('admin_new_member_steps');
    return NewMemberSeries.fromJson(
      res is Map ? Map<String, dynamic>.from(res) : const {},
    );
  }

  Future<void> setEnabled(bool enabled) async {
    await _db.rpc(
      'admin_set_new_member_messages_enabled',
      params: {'p_enabled': enabled},
    );
  }

  Future<void> setStepActive(String id, bool active) async {
    await _db.rpc(
      'admin_set_new_member_step_active',
      params: {'p_id': id, 'p_active': active},
    );
  }

  /// [id] null ise yeni adım eklenir.
  Future<NewMemberStep> saveStep({
    String? id,
    required String title,
    required String body,
    String? voiceText,
    String? voiceGender,
    required String icon,
    required int delayMinutes,
    required String condition,
    String? actionRoute,
    required bool respectQuietHours,
    required bool isActive,
  }) async {
    final res = await _db.rpc(
      'admin_upsert_new_member_step',
      params: {
        'p_id': id,
        'p_title': title,
        'p_body': body,
        'p_voice_text': voiceText,
        'p_voice_gender': voiceGender,
        'p_icon': icon,
        'p_delay_minutes': delayMinutes,
        'p_condition': condition,
        'p_action_route': (actionRoute ?? '').isEmpty ? null : actionRoute,
        'p_respect_quiet_hours': respectQuietHours,
        'p_is_active': isActive,
      },
    );
    return NewMemberStep.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> deleteStep(String id) async {
    await _db.rpc('admin_delete_new_member_step', params: {'p_id': id});
  }

  /// Adımı adminin kendisine gönderir (sayaçlara girmez).
  Future<void> sendTest(String id) async {
    await _db.rpc('admin_send_new_member_step_test', params: {'p_id': id});
  }
}
