// order_service.dart (SERVER-AUTHORITATIVE ADAPTER)
// Tarih: 2026-08-02
//
// Eski API'ler (createOrder, createOrderWithItems, validateCoupon,
// useCoupon) tamamen KALDIRILDI. Bu servis sadece:
//
// 1) prepareCheckout + commitCod/commitBalance (yerel RPC)
// 2) Sorgulama: getOrder, getOrderItems, listOrders
// 3) Eski createOrder çağrılarını yeni akışa çeviren adapter
//
// UI katmanı artık sadece CheckoutService.prepareCheckout() sonucu
// dönen session.server_* alanlarını gösterir.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/checkout_session_model.dart';
import 'checkout_service.dart';

class OrderService {
  final SupabaseClient _supabase;
  final CheckoutService _checkoutService;

  OrderService(this._supabase, this._checkoutService);

  // ═══════════════════════════════════════════════════════════════
  // CREATE — DEPRECATED wrapper
  // ═══════════════════════════════════════════════════════════════
  // Eski UI akışı (CartScreen → OrderService.createOrder) bu adapter
  // üzerinden yeni CheckoutService.prepareCheckout + commit akışına
  // yönlendirilir. Hâlâ cartItems içeriyorsa sadece product_id +
  // quantity kullanılır; unit_price/flash_price ASLA kullanılmaz.
  // ═══════════════════════════════════════════════════════════════

  /// UI uyumluluğu için legacy adapter. Mümkünse kullanmayın; doğrudan
  /// [CheckoutService.prepareCheckout] + [CheckoutService.commitCod]
  /// çağırın.
  Future<CheckoutSession> createOrder({
    required List<CartItemForOrder> cartItems,
    required String addressId,
    required String paymentMethod,
    String? couponId,
    String? couponCode,
    String? notes,
    Map<String, dynamic>? invoiceData,
    String? orderGroupId,
  }) async {
    if (cartItems.isEmpty) {
      throw CheckoutException('empty_cart', 'Sepet boş.');
    }

    final request = CheckoutSessionRequest(
      items: cartItems
          .map((e) => CheckoutItemRequest(
                productId: e.productId,
                quantity: e.quantity,
                variant: e.variant,
                variantId: e.variantId,
                flashSaleId: e.flashSaleId,
              ))
          .toList(),
      addressId: addressId,
      paymentMethod: paymentMethod,
      idempotencyKey: CheckoutService.generateIdempotencyKey(
        prefix: 'order',
      ),
      couponId: couponId,
      couponCode: couponCode,
      notes: notes,
      invoiceData: invoiceData,
      orderGroupId: orderGroupId,
    );

    return _checkoutService.prepareCheckout(request);
  }

  /// Sadece CAP ayrıştırma için uyumluluk: eski "submitOrder" akışı
  /// yerine checkout.session_id döner.
  Future<CheckoutSession> submitOrder(CheckoutSession session) async {
    if (session.isCod) {
      await _checkoutService.commitCodOrder(session.id);
    } else if (session.isBalance) {
      await _checkoutService.commitBalanceOrder(session.id);
    } else {
      throw CheckoutException(
        'wrong_payment_method',
        'submitOrder yalnızca COD/Balance için; online için initOnlinePayment kullanın.',
      );
    }
    return session;
  }

  // ═══════════════════════════════════════════════════════════════
  // READ — sorgulama (yetki RLS üzerinden)
  // ═══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> listOrders({int limit = 50}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw CheckoutException('auth_required', 'Oturum açın.');
    final response = await _supabase
        .from('orders')
        .select('id, order_number, status, total, created_at, shop_id')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<Map<String, dynamic>?> getOrder(String orderId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw CheckoutException('auth_required', 'Oturum açın.');
    final response = await _supabase
        .from('orders')
        .select('*, order_items(*)')
        .eq('id', orderId)
        .eq('user_id', user.id)
        .maybeSingle();
    return response;
  }

  Future<List<Map<String, dynamic>>> getOrderItems(String orderId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw CheckoutException('auth_required', 'Oturum açın.');
    final response = await _supabase
        .from('order_items')
        .select('*')
        .eq('order_id', orderId);
    return List<Map<String, dynamic>>.from(response as List);
  }

  // ═══════════════════════════════════════════════════════════════
  // CANCEL — state machine RPC üzerinden (private.cancel_order)
  // ═══════════════════════════════════════════════════════════════

  Future<void> cancelOrder(String orderId, {String? reason}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw CheckoutException('auth_required', 'Oturum açın.');
    await _supabase.rpc('cancel_order', params: {
      'p_order_id': orderId,
      'p_reason': reason,
    });
  }
}

/// UI katmanının CartScreen'den geçirdiği minimum item.
@immutable
class CartItemForOrder {
  final String productId;
  final int quantity;
  final String? variant;
  final String? variantId;
  final String? flashSaleId;

  const CartItemForOrder({
    required this.productId,
    required this.quantity,
    this.variant,
    this.variantId,
    this.flashSaleId,
  });
}
