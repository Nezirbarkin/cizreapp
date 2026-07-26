import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Şoför kayıt ve atama servisi (admin + sürücü tarafı).
class SehiriciDriverService {
  final SupabaseClient _client;
  SehiriciDriverService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Tüm şoförleri getir (admin).
  Future<List<Map<String, dynamic>>> getAllDriversAdmin() async {
    try {
      final response = await _client.from('sehirici_drivers').select(
          'id, profile_id, license_number, phone, assigned_line_id, is_on_duty, '
          'profiles!inner(full_name, username, avatar_url)');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('getAllDriversAdmin hata: $e');
      return [];
    }
  }

  /// Mevcut kullanıcının şoför kaydını getir (yoksa null).
  Future<Map<String, dynamic>?> getMyDriverProfile() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;
      final response = await _client
          .from('sehirici_drivers')
          .select('*, sehirici_lines(id, code, name, color_hex, vehicle_type)')
          .eq('profile_id', user.id)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('getMyDriverProfile hata: $e');
      return null;
    }
  }

  /// Şoför oluştur (admin).
  Future<String?> createDriver({
    required String profileId,
    String? licenseNumber,
    String? phone,
    String? assignedLineId,
  }) async {
    try {
      final response = await _client
          .from('sehirici_drivers')
          .insert({
            'profile_id': profileId,
            'license_number': licenseNumber,
            'phone': phone,
            'assigned_line_id': assignedLineId,
          })
          .select('id')
          .maybeSingle();
      return response?['id'] as String?;
    } catch (e) {
      debugPrint('createDriver hata: $e');
      return null;
    }
  }

  Future<bool> assignLine(String driverId, String? lineId) async {
    try {
      await _client
          .from('sehirici_drivers')
          .update({'assigned_line_id': lineId})
          .eq('id', driverId);
      return true;
    } catch (e) {
      debugPrint('assignLine hata: $e');
      return false;
    }
  }

  Future<bool> updateDriver(
    String driverId, {
    String? licenseNumber,
    String? phone,
  }) async {
    try {
      final update = <String, dynamic>{};
      if (licenseNumber != null) update['license_number'] = licenseNumber;
      if (phone != null) update['phone'] = phone;
      if (update.isEmpty) return true;
      await _client
          .from('sehirici_drivers')
          .update(update)
          .eq('id', driverId);
      return true;
    } catch (e) {
      debugPrint('updateDriver hata: $e');
      return false;
    }
  }

  Future<bool> deleteDriver(String driverId) async {
    try {
      await _client.from('sehirici_drivers').delete().eq('id', driverId);
      return true;
    } catch (e) {
      debugPrint('deleteDriver hata: $e');
      return false;
    }
  }

  /// profiles tablosundan kullanıcı arama (admin için şoför atarken).
  Future<List<Map<String, dynamic>>> searchProfiles(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final response = await _client
          .from('profiles')
          .select('id, full_name, username, avatar_url, role')
          .or('username.ilike.%$query%,full_name.ilike.%$query%')
          .limit(20);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('searchProfiles hata: $e');
      return [];
    }
  }
}
