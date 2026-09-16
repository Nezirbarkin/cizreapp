import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `profiles` üzerindeki iletişim sütunlarına (email, phone) ilişki
/// doğrulayan RPC'ler üzerinden erişim.
///
/// NEDEN: `email` ve `phone` sütunları `authenticated` rolünden kaldırılıyor
/// (bkz. `supabase/migrations/20260907110001_revoke_profiles_pii_from_authenticated.sql`).
/// Erişim ROLE değil İLİŞKİYE bağlı olduğu için — admin herkesi, satıcı
/// yalnız kendi siparişinin müşterisini, kurye yalnız kendi atamasını
/// görebilmeli — RLS (satır bazlı) ve sütun GRANT'i (rol bazlı) tek başına
/// yetmiyor. Bu yüzden ilişkiyi sunucuda doğrulayan SECURITY DEFINER
/// RPC'ler kullanılıyor.
///
/// Bu sınıf yalnız o RPC'lerin ince bir sarmalayıcısıdır; hiçbir yetki
/// kararı istemcide verilmez.
class ContactLookupService {
  ContactLookupService([SupabaseClient? client])
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Admin için kullanıcı iletişim bilgileri. Admin değilse RPC 42501 atar;
  /// burada boş map'e düşülür ki ekranlar PII olmadan da çalışsın.
  ///
  /// Dönen map: `userId -> {id, username, full_name, avatar_url, email, phone}`
  Future<Map<String, Map<String, dynamic>>> adminContactsByUserId(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    try {
      final rows = await _supabase.rpc(
        'admin_profiles_contact',
        params: {'p_user_ids': ids},
      );
      return _indexBy(rows, 'id');
    } catch (e) {
      debugPrint('⚠️ admin_profiles_contact başarısız: $e');
      return const {};
    }
  }

  /// Siparişin müşteri iletişimi. Yalnız siparişin dükkan sahibi, atanmış
  /// kurye, siparişin sahibi veya admin sonuç alır.
  ///
  /// Dönen map: `orderId -> {order_id, user_id, full_name, username, phone, email}`
  Future<Map<String, Map<String, dynamic>>> customerContactsByOrderId(
    Iterable<String> orderIds,
  ) async {
    final ids = orderIds.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    try {
      final rows = await _supabase.rpc(
        'order_customer_contact',
        params: {'p_order_ids': ids},
      );
      return _indexBy(rows, 'order_id');
    } catch (e) {
      debugPrint('⚠️ order_customer_contact başarısız: $e');
      return const {};
    }
  }

  /// Siparişe atanmış kuryenin iletişimi. Yalnız dükkan sahibi, müşteri,
  /// kuryenin kendisi veya admin sonuç alır.
  ///
  /// Dönen map: `orderId -> {order_id, assignment_id, courier_id, full_name, phone, status}`
  Future<Map<String, Map<String, dynamic>>> courierContactsByOrderId(
    Iterable<String> orderIds,
  ) async {
    final ids = orderIds.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    try {
      final rows = await _supabase.rpc(
        'order_courier_contacts',
        params: {'p_order_ids': ids},
      );
      return _indexBy(rows, 'order_id');
    } catch (e) {
      debugPrint('⚠️ order_courier_contacts başarısız: $e');
      return const {};
    }
  }

  static Map<String, Map<String, dynamic>> _indexBy(
    dynamic rows,
    String keyColumn,
  ) {
    final result = <String, Map<String, dynamic>>{};
    if (rows is! List) return result;
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final key = map[keyColumn]?.toString();
      if (key != null && key.isNotEmpty) result[key] = map;
    }
    return result;
  }
}
