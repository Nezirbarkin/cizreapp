import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/cart_model.dart';
import '../../../core/models/coupon_model.dart';
import '../../../core/models/shop_model.dart';
import '../services/cart_service.dart';
import '../services/flash_sale_service.dart';
import '../services/shop_service.dart';

class CartProvider with ChangeNotifier {
  final CartService _cartService = CartService();
  final FlashSaleService _flashSaleService = FlashSaleService();
  final ShopService _shopService = ShopService();

  // Dinamik olarak mevcut kullanıcı ID'sini Supabase'den al
  // Bu sayede kullanıcı giriş/çıkış yaptığında userId otomatik güncellenir
  String get userId => Supabase.instance.client.auth.currentUser?.id ?? '';

  List<CartItem> _items = [];
  bool _isLoading = false;
  String? _error;

  // Dükkan bilgileri cache
  final Map<String, Shop> _shops = {};

  // Uygulanan kuponlar: shopId -> AppliedCoupon
  // Çok dükkanlı sepette her dükkana ayrı kupon girilebilmesi için key
  // shopId. RPC `validate_coupon` zaten shop-scoped; bu yüzden state de
  // shop-scoped tutuluyor.
  final Map<String, AppliedCoupon> _couponsByShop = {};
  // Son revalidation'da kaldırılan kupon (UI snackbar için).
  // CartScreen CartProvider'ı dinlediği için tüketip temizler.
  AppliedCoupon? _lastRemovedCoupon;

  // Geriye uyumluluk için parametre kabul eder ama kullanmaz
  // userId artık dinamik olarak Supabase auth state'inden alınıyor
  CartProvider([String? ignored]) {
    loadCart();
  }

  List<CartItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  // Kupon state getter'ları.
  Map<String, AppliedCoupon> get couponsByShop =>
      Map.unmodifiable(_couponsByShop);
  AppliedCoupon? couponForShop(String shopId) => _couponsByShop[shopId];
  AppliedCoupon? consumeLastRemovedCoupon() {
    final c = _lastRemovedCoupon;
    // UI'ya yalnızca coupon dönüyoruz; debug/log için satır 53 yorumu yeterli.
    _lastRemovedCoupon = null;
    return c;
  }

  // Sepet özeti (teslimat ücreti dahil)
  CartSummary get summary {
    // Direkt olarak items'dan groupedByShop hesapla, summary'ye bağımlı değil
    double totalDeliveryFee = 0;
    final grouped = <String, List<CartItem>>{};

    for (var item in _items) {
      final shopId = item.shopId ?? 'unknown';
      if (!grouped.containsKey(shopId)) {
        grouped[shopId] = [];
      }
      grouped[shopId]!.add(item);
    }

    // Her dükkan için teslimat ücretini topla
    for (final shopId in grouped.keys) {
      totalDeliveryFee += getDeliveryFee(shopId);
    }

    // Kupon indirimlerini dükkanlara dağıtıp topla.
    double totalCoupon = 0;
    for (final entry in _couponsByShop.entries) {
      final shopId = entry.key;
      final coupon = entry.value;
      // Dükkanın o an sepette hala ürünü var mı kontrol et (boş dükkanı
      // _revalidateCoupons zaten temizlemiş olmalı, yine de defensif).
      if (grouped.containsKey(shopId)) {
        totalCoupon += coupon.discountFor(_shopSubtotal(shopId));
      }
    }

    return CartSummary.fromItems(
      _items,
      deliveryFee: totalDeliveryFee,
      couponDiscount: totalCoupon,
    );
  }

