// cart_service.dart
// Tarih: 2026-08-02
//
// Cart SADECE urun listesi tutar. Fiyat, stok, flash_price HICBIR
// SEKILDE client'ta hesaplanmaz. CheckoutService.prepareCheckout
// snapshot'i serverdan alir.
//
// Eski "addToCart" + "claimFlashSale" + "releaseFlashSale" uca
// yapiskan sepet akisi kaldirildi. Flash sale artik SADECE session
// rezervasyonu ile calisir.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';
import '../models/checkout_session_model.dart';
import 'checkout_service.dart';

class CartService {
  final CheckoutService _checkoutService;

  CartService([SupabaseClient? supabase, CheckoutService? checkoutService])
    : _checkoutService =
          checkoutService ??
          CheckoutService(supabase ?? Supabase.instance.client);

  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Client-side toplam sadece gorsel amacli (X). Gercek tutar
  /// server tarafindan prepare_checkout_session sonucu gelir.
  @visibleForTesting
  num get displaySubtotal {
    return _items.fold(
      0,
      (sum, item) => sum + (item.unitPrice * item.quantity),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LOCAL CART (UI)
  // ═══════════════════════════════════════════════════════════════

  void addItem(CartItem item) {
    final idx = _items.indexWhere(
      (e) =>
          e.productId == item.productId &&
          e.variantId == item.variantId &&
          e.flashSaleId == item.flashSaleId,
    );
    if (idx >= 0) {
      _items[idx] = _items[idx].copyWith(
        quantity: _items[idx].quantity + item.quantity,
      );
    } else {
      _items.add(item);
    }
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
    }
  }

  void updateQuantity(int index, int quantity) {
    if (index < 0 || index >= _items.length) return;
    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      _items[index] = _items[index].copyWith(quantity: quantity);
    }
  }

  void clear() => _items.clear();

  // ═══════════════════════════════════════════════════════════════
  // SERVER-AUTHORITATIVE CHECKOUT
  // ═══════════════════════════════════════════════════════════════

  /// Sepetteki urunleri servera gonderip gercek fiyatlari al.
  /// Burada ASLA cart.item.unitPrice + cart.item.quantity hesabi
  /// YAPILMAZ; sadece product_id + quantity aktarilir.
  Future<CheckoutSession> prepareCheckout({
    required String addressId,
    required String paymentMethod,
    String? couponId,
    String? couponCode,
    String? notes,
    Map<String, dynamic>? invoiceData,
    String? orderGroupId,
  }) async {
    final request = CheckoutSessionRequest(
      items: _items
          .map(
            (e) => CheckoutItemRequest(
              productId: e.productId,
              quantity: e.quantity,
              variant: e.variant,
              variantId: e.variantId,
              flashSaleId: e.flashSaleId,
            ),
          )
          .toList(),
      addressId: addressId,
      paymentMethod: paymentMethod,
      idempotencyKey: CheckoutService.generateIdempotencyKey(prefix: 'cart'),
      couponId: couponId,
      couponCode: couponCode,
      notes: notes,
      invoiceData: invoiceData,
      orderGroupId: orderGroupId,
    );
    return _checkoutService.prepareCheckout(request);
  }
}
