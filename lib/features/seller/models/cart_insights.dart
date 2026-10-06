/// Satıcının sepet istatistiği (Görev 3.3) — `get_shop_cart_stats` dönüşü.
///
/// Yalnız sayılar: hangi müşterinin sepetinde olduğu satıcıya açılmaz.
library;

double _toDouble(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

int _toInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

DateTime? _toTime(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value)?.toUtc() : null;

class CartProductStat {
  const CartProductStat({
    required this.productId,
    required this.name,
    required this.price,
    required this.effectivePrice,
    required this.users,
    required this.quantity,
    this.image,
    this.discountPrice,
    this.oldPrice,
    this.isAvailable = true,
    this.isDigital = false,
    this.firstAddedAt,
    this.lastAddedAt,
    this.notifiedUsers = 0,
    this.lastNotifiedAt,
  });

  final String productId;
  final String name;
  final String? image;
  final double price;
  final double? discountPrice;
  final double? oldPrice;

  /// Müşterinin şu an ödeyeceği fiyat (geçerli indirim varsa o).
  final double effectivePrice;
  final bool isAvailable;
  final bool isDigital;

  /// Ürünü sepetinde tutan farklı müşteri sayısı.
  final int users;

  /// Sepetlerdeki toplam adet.
  final int quantity;
  final DateTime? firstAddedAt;
  final DateTime? lastAddedAt;

  /// Son 30 günde indirim bildirimi giden müşteri sayısı.
  final int notifiedUsers;
  final DateTime? lastNotifiedAt;

  bool get hasDiscount => effectivePrice < price;

  /// Sepetteki toplam tutar (adet × güncel fiyat).
  double get cartValue => quantity * effectivePrice;

  factory CartProductStat.fromJson(Map<String, dynamic> json) {
    final discount = json['discount_price'];
    final old = json['old_price'];
    return CartProductStat(
      productId: json['product_id'] as String,
      name: (json['name'] as String?) ?? '',
      image: json['image'] as String?,
      price: _toDouble(json['price']),
      discountPrice: discount == null ? null : _toDouble(discount),
      oldPrice: old == null ? null : _toDouble(old),
      effectivePrice: _toDouble(json['effective_price'] ?? json['price']),
      isAvailable: json['is_available'] as bool? ?? true,
      isDigital: json['is_digital'] as bool? ?? false,
      users: _toInt(json['users']),
      quantity: _toInt(json['quantity']),
      firstAddedAt: _toTime(json['first_added_at']),
      lastAddedAt: _toTime(json['last_added_at']),
      notifiedUsers: _toInt(json['notified_users']),
      lastNotifiedAt: _toTime(json['last_notified_at']),
    );
  }

  /// %[percent] indirimle müşterinin göreceği fiyat (sunucudaki
  /// `seller_bulk_set_discount` gibi LİSTE fiyatından hesaplanır, 2 hane).
  double priceAfterPercent(double percent) =>
      (price * (1 - percent / 100) * 100).roundToDouble() / 100;

  /// Bu yüzde gerçekten ucuzlatır mı? (Mevcut indirimden daha az indirim
  /// müşterinin fiyatını ARTTIRIR; o durumda bildirim de gitmez.)
  bool percentLowersPrice(double percent) {
    final next = priceAfterPercent(percent);
    return next > 0 && next < effectivePrice;
  }
}

class ShopCartStats {
  const ShopCartStats({
    required this.users,
    required this.productCount,
    required this.quantity,
    required this.value,
    required this.products,
  });

  static const ShopCartStats empty =
      ShopCartStats(users: 0, productCount: 0, quantity: 0, value: 0, products: []);

  /// Mağazanın en az bir ürününü sepetinde tutan farklı müşteri sayısı.
  final int users;
  final int productCount;
  final int quantity;

  /// Sepetlerde bekleyen toplam tutar.
  final double value;
  final List<CartProductStat> products;

  bool get isEmpty => products.isEmpty;

  factory ShopCartStats.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rows = (json['products'] as List?) ?? const [];
    return ShopCartStats(
      users: _toInt(summary['users']),
      productCount: _toInt(summary['products']),
      quantity: _toInt(summary['quantity']),
      value: _toDouble(summary['value']),
      products: [
        for (final row in rows) CartProductStat.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
    );
  }
}