  // Toplam öğe sayısı
  int get itemCount {
    return _items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  // Sepeti yükle
  Future<void> loadCart() async {
    debugPrint('🛒 CartProvider.loadCart() BAŞLADI - userId: $userId');
    
    // userId boşsa sepeti yükleme (giriş yapılmamış)
    if (userId.isEmpty) {
      debugPrint('⚠️ CartProvider.loadCart() ATLA - userId boş (kullanıcı giriş yapmamış)');
      _items = [];
      _isLoading = false;
      _error = null;
      notifyListeners();
      return;
    }
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _items = await _cartService.getCart(userId);
      _error = null;
      debugPrint('🛒 CartProvider.loadCart() BAŞARILI - ${_items.length} ürün yüklendi');
      for (var item in _items) {
        debugPrint('  └─ ProductID: ${item.productId}, Quantity: ${item.quantity}');
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ CartProvider.loadCart() HATA: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // KUPON YÖNETİMİ (shop-scoped)
  // ──────────────────────────────────────────────────────────────────────

  /// Dükkanın mevcut sepet ara-toplamını hesapla (kupon indirimi hariç).
  /// RPC `validate_coupon(p_subtotal)` buradan beslenir.
  double _shopSubtotal(String shopId) {
    double subtotal = 0;
    for (final item in _items) {
      if (item.shopId == shopId) {
        subtotal += item.effectivePrice * item.quantity;
      }
    }
    return subtotal;
  }

  /// `validate_coupon` RPC'sini çağırıp sonucu cache'le.
  /// Hata durumunda exception fırlatır (UI yakalar ve kullanıcıya gösterir).
  Future<AppliedCoupon> applyCoupon({
    required String shopId,
    required String code,
  }) async {
    if (userId.isEmpty) {
      throw Exception('Lütfen önce giriş yapın');
    }
    if (code.trim().isEmpty) {
      throw Exception('Kupon kodu boş olamaz');
    }

    final subtotal = _shopSubtotal(shopId);
    debugPrint('🎟️ CartProvider.applyCoupon() shop=$shopId code=$code subtotal=$subtotal');

    try {
      final response = await Supabase.instance.client.rpc(
        'validate_coupon',
        params: {
          'p_shop_id': shopId,
          'p_code': code.trim().toUpperCase(),
          'p_subtotal': subtotal,
          'p_user_id': userId,
        },
      );

      if (response == null) {
        throw Exception('Kupon doğrulanamadı');
      }

      // RPC tek satır döner. Liste geldiyse ilkini al, Map geldiyse direkt.
      Map<String, dynamic>? row;
      if (response is List) {
        if (response.isEmpty) {
          throw Exception('Kupon doğrulanamadı');
        }
        row = Map<String, dynamic>.from(response.first as Map);
      } else if (response is Map) {
        row = Map<String, dynamic>.from(response);
      } else {
        throw Exception('Beklenmeyen RPC yanıtı');
      }

      final coupon = AppliedCoupon.fromRpcRow(
        row,
        shopId: shopId,
        code: code.trim().toUpperCase(),
      );
      _couponsByShop[shopId] = coupon;
      notifyListeners();
      debugPrint('✅ Kupon uygulandı: ${coupon.label} shop=$shopId');
      return coupon;
    } catch (e) {
      debugPrint('❌ CartProvider.applyCoupon() HATA: $e');
      rethrow;
    }
  }

  /// Dükkanın kuponunu state'ten kaldır.
  void removeCoupon(String shopId) {
    if (_couponsByShop.remove(shopId) != null) {
      notifyListeners();
    }
  }

  /// Tüm kuponları temizle (sepet temizlendiğinde çağrılır).
  void clearCoupons() {
    if (_couponsByShop.isNotEmpty) {
      _couponsByShop.clear();
      notifyListeners();
    }
  }

  /// Sepet değiştikten sonra (add/update/remove/clear) her kuponu
  /// yeniden doğrula. `minimum_order_amount` altına düşen kuponları
  /// sessizce kaldır ve UI'ya `_lastRemovedCoupon` üzerinden bildir.
  void _revalidateCoupons() {
    if (_couponsByShop.isEmpty) return;

    final removed = <AppliedCoupon>[];
    final shopIds = _couponsByShop.keys.toList();
    for (final shopId in shopIds) {
      final coupon = _couponsByShop[shopId]!;
      final subtotal = _shopSubtotal(shopId);
      // Kupon artık geçerli değilse (min. sepet tutarı altına düştüyse) kaldır.
      if (subtotal < coupon.minimumOrderAmount) {
        _couponsByShop.remove(shopId);
        removed.add(coupon);
      }
    }

    if (removed.isNotEmpty) {
      // UI snackbar'ı için yalnız son kaldırılanı sakla.
      _lastRemovedCoupon = removed.last;
      debugPrint('⚠️ ${removed.length} kupon revalidate sonrası kaldırıldı');
      notifyListeners();
    }
  }

  // Sepete ürün ekle
  Future<void> addToCart(
    String productId, {
    int quantity = 1,
    Map<String, dynamic>? variantData,
    String? flashSaleId,
    double? flashPrice,
  }) async {
    debugPrint('➕ CartProvider.addToCart() - productId: $productId, quantity: $quantity, variantData: $variantData, flashSaleId: $flashSaleId, flashPrice: $flashPrice');

    // Kullanıcı giriş yapmamışsa hata fırlat
    if (userId.isEmpty) {
      throw Exception('Lütfen önce giriş yapın');
    }

    try {
      await _cartService.addToCart(
        userId: userId,
        productId: productId,
        quantity: quantity,
        variantData: variantData,
        flashSaleId: flashSaleId,
        flashPrice: flashPrice,
      );
      debugPrint('✅ CartProvider.addToCart() BAŞARILI, sepet yeniden yükleniyor...');
      await loadCart(); // Sepeti yeniden yükle
      _revalidateCoupons();
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ CartProvider.addToCart() HATA: $e');
      notifyListeners();
      rethrow;
    }
  }

  // Miktar güncelle
  Future<void> updateQuantity(String cartItemId, int quantity) async {
    try {
      // Eğer azaltma yapılıyorsa ve bu satır flaş satıştan geldiyse, fark
      // kadar stoğu geri ver (release_flash_sale).
      if (quantity > 0) {
        final existing = _items.firstWhere(
          (it) => it.id == cartItemId,
          orElse: () => _emptyCartItem(cartItemId),
        );
        if (existing.flashSaleId != null && existing.quantity > quantity) {
          final releaseQty = existing.quantity - quantity;
          await _flashSaleService.releaseFlashSale(
            saleId: existing.flashSaleId!,
            quantity: releaseQty,
          );
        }
      }

      await _cartService.updateQuantity(
        cartItemId: cartItemId,
        quantity: quantity,
      );
      await loadCart();
      _revalidateCoupons();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // Sepetten sil
  Future<void> removeFromCart(String cartItemId) async {
    try {
      // Flaş satıştan gelen bir satırsa stoğu geri ver.
      final existing = _items.firstWhere(
        (it) => it.id == cartItemId,
        orElse: () => _emptyCartItem(cartItemId),
      );
      if (existing.flashSaleId != null && existing.quantity > 0) {
        await _flashSaleService.releaseFlashSale(
          saleId: existing.flashSaleId!,
          quantity: existing.quantity,
        );
      }

      await _cartService.removeFromCart(cartItemId);
      await loadCart();
      _revalidateCoupons();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // Sepeti temizle
  Future<void> clearCart() async {
    try {
      // Tüm flaş satışlı satırlar için stoğu geri ver.
      for (final item in _items) {
        if (item.flashSaleId != null && item.quantity > 0) {
          try {
            await _flashSaleService.releaseFlashSale(
              saleId: item.flashSaleId!,
              quantity: item.quantity,
            );
          } catch (e) {
            debugPrint('⚠️ release_flash_sale başarısız (${item.flashSaleId}): $e');
            // Tek bir başarısızlık tüm sepet temizlemeyi engellemesin.
          }
        }
      }

      await _cartService.clearCart(userId);
      _items = [];
      clearCoupons();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Yardımcı: belirli bir cartItemId için boş bir CartItem döndürür
  /// (firstWhere orElse için).
  CartItem _emptyCartItem(String cartItemId) {
    return CartItem(
      id: cartItemId,
      userId: userId,
      productId: '',
      quantity: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // Ürünün sepette olup olmadığını kontrol et
  Future<bool> isInCart(String productId) async {
    try {
      return await _cartService.isInCart(userId, productId);
    } catch (e) {
      return false;
    }
  }

  // Ürünün sepetteki miktarını getir
  Future<int> getProductQuantity(String productId) async {
    try {
      return await _cartService.getProductQuantityInCart(userId, productId);
    } catch (e) {
      return 0;
    }
  }

  // Local'de ürünün sepetteki miktarını al (cache'den)
  int getProductQuantityFromCache(String productId) {
    final item = _items.firstWhere(
      (item) => item.productId == productId,
      orElse: () => CartItem(
        id: '',
        userId: userId,
        productId: productId,
        quantity: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    return item.quantity;
  }

  // Dükkan bilgilerini getir (cache'lenmiş)
  Shop? getShop(String shopId) => _shops[shopId];

  // Dükkan bilgilerini yükle (sepetteki tüm dükkanlar için)
  Future<void> loadShopInfo() async {
    final shopIds = _items.map((item) => item.shopId ?? '').where((id) => id.isNotEmpty).toSet();
    
    for (final shopId in shopIds) {
      if (!_shops.containsKey(shopId)) {
        try {
          final shop = await _shopService.getShopById(shopId);
          if (shop != null) {
            _shops[shopId] = shop;
          }
        } catch (e) {
          debugPrint('Dükkan bilgisi yüklenirken hata ($shopId): $e');
        }
      }
    }
    notifyListeners();
  }

  // Dükkan bazında gruplama (summary'ye bağımlı OLMAYAN versiyon - Stack Overflow önlemi)
  Map<String, List<CartItem>> get groupedByShop {
    final Map<String, List<CartItem>> grouped = {};
    for (var item in _items) {
      final sid = item.shopId ?? 'unknown';
      if (!grouped.containsKey(sid)) {
        grouped[sid] = [];
      }
      grouped[sid]!.add(item);
    }
    return grouped;
  }

  // Dükkan toplamı (summary'ye bağımlı OLMAYAN versiyon - Stack Overflow önlemi)
  double getShopTotal(String shopId) {
    return _items
        .where((item) => item.shopId == shopId)
        .fold<double>(0, (sum, item) => sum + item.itemTotal);
  }

  // Dükkanın minimum sipariş tutarını kontrol et
  bool meetsMinOrderAmount(String shopId) {
    final shop = _shops[shopId];
    if (shop == null || shop.minOrderAmount <= 0) return true;
    
    final shopTotal = getShopTotal(shopId);
    return shopTotal >= shop.minOrderAmount;
  }

  // Eksik miktarı hesapla
  double getRemainingForMinOrder(String shopId) {
    final shop = _shops[shopId];
    if (shop == null || shop.minOrderAmount <= 0) return 0;
    
    final shopTotal = getShopTotal(shopId);
    final remaining = shop.minOrderAmount - shopTotal;
    return remaining > 0 ? remaining : 0;
  }

  // Tüm dükkanların minimum sipariş tutarını karşılayıp karşılamadığını kontrol et
  bool allShopsMeetMinOrder() {
    final shopIds = groupedByShop.keys;
    for (final shopId in shopIds) {
      if (!meetsMinOrderAmount(shopId)) return false;
    }
    return true;
  }

  // Teslimat ücretini hesapla (ücretsiz teslimat kontrolü dahil)
  double getDeliveryFee(String shopId) {
    final shop = _shops[shopId];
    if (shop == null) return 0;
    
    final shopTotal = getShopTotal(shopId);
    final freeDeliveryMinAmount = shop.freeDeliveryMinAmount ?? 0;
    
    // Ücretsiz teslimat kontrolü
    if (freeDeliveryMinAmount > 0 && shopTotal >= freeDeliveryMinAmount) {
      debugPrint('🛒 CartProvider: Ücretsiz teslimat aktif! Shop: $shopId, Toplam: ₺$shopTotal >= Limit: ₺$freeDeliveryMinAmount');
      return 0.0;
    }
    
    return shop.deliveryFee;
  }

  // Toplam teslimat ücreti
  double getTotalDeliveryFee() {
    double total = 0;
    final shopIds = groupedByShop.keys;
    for (final shopId in shopIds) {
      total += getDeliveryFee(shopId);
    }
    return total;
  }

  // Dükkan için ücretsiz teslimat durumunu kontrol et
  bool isFreeDelivery(String shopId) {
    final shop = _shops[shopId];
    if (shop == null || (shop.freeDeliveryMinAmount ?? 0) == 0) return false;
    
    final shopTotal = getShopTotal(shopId);
    return shopTotal >= (shop.freeDeliveryMinAmount ?? 0);
  }

  // Ücretsiz teslimat için kalan tutarı hesapla
  double getRemainingForFreeDelivery(String shopId) {
    final shop = _shops[shopId];
    if (shop == null || (shop.freeDeliveryMinAmount ?? 0) == 0) return 0;
    
    final shopTotal = getShopTotal(shopId);
    final remaining = (shop.freeDeliveryMinAmount ?? 0) - shopTotal;
    return remaining > 0 ? remaining : 0;
  }
}
