// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime Presence servisi.
///
/// Tek sorumluluk: global bir presence channel'a track/untrack yaparak
/// online kullanıcı listesini bir [Stream] üzerinden UI'a yaymak.
///
/// Kullanım:
/// - Login olduktan sonra bir kez [startGlobalPresence] çağrılır.
/// - Uygulama arka plana düşünce [pauseGlobal], öne gelince [resumeGlobal].
/// - UI tarafı [onlineUsersStream]'i dinler.
class PresenceService {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  RealtimeChannel? _globalChannel;
  String? _userId;
  bool _onlineEnabledPref = true;

  final StreamController<List<String>> _onlineUsersController =
      StreamController<List<String>>.broadcast();

  /// Admin panelindeki platform kırılımı (iOS/Android/Web) için
  /// profiles.platform'a yazılır. Değer aralığı DB CHECK ile sınırlı:
  /// 'ios' | 'android' | 'web' | 'unknown'.
  static String _currentPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {
      // Desteklenmeyen platform (masaüstü vb.)
    }
    return 'unknown';
  }

  /// Online kullanıcı id listesi (self dahil).
  Stream<List<String>> get onlineUsersStream => _onlineUsersController.stream;

  /// Global presence channel'ı başlatır. Eski channel varsa unsubscribe eder.
  /// ÖNEMLI DÜZELTME (2026-07-02):
  ///   - Retry mekanizması: track başarısız olursa tekrar dene
  ///   - DB'deki is_online=true olarak da işaretle (fallback)
  ///   - Presence state değişikliklerini de logla
  /// DÜZELTME (2026-07-10):
  ///   - is_online_enabled kontrolü: kullanıcı çevrimdışı tercih etmişse
  ///     is_online=true yazma, sadece last_seen güncelle
  Future<void> startGlobalPresence(String userId) async {
    _userId = userId;

    try {
      await _globalChannel?.unsubscribe();
    } catch (_) {}
    _globalChannel = null;

    // ÖNCE kullanıcının çevrimiçi görünme tercihini kontrol et
    final isOnlineEnabled = await _isOnlineEnabled(userId);
    _onlineEnabledPref = isOnlineEnabled;

    // Tercih açıksa is_online=true yaz, kapalıysa sadece last_seen güncelle.
    // profiles tablosuna doğrudan UPDATE yetkisi authenticated rolünden
    // kaldırıldığı için (bkz. 20260803000006 migration) set_my_presence
    // SECURITY DEFINER RPC'si kullanılıyor.
    try {
      await Supabase.instance.client.rpc(
        'set_my_presence',
        params: {'p_is_online': isOnlineEnabled, 'p_platform': _currentPlatform()},
      );
      debugPrint('✅ DB is_online=$isOnlineEnabled set for user=$userId');
    } catch (e) {
      debugPrint('⚠️ DB is_online update failed: $e');
    }

    final channel = Supabase.instance.client.channel('presence:global');

    // Her sync'te online kullanıcı id'lerini UI'a ilet.
    channel.onPresenceSync((_) {
      if (_globalChannel == null) return;
      try {
        final state = _globalChannel!.presenceState();
        final ids = state
            .expand((p) => p.presences)
            .map((pres) => pres.payload['user_id'] as String?)
            .whereType<String>()
            .toSet()
            .toList();
        _onlineUsersController.add(ids);
        debugPrint('👥 Presence sync: ${ids.length} online users');
      } catch (e) {
        debugPrint('presence sync error: $e');
      }
    });

    // JOIN: Yeni biri online olduğunda
    channel.onPresenceJoin((payload) {
      debugPrint('👋 User joined: ${payload.key}');
      _broadcastOnlineUsers();
    });

    // LEAVE: Bir kullanıcı çevrimdışı olduğunda
    channel.onPresenceLeave((payload) {
      debugPrint('👋 User left: ${payload.key}');
      _broadcastOnlineUsers();
    });

    _globalChannel = channel;

    channel.subscribe((status, error) async {
      debugPrint('📡 Presence channel status: $status');
      if (status == RealtimeSubscribeStatus.subscribed && _onlineEnabledPref) {
        await _trackWithRetry(channel, userId, 0);
      }
      if (error != null) {
        debugPrint('presence subscribe error: $error');
      }
    });
  }

  /// Track'i retry mekanizması ile dene
  Future<void> _trackWithRetry(
    RealtimeChannel channel,
    String userId,
    int attempt,
  ) async {
    const maxAttempts = 3;
    const baseDelay = Duration(seconds: 1);

    try {
      await channel.track({
        'user_id': userId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
        'platform': defaultTargetPlatform.name,
      });
      debugPrint('✅ Presence tracked for user=$userId (attempt=$attempt)');
    } catch (e) {
      debugPrint('⚠️ Presence track attempt $attempt failed: $e');
      if (attempt < maxAttempts - 1) {
        final delay = baseDelay * (attempt + 1);
        await Future.delayed(delay);
        await _trackWithRetry(channel, userId, attempt + 1);
      }
    }
  }

  /// Mevcut online listesini broadcast et
  void _broadcastOnlineUsers() {
    if (_globalChannel == null) return;
    try {
      final state = _globalChannel!.presenceState();
      final ids = state
          .expand((p) => p.presences)
          .map((pres) => pres.payload['user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      _onlineUsersController.add(ids);
    } catch (e) {
      debugPrint('broadcast error: $e');
    }
  }

  /// Kullanıcının çevrimiçi görünme tercihini kontrol eder.
  /// DÜZELTME (2026-07-10): Presence her zaman is_online=true yazıyordu,
  /// bu da kullanıcının çevrimdışı tercihini eziyordu.
  Future<bool> _isOnlineEnabled(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('is_online_enabled')
          .eq('id', userId)
          .maybeSingle();
      // Sütun yoksa veya hata durumunda default true döner (eski davranış)
      return response?['is_online_enabled'] as bool? ?? true;
    } catch (e) {
      debugPrint('⚠️ _isOnlineEnabled check failed: $e');
      return true; // Hata durumunda default açık kabul et
    }
  }

  /// Uygulama arka plana atılınça track'i bırak.
  Future<void> pauseGlobal() async {
    final ch = _globalChannel;
    if (ch == null) return;
    try {
      await ch.untrack();
    } catch (e) {
      debugPrint('pause untrack error: $e');
    }
  }

  /// Uygulama öne gelince tekrar track.
  /// DÜZELTME (2026-07-10): Ayrıca is_online alanını da tercihe göre günceller.
  Future<void> resumeGlobal() async {
    final ch = _globalChannel;
    if (ch == null || _userId == null) return;
    
    // ÖNCE tercihi kontrol et
    final userId = _userId!;
    final isOnlineEnabled = await _isOnlineEnabled(userId);
    _onlineEnabledPref = isOnlineEnabled;

    // Tercihe göre is_online alanını güncelle (profiles tablosuna doğrudan
    // UPDATE yetkisi yok; set_my_presence SECURITY DEFINER RPC'si kullanılır).
    try {
      await Supabase.instance.client.rpc(
        'set_my_presence',
        params: {'p_is_online': isOnlineEnabled, 'p_platform': _currentPlatform()},
      );
      debugPrint('✅ resumeGlobal: is_online=$isOnlineEnabled for user=$_userId');
    } catch (e) {
      debugPrint('⚠️ resumeGlobal DB update failed: $e');
    }

    // Presence track et: tercih kapalıysa hiç track etme (aksi halde
    // Realtime presence kanalı kullanıcıyı DB'deki is_online=false'a
    // rağmen "online" olarak yayınlamaya devam eder).
    if (!isOnlineEnabled) {
      try {
        await ch.untrack();
      } catch (e) {
        debugPrint('resume untrack error: $e');
      }
      return;
    }
    try {
      await ch.track({
        'user_id': _userId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
        'platform': defaultTargetPlatform.name,
      });
    } catch (e) {
      debugPrint('resume track error: $e');
    }
  }

  /// Kullanıcı "çevrimiçi görünme" tercihini uygulama açıkken anlık
  /// değiştirdiğinde çağrılır (Gizlilik & Durum ekranındaki toggle).
  /// Tercih kapatılırsa presence kanalından hemen untrack edilir; aksi
  /// halde kullanıcı DB'de is_online=false olsa bile Realtime presence
  /// üzerinden diğer ekranlarda "çevrimiçi" görünmeye devam eder.
  Future<void> setOnlineEnabled(bool enabled) async {
    _onlineEnabledPref = enabled;
    final ch = _globalChannel;
    if (ch == null) return;
    try {
      if (enabled) {
        await ch.track({
          'user_id': _userId,
          'online_at': DateTime.now().toUtc().toIso8601String(),
          'platform': defaultTargetPlatform.name,
        });
      } else {
        await ch.untrack();
      }
    } catch (e) {
      debugPrint('setOnlineEnabled track/untrack error: $e');
    }
  }

  /// Servisi tamamen kapat.
  Future<void> dispose() async {
    try {
      await _globalChannel?.unsubscribe();
    } catch (_) {}
    _globalChannel = null;
    _userId = null;
    if (!_onlineUsersController.isClosed) {
      await _onlineUsersController.close();
    }
  }
}
