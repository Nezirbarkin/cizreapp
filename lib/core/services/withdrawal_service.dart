import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/seller_withdrawal_model.dart';

/// Çekim Servisi
/// Satıcı çekim işlemleri için API çağrılarını yönetir
class WithdrawalService {
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  /// Çekim talebi oluştur
  Future<WithdrawalRequestResult> requestWithdrawal({
    required double amount,
    required String bankName,
    required String iban,
    String? bankAccountName,
    String? bankAccountNumber,
  }) async {
    try {
      debugPrint('💸 WITHDRAWAL: Çekim talebi oluşturuluyor...');
      debugPrint('  └─ amount: $amount');
      debugPrint('  └─ bank: $bankName');

      final response = await _supabase.functions.invoke(
        'request-withdrawal',
        body: {
          'amount': amount,
          'bank_name': bankName,
          'iban': iban,
          'bank_account_name': bankAccountName,
          'bank_account_number': bankAccountNumber,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Çekim talebi oluşturulamadı';
        throw Exception(error);
      }

      final data = response.data;

      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'İşlem başarısız');
      }

      debugPrint('✅ WITHDRAWAL: Çekim talebi oluşturuldu');
      debugPrint('  └─ withdrawal_id: ${data['withdrawal_id']}');
      debugPrint('  └─ net_amount: ${data['net_amount']}');

      return WithdrawalRequestResult(
        withdrawalId: data['withdrawal_id'],
        amount: (data['amount'] as num).toDouble(),
        fee: (data['fee'] as num).toDouble(),
        netAmount: (data['net_amount'] as num).toDouble(),
        status: data['status'],
      );
    } catch (e) {
      debugPrint('❌ WITHDRAWAL: Çekim talebi hatası - $e');
      rethrow;
    }
  }

  /// Admin: Çekim talebini işle (onayla/reddet)
  Future<void> processWithdrawal({
    required String withdrawalId,
    required String action,
    String? notes,
  }) async {
    try {
      debugPrint('💸 WITHDRAWAL: Çekim işleniyor...');
      debugPrint('  └─ withdrawalId: $withdrawalId');
      debugPrint('  └─ action: $action');

      final response = await _supabase.functions.invoke(
        'process-withdrawal',
        body: {
          'withdrawal_id': withdrawalId,
          'action': action, // approve, reject, process
          'notes': notes,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? 'Çekim işlenemedi';
        throw Exception(error);
      }

      if (response.data['status'] != 'success') {
        throw Exception(response.data['error'] ?? 'İşlem başarısız');
      }

      debugPrint('✅ WITHDRAWAL: Çekim işlendi');
      debugPrint('  └─ new_status: ${response.data['new_status']}');
    } catch (e) {
      debugPrint('❌ WITHDRAWAL: Çekim işleme hatası - $e');
      rethrow;
    }
  }

  /// Satıcının çekim taleplerini getir
  Future<List<SellerWithdrawal>> getMyWithdrawals() async {
    try {
      debugPrint('💸 WITHDRAWAL: Çekim taleplerim getiriliyor...');

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı girişi bulunamadı');
      }

      final response = await _supabase
          .from('seller_withdrawals')
          .select('*')
          .eq('seller_id', userId)
          .order('created_at', ascending: false);

      final withdrawals = (response as List)
          .map((e) => SellerWithdrawal.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint('✅ WITHDRAWAL: ${withdrawals.length} çekim talebi bulundu');

      return withdrawals;
    } catch (e) {
      debugPrint('❌ WITHDRAWAL: Çekim talepleri getirme hatası - $e');
      rethrow;
    }
  }

  /// Admin: Tüm çekim taleplerini getir
  Future<List<WithdrawalWithSeller>> getAllWithdrawals({
    String? status,
    int limit = 50,
  }) async {
    try {
      debugPrint('💸 WITHDRAWAL: Tüm çekim talepleri getiriliyor...');

      var query = _supabase
          .from('seller_withdrawals')
          .select('''
            *,
            profiles: seller_id (full_name, phone)
          ''')
          .order('created_at', ascending: false)
          .limit(limit);

      if (status != null) {
        query = _supabase
            .from('seller_withdrawals')
            .select('''
              *,
              profiles: seller_id (full_name, phone)
            ''')
            .eq('status', status)
            .order('created_at', ascending: false)
            .limit(limit);
      }

      final response = await query;

      final withdrawals = (response as List).map((e) {
        final data = e as Map<String, dynamic>;
        final profile = data['profiles'] as Map<String, dynamic>?;
        
        return WithdrawalWithSeller(
          withdrawal: SellerWithdrawal.fromJson(data),
          sellerName: profile?['full_name'] as String?,
          sellerPhone: profile?['phone'] as String?,
        );
      }).toList();

      debugPrint('✅ WITHDRAWAL: ${withdrawals.length} çekim talebi bulundu');

      return withdrawals;
    } catch (e) {
      debugPrint('❌ WITHDRAWAL: Tüm talepler getirme hatası - $e');
      rethrow;
    }
  }

  /// Çekim detayını getir
  Future<SellerWithdrawal?> getWithdrawalById(String withdrawalId) async {
    try {
      final response = await _supabase
          .from('seller_withdrawals')
          .select('*')
          .eq('id', withdrawalId)
          .maybeSingle();

      if (response == null) return null;

      return SellerWithdrawal.fromJson(response);
    } catch (e) {
      debugPrint('❌ WITHDRAWAL: Çekim detayı hatası - $e');
      rethrow;
    }
  }

  /// Bekleyen çekim sayısı (admin badge için)
  Future<int> getPendingWithdrawalsCount() async {
    try {
      final response = await _supabase
          .from('seller_withdrawals')
          .select('id')
          .eq('status', 'pending');

      return (response as List).length;
    } catch (e) {
      debugPrint('❌ WITHDRAWAL: Bekleyen sayı hatası - $e');
      return 0;
    }
  }
}

/// Satıcı bilgisiyle çekim
class WithdrawalWithSeller {
  final SellerWithdrawal withdrawal;
  final String? sellerName;
  final String? sellerPhone;

  WithdrawalWithSeller({
    required this.withdrawal,
    this.sellerName,
    this.sellerPhone,
  });
}

/// Çekim talebi sonucu
class WithdrawalRequestResult {
  final String withdrawalId;
  final double amount;
  final double fee;
  final double netAmount;
  final String status;

  WithdrawalRequestResult({
    required this.withdrawalId,
    required this.amount,
    required this.fee,
    required this.netAmount,
    required this.status,
  });
}
