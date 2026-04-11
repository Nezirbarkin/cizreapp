import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/address_model.dart';

class AddressService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Kullanıcının adreslerini getir
  Future<List<Address>> getUserAddresses(String userId) async {
    try {
      debugPrint('🔍 Adresler yükleniyor - userId: $userId');
      final response = await _supabase
          .from('addresses')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      debugPrint('✅ Adresler yüklendi - Toplam: ${(response as List).length}');
      return (response as List)
          .map((json) => Address.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ Adres yükleme hatası: $e');
      throw Exception('Adresler yüklenirken hata: $e');
    }
  }

  // Varsayılan adresi getir
  Future<Address?> getDefaultAddress(String userId) async {
    try {
      debugPrint('🔍 Varsayılan adres aranıyor - userId: $userId');
      final response = await _supabase
          .from('addresses')
          .select()
          .eq('user_id', userId)
          .eq('is_default', true)
          .maybeSingle();

      if (response != null) {
        debugPrint('✅ Varsayılan adres bulundu');
        return Address.fromJson(response);
      }
      debugPrint('ℹ️ Varsayılan adres bulunamadı');
      return null;
    } catch (e) {
      debugPrint('❌ Varsayılan adres hatası: $e');
      return null;
    }
  }

  // Adres ekle
  Future<Address> addAddress({
    required String userId,
    required String title,
    required String fullName,
    required String phone,
    required String addressLine1,
    String? addressLine2,
    required String city,
    String? district,
    String? postalCode,
    bool isDefault = false,
  }) async {
    try {
      // Eğer yeni adres varsayılan olarak işaretleniyorsa, diğerlerinin varsayılan işaretini kaldır
      if (isDefault) {
        await _supabase
            .from('addresses')
            .update({'is_default': false})
            .eq('user_id', userId);
      }

      final response = await _supabase
          .from('addresses')
          .insert({
            'user_id': userId,
            'title': title,
            'full_name': fullName,
            'phone': phone,
            'address_line1': addressLine1,
            'address_line2': addressLine2,
            'city': city,
            'district': district,
            'postal_code': postalCode,
            'is_default': isDefault,
          })
          .select()
          .single();

      return Address.fromJson(response);
    } catch (e) {
      throw Exception('Adres eklenirken hata: $e');
    }
  }

  // Adres güncelle
  Future<Address> updateAddress({
    required String addressId,
    required String userId,
    required String title,
    required String fullName,
    required String phone,
    required String addressLine1,
    String? addressLine2,
    required String city,
    String? district,
    String? postalCode,
    bool isDefault = false,
  }) async {
    try {
      // Eğer adres varsayılan olarak işaretleniyorsa, diğerlerinin varsayılan işaretini kaldır
      if (isDefault) {
        await _supabase
            .from('addresses')
            .update({'is_default': false})
            .eq('user_id', userId)
            .neq('id', addressId);
      }

      final response = await _supabase
          .from('addresses')
          .update({
            'title': title,
            'full_name': fullName,
            'phone': phone,
            'address_line1': addressLine1,
            'address_line2': addressLine2,
            'city': city,
            'district': district,
            'postal_code': postalCode,
            'is_default': isDefault,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', addressId)
          .select()
          .single();

      return Address.fromJson(response);
    } catch (e) {
      throw Exception('Adres güncellenirken hata: $e');
    }
  }

  // Adresi varsayılan yap
  Future<void> setDefaultAddress(String userId, String addressId) async {
    try {
      // Önce tüm adreslerin varsayılan işaretini kaldır
      await _supabase
          .from('addresses')
          .update({'is_default': false})
          .eq('user_id', userId);

      // Seçilen adresi varsayılan yap
      await _supabase
          .from('addresses')
          .update({'is_default': true})
          .eq('id', addressId);
    } catch (e) {
      throw Exception('Varsayılan adres ayarlanırken hata: $e');
    }
  }

  // Adres sil
  Future<void> deleteAddress(String addressId) async {
    try {
      await _supabase
          .from('addresses')
          .delete()
          .eq('id', addressId);
    } catch (e) {
      throw Exception('Adres silinirken hata: $e');
    }
  }

  // ID'ye göre adres getir
  Future<Address?> getAddressById(String addressId) async {
    try {
      final response = await _supabase
          .from('addresses')
          .select()
          .eq('id', addressId)
          .single();

      return Address.fromJson(response);
    } catch (e) {
      return null;
    }
  }
}
