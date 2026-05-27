import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Uygulama izinlerini yöneten servis
/// Uygulama açıldığında gerekli izinleri kontrol eder ve talep eder
class PermissionService {
  /// Singleton instance
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// İzin durumlarını sakla
  final Map<Permission, PermissionStatus> _permissionStatus = {};

  /// İzin açıklama metinleri
  static final Map<Permission, String> _permissionDescriptions = {
    Permission.camera:
        'CizreApp\'in kamera erişimine ihtiyacı var; böylece fotoğraf çekip profil fotoğrafınızı güncelleyebilir, gönderi ve hikaye paylaşabilir, satışa sunmak istediğiniz ürünlerin fotoğraflarını çekebilirsiniz.',
    Permission.photos:
        'CizreApp\'in fotoğraf galerinize erişmesi gerekiyor; böylece galerinizden fotoğraf seçip gönderi veya hikaye paylaşabilir, ürün fotoğraflarını mağazanıza yükleyebilir ve profil fotoğrafınızı değiştirebilirsiniz.',
    Permission.storage:
        'CizreApp\'in cihazınızdaki fotoğraflara ve dosyalara erişmesi gerekiyor; böylece medya içeriklerinizi yükleyebilir ve paylaşabilirsiniz.',
    Permission.notification:
        'CizreApp, size önemli bildirimler gönderebilmek için bildirim iznine ihtiyaç duyar; böylece yeni mesajlarınızdan, sipariş durumlarından ve güncellemelerden haberdar olabilirsiniz.',
    Permission.location:
        'CizreApp, yakınınızdaki mağazaları ve ürünleri göstermek için konum bilginize ihtiyaç duyar; böylece çevrenizdeki satıcıları ve fırsatları keşfedebilirsiniz.',
    Permission.microphone:
        'CizreApp\'in mikrofon erişimine ihtiyacı var; böylece video gönderileri ve hikayeler kaydedebilir, satıcılar ürün tanıtım videoları çekebilir ve sesli mesajlar gönderebilirsiniz.',
  };

  /// İzin kısa isimleri
  static final Map<Permission, String> _permissionNames = {
    Permission.camera: 'Kamera',
    Permission.photos: 'Fotoğraf Galerisi',
    Permission.storage: 'Depolama',
    Permission.notification: 'Bildirimler',
    Permission.location: 'Konum',
    Permission.microphone: 'Mikrofon',
  };

  /// İzin ikonları
  static final Map<Permission, IconData> _permissionIcons = {
    Permission.camera: Icons.camera_alt,
    Permission.photos: Icons.photo_library,
    Permission.storage: Icons.folder,
    Permission.notification: Icons.notifications,
    Permission.location: Icons.location_on,
    Permission.microphone: Icons.mic,
  };

  /// İzin açıklama metnini al
  static String getDescription(Permission permission) {
    return _permissionDescriptions[permission] ?? _permissionNames[permission] ?? 'Bu izin';
  }

  /// İzin kısa adını al
  static String getName(Permission permission) {
    return _permissionNames[permission] ?? permission.toString();
  }

  /// İzin ikonunu al
  static IconData getIcon(Permission permission) {
    return _permissionIcons[permission] ?? Icons.security;
  }

  /// Tüm gerekli izinleri kontrol et ve talep et
  /// Bu metod uygulama açıldığında çağrılmalı
  Future<Map<String, PermissionResult>> checkAndRequestAllPermissions() async {
    if (kIsWeb) {
      debugPrint('🔐 Web platformunda izin kontrolü atlanıyor');
      return {};
    }

    final results = <String, PermissionResult>{};

    // Kamera izni
    results['camera'] = await _checkPermission(Permission.camera, 'Kamera');

    // Galeri izni (fotoğraf seçmek için)
    results['photos'] = await _checkPermission(Permission.photos, 'Fotoğraf Galerisi');
    
    // Storage izni (dosya erişimi için - Android 13+)
    results['storage'] = await _checkPermission(Permission.storage, 'Depolama');

    // Bildirim izni
    results['notifications'] = await _checkPermission(Permission.notification, 'Bildirimler');

    // Konum izni (opsiyonel - satıcılar için)
    results['location'] = await _checkPermission(Permission.location, 'Konum');

    debugPrint('🔐 İzin durumu: $results');
    return results;
  }

