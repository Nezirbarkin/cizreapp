import 'package:supabase_flutter/supabase_flutter.dart';

/// Payout Service - Satıcı ödeme istekleri servisi
///
/// YENİ ÖDEDEME MANTIĞI:
/// - Kuryesi OLAN: Kapıda ödeme = komisyon borcu, Online ödeme = alacak
///   Ödenebilir = Alacak - Borç
/// - Kuryesi OLMAYAN: Her ödemede komisyon + teslimat kesilir, kalan alacak
class PayoutService {
  final SupabaseClient _supabase;

  PayoutService(this._supabase);

  /// Satıcının bilgilerini getir (tek sorgu ile tüm veriler)
  Future<Map<String, dynamic>> getShopInfo(String shopId) async {
    try {
      final response = await _supabase
          .from('shops')
          .select('''
            has_own_courier,
            admin_credit,
            commission_debt,
            total_collected_cash,
            cash_payment_revenue,
            online_payment_revenue,
            total_paid,
            commission_rate,
            delivery_fee
          ''')
          .eq('id', shopId)
          .single();

      return response;
    } catch (e) {
      return {};
    }
  }

  /// Satıcının komisyon borcunu getir (shops tablosundan)
  Future<double> getCommissionDebt(String shopId) async {
    try {
      final info = await getShopInfo(shopId);
      return (info['commission_debt'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Satıcının admin'den alacağını getir (shops tablosundan)
  Future<double> getAdminCredit(String shopId) async {
    try {
      final info = await getShopInfo(shopId);
      return (info['admin_credit'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Kapıda ödeme kazancını getir
  Future<double> getCashPaymentRevenue(String shopId) async {
    try {
      final info = await getShopInfo(shopId);
      return (info['cash_payment_revenue'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Online ödeme kazancını getir
  Future<double> getOnlinePaymentRevenue(String shopId) async {
    try {
      final info = await getShopInfo(shopId);
      return (info['online_payment_revenue'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Toplam kapıda tahsilatı getir
  Future<double> getTotalCollectedCash(String shopId) async {
    try {
      final info = await getShopInfo(shopId);
      return (info['total_collected_cash'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Satıcının kuryesi olup olmadığını kontrol et
  Future<bool> hasOwnCourier(String shopId) async {
    try {
      final info = await getShopInfo(shopId);
      return info['has_own_courier'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Net ödeme tutarını hesapla
  /// Kuryesi OLAN: Alacak - Borç
  /// Kuryesi OLMAYAN: Direkt alacak (teslimat zaten düşülmüş)
  Future<double> getNetPayableAmount(String shopId) async {
    try {
      final credit = await getAdminCredit(shopId);
      final debt = await getCommissionDebt(shopId);
      final hasCourier = await hasOwnCourier(shopId);

      if (hasCourier) {
        // Kuryesi var: Alacak - Borç
        return credit - debt;
      } else {
        // Kuryesi yok: Direkt alacak (teslimat zaten kesilmiş)
        return credit;
      }
    } catch (e) {
      return 0;
    }
  }

  /// Satıcının bekleyen ödeme tutarını getir (Net ödenebilir tutar)
  Future<double> getPendingPayoutAmount(String shopId) async {
    try {
      return await getNetPayableAmount(shopId);
    } catch (e) {
      throw Exception('Bekleyen ödeme tutarı getirilemedi: $e');
    }
  }

  /// Özet gelir bilgilerini getir (Dashboard için)
  Future<Map<String, dynamic>> getRevenueSummary(String shopId) async {
    try {
      final info = await getShopInfo(shopId);
      final hasCourier = info['has_own_courier'] as bool? ?? false;
      final cashRevenue = (info['cash_payment_revenue'] as num?)?.toDouble() ?? 0;
      final onlineRevenue = (info['online_payment_revenue'] as num?)?.toDouble() ?? 0;
      final commissionDebt = (info['commission_debt'] as num?)?.toDouble() ?? 0;
      final adminCredit = (info['admin_credit'] as num?)?.toDouble() ?? 0;
      final totalPaid = (info['total_paid'] as num?)?.toDouble() ?? 0;

      double netEarnings;
      String paymentType;

      if (hasCourier) {
        // Kuryesi olan: Kapıda kazanç + Online alacak - Komisyon borcu
        netEarnings = cashRevenue + adminCredit;
        paymentType = 'has_courier';
      } else {
        // Kuryesi olmayan: Online alacak (teslimat ve komisyon zaten düşülmüş)
        netEarnings = adminCredit;
        paymentType = 'no_courier';
      }

      return {
        'has_courier': hasCourier,
        'cash_payment_revenue': cashRevenue,
        'online_payment_revenue': onlineRevenue,
        'commission_debt': commissionDebt,
        'admin_credit': adminCredit,
        'net_earnings': netEarnings,
        'total_paid': totalPaid,
        'payment_type': paymentType,
        'commission_rate': info['commission_rate'] ?? 10.0,
        'delivery_fee': info['delivery_fee'] ?? 0,
      };
    } catch (e) {
      throw Exception('Gelir özeti getirilemedi: $e');
    }
  }

  /// Satıcının toplam ödenen tutarını getir (payout_requests tablosundan approved olanları toplar)
  Future<double> getTotalPaidAmount(String shopId) async {
    try {
      // shops tablosundaki total_paid_amount değerini kullan
      final response = await _supabase
          .from('shops')
          .select('total_paid_amount')
          .eq('id', shopId)
          .single();

      return (response['total_paid_amount'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      throw Exception('Toplam ödenen tutar getirilemedi: $e');
    }
  }

  /// Satıcının ödeme isteklerini getir
  Future<List<Map<String, dynamic>>> getPayoutRequests(String sellerId) async {
    try {
      final response = await _supabase
          .from('payout_requests')
          .select('*')
          .eq('seller_id', sellerId)
          .order('requested_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Ödeme istekleri getirilemedi: $e');
    }
  }

  /// Yeni ödeme isteği oluştur
  Future<Map<String, dynamic>> createPayoutRequest({
    required String sellerId,
    required String shopId,
    required double amount,
    String? iban,
    String? bankName,
    String? accountHolderName,
  }) async {
    try {
      // Önce net ödenebilir tutarı kontrol et
      final netPayoutAmount = await getNetPayableAmount(shopId);
      
      // Komisyon borcunu kontrol et
      final commissionDebt = await getCommissionDebt(shopId);
      final hasCourier = await hasOwnCourier(shopId);

      if (amount > netPayoutAmount) {
        if (hasCourier && commissionDebt > 0) {
          throw Exception(
              'İstediğiniz tutar (₺${amount.toStringAsFixed(2)}) net ödenebilir tutarınızdan (₺${netPayoutAmount.toStringAsFixed(2)}) daha fazla.\n'
              'Admin\'den alacak: ₺${(await getAdminCredit(shopId)).toStringAsFixed(2)}\n'
              'Komisyon borcu: ₺${commissionDebt.toStringAsFixed(2)}');
        } else {
          throw Exception(
              'İstediğiniz tutar (₺${amount.toStringAsFixed(2)}) net ödenebilir tutarınızdan (₺${netPayoutAmount.toStringAsFixed(2)}) daha fazla.');
        }
      }

      if (amount <= 0) {
        throw Exception('Ödeme tutarı 0\'dan büyük olmalıdır.');
      }

      // Minimum ödeme tutarı kontrolü
      const double minPayoutAmount = 100.0;
      if (amount < minPayoutAmount) {
        throw Exception('Minimum ödeme tutarı ₺${minPayoutAmount.toStringAsFixed(2)} olmalıdır.');
      }

      // Dükkan bilgilerinden IBAN bilgilerini al
      final shopResponse = await _supabase
          .from('shops')
          .select('iban, bank_name, account_holder_name')
          .eq('id', shopId)
          .single();

      final shopIban = shopResponse['iban'] as String?;
      final shopBankName = shopResponse['bank_name'] as String?;
      final shopAccountHolder = shopResponse['account_holder_name'] as String?;

      // IBAN bilgisi yoksa hata ver
      if (shopIban == null || shopIban.isEmpty) {
        throw Exception(
            'Ödeme isteği oluşturmak için önce IBAN bilgilerinizi girmelisiniz.');
      }

      // Ödeme isteğini oluştur
      final response = await _supabase
          .from('payout_requests')
          .insert({
            'seller_id': sellerId,
            'shop_id': shopId,
            'amount': amount, // Tutar
            'total_amount': amount, // Geriye dönük uyumluluk
            'commission_amount': commissionDebt, // Komisyon borcunu kaydet
            'net_receivable': netPayoutAmount, // Net ödenebilir
            'admin_credit': await getAdminCredit(shopId),
            'order_count': 0,
            'status': 'pending',
            'iban': shopIban,
            'bank_name': shopBankName,
            'account_holder_name': shopAccountHolder,
          })
          .select()
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      throw Exception('Ödeme isteği oluşturulamadı: $e');
    }
  }

  /// Ödeme isteğini iptal et (sadece pending durumundakiler)
  Future<bool> cancelPayoutRequest(String payoutRequestId) async {
    try {
      final response = await _supabase
          .from('payout_requests')
          .update({'status': 'cancelled'})
          .eq('id', payoutRequestId)
          .eq('status', 'pending')
          .select();

      return response.isNotEmpty;
    } catch (e) {
      throw Exception('Ödeme isteği iptal edilemedi: $e');
    }
  }

  /// Dükkan IBAN bilgilerini güncelle
  Future<void> updateShopIban({
    required String shopId,
    required String iban,
    required String bankName,
    required String accountHolderName,
  }) async {
    try {
      // IBAN formatını doğrula (TR ile başlamalı ve 26 karakter olmalı)
      final cleanIban = iban.replaceAll(' ', '').toUpperCase();
      if (!cleanIban.startsWith('TR') || cleanIban.length != 26) {
        throw Exception(
            'Geçersiz IBAN formatı. IBAN \'TR\' ile başlamalı ve 26 karakter olmalıdır.');
      }

      await _supabase
          .from('shops')
          .update({
            'iban': cleanIban,
            'bank_name': bankName,
            'account_holder_name': accountHolderName,
          })
          .eq('id', shopId);
    } catch (e) {
      throw Exception('IBAN bilgileri güncellenemedi: $e');
    }
  }

  /// Ödeme isteği durumunu al
  Future<String> getPayoutRequestStatus(String payoutRequestId) async {
    try {
      final response = await _supabase
          .from('payout_requests')
          .select('status')
          .eq('id', payoutRequestId)
          .single();

      return response['status'] as String? ?? 'unknown';
    } catch (e) {
      throw Exception('Ödeme isteği durumu getirilemedi: $e');
    }
  }

  /// Pending durumundaki ödeme isteklerinin sayısını getir
  Future<int> getPendingPayoutsCount(String sellerId) async {
    try {
      final response = await _supabase
          .from('payout_requests')
          .select('id')
          .eq('seller_id', sellerId)
          .eq('status', 'pending');

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Pending durumundaki ödeme isteklerinin toplam tutarını getir
  Future<double> getPendingPayoutRequestsTotal(String sellerId) async {
    try {
      final response = await _supabase
          .from('payout_requests')
          .select('total_amount')
          .eq('seller_id', sellerId)
          .eq('status', 'pending');

      double total = 0;
      for (var item in response) {
        total += (item['total_amount'] as num?)?.toDouble() ?? 0;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  /// Durum metnini döndür
  static String getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Bekliyor';
      case 'approved':
        return 'Onaylandı';
      case 'paid':
        return 'Ödendi';
      case 'rejected':
        return 'Reddedildi';
      case 'cancelled':
        return 'İptal Edildi';
      default:
        return 'Bilinmeyen';
    }
  }

  /// Durum rengini döndür
  static int getStatusColorValue(String status) {
    switch (status) {
      case 'pending':
        return 0xFFFFA726; // Orange
      case 'approved':
        return 0xFF42A5F5; // Blue
      case 'paid':
        return 0xFF9C27B0; // Purple (Ödendi için mor renk)
      case 'rejected':
        return 0xFFEF5350; // Red
      case 'cancelled':
        return 0xFF9E9E9E; // Grey
      default:
        return 0xFF9E9E9E;
    }
  }
}
