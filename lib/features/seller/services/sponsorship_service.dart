import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/sponsorship_model.dart';

/// Satıcı öne çıkarma (sponsorlu vitrin) istemcisi — Görev 3.2.
///
/// Paketleri ve mağazanın satın almalarını RLS'li tablolardan okur; satın
/// alma `purchase_shop_sponsorship` RPC'siyle olur (bakiye sunucuda kilitlenip
/// düşülür). Sunucu hatası [SponsorshipException]'a çevrilir; nedeni RPC'nin
/// HINT'inden gelir.
class SponsorshipService {
  SponsorshipService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  /// Satın alınabilir (aktif) paketler; vitrin ve sıraya göre.
  Future<List<SponsorshipPackage>> fetchPackages() async {
    final rows = await _db
        .from('sponsorship_packages')
        .select('id, placement, name, duration_days, price, sort_order')
        .eq('is_active', true)
        // DİKKAT: postgrest-dart'ta order() varsayılanı AZALAN sıradır.
        .order('sort_order', ascending: true);
    return [
      for (final row in rows as List)
        SponsorshipPackage.tryFromJson(Map<String, dynamic>.from(row as Map)),
    ].whereType<SponsorshipPackage>().toList();
  }

  /// Mağazanın satın aldığı öne çıkarmalar (en yeni önce).
  Future<List<ShopSponsorship>> fetchShopSponsorships(String shopId, {int limit = 50}) async {
    final rows = await _db
        .from('shop_sponsorships')
        .select(
          'id, shop_id, product_id, placement, package_name, duration_days, '
          'price_paid, status, starts_at, ends_at, created_at, review_note',
        )
        .eq('shop_id', shopId)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final row in rows as List)
        ShopSponsorship.tryFromJson(Map<String, dynamic>.from(row as Map)),
    ].whereType<ShopSponsorship>().toList();
  }

  /// Oturumdaki kullanıcının bakiyesi (satır yoksa 0).
  Future<double> fetchMyBalance() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 0;
    final row = await _db
        .from('user_balances')
        .select('balance')
        .eq('user_id', uid)
        .maybeSingle();
    final value = row?['balance'];
    return value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  }

  /// Paketi satın alır. Ürün vitrinlerinde [productId] zorunludur.
  Future<SponsorshipPurchase> purchase({
    required String shopId,
    required String packageId,
    String? productId,
  }) async {
    try {
      final result = await _db.rpc(
        'purchase_shop_sponsorship',
        params: {
          'p_shop_id': shopId,
          'p_package_id': packageId,
          if (productId != null) 'p_product_id': productId,
        },
      );
      return SponsorshipPurchase.fromJson(Map<String, dynamic>.from(result as Map));
    } on PostgrestException catch (e) {
      final reason = failureFor(e);
      throw SponsorshipException(
        reason,
        reason == SponsorshipFailure.unknown
            ? 'Öne çıkarma satın alınamadı. Lütfen tekrar deneyin.'
            : e.message,
      );
    }
  }

  /// Sunucu hatasının nedeni (RPC'nin HINT'i; yetki hatası 42501).
  static SponsorshipFailure failureFor(PostgrestException e) => switch (e.hint) {
    'insufficient_balance' => SponsorshipFailure.insufficientBalance,
    'disabled' => SponsorshipFailure.disabled,
    'shop_not_listed' => SponsorshipFailure.shopNotListed,
    'product_not_discounted' => SponsorshipFailure.productNotDiscounted,
    'product_unavailable' => SponsorshipFailure.productUnavailable,
    'package_not_found' => SponsorshipFailure.packageNotFound,
    _ => e.code == '42501' ? SponsorshipFailure.notAllowed : SponsorshipFailure.unknown,
  };
}
