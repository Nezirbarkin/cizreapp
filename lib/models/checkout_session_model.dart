// checkout_session_model.dart
// Server-authoritative checkout oturum modeli
// Tarih: 2026-08-02
//
// Bu model, private.server_checkout_sessions tablosundan gelen
// verileri tutar. Client BU DEGERLERI KESINLIKLE KULLANICIDAN ALMAZ.
// Sadece RPC'den gelen snapshot kullanilir.

import 'package:flutter/foundation.dart';

@immutable
class CheckoutItemSnapshot {
  final String productId;
  final String productName;
  final String shopId;
  final String? shopName;
  final int quantity;
  final String? variant;
  final String? variantId;
  final num unitPrice;
  final num? flashPrice;
  final num lineTotal;
  final num lineDiscount;
  final num commissionAmount;
  final bool isFlashSale;
  final String? flashSaleId;
  final String? imageUrl;

  const CheckoutItemSnapshot({
    required this.productId,
    required this.productName,
    required this.shopId,
    this.shopName,
    required this.quantity,
    this.variant,
    this.variantId,
    required this.unitPrice,
    this.flashPrice,
    required this.lineTotal,
    required this.lineDiscount,
    required this.commissionAmount,
    this.isFlashSale = false,
    this.flashSaleId,
    this.imageUrl,
  });

