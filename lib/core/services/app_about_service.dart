import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_about_settings.dart';

class AppAboutService {
  final SupabaseClient _client;

  AppAboutService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ========== Cache Mekanizması ==========
  // Tüm ekranların aynı ayarlara erişmesi ve slogan/animation
  // değişikliğinin anında yansıması için bellekte tutulur.
  static AppAboutSettings? _cache;
  static final List<VoidCallback> _listeners = [];

  /// Değişiklikleri dinlemek için callback ekle.
  /// Admin panelden güncelleme yapılınca tüm dinleyiciler tetiklenir.
  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Dinleyiciyi kaldır.
  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Tüm dinleyicilere haber ver (cache güncellendi).
  static void _notifyListeners() {
    for (final l in List<VoidCallback>.from(_listeners)) {
      try {
        l();
      } catch (e) {
        debugPrint('AppAboutService listener hata: $e');
      }
    }
  }

  /// Cache'i manuel temizle (test vb. için).
  static void clearCache() {
    _cache = null;
    _notifyListeners();
  }

  /// Mevcut cache'lenmiş ayarları getir (null olabilir).
  static AppAboutSettings? get cached => _cache;

  // ========== API Metotları ==========

  // Hakkında bilgilerini getir (cache ile)
  Future<AppAboutSettings?> getAboutSettings({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) {
      return _cache;
    }

    try {
      final response = await _client
          .from('app_about_settings')
          .select()
          .order('id', ascending: true)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        _cache = AppAboutSettings.fromJson(response);
        return _cache;
      }
      return null;
    } catch (e) {
      debugPrint('Hakkında bilgileri yüklenirken hata: $e');
      return _cache; // Hata varsa cache'i döndür
    }
  }

  // Hakkında bilgilerini güncelle (sadece admin)
  Future<bool> updateAboutSettings(AppAboutSettings settings) async {
    try {
      await _client
          .from('app_about_settings')
          .update(settings.toJson())
          .eq('id', settings.id);

      // Cache'i güncelle ve tüm dinleyicilere haber ver
      _cache = settings;
      _notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Hakkında bilgileri güncellenirken hata: $e');
      return false;
    }
  }
}
