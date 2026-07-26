import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sehirici_models.dart';

/// Kullanıcı favori durak servisi.
class SehiriciFavoriteService {
  final SupabaseClient _client;
  SehiriciFavoriteService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<List<SehiriciFavoriteStop>> getFavorites() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return [];
      final response = await _client
          .from('sehirici_favorite_stops')
          .select()
          .eq('user_id', user.id);
      return (response as List)
          .map((e) =>
              SehiriciFavoriteStop.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SehiriciFavoriteService.getFavorites hata: $e');
      return [];
    }
  }

  Future<bool> addFavorite(String stopId, {int notifyMinutesBefore = 5}) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;
      await _client.from('sehirici_favorite_stops').upsert({
        'user_id': user.id,
        'stop_id': stopId,
        'notify_minutes_before': notifyMinutesBefore,
      });
      return true;
    } catch (e) {
      debugPrint('addFavorite hata: $e');
      return false;
    }
  }

  Future<bool> removeFavorite(String stopId) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;
      await _client
          .from('sehirici_favorite_stops')
          .delete()
          .eq('user_id', user.id)
          .eq('stop_id', stopId);
      return true;
    } catch (e) {
      debugPrint('removeFavorite hata: $e');
      return false;
    }
  }

  Future<bool> updateNotifyMinutes(String stopId, int minutes) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;
      await _client
          .from('sehirici_favorite_stops')
          .update({'notify_minutes_before': minutes})
          .eq('user_id', user.id)
          .eq('stop_id', stopId);
      return true;
    } catch (e) {
      debugPrint('updateNotifyMinutes hata: $e');
      return false;
    }
  }

  /// Belirli bir kullanıcının tüm favorilerini temizle.
  Future<bool> clearAll() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;
      await _client
          .from('sehirici_favorite_stops')
          .delete()
          .eq('user_id', user.id);
      return true;
    } catch (e) {
      debugPrint('clearAll hata: $e');
      return false;
    }
  }

  /// Favori durakların detayını join ile getirir.
  Future<List<Map<String, dynamic>>> getFavoritesDetailed() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return [];
      final response = await _client
          .from('sehirici_favorite_stops')
          .select(
              'id, stop_id, notify_minutes_before, '
              'sehirici_stops(name, address, lat, lng, city_id)')
          .eq('user_id', user.id);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('getFavoritesDetailed hata: $e');
      return [];
    }
  }
}
