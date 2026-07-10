import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/invoice_info_model.dart';

/// Fatura bilgileri servisi
/// 
/// Müşteri fatura bilgilerini yönetir:
/// - profiles tablosundan kayıtlı fatura bilgilerini çeker
/// - profiles tablosuna fatura bilgilerini kaydeder
/// - Sipariş anında fatura bilgisi snapshot'ını hazırlar
class InvoiceService {
  final SupabaseClient _client;

  InvoiceService({SupabaseClient? client}) 
      : _client = client ?? Supabase.instance.client;

  /// Mevcut kullanıcının kayıtlı fatura bilgilerini getirir
  Future<InvoiceInfo?> getMyInvoiceInfo() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('profiles')
        .select('invoice_type, invoice_full_name, invoice_tax_number, '
                'invoice_tc_no, invoice_tax_office, invoice_address, '
                'invoice_email, invoice_saved_at')
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    
    // invoice_full_name null ise fatura bilgisi yok demektir
    if (response['invoice_full_name'] == null) return null;

    return InvoiceInfo.fromJson(response);
  }

  /// Fatura bilgilerini profile kaydeder
  Future<bool> saveInvoiceInfo(InvoiceInfo info) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final data = {
      'invoice_type': info.type.dbValue,
      'invoice_full_name': info.fullName,
      'invoice_tax_number': info.taxNumber,
      'invoice_tc_no': info.tcNo,
      'invoice_tax_office': info.taxOffice,
      'invoice_address': info.address,
      'invoice_email': info.email,
      'invoice_saved_at': DateTime.now().toIso8601String(),
    };

    await _client
        .from('profiles')
        .update(data)
        .eq('id', userId)
        .select()
        .single();

    return true;
  }

  /// Kayıtlı fatura bilgilerini siler
  Future<bool> clearInvoiceInfo() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final data = {
      'invoice_type': null,
      'invoice_full_name': null,
      'invoice_tax_number': null,
      'invoice_tc_no': null,
      'invoice_tax_office': null,
      'invoice_address': null,
      'invoice_email': null,
      'invoice_saved_at': null,
    };

    await _client
        .from('profiles')
        .update(data)
        .eq('id', userId)
        .select()
        .single();

    return true;
  }

  /// Belirli bir kullanıcının profilindeki fatura bilgilerini getirir
  /// (Satıcı paneli için - sadece fatura ünvanı gösterilir, T.C. no gizli)
  Future<InvoiceInfo?> getUserInvoiceInfo(String userId) async {
    final response = await _client
        .from('profiles')
        .select('invoice_type, invoice_full_name, invoice_tax_number, '
                'invoice_tc_no, invoice_tax_office, invoice_address, '
                'invoice_email')
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    
    if (response['invoice_full_name'] == null) return null;

    return InvoiceInfo.fromJson(response);
  }

  /// Sipariş oluşturulurken fatura snapshot'ını hazırlar
  /// Eğer kayıtlı fatura bilgisi yoksa null döner
  static Map<String, dynamic>? prepareOrderSnapshot(InvoiceInfo? info) {
    if (info == null || info.isEmpty) return null;
    return info.toOrderSnapshot();
  }

  /// Sipariş oluşturulurken adres bilgilerinden fatura bilgisi oluşturur
  /// "Adres bilgilerimle aynı" seçeneği için
  static InvoiceInfo? fromAddress({
    required String fullName,
    String? phone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? district,
  }) {
    return InvoiceInfo(
      type: InvoiceType.individual,
      fullName: fullName,
      address: [addressLine1, addressLine2, district, city]
          .where((p) => p != null && p.isNotEmpty)
          .join(', '),
    );
  }
}
