
enum OrderStatus {
  pending,      // Beklemede
  confirmed,    // Onaylandı
  preparing,    // Hazırlanıyor
  ready,        // Hazır
  onTheWay,     // Yolda
  delivered,    // Teslim Edildi
  cancelled;    // İptal Edildi

  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Beklemede';
      case OrderStatus.confirmed:
        return 'Onaylandı';
      case OrderStatus.preparing:
        return 'Hazırlanıyor';
      case OrderStatus.ready:
        return 'Hazır';
      case OrderStatus.onTheWay:
        return 'Yolda';
      case OrderStatus.delivered:
        return 'Teslim Edildi';
      case OrderStatus.cancelled:
        return 'İptal Edildi';
    }
  }

  String get dbValue {
    // Veritabanında snake_case kullanılıyor
    switch (this) {
      case OrderStatus.onTheWay:
        return 'on_the_way';
      default:
        return name;
    }
  }

  static OrderStatus fromString(String value) {
    // Veritabanından gelen snake_case değerleri dönüştür
    switch (value) {
      case 'on_the_way':
        return OrderStatus.onTheWay;
      default:
        return OrderStatus.values.firstWhere(
          (status) => status.name == value,
          orElse: () => OrderStatus.pending,
        );
    }
  }
}

enum PaymentMethod {
  cash,           // Kapıda Nakit
  cardOnDelivery, // Kapıda Kart (POS ile)
  online;         // Online Ödeme (iyzico)

  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Kapıda Nakit';
      case PaymentMethod.cardOnDelivery:
        return 'Kapıda Kart';
      case PaymentMethod.online:
        return 'Online Ödeme';
    }
  }

  String get dbValue {
    return name;
  }

  static PaymentMethod fromString(String value) {
    return PaymentMethod.values.firstWhere(
      (method) => method.name == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}

/// Komisyon Durumu Enum
enum CommissionStatus {
  pending,    // Beklemede
  collected,  // Tahsil Edildi
  debt,       // Borç
  waived;     // Affedildi

  String get label {
    switch (this) {
      case CommissionStatus.pending:
        return 'Beklemede';
      case CommissionStatus.collected:
        return 'Tahsil Edildi';
      case CommissionStatus.debt:
        return 'Borç';
      case CommissionStatus.waived:
        return 'Affedildi';
    }
  }

  String get dbValue {
    return name;
  }

  static CommissionStatus fromString(String value) {
    return CommissionStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => CommissionStatus.pending,
    );
  }
}

