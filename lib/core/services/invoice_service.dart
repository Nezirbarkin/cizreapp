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
  /// Not: profiles tablosundan SELECT grant'i REVOKE edildiği için doğrudan
  /// SELECT yapılamaz. Bunun yerine SECURITY DEFINER RPC kullanılır.
  Future<InvoiceInfo?> getMyInvoiceInfo() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await _client.rpc<Map<String, dynamic>>(
      'get_my_invoice_profile',
    );

    // invoice_full_name null ise fatura bilgisi yok demektir
    if (response['invoice_full_name'] == null) return null;

    return InvoiceInfo.fromJson(response);
  }

  /// Fatura bilgilerini profile kaydeder
  /// Not: profiles UPDATE grant'i REVOKE edildiği için doğrudan UPDATE
  /// yapılamaz. RPC üzerinden yazılır; RPC TC no, vergi no, e-posta
  /// format/length doğrulaması uygular.
  Future<bool> saveInvoiceInfo(InvoiceInfo info) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    await _client.rpc(
      'update_my_invoice_profile',
      params: {
        'p_invoice_type': info.type.dbValue,
        'p_invoice_full_name': info.fullName,
        'p_invoice_tax_number': info.taxNumber,
        'p_invoice_tc_no': info.tcNo,
        'p_invoice_tax_office': info.taxOffice,
        'p_invoice_address': info.address,
        'p_invoice_email': info.email,
      },
    );

    return true;
  }

  /// Kayıtlı fatura bilgilerini siler
  /// Not: profiles UPDATE grant'i REVOKE edildiği için doğrudan UPDATE
  /// yapılamaz. RPC tüm fatura alanlarını NULL'a çeker.
  Future<bool> clearInvoiceInfo() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    // update_my_invoice_profile: tüm alanları NULL geçir; RPC sunucuda
    // boş değerle temizler.
    await _client.rpc(
      'update_my_invoice_profile',
      params: {
        'p_invoice_type': null,
        'p_invoice_full_name': null,
        'p_invoice_tax_number': null,
        'p_invoice_tc_no': null,
        'p_invoice_tax_office': null,
        'p_invoice_address': null,
        'p_invoice_email': null,
      },
    );

    return true;
  }

  /// Belirli bir kullanıcının profilindeki fatura bilgilerini getirir
  /// (Satıcı paneli için - sadece fatura ünvanı gösterilir, T.C. no gizli)
  /// Not: Bu fonksiyon PII (TC no, vergi no, adres) döner. Çağıran taraf
  /// yalnızca fatura ünvanını kullansın; aksi halde sızıntı oluşur. Satici
  /// ekranı InvoiceInfo.fromJson ile yalnız full_name gösterir.
  Future<InvoiceInfo?> getUserInvoiceInfo(String userId) async {
    // profiles SELECT grant'i anon/authenticated'a REVOKE edildiği için
    // bu RPC SECURITY DEFINER ve service_role grant'lı olmalıdır. Henüz
    // böyle bir RPC yoksa çağıran null alır; satıcı paneli yalnız public
    // sütunları gösterir.
    // TODO: Bu fonksiyon için ileride admin_set_user_invoice veya benzeri
    // bir yetkili RPC tanımlanmalıdır. Şimdilik güvenli tarafta kalıp
    // null döndürüyoruz.
    return null;
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
      address: [
        addressLine1,
        addressLine2,
        district,
        city,
      ].where((p) => p != null && p.isNotEmpty).join(', '),
    );
  }
}
