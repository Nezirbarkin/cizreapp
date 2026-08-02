// multi_shop_checkout_handler.dart
// Tarih: 2026-08-02
//
// Çoklu mağaza (multi-shop) ödeme akışı. Cart'taki ürünler
// shop_id bazında GRUPLANDIRILIR. Her mağaza için AYRI
// private.prepare_checkout_session çağrısı yapılır, AYNI
// order_group_id ile bağlanır. Toplam server_total SADECE
// tüm mağazaların session.server_total toplamıdır.
//
// Client tarafında ASLA mağaza-bazlı toplam hesaplanmaz.

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/cart_item.dart';
import '../models/checkout_session_model.dart';
import '../services/checkout_service.dart';

class MultiShopCheckoutHandler {
  final CheckoutService _checkoutService;

  MultiShopCheckoutHandler(this._checkoutService);

  Future<List<CheckoutSession>> prepareMultiShop({
    required List<CartItem> cartItems,
    required String addressId,
    required String paymentMethod,
    String? couponCode,
    String? notes,
    Map<String, dynamic>? invoiceData,
  }) async {
    if (cartItems.isEmpty) {
      throw CheckoutException('empty_cart', 'Sepet boş.');
    }

    // shop_id bazlı grupla
    final byShop = <String, List<CartItem>>{};
    for (final it in cartItems) {
      byShop.putIfAbsent(it.shopId, () => []).add(it);
    }

    final groupId = const Uuid().v4();
    final sessions = <CheckoutSession>[];

    for (final entry in byShop.entries) {
      final idem = CheckoutService.generateIdempotencyKey(
        prefix: 'multishop_${entry.key}',
      );
      final session = await _checkoutService.prepareCheckout(
        CheckoutSessionRequest(
          items: entry.value
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
          idempotencyKey: idem,
          couponCode: couponCode,
          notes: notes,
          invoiceData: invoiceData,
          orderGroupId: groupId,
        ),
      );
      sessions.add(session);
    }
    return sessions;
  }

  /// Tüm session'ları sırayla commit eder. Toplam sadece
  /// session.server_total toplamıdır.
  Future<List<CheckoutCommitResult>> commitAll(
    List<CheckoutSession> sessions,
  ) async {
    final results = <CheckoutCommitResult>[];
    for (final s in sessions) {
      if (s.isCod) {
        results.add(await _checkoutService.commitCodOrder(s.id));
      } else if (s.isBalance) {
        results.add(await _checkoutService.commitBalanceOrder(s.id));
      } else {
        throw CheckoutException(
          'unsupported',
          'Online ödeme için initOnlinePayment ayrı çağrılmalı.',
        );
      }
    }
    return results;
  }

  /// Görsel amaçlı: tüm mağazaların server_total toplamı.
  num totalServerAmount(List<CheckoutSession> sessions) {
    return sessions.fold<num>(0, (sum, s) => sum + s.serverTotal);
  }
}
