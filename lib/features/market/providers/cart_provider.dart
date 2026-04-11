import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/cart_model.dart';
import '../../../core/models/shop_model.dart';
import '../services/cart_service.dart';
import '../services/shop_service.dart';

class CartProvider with ChangeNotifier {
  final CartService _cartService = CartService();
  final ShopService _shopService = ShopService();

  // Dinamik olarak mevcut kullanıcı ID'sini Supabase'den al
  // Bu sayede kullanıcı giriş/çıkış yaptığında userId otomatik güncellenir
  String get userId => Supabase.instance.client.auth.currentUser?.id ?? '';

  List<CartItem> _items = [];
  bool _isLoading = false;
  String? _error;
  
  // Dükkan bilgileri cache
  final Map<String, Shop> _shops = {};

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
    
    return CartSummary.fromItems(_items, deliveryFee: totalDeliveryFee);
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

  // Sepete ürün ekle
  Future<void> addToCart(String productId, {int quantity = 1, Map<String, dynamic>? variantData}) async {
    debugPrint('➕ CartProvider.addToCart() - productId: $productId, quantity: $quantity, variantData: $variantData');
    
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
      );
      debugPrint('✅ CartProvider.addToCart() BAŞARILI, sepet yeniden yükleniyor...');
      await loadCart(); // Sepeti yeniden yükle
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
      await _cartService.updateQuantity(
        cartItemId: cartItemId,
        quantity: quantity,
      );
      await loadCart();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // Sepetten sil
  Future<void> removeFromCart(String cartItemId) async {
    try {
      await _cartService.removeFromCart(cartItemId);
      await loadCart();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // Sepeti temizle
  Future<void> clearCart() async {
    try {
      await _cartService.clearCart(userId);
      _items = [];
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
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
