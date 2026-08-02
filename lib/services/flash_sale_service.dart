// flash_sale_service.dart (SERVER-AUTHORITATIVE)
// Tarih: 2026-08-02
//
// Eski public.claim_flash_sale / public.release_flash_sale RPC'leri
// KALDIRILDI. Flash satış rezervasyonu artık yalnızca:
//
// 1) private.prepare_checkout_session içinde FOR UPDATE ile
//    flash_sales.sold_count + private.flash_sale_reservations tablosu
//    üzerinden yapılır.
// 2) private.commit_cod_order / private.commit_balance_order /
//    private.commit_online_order rezervasyonu committed yapar.
//
// Bu servis sadece OKUMA yapar (UI banner, ürün detayda geri sayım).

import 'package:supabase_flutter/supabase_flutter.dart';

class FlashSaleService {
  final SupabaseClient _supabase;
  FlashSaleService(this._supabase);

  /// Aktif flash sale'ları listeler (ürün listeleme için).
  Future<List<Map<String, dynamic>>> getActiveFlashSales() async {
    final response = await _supabase
        .from('flash_sales')
        .select('id, product_id, flash_price, original_price, stock_limit, sold_count, starts_at, ends_at, status')
        .eq('status', 'active')
        .lte('starts_at', DateTime.now().toIso8601String())
        .gte('ends_at', DateTime.now().toIso8601String())
        .order('ends_at', ascending: true);
    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Ürün detay ekranı için aktif flash sale bilgisi.
  Future<Map<String, dynamic>?> getFlashSaleForProduct(String productId) async {
    final response = await _supabase
        .from('flash_sales')
        .select('id, flash_price, original_price, stock_limit, sold_count, ends_at, starts_at, status')
        .eq('product_id', productId)
        .eq('status', 'active')
        .lte('starts_at', DateTime.now().toIso8601String())
        .gte('ends_at', DateTime.now().toIso8601String())
        .maybeSingle();
    return response;
  }

  /// Kalan stok (sadece göstermelik; gerçek kontrol server'da).
  int? getRemainingStock(Map<String, dynamic> flashSale) {
    final limit = flashSale['stock_limit'] as int?;
    final sold = flashSale['sold_count'] as int?;
    if (limit == null || sold == null) return null;
    final remaining = limit - sold;
    return remaining < 0 ? 0 : remaining;
  }
}
