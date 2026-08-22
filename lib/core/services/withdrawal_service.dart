import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/seller_withdrawal_model.dart';
import '../utils/app_error_handler.dart';

/// Çekim Servisi
/// Satıcı çekim işlemleri için API çağrılarını yönetir
class WithdrawalService {
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      throw FriendlyException.from(e);
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
      throw FriendlyException.from(e);
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
      throw FriendlyException.from(e);
    }
  }

  /// Admin: Tüm çekim taleplerini getir.
  /// `statuses` birden fazla durum içerebilir (ör. ['processing', 'completed']);
  /// tek durum filtrelemek için tek elemanlı liste verin.
  Future<List<WithdrawalWithSeller>> getAllWithdrawals({
    List<String>? statuses,
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

      if (statuses != null && statuses.isNotEmpty) {
        query = _supabase
            .from('seller_withdrawals')
            .select('''
              *,
              profiles: seller_id (full_name, phone)
            ''')
            .inFilter('status', statuses)
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
      throw FriendlyException.from(e);
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
      throw FriendlyException.from(e);
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
