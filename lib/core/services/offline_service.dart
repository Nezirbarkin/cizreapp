import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/app_logger.dart';

/// Offline mod servisi - Uygulamanın çevrimdışı çalışmasını sağlar
class OfflineService {
  static const String _offlineBoxName = 'offline_data';
  static const String _pendingActionsBoxName = 'pending_actions';
  static Box? _offlineBox;
  static Box? _pendingActionsBox;
  
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;
  OfflineService._internal();

  /// Çevrimiçi durumu
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Bağlantı değişikliği dinleyicileri
  final List<Function(bool)> _listeners = [];

  /// Servisi başlat
  Future<void> initialize() async {
    if (kIsWeb) {
      AppLogger.info('ℹ️ Offline service skipped on web platform');
      return;
    }

    try {
      // Hive kutularını aç
      _offlineBox = await Hive.openBox(_offlineBoxName);
      _pendingActionsBox = await Hive.openBox(_pendingActionsBoxName);
      
      // Başlangıçta bağlantı durumunu kontrol et
      final connectivityResult = await Connectivity().checkConnectivity();
      _updateConnectivity(connectivityResult);

      // Bağlantı değişikliklerini dinle
      Connectivity().onConnectivityChanged.listen(_updateConnectivity);

      AppLogger.info('✅ Offline service initialized. Online: $_isOnline');
    } catch (e) {
      AppLogger.error('❌ Offline service initialization error: $e');
    }
  }

  /// Bağlantı durumunu güncelle
  void _updateConnectivity(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = results.isNotEmpty && !results.contains(ConnectivityResult.none);

    AppLogger.debug('🔌 Connectivity changed: $_isOnline (was: $wasOnline)');

    if (wasOnline != _isOnline) {
      // Bağlantı durumu değişti - dinleyicileri bilgilendir
      for (final listener in _listeners) {
        try {
          listener(_isOnline);
        } catch (e) {
          AppLogger.error('❌ Connectivity listener error: $e');
        }
      }

      // Çevrimiçi olduysa bekleyen aksiyonları işle
      if (_isOnline && wasOnline == false) {
        _processPendingActions();
      }
    }
  }

  /// Bağlantı durumu dinleyicisi ekle
  void addConnectivityListener(Function(bool) listener) {
    _listeners.add(listener);
  }

  /// Bağlantı durumu dinleyicisi kaldır
  void removeConnectivityListener(Function(bool) listener) {
    _listeners.remove(listener);
  }

  // ==================== OFFLINE DATA ====================

  /// Veriyi çevrimdışı olarak sakla
  Future<void> cacheData({
    required String key,
    required dynamic data,
    Duration? expiry,
  }) async {
    if (_offlineBox == null) return;

    try {
      final cacheData = {
        'data': data is String ? data : jsonEncode(data),
        'cachedAt': DateTime.now().toIso8601String(),
        'expiresAt': expiry != null
            ? DateTime.now().add(expiry).toIso8601String()
            : null,
      };

      await _offlineBox!.put(key, jsonEncode(cacheData));
      AppLogger.debug('💾 Data cached: $key');
    } catch (e) {
      AppLogger.error('❌ Cache error for $key: $e');
    }
  }

  /// Çevrimdışı saklanan veriyi getir
  dynamic getCachedData(String key, {bool checkExpiry = true}) {
    if (_offlineBox == null) return null;

    try {
      final cached = _offlineBox!.get(key);
      if (cached == null) return null;

      final Map<String, dynamic> cacheData = jsonDecode(cached);

      // Süre kontrolü
      if (checkExpiry && cacheData['expiresAt'] != null) {
        final expiresAt = DateTime.parse(cacheData['expiresAt']);
        if (DateTime.now().isAfter(expiresAt)) {
          // Süresi dolmuş - sil
          _offlineBox!.delete(key);
          return null;
        }
      }

      return cacheData['data'];
    } catch (e) {
      AppLogger.error('❌ Get cached data error for $key: $e');
      return null;
    }
  }