class OrderItem {
  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final String? productImageUrl;
  final String? shopId;
  final String? shopName;
  final DateTime createdAt;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.productImageUrl,
    this.shopId,
    this.shopName,
    required this.createdAt,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? 'Ürün',
      price: (json['price'] as num?)?.toDouble() ??
             (json['product_price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] as int? ?? 0,
      productImageUrl: json['product_image_url'] as String?,
      shopId: json['shop_id'] as String?,
      shopName: json['shop_name'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  double get subtotal => price * quantity;
}

class Order {
  final String id;
  final String userId;
  final String shopId;
  final String? addressId;
  final int? orderNumberInt;  // Sıralı sipariş numarası (1'den başlar)
  final double subtotal;
  final double discountAmount;
  final double deliveryFee;
  final double totalAmount;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final String paymentStatus;
  final List<OrderItem> items;
  final String? deliveryNotes;
  final DateTime? estimatedDeliveryTime;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  // İlişkili veriler
  final String? addressDisplay;
  final String? shopName;

  // Komisyon alanları
  final CommissionStatus? commissionStatus;
  final double? adminCommission;
  final double? adminDeliveryFee;
  final double? sellerNetAmount;
  final double? commissionDebt;
  final DateTime? commissionCalculatedAt;
  
  // Satıcı kurye durumu (ilişkili veri)
  final bool? hasOwnCourier;

  // Müşteri telefonu
  final String? customerPhone;

  // Kupon alanları
  final String? couponId;
  final double couponDiscount;

  // Grup sipariş alanları (çok dükkanlı sipariş sistemi için)
  final String? orderGroupId;        // Grup sipariş ID
  final String? groupOrderNumber;     // Grup sipariş numarası (müşteriye gösterilen)

  Order({
    required this.id,
    required this.userId,
    required this.shopId,
    this.addressId,
    this.orderNumberInt,
    required this.subtotal,
    this.discountAmount = 0,
    required this.deliveryFee,
    required this.totalAmount,
    required this.status,
    required this.paymentMethod,
    this.paymentStatus = 'pending',
    required this.items,
    this.deliveryNotes,
    this.estimatedDeliveryTime,
    this.deliveredAt,
    this.cancelledAt,
    this.cancellationReason,
    required this.createdAt,
    required this.updatedAt,
    this.addressDisplay,
    this.shopName,
    // Komisyon alanları
    this.commissionStatus,
    this.adminCommission,
    this.adminDeliveryFee,
    this.sellerNetAmount,
    this.commissionDebt,
    this.commissionCalculatedAt,
    this.hasOwnCourier,
    // Müşteri telefonu
    this.customerPhone,
    // Kupon alanları
    this.couponId,
    this.couponDiscount = 0,
    // Grup sipariş alanları
    this.orderGroupId,
    this.groupOrderNumber,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final itemsData = json['order_items'] as List? ?? [];
    final items = itemsData
        .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return Order(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      shopId: json['shop_id'] as String? ?? '',
      addressId: json['address_id'] as String?,
      orderNumberInt: json['order_number_int'] as int?,
      // subtotal - hem eski hem yeni alan isimlerini destekle
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      // discount_amount veya discount
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ??
                      (json['discount'] as num?)?.toDouble() ?? 0,
      // delivery_fee
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      // total_amount veya total
      totalAmount: (json['total_amount'] as num?)?.toDouble() ??
                   (json['total'] as num?)?.toDouble() ?? 0.0,
      status: OrderStatus.fromString(json['status'] as String? ?? 'pending'),
      paymentMethod: PaymentMethod.fromString(json['payment_method'] as String? ?? 'cash'),
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      items: items,
      // delivery_notes veya notes
      deliveryNotes: json['delivery_notes'] as String? ??
                     json['notes'] as String?,
      estimatedDeliveryTime: json['estimated_delivery_time'] != null
          ? DateTime.parse(json['estimated_delivery_time'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
      cancellationReason: json['cancellation_reason'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      addressDisplay: json['address_display'] as String? ??
                      json['delivery_address_text'] as String?,
      // shopName - hem doğrudan alan hem de ilişkili tablo desteği
      shopName: json['shop_name'] as String? ??
               (json['shops'] != null && json['shops'] is Map
                   ? json['shops']['name'] as String?
                   : null),
      // Komisyon alanları
      commissionStatus: json['commission_status'] != null
          ? CommissionStatus.fromString(json['commission_status'] as String)
          : null,
      adminCommission: (json['admin_commission'] as num?)?.toDouble(),
      adminDeliveryFee: (json['admin_delivery_fee'] as num?)?.toDouble(),
      sellerNetAmount: (json['seller_net_amount'] as num?)?.toDouble(),
      commissionDebt: (json['commission_debt'] as num?)?.toDouble(),
      commissionCalculatedAt: json['commission_calculated_at'] != null
          ? DateTime.parse(json['commission_calculated_at'] as String)
          : null,
      hasOwnCourier: json['has_own_courier'] as bool?,
      // Müşteri telefonu
      customerPhone: json['customer_phone'] as String?,
      // Kupon alanları
      couponId: json['coupon_id'] as String?,
      couponDiscount: (json['coupon_discount'] as num?)?.toDouble() ?? 0,
      // Grup sipariş alanları
      orderGroupId: json['order_group_id'] as String?,
      groupOrderNumber: json['group_order_number'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'shop_id': shopId,
      'address_id': addressId,
      'order_number_int': orderNumberInt,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'delivery_fee': deliveryFee,
      'total': totalAmount,
      'status': status.dbValue,
      'payment_method': paymentMethod.dbValue,
      'payment_status': paymentStatus,
      'delivery_notes': deliveryNotes,
      'estimated_delivery_time': estimatedDeliveryTime?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancellation_reason': cancellationReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'commission_status': commissionStatus?.dbValue,
      'admin_commission': adminCommission,
      'admin_delivery_fee': adminDeliveryFee,
      'seller_net_amount': sellerNetAmount,
      'commission_debt': commissionDebt,
      'commission_calculated_at': commissionCalculatedAt?.toIso8601String(),
      // Müşteri telefonu
      'customer_phone': customerPhone,
      // Kupon alanları
      'coupon_id': couponId,
      'coupon_discount': couponDiscount,
      // Grup sipariş alanları
      'order_group_id': orderGroupId,
      'group_order_number': groupOrderNumber,
    };
  }

  // Sipariş tamamlanmış mı?
  bool get isCompleted => status == OrderStatus.delivered;

  // Sipariş iptal edilmiş mi?
  bool get isCancelled => status == OrderStatus.cancelled;

  // Sipariş devam ediyor mu?
  bool get isActive => !isCompleted && !isCancelled;

  // Ödeme yapıldı mı?
  bool get isPaid => paymentStatus == 'completed' || paymentStatus == 'paid';

  // Sipariş durumunu değiştirebilir miyiz?
  bool get canCancel => status == OrderStatus.pending || status == OrderStatus.confirmed;

  // Komisyon durumu: Borçlu mu?
  bool get hasDebt => (commissionDebt ?? 0) > 0;
  
  // Admin toplam kazancı
  double get totalAdminEarnings => 
      (adminCommission ?? 0) + (adminDeliveryFee ?? 0);

  // Tarih formatı
  String get formattedDate {
    return '${createdAt.day}.${createdAt.month}.${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  Order copyWith({
    String? id,
    String? userId,
    String? shopId,
    String? addressId,
    int? orderNumberInt,
    double? subtotal,
    double? discountAmount,
    double? deliveryFee,
    double? totalAmount,
    OrderStatus? status,
    PaymentMethod? paymentMethod,
    String? paymentStatus,
    List<OrderItem>? items,
    String? deliveryNotes,
    DateTime? estimatedDeliveryTime,
    DateTime? deliveredAt,
    DateTime? cancelledAt,
    String? cancellationReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? addressDisplay,
    String? shopName,
    // Komisyon alanları
    CommissionStatus? commissionStatus,
    double? adminCommission,
    double? adminDeliveryFee,
    double? sellerNetAmount,
    double? commissionDebt,
    DateTime? commissionCalculatedAt,
    bool? hasOwnCourier,
  }) {
    return Order(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      shopId: shopId ?? this.shopId,
      addressId: addressId ?? this.addressId,
      orderNumberInt: orderNumberInt ?? this.orderNumberInt,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      items: items ?? this.items,
      deliveryNotes: deliveryNotes ?? this.deliveryNotes,
      estimatedDeliveryTime: estimatedDeliveryTime ?? this.estimatedDeliveryTime,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      addressDisplay: addressDisplay ?? this.addressDisplay,
      shopName: shopName ?? this.shopName,
      commissionStatus: commissionStatus ?? this.commissionStatus,
      adminCommission: adminCommission ?? this.adminCommission,
      adminDeliveryFee: adminDeliveryFee ?? this.adminDeliveryFee,
      sellerNetAmount: sellerNetAmount ?? this.sellerNetAmount,
      commissionDebt: commissionDebt ?? this.commissionDebt,
      commissionCalculatedAt: commissionCalculatedAt ?? this.commissionCalculatedAt,
      hasOwnCourier: hasOwnCourier ?? this.hasOwnCourier,
    );
  }
}
