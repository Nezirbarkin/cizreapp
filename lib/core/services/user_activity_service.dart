import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kullanıcı eylem günlüğüne (Admin > Loglar > Kullanıcı Eylemleri) istemci
/// tarafı eylem yazar.
///
/// Gönderi/yorum/beğeni/takip/sipariş/mesaj gibi veritabanına zaten yazılan
/// eylemleri SUNUCU tetikleyicileri kaydeder (bkz.
/// 20260920000001_user_activity_logs.sql) — bu servis yalnızca tablosu
/// olmayan eylemler içindir: giriş, çıkış, uygulama açılışı.
///
/// ASLA hata fırlatmaz ve asla beklenmez (fire-and-forget): günlük tutma hiçbir
/// koşulda kullanıcı akışını yavaşlatmamalı ya da bozmamalı. Sunucu yalnızca
/// izinli eylem adlarını kabul eder; misafir (oturumsuz) eylemler yazılmaz.
class UserActivityService {
  UserActivityService._();
  static final UserActivityService instance = UserActivityService._();

  /// Aynı eylemin art arda yazılmasını engeller (ör. oturum yenilemesinin
  /// tetiklediği tekrarlı `signedIn` olayları).
  static const _throttle = Duration(seconds: 30);
  final Map<String, DateTime> _lastLoggedAt = {};

  String get _platform =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  /// Bir eylemi kaydeder. [action] sunucudaki izinli listede olmalıdır.
  Future<void> log(
    String action, {
    String category = 'app',
    String? entityType,
    String? entityId,
    String? summary,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;

      final key = '$action|${entityId ?? ''}';
      final now = DateTime.now();
      final last = _lastLoggedAt[key];
      if (last != null && now.difference(last) < _throttle) return;
      _lastLoggedAt[key] = now;

      await client.rpc(
        'log_user_action',
        params: {
          'p_action': action,
          'p_category': category,
          'p_entity_type': entityType,
          'p_entity_id': entityId,
          'p_summary': summary,
          'p_metadata': metadata ?? const <String, dynamic>{},
          'p_platform': _platform,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('UserActivityService.log($action): $e');
    }
  }

  /// Supabase auth olaylarını eyleme çevirir (bkz. main.dart'taki dinleyici).
  ///
  /// - `initialSession` (oturum açıkken uygulama açıldı) → app_open
  /// - `signedIn` → login
  void onAuthEvent(AuthChangeEvent event, Session? session) {
    if (session == null) return;
    switch (event) {
      case AuthChangeEvent.initialSession:
        unawaited(
          log('app_open', category: 'auth', summary: 'Uygulamayı açtı'),
        );
        break;
      case AuthChangeEvent.signedIn:
        unawaited(log('login', category: 'auth', summary: 'Giriş yaptı'));
        break;
      default:
        break;
    }
  }
}
