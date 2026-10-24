import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Randevulu sipariş: global anahtar, uygun saatler ve doğrulama.
///
/// Saatleri tek yerde sunucu üretir (`get_shop_schedule_slots`: Türkiye saati,
/// çalışma saatleri, slot süresi, hazırlık süresi). İstemci yalnız listeler;
/// siparişi eklerken sunucu tetikleyicisi yeniden doğrular.
class ScheduledOrderService {
  ScheduledOrderService([SupabaseClient? client]) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  static bool? _globalCache;
  static DateTime? _globalAt;
  static const Duration _globalTtl = Duration(minutes: 2);

  @visibleForTesting
  static void debugSetGlobal(bool? value) {
    _globalCache = value;
    _globalAt = value == null ? null : DateTime.now();
  }

  /// Admin global anahtarı. Okunamazsa false (özellik gizli kalır).
  Future<bool> globallyEnabled({bool forceRefresh = false}) async {
    final at = _globalAt;
    if (!forceRefresh &&
        _globalCache != null &&
        at != null &&
        DateTime.now().difference(at) < _globalTtl) {
      return _globalCache!;
    }
    try {
      final res = await _db.rpc('scheduled_orders_globally_enabled');
      final v = res == true;
      _globalCache = v;
      _globalAt = DateTime.now();
      return v;
    } catch (e) {
      debugPrint('⚠️ Randevulu sipariş ayarı okunamadı: $e');
      return _globalCache ?? false;
    }
  }

  /// Seçilebilir saatler (UTC, artan). Hata ya da kapalıysa boş liste.
  Future<List<DateTime>> slots(String shopId) async {
    try {
      final res = await _db.rpc('get_shop_schedule_slots', params: {'p_shop_id': shopId});
      if (res is! List) return const [];
      final out = <DateTime>[];
      for (final row in res) {
        final raw = row is Map ? row['slot_at'] : row;
        final t = raw == null ? null : DateTime.tryParse(raw.toString());
        if (t != null) out.add(t.toUtc());
      }
      out.sort();
      return out;
    } catch (e) {
      debugPrint('⚠️ Randevu saatleri alınamadı: $e');
      return const [];
    }
  }

  /// Dolu saatler (UTC): dükkânın "aynı saate en fazla" sınırına ulaşmış
  /// saatler (`get_shop_schedule_slot_status`). Sınır yoksa ya da
  /// okunamazsa boş küme — son kararı sipariş eklenirken sunucu verir
  /// ("Seçtiğiniz saat doldu").
  Future<Set<DateTime>> fullSlots(String shopId) async {
    try {
      final res = await _db.rpc('get_shop_schedule_slot_status', params: {'p_shop_id': shopId});
      if (res is! List) return const {};
      final out = <DateTime>{};
      for (final row in res) {
        if (row is! Map || row['is_full'] != true) continue;
        final t = DateTime.tryParse('${row['slot_at']}');
        if (t != null) out.add(t.toUtc());
      }
      return out;
    } catch (e) {
      debugPrint('⚠️ Dolu randevu saatleri alınamadı: $e');
      return const {};
    }
  }

  /// Sipariş öncesi doğrulama. Hata metni ya da null (geçerli). Ağ hatasında
  /// null döner: son kararı sipariş eklenirken sunucu verir.
  Future<String?> validate(String shopId, DateTime at) async {
    try {
      final res = await _db.rpc('validate_scheduled_order_slot', params: {
        'p_shop_id': shopId,
        'p_at': at.toUtc().toIso8601String(),
      });
      final msg = res?.toString().trim();
      return (msg == null || msg.isEmpty) ? null : msg;
    } catch (e) {
      debugPrint('⚠️ Randevu doğrulanamadı: $e');
      return null;
    }
  }
}
