import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';

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

  @override
  String toString() {
    return 'CommissionCalculation(adminCommission: $adminCommission, adminDeliveryFee: $adminDeliveryFee, sellerNetAmount: $sellerNetAmount, commissionStatus: $commissionStatus, commissionDebt: $commissionDebt)';
  }
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

  factory AdminCommissionReport.fromJson(Map<String, dynamic> json) {
    return AdminCommissionReport(
      totalOrders: json['total_orders'] as int? ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      totalCommission: (json['total_commission'] as num?)?.toDouble() ?? 0,
      collectedCommission: (json['collected_commission'] as num?)?.toDouble() ?? 0,
      debtCommission: (json['debt_commission'] as num?)?.toDouble() ?? 0,
      waivedCommission: (json['waived_commission'] as num?)?.toDouble() ?? 0,
      totalDeliveryFee: (json['total_delivery_fee'] as num?)?.toDouble() ?? 0,
      totalNetAdmin: (json['total_net_admin'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  String toString() {
    return 'AdminCommissionReport(totalOrders: $totalOrders, totalAmount: $totalAmount, totalCommission: $totalCommission, collectedCommission: $collectedCommission, debtCommission: $debtCommission, totalDeliveryFee: $totalDeliveryFee, totalNetAdmin: $totalNetAdmin)';
  }
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

  factory SellerCommissionSummary.fromJson(Map<String, dynamic> json) {
    return SellerCommissionSummary(
      totalOrders: json['total_orders'] as int? ?? 0,
      totalSales: (json['total_sales'] as num?)?.toDouble() ?? 0,
      totalCommission: (json['total_commission'] as num?)?.toDouble() ?? 0,
      collectedCommission: (json['collected_commission'] as num?)?.toDouble() ?? 0,
      debtCommission: (json['debt_commission'] as num?)?.toDouble() ?? 0,
      netEarnings: (json['net_earnings'] as num?)?.toDouble() ?? 0,
      pendingPayout: (json['pending_payout'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  String toString() {
    return 'SellerCommissionSummary(totalOrders: $totalOrders, totalSales: $totalSales, totalCommission: $totalCommission, debtCommission: $debtCommission, netEarnings: $netEarnings, pendingPayout: $pendingPayout)';
  }
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

  /// Varsayılan teslimat ücretini getir
  Future<double> getDefaultDeliveryFee() async {
    try {
      final response = await _supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'default_delivery_fee')
          .maybeSingle();

      if (response != null && response['value'] != null) {
        return double.tryParse(response['value'] as String) ?? 30.0;
      }
      return 30.0;
    } catch (e) {
      return 30.0;
    }
  }

  /// Varsayılan teslimat ücretini güncelle
  Future<void> updateDefaultDeliveryFee(double fee) async {
    try {
      await _supabase
          .from('system_settings')
          .upsert({
            'key': 'default_delivery_fee',
            'value': fee.toString(),
            'description': 'Varsayılan teslimat ücreti (₺)',
          });
    } catch (e) {
      throw Exception('Teslimat ücreti güncellenemedi: $e');
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
      List<dynamic> response;
      
      if (sellerId != null) {
        response = await _supabase
            .from('v_debt_orders')
            .select('*')
            .eq('owner_id', sellerId)
            .order('created_at', ascending: false)
            .limit(limit);
      } else {
        response = await _supabase
            .from('v_debt_orders')
            .select('*')
            .order('created_at', ascending: false)
            .limit(limit);
      }

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

  /// Satıcı bazlı komisyon özeti (tüm satıcılar için)
  Future<List<Map<String, dynamic>>> getSellerCommissionList({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      final response = await _supabase
          .from('shops')
          .select('''
            id,
            name,
            owner_id,
            has_own_courier,
            pending_payout,
            total_paid,
            orders!inner(
              subtotal,
              admin_commission,
              admin_delivery_fee,
              seller_net_amount,
              commission_status,
              created_at,
              status
            )
          ''')
          .gte('orders.created_at', start.toIso8601String())
          .lte('orders.created_at', end.toIso8601String())
          .not('orders.status', 'eq', 'cancelled');

      // Her dükkan için özet hesapla
      final Map<String, Map<String, dynamic>> summaryMap = {};

      for (var shop in response) {
        final shopId = shop['id'] as String;
        final orders = shop['orders'] as List? ?? [];

        double totalSales = 0;
        double totalCommission = 0;
        double debtCommission = 0;
        double collectedCommission = 0;
        int orderCount = orders.length;

        for (var order in orders) {
          totalSales += (order['subtotal'] as num?)?.toDouble() ?? 0;
          final comm = (order['admin_commission'] as num?)?.toDouble() ?? 0;
          totalCommission += comm;
          
          final status = order['commission_status'] as String?;
          if (status == 'debt') {
            debtCommission += comm;
          } else if (status == 'collected') {
            collectedCommission += comm;
          }
        }

        summaryMap[shopId] = {
          'shop_id': shopId,
          'shop_name': shop['name'] as String?,
          'owner_id': shop['owner_id'] as String?,
          'has_own_courier': shop['has_own_courier'] as bool?,
          'pending_payout': (shop['pending_payout'] as num?)?.toDouble() ?? 0,
          'total_paid': (shop['total_paid'] as num?)?.toDouble() ?? 0,
          'total_orders': orderCount,
          'total_sales': totalSales,
          'total_commission': totalCommission,
          'debt_commission': debtCommission,
          'collected_commission': collectedCommission,
        };
      }

      return summaryMap.values.toList();
    } catch (e) {
      throw Exception('Satıcı komisyon listesi alınamadı: $e');
    }
  }
}