  /// Belirli bir izni kontrol et ve talep et
  Future<PermissionResult> _checkPermission(Permission permission, String name) async {
    try {
      // Mevcut durumu kontrol et
      final status = await permission.status;
      _permissionStatus[permission] = status;

      debugPrint('🔐 $name izni durumu: ${_getStatusText(status)}');

      // Zaten verilmiş veya sınırlı ise tekrar sorma
      if (status.isGranted || status.isLimited) {
        return PermissionResult(
          permission: name,
          status: status,
          isGranted: true,
          isDenied: false,
          isPermanentlyDenied: status.isPermanentlyDenied,
        );
      }

      // Daha önce reddedildi ama kalıcı değilse tekrar iste
      if (status.isDenied) {
        final newStatus = await permission.request();
        _permissionStatus[permission] = newStatus;
        debugPrint('🔐 $name izni talep edildi: ${_getStatusText(newStatus)}');

        return PermissionResult(
          permission: name,
          status: newStatus,
          isGranted: newStatus.isGranted || newStatus.isLimited,
          isDenied: newStatus.isDenied,
          isPermanentlyDenied: newStatus.isPermanentlyDenied,
        );
      }

      // Kalıcı olarak reddedildi
      if (status.isPermanentlyDenied) {
        return PermissionResult(
          permission: name,
          status: status,
          isGranted: false,
          isDenied: true,
          isPermanentlyDenied: true,
        );
      }

      return PermissionResult(
        permission: name,
        status: status,
        isGranted: status.isGranted,
        isDenied: status.isDenied,
        isPermanentlyDenied: status.isPermanentlyDenied,
      );
    } catch (e) {
      debugPrint('❌ $name izni kontrol edilirken hata: $e');
      return PermissionResult(
        permission: name,
        status: PermissionStatus.denied,
        isGranted: false,
        isDenied: true,
        isPermanentlyDenied: false,
        error: e.toString(),
      );
    }
  }

  /// Kalıcı olarak reddedilen bir izni ayarlar uygulamasında aç
  Future<bool> openPermissionSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      debugPrint('❌ Ayarlar açılamadı: $e');
      return false;
    }
  }

  /// Belirli bir iznin durumunu al
  Future<PermissionStatus> getPermissionStatus(Permission permission) async {
    if (_permissionStatus.containsKey(permission)) {
      return _permissionStatus[permission]!;
    }
    final status = await permission.status;
    _permissionStatus[permission] = status;
    return status;
  }

  /// Kamera izni verildi mi?
  Future<bool> isCameraGranted() async {
    final status = await getPermissionStatus(Permission.camera);
    return status.isGranted || status.isLimited;
  }

  /// Galeri izni verildi mi?
  Future<bool> isPhotosGranted() async {
    final status = await getPermissionStatus(Permission.photos);
    return status.isGranted || status.isLimited;
  }

  /// Bildirim izni verildi mi?
  Future<bool> isNotificationsGranted() async {
    final status = await getPermissionStatus(Permission.notification);
    return status.isGranted || status.isLimited;
  }

  /// Konum izni verildi mi?
  Future<bool> isLocationGranted() async {
    final status = await getPermissionStatus(Permission.location);
    return status.isGranted || status.isLimited;
  }

  /// İzin durumunu metin olarak al
  String _getStatusText(PermissionStatus status) {
    if (status.isGranted) return 'VERİLDİ';
    if (status.isLimited) return 'SINIRLI (iOS)';
    if (status.isRestricted) return 'SINIRLI';
    if (status.isPermanentlyDenied) return 'KALICI REDDEDİLDİ';
    if (status.isDenied) return 'REDDEDİLDİ';
    if (status.isProvisional) return 'GEÇİCİ';
    return 'BİLİNMİYOR';
  }
}

/// İzin sonucu modeli
class PermissionResult {
  final String permission;
  final PermissionStatus status;
  final bool isGranted;
  final bool isDenied;
  final bool isPermanentlyDenied;
  final String? error;

  PermissionResult({
    required this.permission,
    required this.status,
    required this.isGranted,
    required this.isDenied,
    required this.isPermanentlyDenied,
    this.error,
  });

  @override
  String toString() {
    return 'PermissionResult($permission: ${isGranted ? "VERİLDİ" : (isPermanentlyDenied ? "KALICI REDDEDİLDİ" : "REDDEDİLDİ")})';
  }
}
