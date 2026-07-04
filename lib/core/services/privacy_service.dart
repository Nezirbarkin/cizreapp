import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

class PrivacyService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  /// Null döner çünkü bu servis uygulama yaşam döngüsü sırasında Supabase başlatılmadan önce çağrılabilir
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      return null;
    }
  }

  /// Heartbeat timer - periyodik olarak last_seen günceller
  Timer? _heartbeatTimer;

  /// Heartbeat aralığı (2 dakika)
  static const _heartbeatInterval = Duration(minutes: 2);

  /// Bir kullanıcının "aktif" kabul edileceği maksimum süre (3 dakika)
  /// Heartbeat 2 dk'da bir geldiği için 3 dk tolerans yeterli
  static const activeThreshold = Duration(minutes: 3);

  /// Kullanıcının gerçek çevrimiçi durumunu güncelle (is_online).
  /// Bu, app ön plan/arka plan geçişlerinde ve heartbeat'te yazılır.
  /// Kullanıcının *tercihi* için [updateOnlineEnabled] kullanılır.
  Future<bool> updateOnlineStatus(bool isOnline) async {
    try {
      final supabase = _supabase;
      if (supabase == null) {
        AppLogger.error('updateOnlineStatus: Supabase not initialized');
        return false;
      }
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('updateOnlineStatus: userId is null');
        return false;
      }

      AppLogger.debug('Updating online status to: $isOnline for user: $userId');

      final now = DateTime.now().toUtc().toIso8601String();
      await supabase.from('profiles').update({
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

  /// Kullanıcının *tercihini* (çevrimiçi görünüp görünmeyeceğini) günceller.
  /// Bu tercih kalıcıdır: false ise app ön plana gelse bile otomatik online yapılmaz.
  /// Aynı zamanda `is_online` alanını da buna göre setler (online enabled=false ise çevrimdışı).
  /// Toggle ekranları bu metodu çağırmalıdır.
  Future<bool> updateOnlineEnabled(bool enabled) async {
    try {
      final supabase = _supabase;
      if (supabase == null) {
        AppLogger.error('updateOnlineEnabled: Supabase not initialized');
        return false;
      }
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('updateOnlineEnabled: userId is null');
        return false;
      }

      AppLogger.debug('Updating online enabled to: $enabled for user: $userId');

      final now = DateTime.now().toUtc().toIso8601String();
      // enabled=true ise is_online=true, enabled=false ise is_online=false
      // last_seen her durumda güncellenir
      await supabase.from('profiles').update({
        'is_online_enabled': enabled,
        'is_online': enabled, // tercih anında gerçek durumu da eşitler
        'last_seen': now,
        'updated_at': now,
      }).eq('id', userId);

      AppLogger.debug('Online enabled updated successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Error updating online enabled: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Kullanıcının hayalet modunu güncelle
  Future<bool> updateGhostMode(bool isGhostMode) async {
    try {
      final supabase = _supabase;
      if (supabase == null) {
        AppLogger.error('updateGhostMode: Supabase not initialized');
        return false;
      }
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('updateGhostMode: userId is null');
        return false;
      }

      AppLogger.debug('Updating ghost mode to: $isGhostMode for user: $userId');

      final now = DateTime.now().toUtc().toIso8601String();
      // Hayalet mod açılırsa kullanıcıyı çevrimdışı yap (mevcut davranış korunur)
      await supabase.from('profiles').update({
        'is_ghost_mode': isGhostMode,
        if (isGhostMode) 'is_online': false,
        'updated_at': now,
      }).eq('id', userId);

      AppLogger.debug('Ghost mode updated successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Error updating ghost mode: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Kullanıcının mevcut gerçek çevrimiçi durumunu al (is_online).
  /// UI'da toggle görüntüleme için [getOnlineEnabled] tercih edilir.
  Future<bool> getOnlineStatus() async {
    try {
      final supabase = _supabase;
      if (supabase == null) return false;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('getOnlineStatus: userId is null');
        return false;
      }

      final response = await supabase
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

  /// Kullanıcının çevrimiçi görünüp görünmeyeceği *tercihini* al (is_online_enabled).
  /// Toggle ekranları bu değeri göstermeli/güncellemelidir.
  Future<bool> getOnlineEnabled() async {
    try {
      final supabase = _supabase;
      if (supabase == null) return true;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('getOnlineEnabled: userId is null');
        return true;
      }

      final response = await supabase
          .from('profiles')
          .select('is_online_enabled')
          .eq('id', userId)
          .single();

      // Sütun henüz eklenmemişse (migration yapılmadıysa) true döner
      return response['is_online_enabled'] as bool? ?? true;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting online enabled: $e');
      AppLogger.error('Stack trace: $stackTrace');
      // Hata durumunda true dönmek mevcut (eski) davranışı korur
      return true;
    }
  }

  /// Kullanıcının mevcut hayalet modunu al
  Future<bool> getGhostMode() async {
    try {
      final supabase = _supabase;
      if (supabase == null) return false;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        AppLogger.error('getGhostMode: userId is null');
        return false;
      }

      final response = await supabase
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

  /// Heartbeat gönder - last_seen ve is_online günceller
  /// ÖNEMLI DÜZELTME (2026-07-02): Sadece last_seen değil, is_online da güncellenir
  Future<void> _sendHeartbeat() async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Önce tercihleri kontrol et
      final enabled = await getOnlineEnabled();
      if (!enabled) {
        // Tercih kapalı: sadece last_seen güncelle, is_online false kalsın
        final now = DateTime.now().toUtc().toIso8601String();
        await supabase.from('profiles').update({
          'last_seen': now,
        }).eq('id', userId);
        AppLogger.debug('Heartbeat (offline mode) at $now');
        return;
      }

      // Tercih açık: is_online=true ve last_seen güncelle
      final now = DateTime.now().toUtc().toIso8601String();
      await supabase.from('profiles').update({
        'is_online': true,
        'last_seen': now,
      }).eq('id', userId);

      AppLogger.debug('Heartbeat sent at $now (is_online=true)');
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
    // Not: burada tercihe (is_online_enabled) bakmıyoruz çünkü app arka
    // plandayken herkes çevrimdışı görünmelidir; tercih ön plana dönüldüğünde
    // tekrar uygulanır.
    final isGhostMode = await getGhostMode();
    if (!isGhostMode) {
      await updateOnlineStatus(false);
    }
  }

  /// Uygulama ön plana geçtiğinde çağrılır
  Future<void> onAppResumed() async {
    // Çevrimiçi durumunu SADECE kullanıcı tercihi açık ise aç.
    // Bu sayede manuel olarak çevrimdışı yapan kullanıcı app ön plana
    // gelince otomatik online yapılmaz (kalıcı çevrimdışı).
    final isGhostMode = await getGhostMode();
    if (!isGhostMode) {
      final enabled = await getOnlineEnabled();
      if (enabled) {
        await updateOnlineStatus(true);
        startHeartbeat();
      } else {
        // Tercih çevrimdışı: gerçek durumu false yap ve heartbeat başlatma
        await updateOnlineStatus(false);
      }
    }
  }
}
