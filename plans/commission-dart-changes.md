# Komisyon Sistemi - Dart Değişiklikleri

## 1. OrderModel Güncellemeleri

### Dosya: [`lib/core/models/order_model.dart`](../lib/core/models/order_model.dart)

```dart
// Yeni enum ekle
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

// Order sınıfına yeni alanlar ekle
class Order {
  // ... mevcut alanlar ...
  
  // Komisyon alanları
  final CommissionStatus? commissionStatus;
  final double? adminCommission;
  final double? adminDeliveryFee;
  final double? sellerNetAmount;
  final double? commissionDebt;
  final DateTime? commissionCalculatedAt;
  
  // Satıcı kurye durumu (ilişkili veri)
  final bool? hasOwnCourier;

  // Constructor güncelle
  Order({
    // ... mevcut parametreler ...
    this.commissionStatus,
    this.adminCommission,
    this.adminDeliveryFee,
    this.sellerNetAmount,
    this.commissionDebt,
    this.commissionCalculatedAt,
    this.hasOwnCourier,
  });

  // fromJson güncelle
  factory Order.fromJson(Map<String, dynamic> json) {
    // ... mevcut kod ...
    
    return Order(
      // ... mevcut alanlar ...
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
    );
  }

  // copyWith güncelle
  Order copyWith({
    // ... mevcut parametreler ...
    CommissionStatus? commissionStatus,
    double? adminCommission,
    double? adminDeliveryFee,
    double? sellerNetAmount,
    double? commissionDebt,
    DateTime? commissionCalculatedAt,
    bool? hasOwnCourier,
  }) {
    return Order(
      // ... mevcut alanlar ...
      commissionStatus: commissionStatus ?? this.commissionStatus,
      adminCommission: adminCommission ?? this.adminCommission,
      adminDeliveryFee: adminDeliveryFee ?? this.adminDeliveryFee,
      sellerNetAmount: sellerNetAmount ?? this.sellerNetAmount,
      commissionDebt: commissionDebt ?? this.commissionDebt,
      commissionCalculatedAt: commissionCalculatedAt ?? this.commissionCalculatedAt,
      hasOwnCourier: hasOwnCourier ?? this.hasOwnCourier,
    );
  }
  
  // Yardımcı metodlar
  bool get hasDebt => (commissionDebt ?? 0) > 0;
  
  double get totalAdminEarnings => 
      (adminCommission ?? 0) + (adminDeliveryFee ?? 0);
}
```

## 2. ShopModel Güncellemeleri

### Dosya: [`lib/core/models/shop_model.dart`](../lib/core/models/shop_model.dart)

```dart
class Shop {
  // ... mevcut alanlar ...
  
  // Kurye durumu (zaten migration'da eklenmişti)
  final bool? hasOwnCourier;
  
  // Mevcut alanlar
  final double commissionRate;
  final double? pendingPayout;
  final double? totalPaid;

  Shop({
    // ... mevcut parametreler ...
    this.hasOwnCourier,
    this.commissionRate = 10.0,
    this.pendingPayout = 0.0,
    this.totalPaid = 0.0,
  });

  // fromJson güncelle
  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      // ... mevcut alanlar ...
      hasOwnCourier: json['has_own_courier'] as bool?,
      commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 10.0,
      pendingPayout: (json['pending_payout'] as num?)?.toDouble(),
      totalPaid: (json['total_paid'] as num?)?.toDouble(),
    );
  }

  // copyWith güncelle
  Shop copyWith({
    // ... mevcut parametreler ...
    bool? hasOwnCourier,
    double? commissionRate,
    double? pendingPayout,
    double? totalPaid,
  }) {
    return Shop(
      // ... mevcut alanlar ...
      hasOwnCourier: hasOwnCourier ?? this.hasOwnCourier,
      commissionRate: commissionRate ?? this.commissionRate,
      pendingPayout: pendingPayout ?? this.pendingPayout,
      totalPaid: totalPaid ?? this.totalPaid,
    );
  }
}
```

## 3. CommissionService Yeni Dosya

### Dosya: `lib/features/admin/services/commission_service.dart`

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/order_model.dart';

/// Komisyon Hesaplama Sonucu
class CommissionCalculation {
  final double adminCommission;
  final double adminDeliveryFee;
  final double sellerNetAmount;
  final CommissionStatus commissionStatus;
  final double commissionDebt;

  CommissionCalculation({
    required this.adminCommission,
    required this.adminDeliveryFee,
    required this.sellerNetAmount,
    required this.commissionStatus,
    required this.commissionDebt,
  });
}