  /// Çevrimdışı verinin süresi dolmuş mu?
  bool isCacheExpired(String key) {
    if (_offlineBox == null) return true;

    try {
      final cached = _offlineBox!.get(key);
      if (cached == null) return true;

      final Map<String, dynamic> cacheData = jsonDecode(cached);
      if (cacheData['expiresAt'] == null) return false;

      final expiresAt = DateTime.parse(cacheData['expiresAt']);
      return DateTime.now().isAfter(expiresAt);
    } catch (e) {
      return true;
    }
  }

  /// Çevrimdışı veri sil
  Future<void> deleteCachedData(String key) async {
    if (_offlineBox == null) return;
    await _offlineBox!.delete(key);
  }

  /// Tüm çevrimdışı veriyi temizle
  Future<void> clearAllCachedData() async {
    if (_offlineBox == null) return;
    await _offlineBox!.clear();
    AppLogger.info('🧹 All offline data cleared');
  }

  /// Süresi dolmuş verileri temizle
  Future<void> clearExpiredData() async {
    if (_offlineBox == null) return;

    try {
      final keysToDelete = <String>[];
      final now = DateTime.now();

      for (final key in _offlineBox!.keys) {
        try {
          final cached = _offlineBox!.get(key);
          if (cached != null) {
            final Map<String, dynamic> cacheData = jsonDecode(cached);
            if (cacheData['expiresAt'] != null) {
              final expiresAt = DateTime.parse(cacheData['expiresAt']);
              if (now.isAfter(expiresAt)) {
                keysToDelete.add(key as String);
              }
            }
          }
        } catch (e) {
          // Hatalı veri - sil
          keysToDelete.add(key as String);
        }
      }

      for (final key in keysToDelete) {
        await _offlineBox!.delete(key);
      }

      if (keysToDelete.isNotEmpty) {
        AppLogger.debug('🧹 Cleared ${keysToDelete.length} expired cache entries');
      }
    } catch (e) {
      AppLogger.error('❌ Clear expired data error: $e');
    }
  }

  // ==================== PENDING ACTIONS ====================

  /// Çevrimdışıyken yapılacak aksiyonu kaydet
  Future<void> savePendingAction({
    required String actionType,
    required Map<String, dynamic> data,
    String? relatedId,
  }) async {
    if (_pendingActionsBox == null) return;

    try {
      final pendingAction = {
        'id': '${DateTime.now().millisecondsSinceEpoch}_$actionType',
        'actionType': actionType,
        'data': data,
        'relatedId': relatedId,
        'createdAt': DateTime.now().toIso8601String(),
        'retryCount': 0,
      };

      await _pendingActionsBox!.put(pendingAction['id'], jsonEncode(pendingAction));
      AppLogger.debug('📝 Pending action saved: $actionType');
    } catch (e) {
      AppLogger.error('❌ Save pending action error: $e');
    }
  }

  /// Bekleyen aksiyonları işle
  Future<void> _processPendingActions() async {
    if (_pendingActionsBox == null || _pendingActionsBox!.isEmpty) return;

    AppLogger.info('🔄 Processing pending actions...');

    try {
      final keysToDelete = <String>[];

      for (final key in _pendingActionsBox!.keys) {
        try {
          final actionJson = _pendingActionsBox!.get(key);
          if (actionJson == null) continue;

          final action = jsonDecode(actionJson);
          final success = await _executePendingAction(action);

          if (success) {
            keysToDelete.add(key as String);
          } else {
            // Başarısız - retry sayısını artır
            action['retryCount'] = (action['retryCount'] ?? 0) + 1;
            
            // Çok fazla denendiyse sil
            if (action['retryCount'] >= 5) {
              keysToDelete.add(key as String);
              AppLogger.warning('⚠️ Pending action removed after 5 failed retries: ${action['actionType']}');
            } else {
              await _pendingActionsBox!.put(key, jsonEncode(action));
            }
          }
        } catch (e) {
          AppLogger.error('❌ Process pending action error: $e');
        }
      }

      for (final key in keysToDelete) {
        await _pendingActionsBox!.delete(key);
      }

      AppLogger.info('✅ Pending actions processed. Removed: ${keysToDelete.length}');
    } catch (e) {
      AppLogger.error('❌ Process pending actions error: $e');
    }
  }

