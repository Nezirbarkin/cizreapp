// cart_item.dart
// Tarih: 2026-08-02
//
// Sepette gosterilen urun modeli. Fiyat alanlari SADECE gorsel
// amaclidir; gercek odeme tutari server tarafindan hesaplanir.

import 'package:flutter/foundation.dart';

@immutable
class CartItem {
  final String productId;
  final String productName;
  final String? imageUrl;
  final String shopId;
  final String? shopName;
  final int quantity;
  final String? variant;
  final String? variantId;
  final num unitPrice; // sadece gorsel (X)
  final num? flashPrice; // sadece gorsel
  final String? flashSaleId;
  final bool isFlashSale;

  const CartItem({
    required this.productId,
    required this.productName,
    this.imageUrl,
    required this.shopId,
    this.shopName,
    required this.quantity,
    this.variant,
    this.variantId,
    required this.unitPrice,
    this.flashPrice,
    this.flashSaleId,
    this.isFlashSale = false,
  });

  CartItem copyWith({
    String? productId,
    String? productName,
    String? imageUrl,
    String? shopId,
    String? shopName,
    int? quantity,
    String? variant,
    String? variantId,
    num? unitPrice,
    num? flashPrice,
    String? flashSaleId,
    bool? isFlashSale,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      quantity: quantity ?? this.quantity,
      variant: variant ?? this.variant,
      variantId: variantId ?? this.variantId,
      unitPrice: unitPrice ?? this.unitPrice,
      flashPrice: flashPrice ?? this.flashPrice,
      flashSaleId: flashSaleId ?? this.flashSaleId,
      isFlashSale: isFlashSale ?? this.isFlashSale,
    );
  }
}
