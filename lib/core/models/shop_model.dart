class Shop {
  final String id;
  final String ownerId;
  final String categoryId;
  final String name;
  final String slug;
  final String? description;
  final String? logoUrl;
  final String? bannerUrl;
  final String? phone;
  final String? email;
  final String? address;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic>? workingHours;
  final bool _isOpenManual;
  final double commissionRate;
  final double minOrderAmount;
  final double deliveryFee;
  final double? freeDeliveryMinAmount;
  final String? deliveryTime;
  final String? bankName;
  final String? iban;
  final String? accountHolder;
  final double rating;
  final int totalReviews;
  final int totalOrders;
  final bool isVerified;
  final bool isActive;
  final bool isApproved;
  final bool isAcceptingOrders;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Kurye durumu
  final bool? hasOwnCourier;
  
  // Ödeme alanları
  final double? pendingPayout;
  final double? totalPaid;
  
  // Satıcının kendi oluşturduğu kategoriler
  final List<String> sellerCategories;
  
  // Sabitleme durumu
  final bool isPinned;

  Shop({
    required this.id,
    required this.ownerId,
    required this.categoryId,
    required this.name,
    required this.slug,
    this.description,
    this.logoUrl,
    this.bannerUrl,
    this.phone,
    this.email,
    this.address,
    this.latitude,
    this.longitude,
    this.workingHours,
    bool isOpen = true,
    this.commissionRate = 10.0,
    this.minOrderAmount = 0.0,
    this.deliveryFee = 0.0,
    this.freeDeliveryMinAmount,
    this.deliveryTime,
    this.bankName,
    this.iban,
    this.accountHolder,
    this.rating = 0.0,
    this.totalReviews = 0,
    this.totalOrders = 0,
    this.isVerified = false,
    this.isActive = true,
    this.isApproved = false,
    this.isAcceptingOrders = true,
    required this.createdAt,
    required this.updatedAt,
    this.hasOwnCourier,
    this.pendingPayout,
    this.totalPaid,
    this.sellerCategories = const [],
    this.isPinned = false,
  }) : _isOpenManual = isOpen;

  // Türkiye saatine göre (UTC+3) dükkan açık mı hesapla
  bool get isOpen {
    // Eğer çalışma saatleri tanımlı değilse manuel değeri kullan
    if (workingHours == null || workingHours!.isEmpty) {
      return _isOpenManual;
    }

    // Türkiye saatini hesapla (UTC+3)
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final currentDay = _getDayName(now.weekday);
    final currentTime = now.hour * 60 + now.minute; // Dakika cinsinden şu anki zaman

    // Bugünün çalışma saatlerini kontrol et
    final todayHours = workingHours![currentDay];
    if (todayHours == null) return false;

    // Kapalı mı kontrolü (active kontrolü)
    if (todayHours is Map && todayHours['active'] == false) {
      return false;
    }

    // Açılış ve kapanış saatlerini al
    String? openTime;
    String? closeTime;

    if (todayHours is Map) {
      openTime = todayHours['open'] as String?;
      closeTime = todayHours['close'] as String?;
    }

    if (openTime == null || closeTime == null) return _isOpenManual;

    // Saatleri dakika cinsine çevir
    final openMinutes = _parseTime(openTime);
    final closeMinutes = _parseTime(closeTime);

    if (openMinutes == null || closeMinutes == null) return _isOpenManual;

    // Gece yarısını geçen saatler için kontrol (örn: 22:00 - 02:00)
    if (closeMinutes < openMinutes) {
      // Gece yarısından sonra veya önce açık mı?
      return currentTime >= openMinutes || currentTime < closeMinutes;
    }

    // Normal saat aralığı
    return currentTime >= openMinutes && currentTime < closeMinutes;
  }

  // Gün numarasını Türkçe gün ismine çevir
  static String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'monday';
      case 2:
        return 'tuesday';
      case 3:
        return 'wednesday';
      case 4:
        return 'thursday';
      case 5:
        return 'friday';
      case 6:
        return 'saturday';
      case 7:
        return 'sunday';
      default:
        return 'monday';
    }
  }

  // "09:00" formatındaki saati dakikaya çevir
  static int? _parseTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  // Bugünün çalışma saatlerini al
  String? get todayWorkingHours {
    if (workingHours == null || workingHours!.isEmpty) return null;
    
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final currentDay = _getDayName(now.weekday);
    final todayHours = workingHours![currentDay];
    
    if (todayHours == null) return 'Kapalı';
    if (todayHours is Map && todayHours['active'] == false) return 'Kapalı';
    
    final openTime = todayHours['open'] as String?;
    final closeTime = todayHours['close'] as String?;
    
    if (openTime == null || closeTime == null) return null;
    return '$openTime - $closeTime';
  }

  // Ne zaman açılır/kapanır bilgisi
  String? get nextStatusChange {
    if (!isOpen) {
      // Kapalıysa ne zaman açılacağını hesapla
      final todayHours = todayWorkingHours;
      if (todayHours != null && todayHours != 'Kapalı') {
        final parts = todayHours.split(' - ');
        if (parts.isNotEmpty) {
          return 'Açılış: ${parts[0]}';
        }
      }
      return null;
    } else {
      // Açıksa ne zaman kapanacağını hesapla
      final todayHours = todayWorkingHours;
      if (todayHours != null && todayHours != 'Kapalı') {
        final parts = todayHours.split(' - ');
        if (parts.length > 1) {
          return 'Kapanış: ${parts[1]}';
        }
      }
      return null;
    }
  }

  Shop copyWith({
    String? id,
    String? ownerId,
    String? categoryId,
    String? name,
    String? slug,
    String? description,
    String? logoUrl,
    String? bannerUrl,
    String? phone,
    String? email,
    String? address,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? workingHours,
    bool? isOpen,
    double? commissionRate,
    double? minOrderAmount,
    double? deliveryFee,
    double? freeDeliveryMinAmount,
    String? deliveryTime,
    String? bankName,
    String? iban,
    String? accountHolder,
    double? rating,
    int? totalReviews,
    int? totalOrders,
    bool? isVerified,
    bool? isActive,
    bool? isApproved,
    bool? isAcceptingOrders,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? hasOwnCourier,
    double? pendingPayout,
    double? totalPaid,
    List<String>? sellerCategories,
    bool? isPinned,
  }) {
    return Shop(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      logoUrl: logoUrl ?? this.logoUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      workingHours: workingHours ?? this.workingHours,
      isOpen: isOpen ?? _isOpenManual,
      commissionRate: commissionRate ?? this.commissionRate,
      minOrderAmount: minOrderAmount ?? this.minOrderAmount,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      freeDeliveryMinAmount: freeDeliveryMinAmount ?? this.freeDeliveryMinAmount,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      bankName: bankName ?? this.bankName,
      iban: iban ?? this.iban,
      accountHolder: accountHolder ?? this.accountHolder,
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
      totalOrders: totalOrders ?? this.totalOrders,
      isVerified: isVerified ?? this.isVerified,
      isActive: isActive ?? this.isActive,
      isApproved: isApproved ?? this.isApproved,
      isAcceptingOrders: isAcceptingOrders ?? this.isAcceptingOrders,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hasOwnCourier: hasOwnCourier ?? this.hasOwnCourier,
      pendingPayout: pendingPayout ?? this.pendingPayout,
      totalPaid: totalPaid ?? this.totalPaid,
      sellerCategories: sellerCategories ?? this.sellerCategories,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_id': ownerId,
      'category_id': categoryId,
      'name': name,
      'slug': slug,
      'description': description,
      'logo_url': logoUrl,
      'banner_url': bannerUrl,
      'phone': phone,
      'email': email,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'working_hours': workingHours,
      'is_open': _isOpenManual,
      'commission_rate': commissionRate,
      'min_order_amount': minOrderAmount,
      'delivery_fee': deliveryFee,
      'free_delivery_min_amount': freeDeliveryMinAmount,
      'delivery_time': deliveryTime,
      'bank_name': bankName,
      'iban': iban,
      'account_holder': accountHolder,
      'rating': rating,
      'total_reviews': totalReviews,
      'total_orders': totalOrders,
      'is_verified': isVerified,
      'is_active': isActive,
      'is_approved': isApproved,
      'is_accepting_orders': isAcceptingOrders,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'has_own_courier': hasOwnCourier,
      'pending_payout': pendingPayout,
      'total_paid': totalPaid,
      'seller_categories': sellerCategories,
      'is_pinned': isPinned,
    };
  }

  factory Shop.fromJson(Map<String, dynamic> json) {
    // Güvenli null kontrol ile alanları al
    final id = (json['id'] ?? '').toString().trim();
    final ownerId = (json['owner_id'] ?? '').toString().trim();
    final categoryId = (json['category_id'] ?? 'default').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    final createdAtStr = (json['created_at'] ?? DateTime.now().toIso8601String()).toString().trim();
    final updatedAtStr = (json['updated_at'] ?? DateTime.now().toIso8601String()).toString().trim();
    
    // Zorunlu alanları kontrol et
    if (id.isEmpty) {
      throw Exception('Hata: Shop ID boş');
    }
    if (ownerId.isEmpty) {
      throw Exception('Hata: Owner ID boş');
    }
    if (name.isEmpty) {
      throw Exception('Hata: Shop adı boş');
    }
    if (createdAtStr.isEmpty) {
      throw Exception('Hata: Created At boş');
    }
    if (updatedAtStr.isEmpty) {
      throw Exception('Hata: Updated At boş');
    }

    return Shop(
      id: id,
      ownerId: ownerId,
      categoryId: categoryId,
      name: name,
      slug: json['slug'] as String? ?? name.toLowerCase().replaceAll(' ', '-'),
      description: json['description'] as String?,
      logoUrl: json['logo_url'] as String?,
      // Önce cover_image, sonra banner_url kontrol et (backwards compatibility)
      bannerUrl: json['cover_image'] as String? ?? json['banner_url'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      workingHours: json['working_hours'] as Map<String, dynamic>?,
      isOpen: json['is_open'] as bool? ?? true,
      commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 10.0,
      minOrderAmount: (json['min_order_amount'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      freeDeliveryMinAmount: (json['free_delivery_min_amount'] as num?)?.toDouble(),
      deliveryTime: json['delivery_time'] as String?,
      bankName: json['bank_name'] as String?,
      iban: json['iban'] as String?,
      accountHolder: json['account_holder'] as String? ?? json['account_holder_name'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      totalReviews: json['total_reviews'] as int? ?? 0,
      totalOrders: json['total_orders'] as int? ?? 0,
      isVerified: json['is_verified'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      isApproved: json['is_approved'] as bool? ?? false,
      isAcceptingOrders: (json['is_accepting_orders'] as bool?) ?? true,  // Explicit null check
      createdAt: DateTime.parse(createdAtStr),
      updatedAt: DateTime.parse(updatedAtStr),
      hasOwnCourier: json['has_own_courier'] as bool?,
      pendingPayout: (json['pending_payout'] as num?)?.toDouble(),
      totalPaid: (json['total_paid'] as num?)?.toDouble(),
      sellerCategories: json['seller_categories'] != null
          ? List<String>.from(json['seller_categories'])
          : const [],
      isPinned: json['is_pinned'] as bool? ?? false,
    );
  }
}
