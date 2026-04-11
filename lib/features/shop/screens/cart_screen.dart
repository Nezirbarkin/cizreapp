// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/product_model.dart';
import '../../market/services/product_service.dart';
import '../services/cart_service.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with TickerProviderStateMixin {
  final CartService _cartService = CartService();
  final ProductService _productService = ProductService();
  
  List<CartItemWithProduct> _cartItems = [];
  bool _isLoading = true;
  double _subtotal = 0;
  double _deliveryFee = 15.0; // Dinamik olarak yüklenecek
  double _baseDeliveryFee = 15.0; // Dükkanın standart teslimat ücreti
  double _freeDeliveryMinAmount = 0.0; // Ücretsiz teslimat alt sınırı
  double _total = 0;
  double _discountAmount = 0;
  String? _appliedCoupon;
  Map<String, dynamic>? _appliedCouponData; // Tam kupon verisi
  final TextEditingController _couponController = TextEditingController();
  String? _currentShopId; // Sepetteki dükkan ID'si
  bool _isFreeDelivery = false; // Ücretsiz teslimat durumu

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _loadCart();
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _loadCart() async {
    setState(() => _isLoading = true);

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('🛒 CART: Kullanıcı giriş yapmamış');
      setState(() => _isLoading = false);
      return;
    }

    try {
      debugPrint('🛒 CART: Sepet yükleniyor... userId: $userId');
      
      // CartService kullan - ShopDetailScreen ile aynı
      final items = await _cartService.getCartItems(userId);
      debugPrint('🛒 CART: ${items.length} adet sepet öğesi bulundu');

      final List<CartItemWithProduct> cartWithProducts = [];
      for (var item in items) {
        debugPrint('🛒 CART: Ürün yükleniyor - productId: ${item.productId}, quantity: ${item.quantity}');
        final product = await _productService.getProductById(item.productId);
        // ignore: unnecessary_null_comparison
        if (product != null) {
          cartWithProducts.add(CartItemWithProduct(
            cartItem: item,
            product: product,
          ));
          debugPrint('🛒 CART: Ürün yüklendi - ${product.name}');
        // ignore: dead_code
        } else {
          debugPrint('⚠️ CART: Ürün bulunamadı - productId: ${item.productId}');
        }
      }

      debugPrint('🛒 CART: Toplam ${cartWithProducts.length} ürün sepete eklendi');

      // Dükkan teslimat bilgilerini al
      if (cartWithProducts.isNotEmpty) {
        _currentShopId = cartWithProducts.first.product.shopId;
        final deliveryInfo = await _cartService.getShopDeliveryInfo(_currentShopId!);
        _baseDeliveryFee = deliveryInfo['delivery_fee'] ?? 15.0;
        _freeDeliveryMinAmount = deliveryInfo['free_delivery_min_amount'] ?? 0.0;
        debugPrint('🛒 CART: Dükkan teslimat ücreti: ₺$_baseDeliveryFee, Ücretsiz teslimat limiti: ₺$_freeDeliveryMinAmount');
        
        setState(() {
          _cartItems = cartWithProducts;
          _calculateTotals(); // Bu metod _deliveryFee'i hesaplayacak
          _isLoading = false;
        });
      } else {
        setState(() {
          _cartItems = cartWithProducts;
          _calculateTotals();
          _isLoading = false;
        });
      }
      
      debugPrint('🛒 CART: Sepet yükleme tamamlandı - Ara toplam: ₺$_subtotal, Teslimat: ₺$_deliveryFee');
    } catch (e) {
      debugPrint('❌ CART: Sepet yüklenirken hata: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sepet yüklenirken hata: $e')),
        );
      }
    }
  }

  void _calculateTotals() {
    _subtotal = 0;
    for (var item in _cartItems) {
      _subtotal += item.product.effectivePrice * item.cartItem.quantity;
    }
    
    // Kupon indirimini hesapla
    if (_appliedCouponData != null) {
      final discountType = _appliedCouponData!['discount_type']?.toString() ?? 'fixed_amount';
      final rawValue = _appliedCouponData!['discount_value'];
      final discountValue = (rawValue is num) ? rawValue.toDouble() : 0.0;
      
      if (discountType == 'percentage') {
        _discountAmount = _subtotal * discountValue / 100;
      } else {
        _discountAmount = discountValue;
      }
    } else {
      _discountAmount = 0;
    }
    
    // Ücretsiz teslimat kontrolü
    if (_freeDeliveryMinAmount > 0 && _subtotal >= _freeDeliveryMinAmount) {
      _deliveryFee = 0.0;
      _isFreeDelivery = true;
      debugPrint('🛒 CART: Ücretsiz teslimat aktif! Sepet toplamı: ₺$_subtotal >= Limit: ₺$_freeDeliveryMinAmount');
    } else {
      _deliveryFee = _baseDeliveryFee;
      _isFreeDelivery = false;
    }
    
    _total = _subtotal - _discountAmount + _deliveryFee;
  }

  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim().toUpperCase();
    
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kupon kodunu giriniz'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_currentShopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sepette ürün bulunamadı'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      // Supabase'den kuponu kontrol et
      final response = await Supabase.instance.client
          .from('shop_coupons')
          .select()
          .eq('shop_id', _currentShopId!)
          .eq('code', code)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Geçersiz kupon kodu'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Min sipariş tutarı kontrolü
      final minOrderAmount = (response['minimum_order_amount'] ?? 0).toDouble();
      if (minOrderAmount > 0 && _subtotal < minOrderAmount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bu kupon için minimum ₺${minOrderAmount.toStringAsFixed(0)} tutarında alışveriş yapmalısınız'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Kuponu uygula
      setState(() {
        _appliedCoupon = code;
        _appliedCouponData = response;
        _calculateTotals();
      });

      final discountType = response['discount_type'] ?? 'fixed_amount';
      final discountValue = (response['discount_value'] ?? 0).toDouble();
      final discountText = discountType == 'percentage'
          ? '%${discountValue.toStringAsFixed(0)} indirim'
          : '₺${discountValue.toStringAsFixed(0)} indirim';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$discountText uygulandı!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ CART: Kupon kontrolü hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kupon kontrolü sırasında hata: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatCouponLabel() {
    if (_appliedCouponData == null) return '';
    final dType = _appliedCouponData!['discount_type']?.toString() ?? 'fixed_amount';
    final rawValue = _appliedCouponData!['discount_value'];
    final dValue = (rawValue is num) ? rawValue.toDouble() : 0.0;
    if (dType == 'percentage') {
      return '%${dValue.toStringAsFixed(0)} indirim';
    }
    return '₺${dValue.toStringAsFixed(0)} indirim';
  }

  void _removeCoupon() {
    setState(() {
      _appliedCoupon = null;
      _appliedCouponData = null;
      _couponController.clear();
      _calculateTotals();
    });
  }

  Future<void> _updateQuantity(CartItemWithProduct item, int newQuantity) async {
    if (newQuantity < 1) return;

    try {
      debugPrint('🛒 CART: Miktar güncelleniyor - cartItemId: ${item.cartItem.id}, newQuantity: $newQuantity');
      await _cartService.updateCartItemQuantity(item.cartItem.id, newQuantity);
      await _loadCart();
    } catch (e) {
      debugPrint('❌ CART: Miktar güncellenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Miktar güncellenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _removeItem(CartItemWithProduct item) async {
    try {
      debugPrint('🛒 CART: Ürün çıkarılıyor - cartItemId: ${item.cartItem.id}');
      await _cartService.removeFromCart(item.cartItem.id);
      await _loadCart();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün sepetten çıkarıldı')),
        );
      }
    } catch (e) {
      debugPrint('❌ CART: Ürün çıkarılırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ürün çıkarılırken hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withOpacity(0.7),
              const Color(0xFFF5F7FA),
            ],
            stops: const [0.0, 0.35, 0.35],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Modern Header
              _buildModernHeader(context),
              
              // Content
              Expanded(
                child: SlideTransition(
                  position: _slideAnimation,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : _cartItems.isEmpty
                          ? _buildModernEmptyCart(context)
                          : _buildCartContent(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Back Button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sepetim',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_cartItems.length} ürün',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Clear Cart Button
          if (_cartItems.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () async {
                  final userId = Supabase.instance.client.auth.currentUser?.id;
                  if (userId != null) {
                    debugPrint('🛒 CART: Sepet temizleniyor');
                    await _cartService.clearCart(userId);
                    _loadCart();
                  }
                },
                icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                tooltip: 'Sepeti Temizle',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModernEmptyCart(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          Theme.of(context).colorScheme.primary.withOpacity(0.05),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shopping_cart_outlined,
                      size: 60,
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 32),
            
            const Text(
              'Sepetiniz Boş',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              ),
            ),
            
            const SizedBox(height: 12),
            
            Text(
              'Hemen alışverişe başla ve\nevini çıkar!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartContent(BuildContext context) {
    return Column(
      children: [
        // Sepet öğeleri
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: _cartItems.length,
            itemBuilder: (context, index) {
              final item = _cartItems[index];
              
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 300 + (index * 50)),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, 30 * (1 - value)),
                    child: Opacity(
                      opacity: value,
                      child: _buildModernCartItem(item),
                    ),
                  );
                },
              );
            },
          ),
        ),
        
        // Checkout button
        _buildModernCheckoutSection(context),
      ],
    );
  }

  Widget _buildModernCartItem(CartItemWithProduct item) {
    final product = item.product;
    final cartItem = item.cartItem;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ürün resmi
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                image: product.images.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(product.images.first),
                        fit: BoxFit.cover,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: product.images.isEmpty
                  ? Icon(Icons.image, size: 40, color: Colors.grey.shade400)
                  : null,
            ),
            const SizedBox(width: 16),

            // Ürün bilgileri
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  
                  // Fiyat
                  Row(
                    children: [
                      if (product.hasDiscount) ...[
                        Text(
                          '₺${product.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '₺${product.effectivePrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Miktar kontrolü
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _updateQuantity(item, cartItem.quantity - 1),
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.remove_rounded,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                cartItem.quantity.toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _updateQuantity(item, cartItem.quantity + 1),
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Sil butonu
                      Material(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () => _removeItem(item),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red.shade700,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernCheckoutSection(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kupon Kodu Bölümü
            if (_appliedCoupon == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _couponController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'Kupon kodunu girin',
                          prefixIcon: const Icon(Icons.local_offer_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _applyCoupon,
                      icon: const Icon(Icons.check),
                      label: const Text('Uygula'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kupon Uygulandı',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            Text(
                              _appliedCouponData != null
                                  ? '$_appliedCoupon - ${_formatCouponLabel()}'
                                  : _appliedCoupon ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _removeCoupon,
                        icon: Icon(Icons.close, color: Colors.green.shade700),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            
            // Ara Toplam
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ara Toplam:',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  '₺${_subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (_discountAmount > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'İndirim:',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '-₺${_discountAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            // Teslimat
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Teslimat:',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _isFreeDelivery ? 'Ücretsiz' : '₺${_deliveryFee.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _isFreeDelivery ? Colors.green : null,
                      ),
                    ),
                    if (!_isFreeDelivery && _freeDeliveryMinAmount > 0)
                      Text(
                        '₺${(_freeDeliveryMinAmount - _subtotal).toStringAsFixed(0)} daha ekleyin',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            // Ücretsiz teslimat bilgilendirmesi
            if (_isFreeDelivery) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text(
                      '₺${_freeDeliveryMinAmount.toStringAsFixed(0)} üzeri ücretsiz teslimat!',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: Colors.grey.shade300),
            ),
            // Toplam - Vurgulu
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.1),
                    theme.colorScheme.primaryContainer.withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Toplam:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    '₺${_total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Sipariş Ver Butonu - Modern
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CheckoutScreen(
                        cartItems: _cartItems,
                        subtotal: _subtotal,
                        deliveryFee: _deliveryFee,
                        total: _total,
                        discountAmount: _discountAmount,
                        appliedCoupon: _appliedCoupon,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor: theme.colorScheme.primary.withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Sipariş Ver',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// Helper class
class CartItemWithProduct {
  final CartItem cartItem;
  final Product product;

  CartItemWithProduct({
    required this.cartItem,
    required this.product,
  });
}
