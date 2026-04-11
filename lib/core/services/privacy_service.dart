import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

class PrivacyService {
  final _supabase = Supabase.instance.client;

  /// Heartbeat timer - periyodik olarak last_seen günceller
  Timer? _heartbeatTimer;

  /// Heartbeat aralığı (2 dakika)
  static const _heartbeatInterval = Duration(minutes: 2);

  /// Bir kullanıcının "aktif" kabul edileceği maksimum süre (3 dakika)
  /// Heartbeat 2 dk'da bir geldiği için 3 dk tolerans yeterli
  static const activeThreshold = Duration(minutes: 3);

  /// Kullanıcının çevrimiçi durumunu güncelle
  Future<bool> updateOnlineStatus(bool isOnline) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('updateOnlineStatus: userId is null');
        return false;
      }

      AppLogger.debug('Updating online status to: $isOnline for user: $userId');

      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('profiles').update({
        'is_online': isOnline,
        'last_seen': now,
        'updated_at': now,
      }).eq('id', userId);

      AppLogger.debug('Online status updated successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Error updating online status: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Kullanıcının hayalet modunu güncelle
  Future<bool> updateGhostMode(bool isGhostMode) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('updateGhostMode: userId is null');
        return false;
      }

      AppLogger.debug('Updating ghost mode to: $isGhostMode for user: $userId');

      await _supabase.from('profiles').update({
        'is_ghost_mode': isGhostMode,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      AppLogger.debug('Ghost mode updated successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Error updating ghost mode: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Kullanıcının mevcut çevrimiçi durumunu al
  Future<bool> getOnlineStatus() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('getOnlineStatus: userId is null');
        return false;
      }

      final response = await _supabase
          .from('profiles')
          .select('is_online')
          .eq('id', userId)
          .single();

      return response['is_online'] as bool? ?? false;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting online status: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Kullanıcının mevcut hayalet modunu al
  Future<bool> getGhostMode() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('getGhostMode: userId is null');
        return false;
      }

      final response = await _supabase
          .from('profiles')
          .select('is_ghost_mode')
          .eq('id', userId)
          .single();

      return response['is_ghost_mode'] as bool? ?? false;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting ghost mode: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Heartbeat gönder - sadece last_seen günceller (hafif sorgu)
  Future<void> _sendHeartbeat() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('profiles').update({
        'last_seen': now,
      }).eq('id', userId);

      AppLogger.debug('Heartbeat sent at $now');
    } catch (e) {
      AppLogger.error('Heartbeat error: $e');
    }
  }

  /// Heartbeat timer'ı başlat
  void startHeartbeat() {
    stopHeartbeat(); // Mevcut timer varsa durdur
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _sendHeartbeat();
    });
    AppLogger.debug('Heartbeat timer started (interval: ${_heartbeatInterval.inSeconds}s)');
  }

  /// Heartbeat timer'ı durdur
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    AppLogger.debug('Heartbeat timer stopped');
  }

  /// Bir kullanıcının gerçekten aktif olup olmadığını kontrol et
  /// is_online=true VE last_seen son [activeThreshold] içinde ise aktif kabul edilir
  static bool isUserTrulyActive(bool isOnline, DateTime? lastSeen) {
    if (!isOnline) return false;
    if (lastSeen == null) return false;

    final now = DateTime.now().toUtc();
    final lastSeenUtc = lastSeen.toUtc();
    final diff = now.difference(lastSeenUtc);

    // is_online=true ama son 3 dakikadan fazla heartbeat yok → aktif değil
    return diff <= activeThreshold;
  }

  /// Uygulama arka plana geçtiğinde çağrılır
  Future<void> onAppPaused() async {
    stopHeartbeat();
    // Çevrimiçi durumunu kapat (hayalet mod aktif değilse)
    final isGhostMode = await getGhostMode();
    if (!isGhostMode) {
      await updateOnlineStatus(false);
    }
  }

  /// Uygulama ön plana geçtiğinde çağrılır
  Future<void> onAppResumed() async {
    // Çevrimiçi durumunu aç (hayalet mod aktif değilse)
    final isGhostMode = await getGhostMode();
    if (!isGhostMode) {
      await updateOnlineStatus(true);
    }
    startHeartbeat();
  }
}
