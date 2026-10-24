import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/order_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/services/order_availability_service.dart';
import '../providers/cart_provider.dart';

/// Sepete eklenecek tek kalem.
class ReorderLine {
  const ReorderLine({
    required this.productId,
    required this.name,
    required this.quantity,
    this.reducedFrom,
  });

  final String productId;
  final String name;
  final int quantity;

  /// Stok / adet sınırı yüzünden düşürüldüyse istenen adet.
  final int? reducedFrom;
}

/// "Tekrar sipariş ver" planı: neyin ekleneceği, neyin neden eklenemeyeceği.
class ReorderPlan {
  const ReorderPlan({
    this.lines = const [],
    this.unavailable = const [],
    this.needsOptions = const [],
    this.priceChanged = const [],
    this.alreadyInCart = const [],
  });

  final List<ReorderLine> lines;

  /// Satıştan kalkmış / stokta yok.
  final List<String> unavailable;

  /// Beden/renk gibi seçenekli ürün: sipariş satırında seçim saklanmıyor,
  /// kullanıcı ürün sayfasından seçmeli (ürün id'leri).
  final List<Product> needsOptions;

  /// Fiyatı sipariş anından farklı olanlar (ad).
  final List<String> priceChanged;

  /// Sepette zaten sınır kadar olanlar (ad).
  final List<String> alreadyInCart;

  bool get isEmpty => lines.isEmpty;
}

/// Sonuç özeti (ekranda gösterilir).
class ReorderResult {
  const ReorderResult({
    required this.plan,
    this.added = const [],
    this.failed = const [],
    this.ordersClosed = false,
  });

  final ReorderPlan plan;
  final List<ReorderLine> added;

  /// Sepete eklenirken sunucunun reddettiği kalemler (ad).
  final List<String> failed;

  /// Uygulama genelinde sipariş alımı kapalı.
  final bool ordersClosed;
}

/// Geçmiş siparişteki ürünleri sepete yeniden ekler. Sepete ekleme yolu
/// değişmez (CartProvider.addToCart → stok / sınırsız stokta en fazla 2 /
/// satıcı sınırı sunucuda da uygulanır); planlayıcı yalnız önceden kırpar.
class ReorderService {
  ReorderService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  /// Saf planlayıcı (test edilebilir).
  ///
  /// [products]: güncel ürün satırları (id → ürün; bulunamayan = silinmiş).
  /// [inCart]: sepette zaten olan adet (id → adet).
  @visibleForTesting
  static ReorderPlan plan(
    List<OrderItem> items,
    Map<String, Product> products,
    Map<String, int> inCart,
  ) {
    // Aynı ürün birden çok satırdaysa adetler toplanır.
    final wanted = <String, int>{};
    final names = <String, String>{};
    final paid = <String, double>{};
    for (final it in items) {
      if (it.productId.isEmpty || it.quantity <= 0) continue;
      wanted[it.productId] = (wanted[it.productId] ?? 0) + it.quantity;
      names[it.productId] = it.productName;
      paid[it.productId] = it.flashPrice ?? it.price;
    }

    final lines = <ReorderLine>[];
    final unavailable = <String>[];
    final needsOptions = <Product>[];
    final priceChanged = <String>[];
    final alreadyInCart = <String>[];

    for (final entry in wanted.entries) {
      final p = products[entry.key];
      final name = p?.name ?? names[entry.key] ?? 'Ürün';
      if (p == null || !p.isAvailable || p.isDigital || !p.inStock) {
        unavailable.add(name);
        continue;
      }
      if (p.hasVariants) {
        needsOptions.add(p);
        continue;
      }
      final cap = p.maxCartQuantity;
      final room = cap - (inCart[p.id] ?? 0);
      if (room <= 0) {
        alreadyInCart.add(name);
        continue;
      }
      final want = entry.value < p.minOrderQty ? p.minOrderQty : entry.value;
      final qty = want > room ? room : want;
      if (qty < p.minOrderQty) {
        alreadyInCart.add(name);
        continue;
      }
      lines.add(ReorderLine(
        productId: p.id,
        name: name,
        quantity: qty,
        reducedFrom: qty < entry.value ? entry.value : null,
      ));
      final before = paid[entry.key];
      if (before != null && (p.effectivePrice - before).abs() >= 0.01) {
        priceChanged.add(name);
      }
    }

    return ReorderPlan(
      lines: lines,
      unavailable: unavailable,
      needsOptions: needsOptions,
      priceChanged: priceChanged,
      alreadyInCart: alreadyInCart,
    );
  }

  /// Ürünleri tek istekte okur, planlar ve uygun kalemleri sepete ekler.
  Future<ReorderResult> reorder(List<OrderItem> items, CartProvider cart) async {
    if (!await OrderAvailabilityService.fetchGlobalOrdersEnabled()) {
      return const ReorderResult(plan: ReorderPlan(), ordersClosed: true);
    }
    final ids = items.map((i) => i.productId).where((id) => id.isNotEmpty).toSet().toList();
    final products = <String, Product>{};
    if (ids.isNotEmpty) {
      final rows = await _db.from('products').select().inFilter('id', ids);
      for (final row in (rows as List)) {
        try {
          final p = Product.fromJson(Map<String, dynamic>.from(row as Map));
          products[p.id] = p;
        } catch (e) {
          debugPrint('Tekrar sipariş: ürün okunamadı: $e');
        }
      }
    }
    final inCart = {for (final id in ids) id: cart.getProductQuantityFromCache(id)};
    final plan = ReorderService.plan(items, products, inCart);

    final added = <ReorderLine>[];
    final failed = <String>[];
    for (final line in plan.lines) {
      try {
        await cart.addToCart(line.productId, quantity: line.quantity);
        added.add(line);
      } catch (e) {
        debugPrint('Tekrar sipariş: ${line.name} eklenemedi: $e');
        failed.add(line.name);
      }
    }
    return ReorderResult(plan: plan, added: added, failed: failed);
  }
}