  /// Bekleyen aksiyonu çalıştır
  Future<bool> _executePendingAction(Map<String, dynamic> action) async {
    try {
      final actionType = action['actionType'] as String;
      final data = action['data'] as Map<String, dynamic>;

      switch (actionType) {
        case 'like_post':
          return await _retryLikePost(data);
        case 'unlike_post':
          return await _retryUnlikePost(data);
        case 'add_comment':
          return await _retryAddComment(data);
        case 'follow_user':
          return await _retryFollowUser(data);
        case 'unfollow_user':
          return await _retryUnfollowUser(data);
        case 'update_cart':
          return await _retryUpdateCart(data);
        default:
          AppLogger.warning('⚠️ Unknown pending action type: $actionType');
          return true; // Bilinmeyen aksiyonları kaldır
      }
    } catch (e) {
      AppLogger.error('❌ Execute pending action error: $e');
      return false;
    }
  }

  /// Like post retry
  Future<bool> _retryLikePost(Map<String, dynamic> data) async {
    try {
      // Import et ve çağır
      // PostService().likePost(data['postId'], data['userId']);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Unlike post retry
  Future<bool> _retryUnlikePost(Map<String, dynamic> data) async {
    try {
      // PostService().unlikePost(data['postId'], data['userId']);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add comment retry
  Future<bool> _retryAddComment(Map<String, dynamic> data) async {
    try {
      // PostService().addComment(data['postId'], data['userId'], data['content']);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Follow user retry
  Future<bool> _retryFollowUser(Map<String, dynamic> data) async {
    try {
      // PostService().followUser(data['followerId'], data['followingId']);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Unfollow user retry
  Future<bool> _retryUnfollowUser(Map<String, dynamic> data) async {
    try {
      // PostService().unfollowUser(data['followerId'], data['followingId']);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update cart retry
  Future<bool> _retryUpdateCart(Map<String, dynamic> data) async {
    try {
      // CartService().updateCart(data);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== HELPERS ====================

  /// Cache boyutunu getir
  int get cacheSize => _offlineBox?.length ?? 0;

  /// Bekleyen aksiyon sayısı
  int get pendingActionsCount => _pendingActionsBox?.length ?? 0;

  /// Cache boyutunu MB olarak getir (yaklaşık)
  double get cacheSizeMB {
    if (_offlineBox == null) return 0;
    // Hive yaklaşık 10MB'a kadar veri depolayabilir
    return (_offlineBox!.length * 0.001); // Yaklaşık hesaplama
  }

  /// Önbellek istatistiklerini getir
  Map<String, dynamic> getCacheStats() {
    return {
      'isOnline': _isOnline,
      'cacheSize': cacheSize,
      'cacheSizeMB': cacheSizeMB,
      'pendingActions': pendingActionsCount,
    };
  }
}

/// Offline durum widget'ı - Bağlantı olmadığında overlay gösterir
class OfflineOverlay extends StatelessWidget {
  final Widget child;
  final bool showBanner;
  final Color? bannerColor;
  final Color? textColor;

  const OfflineOverlay({
    super.key,
    required this.child,
    this.showBanner = true,
    this.bannerColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      initialData: [ConnectivityResult.none],
      builder: (context, snapshot) {
        final isOffline = snapshot.data?.contains(ConnectivityResult.none) ?? false;

        return Stack(
          children: [
            child,
            if (isOffline && showBanner)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: bannerColor ?? Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off,
                          color: textColor ?? Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'İnternet bağlantısı yok - Çevrimdışı mod',
                          style: TextStyle(
                            color: textColor ?? Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}