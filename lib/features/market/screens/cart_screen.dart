// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../providers/address_provider.dart';
import '../../../core/models/cart_model.dart';
import 'checkout_screen.dart';
import 'multi_shop_checkout_screen.dart';

class CartScreen extends StatefulWidget {
  final bool isMainTab;
  
  const CartScreen({super.key, this.isMainTab = false});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with TickerProviderStateMixin {
  late AnimationController _fabController;
  late AnimationController _slideController;
  late AnimationController _expandController;
  late Animation<double> _fabAnimation;
  late Animation<Offset> _slideAnimation;
  // ignore: unused_field
  late Animation<double> _expandAnimation;
  // ignore: unused_field
  bool _isSummaryExpanded = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🔵 CartScreen.initState() BAŞLADI');
    
    // FAB animasyonu
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabController,
      curve: Curves.elasticOut,
    );

    // Slide animasyonu
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

    // Expand animasyonu
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );

    // Sepet verilerini ve dükkan bilgilerini yükle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      debugPrint('🔵 CartScreen: PostFrameCallback, animasyonlar başlatılıyor...');
      _fabController.forward();
      _slideController.forward();
      final cartProvider = context.read<CartProvider>();
      debugPrint('🔵 CartScreen: CartProvider alındı, userId: ${cartProvider.userId}');
      debugPrint('🔵 CartScreen: loadCart() çağrılıyor...');
      cartProvider.loadCart().then((_) {
        debugPrint('🔵 CartScreen: loadCart() tamamlandı, loadShopInfo() çağrılıyor...');
        if (mounted) {
          cartProvider.loadShopInfo();
        }
      });
    });
  }

  @override
  void dispose() {
    _fabController.dispose();
    _slideController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    
    if (userId == null) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withOpacity(0.8),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildModernHeader(context, 0, null),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Lütfen giriş yapın',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cartProvider = context.watch<CartProvider>();
    debugPrint('🟢 CartScreen.build() - itemCount: ${cartProvider.itemCount}, isEmpty: ${cartProvider.isEmpty}, isLoading: ${cartProvider.isLoading}');

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
              _buildModernHeader(context, cartProvider.itemCount, cartProvider),
              
              // Content
              Expanded(
                child: SlideTransition(
                  position: _slideAnimation,
                  child: cartProvider.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : cartProvider.isEmpty
                          ? _buildModernEmptyCart(context)
                          : _buildCartContent(context, cartProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(BuildContext context, int itemCount, CartProvider? cartProvider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Back Button - MainScreen tab'i ise gösterme
          if (!widget.isMainTab)
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
            )
          else
            const SizedBox(width: 36),
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
                      '$itemCount ürün',
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
          if (cartProvider != null && cartProvider.isNotEmpty)
            ScaleTransition(
              scale: _fabAnimation,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => _showClearCartDialog(context),
                  icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                  tooltip: 'Sepeti Temizle',
                ),
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
            // Animated Icon
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
            
            // Title
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
            
            // Subtitle
            Text(
              'Hemen alışverişe başla ve\nevini çıkar!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            
            const SizedBox(height: 40),
            
            // CTA Button - Main tab ise gösterme
            if (!widget.isMainTab)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, 30 * (1 - value)),
                    child: Opacity(
                      opacity: value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.primary.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.maybePop(context),
                            borderRadius: BorderRadius.circular(16),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.storefront, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Alışverişe Başla',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartContent(BuildContext context, CartProvider cartProvider) {
    debugPrint('🟢 CartScreen._buildCartContent() - itemCount: ${cartProvider.itemCount}, isEmpty: ${cartProvider.isEmpty}');
    final groupedItems = cartProvider.groupedByShop;
    debugPrint('🟢 CartScreen: groupedByShop.length: ${groupedItems.length}');
    
    return Column(
      children: [
        // Sepet öğeleri
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: groupedItems.length,
            itemBuilder: (context, index) {
              final shopId = groupedItems.keys.elementAt(index);
              final items = groupedItems[shopId]!;
              final shopName = items.first.shopName ?? 'Dükkan';
              
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 300 + (index * 50)),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, 30 * (1 - value)),
                    child: Opacity(
                      opacity: value,
                      child: _buildModernShopSection(context, shopName, items, shopId, cartProvider),
                    ),
                  );
                },
              );
            },
          ),
        ),
        
        // Checkout button
        _buildModernCheckoutSection(context, cartProvider),
      ],
    );
  }

  Widget _buildModernShopSection(
    BuildContext context,
    String shopName,
    List<CartItem> items,
    String shopId,
    CartProvider cartProvider,
  ) {
    final shop = cartProvider.getShop(shopId);
    final shopTotal = cartProvider.getShopTotal(shopId);
    final minOrderAmount = shop?.minOrderAmount ?? 0;
    final deliveryFee = shop?.deliveryFee ?? 0;
    final meetsMinOrder = minOrderAmount <= 0 || shopTotal >= minOrderAmount;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dükkan başlığı
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  Theme.of(context).colorScheme.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.store,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        '${items.length} ürün',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${shopTotal.toStringAsFixed(2)}₺',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Min. Sipariş ve Teslimat Ücreti Bilgisi
          if (minOrderAmount > 0 || deliveryFee > 0)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: meetsMinOrder
                    ? Colors.green.shade50.withOpacity(0.5)
                    : Colors.orange.shade50.withOpacity(0.5),
                border: Border(
                  left: BorderSide(
                    color: meetsMinOrder ? Colors.green : Colors.orange,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (minOrderAmount > 0) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: meetsMinOrder
                                ? Colors.green.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            meetsMinOrder ? Icons.check_circle : Icons.warning,
                            size: 14,
                            color: meetsMinOrder ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Min. Sipariş',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              if (!meetsMinOrder)
                                Text(
                                  '₺${(minOrderAmount - shopTotal).toStringAsFixed(2)} ekle',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '₺${minOrderAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: meetsMinOrder ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (minOrderAmount > 0 && deliveryFee > 0) const SizedBox(height: 8),
                  if (deliveryFee > 0)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.delivery_dining_outlined,
                            size: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Teslimat',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '₺${deliveryFee.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          
          // Ürünler
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1, color: Colors.grey.shade100),
            ),
            itemBuilder: (context, index) {
              return _buildModernCartItem(context, items[index], cartProvider);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModernCartItem(
    BuildContext context,
    CartItem item,
    CartProvider cartProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ürün görseli
          Hero(
            tag: 'cart_item_${item.id}_${item.productId}_${item.variantData?.hashCode ?? 0}',
            child: Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade100,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.productImageUrl != null
                    ? Image.network(
                        item.productImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.image_not_supported, size: 24),
                          );
                        },
                      )
                    : const Center(
                        child: Icon(Icons.shopping_bag, size: 24, color: Colors.grey),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          
          // Ürün bilgileri
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName ?? 'Ürün',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                
                // Fiyat
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(item.productPrice ?? 0).toStringAsFixed(2)}₺',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    if (item.hasDiscount) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${(item.productOldPrice ?? 0).toStringAsFixed(2)}₺',
                        style: TextStyle(
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                
                // Miktar kontrolü
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModernQuantityButton(
                        icon: Icons.remove_rounded,
                        onTap: () {
                          if (item.quantity > 1) {
                            cartProvider.updateQuantity(item.id, item.quantity - 1);
                          } else {
                            cartProvider.removeFromCart(item.id);
                          }
                        },
                      ),
                      Container(
                        width: 40,
                        alignment: Alignment.center,
                        child: Text(
                          '${item.quantity}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      _buildModernQuantityButton(
                        icon: Icons.add_rounded,
                        onTap: item.canAddMore
                            ? () => cartProvider.updateQuantity(item.id, item.quantity + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Sil butonu
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => cartProvider.removeFromCart(item.id),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.close, color: Colors.red.shade400, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernQuantityButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null ? Colors.white : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade400,
        ),
      ),
    );
  }

  Widget _buildModernCheckoutSection(BuildContext context, CartProvider cartProvider) {
    final summary = cartProvider.summary;
    final allShopsMeetMinOrder = cartProvider.allShopsMeetMinOrder();
    
    // Minimum sipariş uyarı mesajı
    String minOrderWarning = '';
    if (!allShopsMeetMinOrder) {
      final shopIds = cartProvider.groupedByShop.keys;
      for (final shopId in shopIds) {
        if (!cartProvider.meetsMinOrderAmount(shopId)) {
          final shop = cartProvider.getShop(shopId);
          final remaining = cartProvider.getRemainingForMinOrder(shopId);
          if (shop != null && remaining > 0) {
            minOrderWarning += '${shop.name}: ₺${remaining.toStringAsFixed(2)} daha ekle\n';
          }
        }
      }
    }
    
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
            // Expandable Header
            GestureDetector(
              onTap: () {
                setState(() {
                  _isSummaryExpanded = !_isSummaryExpanded;
                  if (_isSummaryExpanded) {
                    _expandController.forward();
                  } else {
                    _expandController.reverse();
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    // Toplam Tutar (Kapalı iken görünür)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Toplam',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${summary.total.toStringAsFixed(2)}₺',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Chevron icon
                    AnimatedBuilder(
                      animation: _expandAnimation,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _expandAnimation.value * 3.14159,
                          child: Icon(
                            Icons.keyboard_arrow_up,
                            color: Colors.grey.shade600,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            // Divider
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1),
            ),
            
            // Expandable Content
            SizeTransition(
              sizeFactor: _expandAnimation,
              axisAlignment: -1.0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    // Özet bilgileri
                    _buildModernSummaryRow('Ara Toplam', summary.subtotal),
                    if (summary.discount > 0) ...[
                      const SizedBox(height: 12),
                      _buildModernSummaryRow('İndirim', -summary.discount, isDiscount: true),
                    ],
                    const SizedBox(height: 12),
                    _buildModernSummaryRow('Teslimat', summary.deliveryFee),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            if (minOrderWarning.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.shade50,
                      Colors.orange.shade100.withOpacity(0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Minimum Sipariş Tutarı',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            minOrderWarning.trim(),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            
            // Checkout butonu
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: allShopsMeetMinOrder
                    ? LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primary.withOpacity(0.8),
                        ],
                      )
                    : null,
                color: allShopsMeetMinOrder ? null : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(16),
                boxShadow: allShopsMeetMinOrder
                    ? [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: allShopsMeetMinOrder ? () => _goToCheckout(context) : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (allShopsMeetMinOrder)
                          Icon(
                            Icons.lock_open_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        if (allShopsMeetMinOrder) const SizedBox(width: 8),
                        Text(
                          allShopsMeetMinOrder ? 'Siparişi Tamamla' : 'Minimum Tutar Yetersiz',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: allShopsMeetMinOrder ? Colors.white : Colors.grey.shade600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernSummaryRow(
    String label,
    double amount, {
    bool isDiscount = false,
    bool isTotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isTotal ? const Color(0xFF1A1A2E) : Colors.grey.shade700,
          ),
        ),
        Text(
          '${amount.toStringAsFixed(2)}₺',
          style: TextStyle(
            fontSize: isTotal ? 22 : 16,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
            color: isDiscount
                ? Colors.green
                : isTotal
                    ? const Color(0xFF1A1A2E)
                    : const Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }

  Future<void> _showClearCartDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Sepeti Temizle'),
          ],
        ),
        content: const Text('Sepetinizdeki tüm ürünleri silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('İptal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Temizle', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final cartProvider = context.read<CartProvider>();
      await cartProvider.clearCart();
    }
  }

  Future<void> _goToCheckout(BuildContext context) async {
    final cartProvider = context.read<CartProvider>();
    
    if (cartProvider.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sepetiniz boş'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Dükkan bilgilerinin yüklü olduğundan emin ol
    await cartProvider.loadShopInfo();

    if (!cartProvider.allShopsMeetMinOrder()) {
      // Hangi dükkanların minimum tutarı karşılamadığını detaylı göster
      final shopIds = cartProvider.groupedByShop.keys;
      final warnings = <String>[];
      for (final shopId in shopIds) {
        if (!cartProvider.meetsMinOrderAmount(shopId)) {
          final shop = cartProvider.getShop(shopId);
          final remaining = cartProvider.getRemainingForMinOrder(shopId);
          if (shop != null) {
            warnings.add('${shop.name}: ₺${remaining.toStringAsFixed(2)} daha eklemeniz gerekiyor (Min: ₺${shop.minOrderAmount.toStringAsFixed(2)})');
          }
        }
      }
      
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warnings.isNotEmpty
                ? warnings.join('\n')
                : 'Lütfen tüm dükkanlar için minimum sipariş tutarını karşılayın',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    
    if (!context.mounted) return;

    // Kaç farklı dükkan var kontrol et
    final shopIds = cartProvider.items
        .map((item) => item.shopId)
        .where((id) => id != null)
        .toSet();
    
    debugPrint('🛒 Sepette ${shopIds.length} farklı dükkan var');
    
    if (shopIds.length > 1) {
      // Birden fazla dükkan var - çok dükkanlı checkout'a yönlendir
      debugPrint('🛒 Çok dükkanlı checkout ekranına yönlendiriliyor...');
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => AddressProvider(userId)),
              ChangeNotifierProvider.value(value: cartProvider),
            ],
            child: const MultiShopCheckoutScreen(),
          ),
        ),
      );
    } else {
      // Tek dükkan - eski checkout ekranını kullan
      debugPrint('🛒 Tek dükkan checkout ekranına yönlendiriliyor...');
      final firstItem = cartProvider.items.first;
      final shopId = firstItem.shopId ?? 'unknown';
      final shopName = firstItem.shopName ?? 'Dükkan';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(
            shopId: shopId,
            shopName: shopName,
          ),
        ),
      );
    }
  }
}
