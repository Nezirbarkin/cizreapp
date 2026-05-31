// Kurye Atama Modeli
// Kuryelerin sipariş atamalarını yönetmek için

enum CourierAssignmentStatus {
  assigned,    // Atandı
  pickedUp,    // Alındı
  delivered,   // Teslim Edildi
  cancelled;   // İptal Edildi

  String get label {
    switch (this) {
      case CourierAssignmentStatus.assigned:
        return 'Atandı';
      case CourierAssignmentStatus.pickedUp:
        return 'Alındı';
      case CourierAssignmentStatus.delivered:
        return 'Teslim Edildi';
      case CourierAssignmentStatus.cancelled:
        return 'İptal Edildi';
    }
  }

  String get dbValue => name;

  static CourierAssignmentStatus fromString(String value) {
    return CourierAssignmentStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => CourierAssignmentStatus.assigned,
    );
  }
}

class CourierAssignment {
  final String id;
  final String orderId;
  final String courierId;
  final CourierAssignmentStatus status;
  final double feeAmount;
  final DateTime assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  // İlişkili veriler
  final Map<String, dynamic>? order;
  final String? courierName;
  final String? courierPhone;

  CourierAssignment({
    required this.id,
    required this.orderId,
    required this.courierId,
    required this.status,
    required this.feeAmount,
    required this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.cancelledAt,
    this.cancellationReason,
    required this.createdAt,
    required this.updatedAt,
    this.order,
    this.courierName,
    this.courierPhone,
  });

  factory CourierAssignment.fromJson(Map<String, dynamic> json) {
    return CourierAssignment(
      id: json['id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      courierId: json['courier_id'] as String? ?? '',
      status: CourierAssignmentStatus.fromString(json['status'] as String? ?? 'assigned'),
      feeAmount: (json['fee_amount'] as num?)?.toDouble() ?? 0,
      assignedAt: json['assigned_at'] != null
          ? DateTime.parse(json['assigned_at'] as String)
          : DateTime.now(),
      pickedUpAt: json['picked_up_at'] != null
          ? DateTime.parse(json['picked_up_at'] as String)
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
      order: json['orders'] as Map<String, dynamic>?,
      courierName: json['courier_name'] as String?,
      courierPhone: json['courier_phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'courier_id': courierId,
      'status': status.dbValue,
      'fee_amount': feeAmount,
      'assigned_at': assignedAt.toIso8601String(),
      'picked_up_at': pickedUpAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancellation_reason': cancellationReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

// Kurye Sipariş Modeli
// Kurye paneline düşen siparişler için
class CourierOrder {
  final String id;
  final String orderNumber;
  final double totalAmount;
  final String status;
  final String paymentMethod;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final String? shopName;
  final List<CourierOrderItem> items;
  final DateTime createdAt;

  CourierOrder({
    required this.id,
    required this.orderNumber,
    required this.totalAmount,
    required this.status,
    required this.paymentMethod,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.shopName,
    required this.items,
    required this.createdAt,
  });

  factory CourierOrder.fromJson(Map<String, dynamic> json) {
    final itemsData = json['order_items'] as List? ?? [];
    final items = itemsData
        .map((item) => CourierOrderItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return CourierOrder(
      id: json['id'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? '#${json['id']?.toString().substring(0, 8) ?? ''}',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      deliveryAddress: json['address_display'] as String? ??
          json['delivery_address_text'] as String?,
      shopName: json['shop_name'] as String? ??
          (json['shops'] != null ? (json['shops'] as Map)['name'] as String? : null),
      items: items,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

class CourierOrderItem {
  final String productName;
  final int quantity;
  final String? productImageUrl;

  CourierOrderItem({
    required this.productName,
    required this.quantity,
    this.productImageUrl,
  });

  factory CourierOrderItem.fromJson(Map<String, dynamic> json) {
    return CourierOrderItem(
      productName: json['product_name'] as String? ?? 'Ürün',
      quantity: json['quantity'] as int? ?? 1,
      productImageUrl: json['product_image_url'] as String?,
    );
  }
}
