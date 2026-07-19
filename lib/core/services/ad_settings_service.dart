import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ad_settings_model.dart';

/// Reklam ayarları servisi (ad_settings tekil satırı)
class AdSettingsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<AdSettings?> getSettings() async {
    try {
      final row = await _supabase.from('ad_settings').select('*').eq('id', 1).single();
      return AdSettings.fromJson(row);
    } catch (e) {
      debugPrint('⚠️ ad_settings okunamadı: $e');
      return null;
    }
  }

  Future<bool> updateSettings(AdSettings settings) async {
    try {
      await _supabase.from('ad_settings').update(settings.toJson()).eq('id', 1);
      return true;
    } catch (e) {
      debugPrint('❌ ad_settings güncellenemedi: $e');
      return false;
    }
  }
}