  factory CheckoutItemSnapshot.fromJson(Map<String, dynamic> json) {
    return CheckoutItemSnapshot(
      productId: json['product_id'] as String,
      productName: json['product_name'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      variant: json['variant'] as String?,
      variantId: json['variant_id'] as String?,
      unitPrice: json['unit_price'] as num? ?? 0,
      flashPrice: json['flash_price'] as num?,
      lineTotal: json['line_total'] as num? ?? 0,
      lineDiscount: json['line_discount'] as num? ?? 0,
      commissionAmount: json['commission_amount'] as num? ?? 0,
      isFlashSale: json['is_flash_sale'] as bool? ?? false,
      flashSaleId: json['flash_sale_id'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }
}

enum CheckoutSessionStatus { draft, active, completed, expired, cancelled }

CheckoutSessionStatus _statusFromString(String? raw) {
  switch (raw) {
    case 'completed':
      return CheckoutSessionStatus.completed;
    case 'expired':
      return CheckoutSessionStatus.expired;
    case 'cancelled':
      return CheckoutSessionStatus.cancelled;
    case 'active':
    case 'draft':
    default:
      return CheckoutSessionStatus.active;
  }
}

@immutable
class CheckoutSession {
  final String id;
  final String userId;
  final String? addressId;
  final String paymentMethod;
  final String? couponId;
  final String? couponCode;

  // SERVER-AUTHORITATIVE (asla client hesaplamaz)
  final num serverSubtotal;
  final num serverDeliveryFee;
  final num serverCouponDiscount;
  final num serverTotal;
  final num serverCommissionTotal;

  // iyzico beklentileri (callback ile karsilastirilacak)
  final num? expectedPaidPrice;
  final String? paymentTransactionId;

  // Detaylar
  final List<CheckoutItemSnapshot> items;
  final String? notes;
  final Map<String, dynamic>? invoiceData;
  final CheckoutSessionStatus status;
  final DateTime? expiresAt;
  final DateTime createdAt;

  const CheckoutSession({
    required this.id,
    required this.userId,
    this.addressId,
    required this.paymentMethod,
    this.couponId,
    this.couponCode,
    required this.serverSubtotal,
    required this.serverDeliveryFee,
    required this.serverCouponDiscount,
    required this.serverTotal,
    required this.serverCommissionTotal,
    this.expectedPaidPrice,
    this.paymentTransactionId,
    required this.items,
    this.notes,
    this.invoiceData,
    required this.status,
    this.expiresAt,
    required this.createdAt,
  });

  factory CheckoutSession.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items_snapshot'] as List<dynamic>? ?? [];
    return CheckoutSession(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      addressId: json['address_id'] as String?,
      paymentMethod: json['payment_method'] as String? ?? 'cod',
      couponId: json['coupon_id'] as String?,
      couponCode: json['coupon_code'] as String?,
      serverSubtotal: json['server_subtotal'] as num? ?? 0,
      serverDeliveryFee: json['server_delivery_fee'] as num? ?? 0,
      serverCouponDiscount: json['server_coupon_discount'] as num? ?? 0,
      serverTotal: json['server_total'] as num? ?? 0,
      serverCommissionTotal: json['server_commission_total'] as num? ?? 0,
      expectedPaidPrice: json['expected_paid_price'] as num?,
      paymentTransactionId: json['payment_transaction_id'] as String?,
      items: itemsRaw
          .map((e) => CheckoutItemSnapshot.fromJson(e as Map<String, dynamic>))
          .toList(),
      notes: json['notes'] as String?,
      invoiceData: json['invoice_data'] as Map<String, dynamic>?,
      status: _statusFromString(json['status'] as String?),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  bool get isExpired =>
      status == CheckoutSessionStatus.expired ||
      (expiresAt != null && expiresAt!.isBefore(DateTime.now()));

  bool get isCompleted => status == CheckoutSessionStatus.completed;

  bool get isBalance => paymentMethod == 'balance';
  bool get isOnline => paymentMethod == 'online';
  bool get isCod => paymentMethod == 'cod' || paymentMethod == 'cash_on_delivery';

  CheckoutSession copyWith({
    String? id,
    String? userId,
    String? addressId,
    String? paymentMethod,
    String? couponId,
    String? couponCode,
    num? serverSubtotal,
    num? serverDeliveryFee,
    num? serverCouponDiscount,
    num? serverTotal,
    num? serverCommissionTotal,
    num? expectedPaidPrice,
    String? paymentTransactionId,
    List<CheckoutItemSnapshot>? items,
    String? notes,
    Map<String, dynamic>? invoiceData,
    CheckoutSessionStatus? status,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) {
    return CheckoutSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      addressId: addressId ?? this.addressId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      couponId: couponId ?? this.couponId,
      couponCode: couponCode ?? this.couponCode,
      serverSubtotal: serverSubtotal ?? this.serverSubtotal,
      serverDeliveryFee: serverDeliveryFee ?? this.serverDeliveryFee,
      serverCouponDiscount: serverCouponDiscount ?? this.serverCouponDiscount,
      serverTotal: serverTotal ?? this.serverTotal,
      serverCommissionTotal: serverCommissionTotal ?? this.serverCommissionTotal,
      expectedPaidPrice: expectedPaidPrice ?? this.expectedPaidPrice,
      paymentTransactionId: paymentTransactionId ?? this.paymentTransactionId,
      items: items ?? this.items,
      notes: notes ?? this.notes,
      invoiceData: invoiceData ?? this.invoiceData,
      status: status ?? this.status,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Client'ın gönderdiği minimum payload.
/// Client ASLA fiyat, ücret, iskonto göndermez.
@immutable
class CheckoutSessionRequest {
  final List<CheckoutItemRequest> items;
  final String addressId;
  final String paymentMethod; // 'cod' | 'online' | 'balance'
  final String idempotencyKey;
  final String? couponId;
  final String? couponCode;
  final String? notes;
  final Map<String, dynamic>? invoiceData;
  final String? orderGroupId;

  const CheckoutSessionRequest({
    required this.items,
    required this.addressId,
    required this.paymentMethod,
    required this.idempotencyKey,
    this.couponId,
    this.couponCode,
    this.notes,
    this.invoiceData,
    this.orderGroupId,
  });

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((e) => e.toJson()).toList(),
      'address_id': addressId,
      'payment_method': paymentMethod,
      'idempotency_key': idempotencyKey,
      if (couponId != null) 'coupon_id': couponId,
      if (couponCode != null) 'coupon_code': couponCode,
      if (notes != null) 'notes': notes,
      if (invoiceData != null) 'invoice_data': invoiceData,
      if (orderGroupId != null) 'order_group_id': orderGroupId,
    };
  }
}

@immutable
class CheckoutItemRequest {
  final String productId;
  final int quantity;
  final String? variant;
  final String? variantId;
  final String? flashSaleId;

  const CheckoutItemRequest({
    required this.productId,
    required this.quantity,
    this.variant,
    this.variantId,
    this.flashSaleId,
  });

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'quantity': quantity,
      if (variant != null) 'variant': variant,
      if (variantId != null) 'variant_id': variantId,
      if (flashSaleId != null) 'flash_sale_id': flashSaleId,
    };
  }
}
