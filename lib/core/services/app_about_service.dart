import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_about_settings.dart';

class AppAboutService {
  final SupabaseClient _client;

  AppAboutService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Hakkında bilgilerini getir
  Future<AppAboutSettings?> getAboutSettings() async {
    try {
      final response = await _client
          .from('app_about_settings')
          .select()
          .order('id', ascending: true)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return AppAboutSettings.fromJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('Hakkında bilgileri yüklenirken hata: $e');
      return null;
    }
  }

  // Hakkında bilgilerini güncelle (sadece admin)
  Future<bool> updateAboutSettings(AppAboutSettings settings) async {
    try {
      await _client
          .from('app_about_settings')
          .update(settings.toJson())
          .eq('id', settings.id);
      return true;
    } catch (e) {
      debugPrint('Hakkında bilgileri güncellenirken hata: $e');
      return false;
    }
  }
}
