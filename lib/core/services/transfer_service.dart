import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Havale/EFT bildirimi → admin onay akışı.
///
/// Müşteri `submitTransferConfirmation` ile `transfer_confirmations`
/// tablosuna pending kayıt ekler. Admin `getPendingConfirmations` ile
/// listeler, `approveConfirmation`/`rejectConfirmation` ile karara bağlar.
///
/// Onaylandığında DB tarafında `approve_transfer_confirmation` RPC'si
/// OTOMATİK olarak bakiye ekler (add_to_balance) + kullanıcıya
/// notifications kaydı insert eder. Bu notification kaydı
/// `notifications_outbox_trigger` ile outbox'a yazılır ve
/// `process-notification-outbox` worker'ı FCM push'u gönderir.
///
/// Flutter istemcisi push göndermek için herhangi bir Edge Function
/// çağırmaz; `fcm_token` SELECT etmez. Push tamamen outbox üzerinden akar.
///
/// Tüm DB işlemleri RLS tarafından korunur:
/// - Kullanıcı yalnızca kendi kayıtlarını görür, sadece pending INSERT eder.
/// - Sadece admin onay/red yapabilir (RPC içinde rol kontrolü).
class TransferService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Kullanıcı havale bildirimi gönderir (pending kayıt oluşturur).
  ///
  /// [amount] yüklenecek tutar, [note] opsiyonel dekont/açıklama notu,
  /// [bankAccountId] seçili banka hesabı id'si (UI'dan),
  /// [senderFullName] havaleyi YAPAN kişinin ad soyadı (admin onaylarken
  /// görmesi için; kullanıcı kendi hesabından yapıyorsa kendi adını girer,
  /// başkasının hesabından yapıyorsa o kişinin adını girer). Zorunlu.
  ///
  /// RLS: user_id = auth.uid() ve status = 'pending' kontrolü INSERT policy'de
  /// var, bu yüzden kullanıcı başkası adına veya status='approved' ile kayıt
  /// ekleyemez.
  ///
  /// Aynı kullanıcı için zaten pending bir kayıt varsa, DB tarafında unique
  /// kontrolü yok (kasıtlı: kullanıcı yeni tutar için yeni bildirim gönderebilir).
  Future<void> submitTransferConfirmation({
    required double amount,
    required String senderFullName,
    String? note,
    String? bankAccountId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Oturum açmanız gerekli');
    }
    if (amount <= 0) {
      throw Exception('Geçersiz tutar');
    }

    try {
      await _supabase.from('transfer_confirmations').insert({
        'user_id': userId,
        'amount': amount,
        'note': note,
        'bank_account_id': bankAccountId,
        'sender_full_name': senderFullName.trim(),
        'status': 'pending',
      });
    } on PostgrestException catch (e) {
      // RLS reddi veya CHECK hatası
      debugPrint('❌ TransferService.submit hatası: ${e.code} ${e.message}');
      throw Exception('Bildirim gönderilemedi: ${e.message}');
    }
  }

  /// (Admin) Bekleyen havale bildirimlerini listeler.
  /// RLS: admin policy tüm kayıtları görür.
  Future<List<Map<String, dynamic>>> getPendingConfirmations() async {
    try {
      final response = await _supabase
          .from('transfer_confirmations')
          .select('''
            id, user_id, amount, note, status, created_at,
            bank_account_id, receipt_url, sender_full_name,
            bank_account:bank_accounts ( bank_name, account_name, iban ),
            user:profiles!transfer_confirmations_user_id_fkey (
              full_name, phone
            )
          ''')
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(200);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ TransferService.getPending hatası: $e');
      rethrow;
    }
  }

  /// (Admin) Bekleyen onay sayısı — admin sekmesinde rozet için.
  Future<int> getPendingCount() async {
    try {
      final response = await _supabase
          .from('transfer_confirmations')
          .select('id')
          .eq('status', 'pending');
      return (response as List).length;
    } catch (e) {
      debugPrint('❌ TransferService.getPendingCount hatası: $e');
      return 0;
    }
  }

  /// (Admin) Onayla → RPC bakiyeyi OTOMATİK ekler + kullanıcıya notification
  /// insert eder (trigger). Bu çağrı başarılıysa bakiye kesin eklenmiştir.
  /// Push, outbox trigger'ı + worker tarafından güvenli biçimde gönderilir.
  ///
  /// Idempotent: aynı id ikinci kez onaylanırsa RPC hata fırlatır
  /// ("Bu kayıt zaten approved olarak işlenmiş") → UI bunu yakalar.
  Future<Map<String, dynamic>> approveConfirmation({
    required String confirmationId,
    String? adminNote,
  }) async {
    try {
      final result = await _supabase.rpc(
        'approve_transfer_confirmation',
        params: {
          'p_confirmation_id': confirmationId,
          'p_admin_note': adminNote,
        },
      );
      // RPC RETURNS JSON → Map döner.
      // Notification kaydı RPC içinde INSERT edilir; outbox trigger'ı
      // otomatik olarak push'u planlar. İstemci tarafında ek bir
      // push çağrısı YAPILMAZ.
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      debugPrint('❌ approve_confirmation RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyRpcError(e));
    }
  }

  /// (Admin) Reddet → kullanıcıya notification insert edilir (trigger).
  /// Bakiye eklenmez. admin_note kullanıcıya gösterilir (red gerekçesi).
  Future<Map<String, dynamic>> rejectConfirmation({
    required String confirmationId,
    String? adminNote,
  }) async {
    try {
      final result = await _supabase.rpc(
        'reject_transfer_confirmation',
        params: {
          'p_confirmation_id': confirmationId,
          'p_admin_note': adminNote,
        },
      );
      // Notification kaydı RPC içinde INSERT edilir; outbox trigger'ı
      // otomatik olarak push'u planlar. İstemci tarafında ek bir
      // push çağrısı YAPILMAZ.
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      debugPrint('❌ reject_confirmation RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyRpcError(e));
    }
  }

  /// (Müşteri) Kendi bildirim geçmişini görür.
  Future<List<Map<String, dynamic>>> getMyConfirmations() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await _supabase
          .from('transfer_confirmations')
          .select(
            'id, amount, note, status, admin_note, created_at, resolved_at',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ getMyConfirmations hatası: $e');
      return [];
    }
  }

  String _friendlyRpcError(PostgrestException e) {
    // e.message PostgrestException'da nullable olabilir; boş string fallback.
    final msg = e.message.isEmpty ? '(mesaj yok)' : e.message;
    if (e.code == '42501' || msg.contains('admin')) {
      return 'Bu işlem için admin yetkisi gerekli';
    }
    if (msg.contains('zaten')) {
      return msg; // idempotent ikinci onay mesajı
    }
    if (msg.contains('bulunamadı')) {
      return 'Kayıt bulunamadı, liste yenileniyor';
    }
    return 'İşlem başarısız: $msg';
  }
}
