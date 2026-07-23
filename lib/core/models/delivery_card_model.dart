class DeliveryCard {
  final String id;
  final String name;
  final String? description;
  final double fee;
  final int deliveryTimeMin;
  final int deliveryTimeMax;
  final double? freeMinOrder;
  final bool isActive;
  final int displayOrder;

  DeliveryCard({
    required this.id,
    required this.name,
    this.description,
    required this.fee,
    required this.deliveryTimeMin,
    required this.deliveryTimeMax,
    this.freeMinOrder,
    required this.isActive,
    required this.displayOrder,
  });

  bool get isFree => fee == 0;
  String get timeRange => '${deliveryTimeMin}dk - ${deliveryTimeMax}dk';
  String get feeDisplay => isFree ? 'BEDAVA' : '₺${fee.toStringAsFixed(2)}';

  factory DeliveryCard.fromJson(Map<String, dynamic> json) {
    return DeliveryCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
      deliveryTimeMin: json['delivery_time_min'] as int? ?? 30,
      deliveryTimeMax: json['delivery_time_max'] as int? ?? 60,
      freeMinOrder: (json['free_min_order'] as num?)?.toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'fee': fee,
      'delivery_time_min': deliveryTimeMin,
      'delivery_time_max': deliveryTimeMax,
      'free_min_order': freeMinOrder,
      'is_active': isActive,
      'display_order': displayOrder,
    };
  }
}
