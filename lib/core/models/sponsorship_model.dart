/// Satıcı öne çıkarma (sponsorlu vitrin) modelleri — Görev 3.2.
///
/// Veritabanı değerleri göç 20260928000006 ile birebir aynıdır.
library;

/// Öne çıkarmanın gösterildiği vitrin.
enum SponsorPlacement {
  shopList(
    'shop_list',
    'Dükkanlar listesi',
    'Ana sayfadaki ve Tüm Dükkanlar listesinde en üstte',
    isProduct: false,
  ),
  shopCategory(
    'shop_category',
    'Kategori sayfası',
    'Mağazanın kategori sayfasında en üstte',
    isProduct: false,
  ),
  productCategory(
    'product_category',
    'Ürünler sayfası',
    'Ürünler sayfasında ve ürünün kategorisinde en üstte',
    isProduct: true,
  ),
  productDiscount(
    'product_discount',
    'İndirimdekiler',
    'İndirimdeki ürünlerin en üstünde (yalnız indirimli ürün)',
    isProduct: true,
  );

  const SponsorPlacement(this.dbValue, this.label, this.description, {required this.isProduct});

  final String dbValue;
  final String label;
  final String description;

  /// Ürün mü öne çıkar (değilse mağaza)?
  final bool isProduct;

  static SponsorPlacement? fromDb(Object? value) {
    for (final placement in values) {
      if (placement.dbValue == value) return placement;
    }
    return null;
  }
}

/// Bir bitiş zamanı şu an hâlâ geçerli mi (sunucu saatiyle yazılır, UTC).
bool isSponsoredUntil(DateTime? until, {DateTime? now}) =>
    until != null && until.isAfter((now ?? DateTime.now()).toUtc());

/// `…_until` / zaman sütunu (ISO metin) → UTC; boşsa ya da bozuksa null.
DateTime? parseSponsorTime(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value)?.toUtc() : null;

DateTime? _parseTime(Object? value) => parseSponsorTime(value);

double _toDouble(Object? value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

/// Satın alınabilir paket (vitrin + süre + fiyat).
class SponsorshipPackage {
  const SponsorshipPackage({
    required this.id,
    required this.placement,
    required this.name,
    required this.durationDays,
    required this.price,
    this.sortOrder = 0,
  });

  final String id;
  final SponsorPlacement placement;
  final String name;
  final int durationDays;
  final double price;
  final int sortOrder;

  /// Tanınmayan vitrin (daha yeni bir sürümün) null döner ve listelenmez.
  static SponsorshipPackage? tryFromJson(Map<String, dynamic> json) {
    final placement = SponsorPlacement.fromDb(json['placement']);
    if (placement == null) return null;
    return SponsorshipPackage(
      id: json['id'] as String,
      placement: placement,
      name: (json['name'] as String?) ?? '',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 1,
      price: _toDouble(json['price']),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

enum SponsorshipStatus {
  pending,
  active,
  rejected,
  cancelled;

  static SponsorshipStatus fromDb(Object? value) => switch (value) {
    'pending' => SponsorshipStatus.pending,
    'rejected' => SponsorshipStatus.rejected,
    'cancelled' => SponsorshipStatus.cancelled,
    _ => SponsorshipStatus.active,
  };
}

/// Satın alınmış bir öne çıkarma.
class ShopSponsorship {
  const ShopSponsorship({
    required this.id,
    required this.shopId,
    required this.placement,
    required this.packageName,
    required this.durationDays,
    required this.pricePaid,
    required this.status,
    required this.createdAt,
    this.productId,
    this.startsAt,
    this.endsAt,
    this.reviewNote,
  });

  final String id;
  final String shopId;
  final String? productId;
  final SponsorPlacement placement;
  final String packageName;
  final int durationDays;
  final double pricePaid;
  final SponsorshipStatus status;
  final DateTime createdAt;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? reviewNote;

  static ShopSponsorship? tryFromJson(Map<String, dynamic> json) {
    final placement = SponsorPlacement.fromDb(json['placement']);
    if (placement == null) return null;
    return ShopSponsorship(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      productId: json['product_id'] as String?,
      placement: placement,
      packageName: (json['package_name'] as String?) ?? '',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 0,
      pricePaid: _toDouble(json['price_paid']),
      status: SponsorshipStatus.fromDb(json['status']),
      createdAt: _parseTime(json['created_at']) ?? DateTime.now().toUtc(),
      startsAt: _parseTime(json['starts_at']),
      endsAt: _parseTime(json['ends_at']),
      reviewNote: json['review_note'] as String?,
    );
  }

  /// Şu an vitrinde mi?
  bool isRunning(DateTime now) {
    final start = startsAt, end = endsAt;
    if (status != SponsorshipStatus.active || start == null || end == null) return false;
    final t = now.toUtc();
    return !t.isBefore(start) && t.isBefore(end);
  }

  /// Ödendi, sırasını bekliyor (önceki öne çıkarma bitince başlar).
  bool isQueued(DateTime now) =>
      status == SponsorshipStatus.active && startsAt != null && now.toUtc().isBefore(startsAt!);

  bool isFinished(DateTime now) =>
      status == SponsorshipStatus.active && endsAt != null && !now.toUtc().isBefore(endsAt!);

  String statusLabel(DateTime now) => switch (status) {
    SponsorshipStatus.pending => 'Onay bekliyor',
    SponsorshipStatus.rejected => 'Reddedildi',
    SponsorshipStatus.cancelled => 'İptal edildi',
    SponsorshipStatus.active =>
      isRunning(now) ? 'Yayında' : (isQueued(now) ? 'Sırada' : 'Sona erdi'),
  };
}

/// Satın alma sonucu (RPC dönüşü).
class SponsorshipPurchase {
  const SponsorshipPurchase({
    required this.id,
    required this.status,
    required this.placement,
    required this.price,
    required this.balanceAfter,
    this.startsAt,
    this.endsAt,
  });

  final String id;
  final SponsorshipStatus status;
  final SponsorPlacement? placement;
  final double price;
  final double balanceAfter;
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory SponsorshipPurchase.fromJson(Map<String, dynamic> json) => SponsorshipPurchase(
    id: json['id'] as String,
    status: SponsorshipStatus.fromDb(json['status']),
    placement: SponsorPlacement.fromDb(json['placement']),
    price: _toDouble(json['price']),
    balanceAfter: _toDouble(json['balance_after']),
    startsAt: _parseTime(json['starts_at']),
    endsAt: _parseTime(json['ends_at']),
  );
}

/// Satın almanın başarısız olma nedeni (sunucunun HINT'i).
enum SponsorshipFailure {
  insufficientBalance,
  disabled,
  shopNotListed,
  productNotDiscounted,
  productUnavailable,
  packageNotFound,
  notAllowed,
  unknown,
}

class SponsorshipException implements Exception {
  const SponsorshipException(this.reason, this.message);

  final SponsorshipFailure reason;
  final String message;

  @override
  String toString() => message;
}
