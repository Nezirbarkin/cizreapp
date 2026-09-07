import 'dart:async';
import 'dart:io' show Platform;
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

  /// Admin panelindeki platform kırılımı (iOS/Android/Web) için gönderilir.
  /// `set_my_presence` RPC'si her heartbeat'te bunu profiles.platform'a yazar.
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

  /// Kullanıcının gerçek çevrimiçi durumunu güncelle (is_online).
  /// Bu, app ön plan/arka plan geçişlerinde ve heartbeat'te yazılır.
  /// Kullanıcının *tercihi* için [updateOnlineEnabled] kullanılır.
  /// Doğrudan profiles UPDATE yazmaz; SECURITY DEFINER RPC kullanır.
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

      await supabase.rpc(
        'set_my_presence',
        params: {'p_is_online': isOnline, 'p_platform': _currentPlatform()},
      );

      AppLogger.debug('Online status updated successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error updating online status',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Kullanıcının *tercihini* (çevrimiçi görünüp görünmeyeceğini) günceller.
  /// Bu tercih kalıcıdır: false ise app ön plana gelse bile otomatik online yapılmaz.
  /// RPC: update_my_privacy_settings.
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

      await supabase.rpc(
        'update_my_privacy_settings',
        params: {'p_is_online_enabled': enabled},
      );

      AppLogger.debug('Online enabled updated successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error updating online enabled',
        error: e,
        stackTrace: stackTrace,
      );
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

      await supabase.rpc(
        'update_my_privacy_settings',
        params: {'p_is_ghost_mode': isGhostMode},
      );

      AppLogger.debug('Ghost mode updated successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error updating ghost mode',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// `get_my_profile()` sonucunu güvenli okur; profil yoksa `null` döner.
  ///
  /// RPC `RETURNS profiles` (kompozit satır). Kullanıcının profil satırı yoksa
  /// gövde `null` gelir ve `rpc<Map<String, dynamic>>` bunu cast edemeyip
  /// TypeError atıyordu — çağıran taraf bunu "Error getting ghost mode" gibi
  /// kaynağı belirsiz bir hata olarak kaydediyordu. Profil yokluğu bir tip
  /// hatası değil, açıkça ele alınan bir durum.
  Future<Map<String, dynamic>?> _fetchMyProfile() async {
    final supabase = _supabase;
    if (supabase == null) return null;
    if (supabase.auth.currentUser?.id == null) return null;
    final response = await supabase.rpc<dynamic>('get_my_profile');
    if (response is Map) return Map<String, dynamic>.from(response);
    return null;
  }

  /// Kullanıcının mevcut gerçek çevrimiçi durumunu al (is_online).
  Future<bool> getOnlineStatus() async {
    try {
      final profile = await _fetchMyProfile();
      return (profile?['is_online'] as bool?) ?? false;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error getting online status',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Kullanıcının çevrimiçi görünüp görünmeyeceği *tercihini* al (is_online_enabled).
  Future<bool> getOnlineEnabled() async {
    try {
      final profile = await _fetchMyProfile();
      return (profile?['is_online_enabled'] as bool?) ?? true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error getting online enabled',
        error: e,
        stackTrace: stackTrace,
      );
      return true;
    }
  }

  /// Kullanıcının mevcut hayalet modunu al
  Future<bool> getGhostMode() async {
    try {
      final profile = await _fetchMyProfile();
      return (profile?['is_ghost_mode'] as bool?) ?? false;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error getting ghost mode',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Heartbeat gönder - last_seen ve is_online günceller
  /// RPC: set_my_presence (server timestamp).
  Future<void> _sendHeartbeat() async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Önce tercihleri kontrol et
      final enabled = await getOnlineEnabled();
      if (!enabled) {
        // Tercih kapalı: RPC yine çağrılır ama RPC is_online=false yazar.
        await supabase.rpc(
          'set_my_presence',
          params: {'p_is_online': false, 'p_platform': _currentPlatform()},
        );
        return;
      }

      await supabase.rpc(
        'set_my_presence',
        params: {'p_is_online': true, 'p_platform': _currentPlatform()},
      );
      AppLogger.debug('Heartbeat sent (is_online=true)');
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
    AppLogger.debug(
      'Heartbeat timer started (interval: ${_heartbeatInterval.inSeconds}s)',
    );
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
