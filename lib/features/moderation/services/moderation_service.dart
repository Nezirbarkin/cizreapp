import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/moderation_models.dart';

/// Moderasyon (Görev 4.6): yetki okuma ve moderatör işlemleri.
///
/// Yetki kararı sunucudadır (`auth_is_moderator(scope)`, RLS ve `mod_*`
/// RPC'leri); buradaki [cachedAccess] yalnız menü/panel görünürlüğü içindir.
class ModerationService {
  ModerationService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  static ModerationAccess _cached = ModerationAccess.none;
  static String? _cachedFor;

  static String? get _currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Son okunan yetki; hesap değiştiyse boş (sızmasın).
  static ModerationAccess get cachedAccess =>
      _cachedFor != null && _cachedFor == _currentUserId ? _cached : ModerationAccess.none;

  /// Yetkiyi sunucudan okur. ASLA hata fırlatmaz (okunamazsa önceki/boş).
  static Future<ModerationAccess> fetchMyAccess({SupabaseClient? client}) async {
    final userId = _currentUserId;
    if (userId == null) return ModerationAccess.none;
    try {
      final data = await (client ?? Supabase.instance.client).rpc('my_moderation');
      _cached = ModerationAccess.fromJson(data);
      _cachedFor = userId;
    } catch (e) {
      debugPrint('⚠️ Moderasyon yetkisi okunamadı: $e');
    }
    return cachedAccess;
  }

  @visibleForTesting
  static void setCacheForTesting(ModerationAccess? access, {String? userId}) {
    _cached = access ?? ModerationAccess.none;
    _cachedFor = access == null ? null : userId;
  }

  // ---------------------------------------------------------------- şikayetler

  /// status: 'open' | 'closed' | 'all'
  Future<ModReportsPage> reports({String status = 'open', int limit = 30, int offset = 0}) async {
    final data = await _client.rpc(
      'mod_reports',
      params: {'p_status': status, 'p_limit': limit, 'p_offset': offset},
    );
    return ModReportsPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// status: 'reviewing' | 'resolved' | 'rejected'. [hidePost] gönderi
  /// şikayetinde gönderiyi de gizler ('content' yetkisi gerekir).
  Future<void> resolveReport(
    ModReport report, {
    required String status,
    String? response,
    bool hidePost = false,
  }) async {
    await _client.rpc(
      'mod_resolve_report',
      params: {
        'p_kind': report.kind,
        'p_id': report.id,
        'p_status': status,
        'p_response': _clean(response),
        'p_hide_post': hidePost,
      },
    );
  }

  // ---------------------------------------------------------------- içerik

  /// filter: 'recent' | 'reported' | 'hidden'
  Future<ModPostsPage> posts({String filter = 'recent', String? search, int limit = 30, int offset = 0}) async {
    final data = await _client.rpc(
      'mod_posts',
      params: {'p_filter': filter, 'p_search': _clean(search), 'p_limit': limit, 'p_offset': offset},
    );
    return ModPostsPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Gizle (active=false) ya da geri aç; durum değiştiyse true.
  Future<bool> setPostActive(String postId, bool active, {String? reason}) async {
    final data = await _client.rpc(
      'mod_set_post_active',
      params: {'p_post_id': postId, 'p_active': active, 'p_reason': _clean(reason)},
    );
    return data is Map && data['changed'] == true;
  }

  // ---------------------------------------------------------------- ilanlar

  Future<ModIlansPage> pendingIlanlar({int limit = 30, int offset = 0}) async {
    final data = await _client.rpc('mod_pending_ilanlar', params: {'p_limit': limit, 'p_offset': offset});
    return ModIlansPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> reviewIlan(String ilanId, {required bool approve, String? reason}) async {
    await _client.rpc(
      'mod_review_ilan',
      params: {'p_ilan_id': ilanId, 'p_approve': approve, 'p_reason': _clean(reason)},
    );
  }

  static String? _clean(String? text) {
    final t = text?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  static String errorMessage(Object error) {
    if (error is PostgrestException) {
      switch (error.hint) {
        case 'MOD_REPORT_NOT_FOUND':
          return 'Şikayet bulunamadı (silinmiş olabilir).';
        case 'MOD_POST_NOT_FOUND':
          return 'Gönderi bulunamadı (silinmiş olabilir).';
        case 'MOD_SCOPE_MISSING':
          return 'Gönderi gizlemek için İçerik yetkin olmalı.';
        case 'MOD_ILAN_NOT_PENDING':
          return 'Bu ilan artık onay beklemiyor.';
        case 'MOD_REASON_REQUIRED':
          return 'Ret nedeni yazmalısın.';
        case 'ILAN_NOT_FOUND':
          return 'İlan bulunamadı.';
        case 'MOD_INVALID':
          return 'Geçersiz işlem.';
        case 'MOD_CATEGORY_FORBIDDEN':
          return 'Bu kategori senin moderasyon alanında değil.';
      }
      if (error.code == '42501') return 'Bu işlem için moderatör yetkin yok.';
      return error.message;
    }
    return 'İşlem tamamlanamadı: $error';
  }
}
