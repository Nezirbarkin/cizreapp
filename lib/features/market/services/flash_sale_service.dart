import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/flash_sale_model.dart';

/// Flash Satış servisi - aktif kampanyaları getir, atomik stok düşürme (RPC),
/// Supabase Realtime ile canlı stok/süre değişimi dinleme.
class FlashSaleService {
  SupabaseClient get _supabase => Supabase.instance.client;

  // ------------------ READ ------------------

  /// Şu an aktif (zaman penceresinde + is_active) flash sale'leri getir.
  /// products + shops join ile ürün/mağaza bilgisi dahil.
  Future<List<FlashSale>> getActiveFlashSales({int limit = 50}) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await _supabase
          .from('flash_sales')
          .select('''
            *,
            products!inner(id, name, image_url),
            shops!inner(id, name)
          ''')
          .eq('is_active', true)
          .lte('start_at', now)
          .gte('end_at', now)
          .order('end_at', ascending: true)
          .limit(limit);

      return (response as List)
          .map((json) => FlashSale.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('FlashSaleService.getActiveFlashSales error: $e');
      rethrow;
    }
  }

  /// Belirli ürün için aktif flash sale var mı (ürün detayda rozet için).
  Future<FlashSale?> getActiveFlashSaleForProduct(String productId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await _supabase
          .from('flash_sales')
          .select('*, products!inner(id, name, image_url), shops!inner(id, name)')
          .eq('product_id', productId)
          .eq('is_active', true)
          .lte('start_at', now)
          .gte('end_at', now)
          .order('end_at', ascending: true)
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return FlashSale.fromJson(response);
    } catch (e) {
      debugPrint('FlashSaleService.getActiveFlashSaleForProduct error: $e');
      return null;
    }
  }

  // ------------------ CLAIM (atomic stock) ------------------

  /// Atomik stok düşürme. Sepete eklemeden önce çağrılır.
  /// Başarı: {success, remaining, flash_price, product_id}
  /// Başarısız: {success:false, error, remaining?}
  Future<Map<String, dynamic>> claimFlashSale({
    required String saleId,
    required int quantity,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return {'success': false, 'error': 'Oturum açmanız gerekli'};
    }
    try {
      final response = await _supabase.rpc('claim_flash_sale', params: {
        'p_sale_id': saleId,
        'p_quantity': quantity,
        'p_user_id': userId,
      });
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint('FlashSaleService.claimFlashSale error: $e');
      return {'success': false, 'error': 'Satın alma talebi başarısız: $e'};
    }
  }

  /// Ödeme başarısızlığında / sepetten çıkarıldığında stoku geri ver.
  Future<Map<String, dynamic>> releaseFlashSale({
    required String saleId,
    required int quantity,
  }) async {
    try {
      final response = await _supabase.rpc('release_flash_sale', params: {
        'p_sale_id': saleId,
        'p_quantity': quantity,
      });
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint('FlashSaleService.releaseFlashSale error: $e');
      return {'success': false, 'error': '$e'};
    }
  }

  // ------------------ REALTIME ------------------

  /// Aktif flash sale'lerde stok değişimini dinle. UI'da progress bar günceller.
  /// Stream, sadece değişen sale'in güncel verisini yayar.
  Stream<FlashSale> watchFlashSaleChanges() {
    final controller = StreamController<FlashSale>.broadcast();
    void handlePayload(dynamic payload) {
      try {
        final record = payload is Map
            ? (payload['new'] ?? payload['record'])
            : null;
        if (record is Map) {
          controller.add(FlashSale.fromJson(record as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('FlashSaleService.watch changes parse error: $e');
      }
    }

    final channel = _supabase
        .channel('flash_sales_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'flash_sales',
          callback: handlePayload,
        )
        .subscribe();

    controller.onCancel = () {
      _supabase.removeChannel(channel);
    };

    return controller.stream;
  }

  // ------------------ SELLER ADMIN ------------------

  /// Satıcı: kendi mağazasının flash sale'lerini getir.
  Future<List<FlashSale>> getMyShopFlashSales(String shopId) async {
    try {
      final response = await _supabase
          .from('flash_sales')
          .select('*, products!inner(id, name, image_url), shops!inner(id, name)')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((json) => FlashSale.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('FlashSaleService.getMyShopFlashSales error: $e');
      rethrow;
    }
  }

  /// Satıcı: yeni flash sale oluştur.
  Future<FlashSale> createFlashSale({
    required String productId,
    required String shopId,
    required double originalPrice,
    required double flashPrice,
    required int stockLimit,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Oturum açmanız gerekli');
    final response = await _supabase
        .from('flash_sales')
        .insert({
          'product_id': productId,
          'shop_id': shopId,
          'original_price': originalPrice,
          'flash_price': flashPrice,
          'stock_limit': stockLimit,
          'start_at': startAt.toUtc().toIso8601String(),
          'end_at': endAt.toUtc().toIso8601String(),
          'is_active': true,
          'created_by': userId,
        })
        .select('*, products!inner(id, name, image_url), shops!inner(id, name)')
        .single();
    return FlashSale.fromJson(response);
  }

  /// Satıcı: flash sale'i durdur (pasifleştir).
  Future<void> deactivateFlashSale(String saleId) async {
    await _supabase
        .from('flash_sales')
        .update({'is_active': false}).eq('id', saleId);
  }

  /// Satıcı: flash sale sil.
  Future<void> deleteFlashSale(String saleId) async {
    await _supabase.from('flash_sales').delete().eq('id', saleId);
  }
}