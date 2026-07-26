import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/price_alert_model.dart';

/// Fiyat Düşüş Alarmı servisi - favori ürün için hedef fiyat kurma,
/// aktif alarmları listeleme, deaktive etme.
/// Tetikleme DB trigger (notify_price_drops) ile sunucu-taraflı yapılır.
class PriceAlertService {
  SupabaseClient get _supabase => Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  /// Belirli ürün için aktif alarmı var mı? (ürün detayda rozet için)
  Future<PriceAlert?> getActiveAlertForProduct(String productId) async {
    if (_userId == null) return null;
    try {
      final response = await _supabase
          .from('price_alerts')
          .select('*, products!inner(id, name, image_url, price, discount_price)')
          .eq('user_id', _userId!)
          .eq('product_id', productId)
          .eq('is_active', true)
          .maybeSingle();
      if (response == null) return null;
      return PriceAlert.fromJson(response);
    } catch (e) {
      debugPrint('PriceAlertService.getActiveAlertForProduct error: $e');
      return null;
    }
  }

  /// Kullanıcının tüm aktif alarmları.
  Future<List<PriceAlert>> getUserAlerts({bool onlyActive = true}) async {
    if (_userId == null) return [];
    try {
      // Önce filtre zincirini kur (eq bir PostgrestFilterBuilder döner),
      // .order() en sonda çağrılmalı çünkü o artık transform builder'a döndürür.
      PostgrestFilterBuilder<dynamic> filter = _supabase
          .from('price_alerts')
          .select(
              '*, products!inner(id, name, image_url, price, discount_price)')
          .eq('user_id', _userId!);
      if (onlyActive) {
        filter = filter.eq('is_active', true);
      }
      final response = await filter.order('created_at', ascending: false);
      return (response as List)
          .map((json) => PriceAlert.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('PriceAlertService.getUserAlerts error: $e');
      rethrow;
    }
  }

  /// Alarm kur/upsert. Aynı ürün+user zaten varsa günceller (unique constraint).
  /// [currentPrice] ürünün o anki fiyatı (kayıt için).
  Future<PriceAlert> setAlert({
    required String productId,
    required double targetPrice,
    required double currentPrice,
  }) async {
    if (_userId == null) throw Exception('Oturum açmanız gerekli');
    if (targetPrice <= 0) throw Exception('Hedef fiyat geçersiz');
    if (targetPrice >= currentPrice) {
      throw Exception('Hedef fiyat, mevcut fiyattan düşük olmalı');
    }

    // Upsert: aynı (user_id, product_id) varsa güncelle
    final response = await _supabase
        .from('price_alerts')
        .upsert(
          {
            'user_id': _userId!,
            'product_id': productId,
            'target_price': targetPrice,
            'current_price_at_creation': currentPrice,
            'is_active': true,
            'triggered_at': null,
          },
          onConflict: 'user_id, product_id',
        )
        .select('*, products!inner(id, name, image_url, price, discount_price)')
        .limit(1)
        .single();
    return PriceAlert.fromJson(response);
  }

  /// Alarmı deaktive et (tetiklendikten sonra veya kullanıcı kapattı).
  Future<void> deactivateAlert(String alertId) async {
    await _supabase
        .from('price_alerts')
        .update({'is_active': false}).eq('id', alertId);
  }

  /// Alarmı tamamen sil.
  Future<void> deleteAlert(String alertId) async {
    await _supabase.from('price_alerts').delete().eq('id', alertId);
  }
}