/// Admin Komisyon Raporu
class AdminCommissionReport {
  final int totalOrders;
  final double totalAmount;
  final double totalCommission;
  final double collectedCommission;
  final double debtCommission;
  final double waivedCommission;
  final double totalDeliveryFee;
  final double totalNetAdmin;

  AdminCommissionReport({
    required this.totalOrders,
    required this.totalAmount,
    required this.totalCommission,
    required this.collectedCommission,
    required this.debtCommission,
    required this.waivedCommission,
    required this.totalDeliveryFee,
    required this.totalNetAdmin,
  });
}

/// Satıcı Komisyon Özeti
class SellerCommissionSummary {
  final int totalOrders;
  final double totalSales;
  final double totalCommission;
  final double collectedCommission;
  final double debtCommission;
  final double netEarnings;
  final double pendingPayout;

  SellerCommissionSummary({
    required this.totalOrders,
    required this.totalSales,
    required this.totalCommission,
    required this.collectedCommission,
    required this.debtCommission,
    required this.netEarnings,
    required this.pendingPayout,
  });
}

/// Commission Service - Komisyon hesaplama ve raporlama servisi
class CommissionService {
  final SupabaseClient _supabase;

  CommissionService(this._supabase);

  /// Admin komisyon oranını getir
  Future<double> getAdminCommissionRate() async {
    try {
      final response = await _supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'admin_commission_rate')
          .maybeSingle();

      if (response != null && response['value'] != null) {
        return double.tryParse(response['value'] as String) ?? 10.0;
      }
      return 10.0;
    } catch (e) {
      return 10.0;
    }
  }

  /// Admin komisyon oranını güncelle
  Future<void> updateAdminCommissionRate(double rate) async {
    try {
      await _supabase
          .from('system_settings')
          .upsert({
            'key': 'admin_commission_rate',
            'value': rate.toString(),
            'description': 'Admin komisyon oranı (%)',
          });
    } catch (e) {
      throw Exception('Komisyon oranı güncellenemedi: $e');
    }
  }

  /// Sipariş için komisyon hesapla
  Future<CommissionCalculation> calculateCommission({
    required double totalAmount,
    required double deliveryFee,
    required bool hasOwnCourier,
    required PaymentMethod paymentMethod,
    double? adminCommissionRate,
  }) async {
    final rate = adminCommissionRate ?? await getAdminCommissionRate();
    
    final adminCommission = totalAmount * rate / 100;
    double adminDeliveryFee = 0;
    CommissionStatus commissionStatus;
    double commissionDebt = 0;

    if (!hasOwnCourier) {
      // Kuryesi yok - teslimat ücretini kes
      adminDeliveryFee = deliveryFee;
      commissionStatus = CommissionStatus.collected;
    } else {
      // Kuryesi var
      if (paymentMethod == PaymentMethod.cash || 
          paymentMethod == PaymentMethod.cardOnDelivery) {
        // Kapıda ödeme - borç olarak işaretle
        commissionStatus = CommissionStatus.debt;
        commissionDebt = adminCommission;
      } else {
        // Online ödeme - tahsil et
        commissionStatus = CommissionStatus.collected;
      }
    }

    final sellerNetAmount = totalAmount - adminCommission - adminDeliveryFee;

    return CommissionCalculation(
      adminCommission: adminCommission,
      adminDeliveryFee: adminDeliveryFee,
      sellerNetAmount: sellerNetAmount,
      commissionStatus: commissionStatus,
      commissionDebt: commissionDebt,
    );
  }

  /// Sipariş için manuel komisyon kaydet (trigger çalışmazsa)
  Future<void> saveOrderCommission(String orderId, CommissionCalculation calculation) async {
    try {
      await _supabase
          .from('orders')
          .update({
            'admin_commission': calculation.adminCommission,
            'admin_delivery_fee': calculation.adminDeliveryFee,
            'seller_net_amount': calculation.sellerNetAmount,
            'commission_status': calculation.commissionStatus.dbValue,
            'commission_debt': calculation.commissionDebt,
            'commission_calculated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
    } catch (e) {
      throw Exception('Komisyon kaydedilemedi: $e');
    }
  }

  /// Admin komisyon raporu
  Future<AdminCommissionReport> getAdminCommissionReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      final response = await _supabase
          .rpc('get_admin_commission_report', params: {
            'p_start_date': start.toIso8601String(),
            'p_end_date': end.toIso8601String(),
          });

      if (response != null && response is List && response.isNotEmpty) {
        final data = response[0] as Map<String, dynamic>;
        return AdminCommissionReport(
          totalOrders: data['total_orders'] as int? ?? 0,
          totalAmount: (data['total_amount'] as num?)?.toDouble() ?? 0,
          totalCommission: (data['total_commission'] as num?)?.toDouble() ?? 0,
          collectedCommission: (data['collected_commission'] as num?)?.toDouble() ?? 0,
          debtCommission: (data['debt_commission'] as num?)?.toDouble() ?? 0,
          waivedCommission: (data['waived_commission'] as num?)?.toDouble() ?? 0,
          totalDeliveryFee: (data['total_delivery_fee'] as num?)?.toDouble() ?? 0,
          totalNetAdmin: (data['total_net_admin'] as num?)?.toDouble() ?? 0,
        );
      }

      return AdminCommissionReport(
        totalOrders: 0,
        totalAmount: 0,
        totalCommission: 0,
        collectedCommission: 0,
        debtCommission: 0,
        waivedCommission: 0,
        totalDeliveryFee: 0,
        totalNetAdmin: 0,
      );
    } catch (e) {
      throw Exception('Komisyon raporu alınamadı: $e');
    }
  }

  /// Satıcı komisyon özeti
  Future<SellerCommissionSummary> getSellerCommissionSummary(
    String sellerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      final response = await _supabase
          .rpc('get_seller_commission_summary', params: {
            'p_seller_id': sellerId,
            'p_start_date': start.toIso8601String(),
            'p_end_date': end.toIso8601String(),
          });

      if (response != null && response is List && response.isNotEmpty) {
        final data = response[0] as Map<String, dynamic>;
        return SellerCommissionSummary(
          totalOrders: data['total_orders'] as int? ?? 0,
          totalSales: (data['total_sales'] as num?)?.toDouble() ?? 0,
          totalCommission: (data['total_commission'] as num?)?.toDouble() ?? 0,
          collectedCommission: (data['collected_commission'] as num?)?.toDouble() ?? 0,
          debtCommission: (data['debt_commission'] as num?)?.toDouble() ?? 0,
          netEarnings: (data['net_earnings'] as num?)?.toDouble() ?? 0,
          pendingPayout: (data['pending_payout'] as num?)?.toDouble() ?? 0,
        );
      }

      return SellerCommissionSummary(
        totalOrders: 0,
        totalSales: 0,
        totalCommission: 0,
        collectedCommission: 0,
        debtCommission: 0,
        netEarnings: 0,
        pendingPayout: 0,
      );
    } catch (e) {
      throw Exception('Satıcı komisyon özeti alınamadı: $e');
    }
  }

  /// Borçlu siparişleri getir
  Future<List<Map<String, dynamic>>> getDebtOrders({
    String? sellerId,
    int limit = 50,
  }) async {
    try {
      final query = _supabase
          .from('v_debt_orders')
          .select('*')
          .order('created_at', ascending: false)
          .limit(limit);

      final response = sellerId != null
          ? await query.eq('owner_id', sellerId)
          : await query;

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Borçlu siparişler alınamadı: $e');
    }
  }

  /// Dashboard verileri
  Future<List<Map<String, dynamic>>> getDashboardData({
    int days = 30,
  }) async {
    try {
      final response = await _supabase
          .from('v_admin_commission_dashboard')
          .select('*')
          .order('date', ascending: false)
          .limit(days);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Dashboard verileri alınamadı: $e');
    }
  }

  /// Komisyon durumunu güncelle
  Future<void> updateCommissionStatus(
    String orderId,
    CommissionStatus newStatus,
  ) async {
    try {
      await _supabase
          .from('orders')
          .update({'commission_status': newStatus.dbValue})
          .eq('id', orderId);
    } catch (e) {
      throw Exception('Komisyon durumu güncellenemedi: $e');
    }
  }

  /// Toplam borç tutarı
  Future<double> getTotalDebtAmount({String? sellerId}) async {
    try {
      final query = _supabase
          .from('orders')
          .select('commission_debt')
          .eq('commission_status', 'debt')
          .eq('status', 'delivered');

      final response = sellerId != null
          ? await query.eq('shop_id', sellerId)
          : await query;

      double total = 0;
      for (var item in response) {
        total += (item['commission_debt'] as num?)?.toDouble() ?? 0;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
}
```

## 4. OrderService Güncellemeleri

### Dosya: [`lib/features/shop/services/order_service.dart`](../lib/features/shop/services/order_service.dart)

```dart
// Sipariş oluştururken komisyon hesaplaması için güncelleme
// OrderService'e yeni metod ekle:

/// Sipariş oluştururken komisyon bilgilerini de al
Future<Order> createOrderWithCommission({
  required String userId,
  required String shopId,
  required List<Map<String, dynamic>> items,
  required String addressId,
  required PaymentMethod paymentMethod,
  String? deliveryNotes,
}) async {
  try {
    // Önce dükkan bilgilerini al (hasOwnCourier için)
    final shopData = await _supabase
        .from('shops')
        .select('has_own_courier, delivery_fee')
        .eq('id', shopId)
        .single();

    final hasOwnCourier = shopData['has_own_courier'] as bool? ?? false;
    final shopDeliveryFee = (shopData['delivery_fee'] as num?)?.toDouble() ?? 0;

    // Siparişi oluştur (trigger otomatik komisyon hesaplayacak)
    // ... mevcut sipariş oluşturma kodu ...

    return order;
  } catch (e) {
    throw Exception('Sipariş oluşturulamadı: $e');
  }
}
```

## 5. PayoutService Güncellemeleri

### Dosya: [`lib/features/seller/services/payout_service.dart`](../lib/features/seller/services/payout_service.dart)

```dart
// Ödeme isteği oluştururken borçları dikkate al

/// Yeni ödeme isteği oluştur (borç kontrolü ile güncellenmiş)
Future<Map<String, dynamic>> createPayoutRequest({
  required String sellerId,
  required String shopId,
  required double amount,
  String? iban,
  String? bankName,
  String? accountHolderName,
}) async {
  try {
    // Önce borç tutarını kontrol et
    final debtAmount = await _commissionService.getTotalDebtAmount(sellerId: sellerId);
    
    // Bekleyen ödeme tutarını kontrol et
    final pendingAmount = await getPendingPayoutAmount(shopId);

    // Net ödenecek tutar = pending - debt
    final netPayoutAmount = pendingAmount - debtAmount;

    if (amount > netPayoutAmount) {
      throw Exception(
          'İstediğiniz tutar (₺${amount.toStringAsFixed(2)}) net ödenebilir tutarınızdan (₺${netPayoutAmount.toStringAsFixed(2)}) daha fazla. '
          'Borç tutarınız: ₺${debtAmount.toStringAsFixed(2)}');
    }

    if (amount <= 0) {
      throw Exception('Ödeme tutarı 0\'dan büyük olmalıdır.');
    }

    // ... devam eden kod mevcut payout_service.dart ile aynı ...
    
    return result;
  } catch (e) {
    throw Exception('Ödeme isteği oluşturulamadı: $e');
  }
}
```

## 6. UI Bileşenleri için Yardımcı Widget'lar

### Dosya: `lib/core/widgets/commission_info_widget.dart`

```dart
import 'package:flutter/material.dart';
import '../models/order_model.dart';

class CommissionInfoWidget extends StatelessWidget {
  final Order order;

  const CommissionInfoWidget({Key? key, required this.order}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '💵 Komisyon Detayları',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            _buildRow('Sipariş Tutarı', '₺${order.subtotal.toStringAsFixed(2)}'),
            if (order.adminCommission != null && order.adminCommission! > 0)
              _buildRow('Admin Komisyonu', '-₺${order.adminCommission!.toStringAsFixed(2)}', Colors.red),
            if (order.adminDeliveryFee != null && order.adminDeliveryFee! > 0)
              _buildRow('Admin Teslimat Ücreti', '-₺${order.adminDeliveryFee!.toStringAsFixed(2)}', Colors.red),
            const Divider(),
            if (order.sellerNetAmount != null)
              _buildRow(
                'Net Ödeme',
                '₺${order.sellerNetAmount!.toStringAsFixed(2)}',
                Colors.green,
                bold: true,
              ),
            if (order.commissionStatus != null)
              _buildStatusBadge(order.commissionStatus!),
            if (order.hasDebt)
              _buildDebtWarning(order.commissionDebt ?? 0),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, [Color? color, bool bold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(CommissionStatus status) {
    Color badgeColor;
    IconData icon;
    
    switch (status) {
      case CommissionStatus.collected:
        badgeColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case CommissionStatus.debt:
        badgeColor = Colors.orange;
        icon = Icons.warning;
        break;
      case CommissionStatus.waived:
        badgeColor = Colors.grey;
        icon = Icons.block;
        break;
      default:
        badgeColor = Colors.grey;
        icon = Icons.pending;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: badgeColor),
          const SizedBox(width: 8),
          Text(
            'Durum: ${status.label}',
            style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtWarning(double debtAmount) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '⚠️ Tahsil Edilecek Komisyon Borcu: ₺${debtAmount.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}
```
