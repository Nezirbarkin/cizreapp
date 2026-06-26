import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bank_account_model.dart';

/// Banka Hesapları Servisi
class BankAccountService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Tüm aktif banka hesaplarını getir (kullanıcı tarafı için)
  Future<List<BankAccount>> getActiveBankAccounts() async {
    try {
      final response = await _supabase
          .from('bank_accounts')
          .select('*')
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .order('created_at', ascending: false);

      return (response as List)
          .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ BANK: Aktif banka hesapları getirme hatası: $e');
      return [];
    }
  }

  /// Tüm banka hesaplarını getir (admin için)
  Future<List<BankAccount>> getAllBankAccounts({bool includeInactive = true}) async {
    try {
      final response = await _supabase
          .from('bank_accounts')
          .select('*')
          .order('display_order', ascending: true)
          .order('created_at', ascending: false);

      final accounts = (response as List)
          .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
          .toList();

      // Filtreleme
      if (!includeInactive) {
        return accounts.where((a) => a.isActive).toList();
      }
      return accounts;
    } catch (e) {
      debugPrint('❌ BANK: Tüm banka hesapları getirme hatası: $e');
      return [];
    }
  }

  /// Yeni banka hesabı ekle
  Future<BankAccount> addBankAccount({
    required String bankName,
    required String iban,
    required String accountName,
    String? branch,
    String? accountNumber,
    String? description,
    int displayOrder = 0,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final response = await _supabase
          .from('bank_accounts')
          .insert({
            'bank_name': bankName,
            'iban': iban.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
            'account_name': accountName,
            'branch': branch,
            'account_number': accountNumber,
            'description': description,
            'display_order': displayOrder,
            'is_active': true,
            'created_by': userId,
          })
          .select()
          .single();

      return BankAccount.fromJson(response);
    } catch (e) {
      debugPrint('❌ BANK: Banka hesabı ekleme hatası: $e');
      rethrow;
    }
  }

  /// Banka hesabını güncelle
  Future<BankAccount> updateBankAccount({
    required String id,
    String? bankName,
    String? iban,
    String? accountName,
    String? branch,
    String? accountNumber,
    String? description,
    int? displayOrder,
    bool? isActive,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      if (bankName != null) updateData['bank_name'] = bankName;
      if (iban != null) updateData['iban'] = iban.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      if (accountName != null) updateData['account_name'] = accountName;
      if (branch != null) updateData['branch'] = branch;
      if (accountNumber != null) updateData['account_number'] = accountNumber;
      if (description != null) updateData['description'] = description;
      if (displayOrder != null) updateData['display_order'] = displayOrder;
      if (isActive != null) updateData['is_active'] = isActive;

      final response = await _supabase
          .from('bank_accounts')
          .update(updateData)
          .eq('id', id)
          .select()
          .single();

      return BankAccount.fromJson(response);
    } catch (e) {
      debugPrint('❌ BANK: Banka hesabı güncelleme hatası: $e');
      rethrow;
    }
  }

  /// Banka hesabını sil
  Future<void> deleteBankAccount(String id) async {
    try {
      await _supabase
          .from('bank_accounts')
          .delete()
          .eq('id', id);
    } catch (e) {
      debugPrint('❌ BANK: Banka hesabı silme hatası: $e');
      rethrow;
    }
  }

  /// Banka hesabını aktif/pasif yap
  Future<void> toggleBankAccountStatus(String id, bool isActive) async {
    try {
      await _supabase
          .from('bank_accounts')
          .update({'is_active': isActive})
          .eq('id', id);
    } catch (e) {
      debugPrint('❌ BANK: Banka hesabı durum değiştirme hatası: $e');
      rethrow;
    }
  }
}