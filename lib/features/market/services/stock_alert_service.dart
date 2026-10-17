import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/app_error_handler.dart' show FriendlyException;

/// "Stoğa gelince haber ver" aboneliği (`public.stock_alerts`).
///
/// Bildirimi sunucu gönderir: ürün yeniden satılabilir olduğunda
/// `private.notify_stock_back` bekleyenlere bir kez `stock_back` bildirimi
/// yazar ve abonelikleri siler (20261017000004_stock_back_alerts.sql).
class StockAlertService {
  StockAlertService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  bool get isSignedIn => _userId != null;

  Future<bool> isSubscribed(String productId) async {
    final uid = _userId;
    if (uid == null) return false;
    final row = await _supabase
        .from('stock_alerts')
        .select('id')
        .eq('user_id', uid)
        .eq('product_id', productId)
        .maybeSingle();
    return row != null;
  }

  Future<void> subscribe(String productId) async {
    final uid = _userId;
    if (uid == null) {
      throw const FriendlyException('Stok bildirimi için giriş yapmalısınız');
    }
    await _supabase.from('stock_alerts').upsert(
      {'user_id': uid, 'product_id': productId},
      onConflict: 'user_id,product_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> unsubscribe(String productId) async {
    final uid = _userId;
    if (uid == null) return;
    await _supabase
        .from('stock_alerts')
        .delete()
        .eq('user_id', uid)
        .eq('product_id', productId);
  }
}
