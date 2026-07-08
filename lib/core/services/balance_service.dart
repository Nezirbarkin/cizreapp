import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/balance_model.dart';
import '../models/balance_transaction_model.dart';
import '../utils/app_error_handler.dart';

/// Bakiye Servisi
/// Bakiye işlemleri için API çağrılarını yönetir
class BalanceService {
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      throw FriendlyException.from(e);
    }
  }

  /// Kullanıcının bakiyesini getir
  Future<UserBalance?> getBalance() async {
    try {
      debugPrint('💰 BALANCE: Bakiye getiriliyor...');

      final response = await _supabase.functions.invoke('get-balance');

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Bakiye alınamadı';
        throw Exception(error);
      }

      if (response.data['balance'] == null) {
        return null;
      }

      return UserBalance.fromJson(response.data['balance']);
    } catch (e) {
      debugPrint('❌ BALANCE: Bakiye getirme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Bakiye yükleme başlat (İyzico)
  Future<TopupInitResult> initializeTopup({
    required double amount,
  }) async {
    try {
      debugPrint('💰 BALANCE: Yükleme başlatılıyor...');
      debugPrint('  └─ amount: $amount');

      final response = await _supabase.functions.invoke(
        'create-balance-topup',
        body: {'amount': amount},
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Yükleme başlatılamadı';
        throw Exception(error);
      }

      final data = response.data;

      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'Yükleme başlatılamadı');
      }

      debugPrint('✅ BALANCE: Yükleme başlatıldı');
      debugPrint('  └─ conversation_id: ${data['conversation_id']}');

      return TopupInitResult(
        paymentPageUrl: data['payment_page_url'],
        token: data['token'],
        conversationId: data['conversation_id'],
      );
    } catch (e) {
      debugPrint('❌ BALANCE: Yükleme başlatma hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Siparişte bakiye kullan
  Future<BalancePaymentResult> useBalanceForOrder({
    required String orderId,
    required double amount,
    required double orderTotal,
  }) async {
    try {
      debugPrint('💰 BALANCE: Siparişte bakiye kullanılıyor...');
      debugPrint('  └─ orderId: $orderId');
      debugPrint('  └─ amount: $amount');

      final response = await _supabase.functions.invoke(
        'use-balance-for-order',
        body: {
          'order_id': orderId,
          'amount': amount,
          'order_total': orderTotal,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Bakiye kullanılamadı';
        throw Exception(error);
      }

      final data = response.data;

      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'İşlem başarısız');
      }

      debugPrint('✅ BALANCE: Bakiye kullanıldı');
      debugPrint('  └─ amount_paid: ${data['amount_paid']}');
      debugPrint('  └─ new_balance: ${data['new_balance']}');

      // Güvenli parse: Edge function veya RPC bazı alanları null döndürürse
      // (örn. deploy edilmemis Edge function, veya deduct_from_balance RPC
      // RETURNS TABLE boş dönerse) 'as num)' cast'i patlamadan 0'a fallback
      // yapıyoruz. Eski davranışta null cast hatayı sipariş iptaline kadar
      // götürüyordu.
      num safeNum(dynamic v, [num fallback = 0]) =>
          v is num ? v : (v is String ? (num.tryParse(v) ?? fallback) : fallback);

      return BalancePaymentResult(
        transactionId: (data['transaction_id'] as String?) ?? '',
        amountPaid: safeNum(data['amount_paid']).toDouble(),
        remainingAmount: safeNum(data['remaining_amount']).toDouble(),
        newBalance: safeNum(data['new_balance']).toDouble(),
        isFullyPaid: data['is_fully_paid'] == true,
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final serverError = details is Map ? details['error'] as String? : null;
      final debugDetail = details is Map ? details['debug_detail'] : null;
      debugPrint('❌ BALANCE: Bakiye kullanma hatası - status: ${e.status}, error: $serverError');
      if (debugDetail != null) {
        debugPrint('🔎 BALANCE: debug_detail = $debugDetail');
      }
      throw FriendlyException(serverError ?? 'Bakiye ile ödeme başarısız oldu.', originalError: e);
    } catch (e) {
      debugPrint('❌ BALANCE: Bakiye kullanma hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Sipariş iptalinde bakiyeye iade
  Future<RefundResult> refundToBalance({
    required String orderId,
    required double amount,
    String? reason,
  }) async {
    try {
      debugPrint('💰 BALANCE: Bakiyeye iade yapılıyor...');
      debugPrint('  └─ orderId: $orderId');
      debugPrint('  └─ amount: $amount');

      final response = await _supabase.functions.invoke(
        'refund-to-balance',
        body: {
          'order_id': orderId,
          'amount': amount,
          'reason': reason ?? 'Sipariş iadesi',
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'İade yapılamadı';
        throw Exception(error);
      }

      final data = response.data;

      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'İşlem başarısız');
      }

      debugPrint('✅ BALANCE: İade yapıldı');
      debugPrint('  └─ refund_amount: ${data['refund_amount']}');
      debugPrint('  └─ new_balance: ${data['new_balance']}');

      return RefundResult(
        transactionId: data['transaction_id'],
        refundAmount: (data['refund_amount'] as num).toDouble(),
        newBalance: (data['new_balance'] as num).toDouble(),
      );
    } catch (e) {
      debugPrint('❌ BALANCE: İade hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// İşlem geçmişini getir
  Future<BalanceTransactionPage> getTransactionHistory({
    int page = 1,
    int limit = 20,
    String? type,
    String? status,
  }) async {
    try {
      debugPrint('💰 BALANCE: İşlem geçmişi getiriliyor...');
      debugPrint('  └─ page: $page, limit: $limit');

      final params = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (type != null) params['type'] = type;
      if (status != null) params['status'] = status;

      final queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');

      final response = await _supabase.functions.invoke(
        'get-transaction-history?$queryString',
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Geçmiş alınamadı';
        throw Exception(error);
      }

      return BalanceTransactionPage.fromJson(response.data);
    } catch (e) {
      debugPrint('❌ BALANCE: Geçmiş getirme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Satıcı kazanç özetini getir
  Future<SellerEarningsSummary?> getSellerEarnings() async {
    try {
      debugPrint('💰 BALANCE: Satıcı kazanç özeti getiriliyor...');

      final response = await _supabase.functions.invoke('get-seller-earnings');

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Kazanç alınamadı';
        throw Exception(error);
      }

      if (response.data['earnings_summary'] == null) {
        return null;
      }

      return SellerEarningsSummary.fromJson(response.data['earnings_summary']);
    } catch (e) {
      debugPrint('❌ BALANCE: Kazanç getirme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Bakiye kontrolü (yeterli mi?)
  Future<bool> hasEnoughBalance(double amount) async {
    try {
      final balance = await getBalance();
      if (balance == null) return false;
      return balance.availableBalance >= amount;
    } catch (e) {
      debugPrint('❌ BALANCE: Bakiye kontrol hatası - $e');
      return false;
    }
  }

  /// Yükleme durumunu kontrol et (callback sonrası)
  Future<bool> checkTopupStatus(String conversationId) async {
    try {
      final response = await _supabase
          .from('balance_transactions')
          .select('status')
          .eq('payment_reference', conversationId)
          .eq('type', 'topup')
          .maybeSingle();

      return response?['status'] == 'completed';
    } catch (e) {
      debugPrint('❌ BALANCE: Yükleme durumu kontrol hatası - $e');
      return false;
    }
  }

  /// Admin: Kullanıcı bakiyesine ekleme yap
  Future<void> adminAddBalance({
    required String userId,
    required double amount,
    required String description,
  }) async {
    try {
      debugPrint('💰 BALANCE: Admin bakiye ekleme...');
      debugPrint('  └─ userId: $userId');
      debugPrint('  └─ amount: $amount');

      final response = await _supabase.functions.invoke(
        'admin-add-balance',
        body: {
          'user_id': userId,
          'amount': amount,
          'description': description,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'İşlem başarısız';
        throw Exception(error);
      }
    } catch (e) {
      debugPrint('❌ BALANCE: Admin ekleme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Admin: Kullanıcı bakiyesinden düşme yap
  Future<void> adminDeductBalance({
    required String userId,
    required double amount,
    required String description,
  }) async {
    try {
      debugPrint('💰 BALANCE: Admin bakiye düşme...');
      debugPrint('  └─ userId: $userId');
      debugPrint('  └─ amount: $amount');

      final response = await _supabase.functions.invoke(
        'admin-deduct-balance',
        body: {
          'user_id': userId,
          'amount': amount,
          'description': description,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'İşlem başarısız';
        throw Exception(error);
      }
    } catch (e) {
      debugPrint('❌ BALANCE: Admin düşme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Admin: Tüm işlemleri getir
  /// Sadece başarılı (status='completed') işlemleri listeler.
  /// pending ve failed kayıtlar cüzdan yönetimi işlem geçmişinde gösterilmez.
  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    try {
      debugPrint('💰 BALANCE: Tüm işlemler getiriliyor...');

      final response = await _supabase
          .from('balance_transactions')
          .select('*')
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(100);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ BALANCE: İşlemler getirme hatası - $e');
      return [];
    }
  }
}

/// Yükleme başlatma sonucu
class TopupInitResult {
  final String paymentPageUrl;
  final String token;
  final String conversationId;

  TopupInitResult({
    required this.paymentPageUrl,
    required this.token,
    required this.conversationId,
  });
}

/// Bakiye ödeme sonucu
class BalancePaymentResult {
  final String transactionId;
  final double amountPaid;
  final double remainingAmount;
  final double newBalance;
  final bool isFullyPaid;

  BalancePaymentResult({
    required this.transactionId,
    required this.amountPaid,
    required this.remainingAmount,
    required this.newBalance,
    required this.isFullyPaid,
  });
}

/// İade sonucu
class RefundResult {
  final String transactionId;
  final double refundAmount;
  final double newBalance;

  RefundResult({
    required this.transactionId,
    required this.refundAmount,
    required this.newBalance,
  });
}
