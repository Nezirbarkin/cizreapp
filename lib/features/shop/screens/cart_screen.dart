// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/cart_model.dart';
import '../../market/providers/cart_provider.dart';
import '../../market/screens/checkout_screen.dart';

/// Mağaza içi (tek mağaza) sepet ekranı.
///
/// Ortak `CartProvider`/`cart` tablosunun yalnızca [shopId]'ye ait
/// satırlarını gösteren bir görünümdür — başka mağazaların ürünleri
/// burada ASLA görünmez. Veri kaynağı, "Sepetim" sekmesiyle (bkz.
/// `market/screens/cart_screen.dart`) aynıdır; bu sayede bir mağazadan
/// eklenen ürün ana sepette de, buradan eklenen ürün de her iki yerde
/// tutarlı görünür.
class CartScreen extends StatefulWidget {
  final String shopId;
  final String? shopName;

  const CartScreen({super.key, required this.shopId, this.shopName});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  final TextEditingController _couponController = TextEditingController();
  bool _isApplyingCoupon = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
    _slideController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CartProvider>().loadShopInfo();
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.shopName ?? 'Sepet')),
        body: const Center(child: Text('Lütfen giriş yapın')),
      );
    }

    final cartProvider = context.watch<CartProvider>();
    final items =
        cartProvider.groupedByShop[widget.shopId] ?? const <CartItem>[];
    final coupon = cartProvider.couponForShop(widget.shopId);
    if (coupon != null && _couponController.text != coupon.code) {
      _couponController.value = TextEditingValue(
        text: coupon.code,
        selection: TextSelection.collapsed(offset: coupon.code.length),
      );
    }

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
              _buildHeader(context, items),
              Expanded(
                child: SlideTransition(
                  position: _slideAnimation,
                  child: items.isEmpty
                      ? _buildEmptyCart(context)
                      : _buildCartContent(context, cartProvider, items),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<CartItem> items) {
    final itemCount = items.fold<int>(0, (sum, item) => sum + item.quantity);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.shopName ?? 'Sepetim',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          if (items.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => _showClearCartDialog(context),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.white,
                  size: 18,
                ),
                tooltip: 'Sepeti Temizle',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
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
            const SizedBox(height: 32),
            const Text(
              'Bu mağazadan sepetiniz boş',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ürünleri sepete ekleyip buradan\nsipariş verebilirsiniz.',
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

  Widget _buildCartContent(
    BuildContext context,
    CartProvider cartProvider,
    List<CartItem> items,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: items.length,
            separatorBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Divider(height: 1, color: Colors.grey.shade100),
            ),
            itemBuilder: (context, index) => Container(
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
              margin: const EdgeInsets.only(bottom: 4),
              child: _buildCartItem(context, items[index], cartProvider),
            ),
          ),
        ),
        _buildCouponSection(context, cartProvider),
        _buildCheckoutSection(context, cartProvider, items),
      ],
    );
  }

  Widget _buildCartItem(
    BuildContext context,
    CartItem item,
    CartProvider cartProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade100,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.productImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.productImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Icons.image_not_supported, size: 24),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.shopping_bag,
                        size: 24,
                        color: Colors.grey,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
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
                Row(
                  children: [
                    Text(
                      '${item.effectivePrice.toStringAsFixed(2)}₺',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: item.isFlashSaleItem
                            ? const Color(0xFFE53935)
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (item.hasDiscount) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${(item.isFlashSaleItem ? (item.productPrice ?? 0) : (item.productOldPrice ?? 0)).toStringAsFixed(2)}₺',
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
                      _quantityButton(
                        icon: Icons.remove_rounded,
                        onTap: () {
                          // Satıcı minimum adet koyduysa onun altına inmek
                          // yerine ürün sepetten çıkarılır.
                          if (item.canRemoveOne) {
                            cartProvider.updateQuantity(
                              item.id,
                              item.quantity - 1,
                            );
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
                          ),
                        ),
                      ),
                      _quantityButton(
                        icon: Icons.add_rounded,
                        onTap: item.canAddMore
                            ? () => cartProvider.updateQuantity(
                                item.id,
                                item.quantity + 1,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),

                // Satıcı adet limitine uymayan satır için uyarı — ödeme
                // adımında sunucu reddedeceği için burada erken uyarıyoruz.
                if (item.quantityLimitWarning != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.quantityLimitWarning!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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

  Widget _quantityButton({
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

  Widget _buildCouponSection(BuildContext context, CartProvider cartProvider) {
    final theme = Theme.of(context);
    final coupon = cartProvider.couponForShop(widget.shopId);
    final subtotal = cartProvider.getShopTotal(widget.shopId);

    if (coupon != null) {
      final discount = coupon.discountFor(subtotal);
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                    '${coupon.code} • ${coupon.label} • -₺${discount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green.shade600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                cartProvider.removeCoupon(widget.shopId);
                _couponController.clear();
              },
              icon: Icon(Icons.close, color: Colors.green.shade700),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _couponController,
              textCapitalization: TextCapitalization.characters,
              enabled: !_isApplyingCoupon,
              decoration: InputDecoration(
                hintText: 'Kupon kodunu girin',
                prefixIcon: const Icon(Icons.local_offer_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isApplyingCoupon
                ? null
                : () => _applyCoupon(cartProvider),
            icon: _isApplyingCoupon
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.check, size: 18),
            label: const Text('Uygula'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyCoupon(CartProvider cartProvider) async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;
    setState(() => _isApplyingCoupon = true);
    try {
      final coupon = await cartProvider.applyCoupon(
        shopId: widget.shopId,
        code: code,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kupon uygulandı: ${coupon.label}'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isApplyingCoupon = false);
    }
  }

  Widget _buildCheckoutSection(
    BuildContext context,
    CartProvider cartProvider,
    List<CartItem> items,
  ) {
    final subtotal = cartProvider.getShopTotal(widget.shopId);
    final coupon = cartProvider.couponForShop(widget.shopId);
    final discount = coupon?.discountFor(subtotal) ?? 0.0;
    final deliveryFee = cartProvider.getDeliveryFee(widget.shopId);
    final total = subtotal - discount + deliveryFee;
    final meetsMinOrder = cartProvider.meetsMinOrderAmount(widget.shopId);
    final remaining = cartProvider.getRemainingForMinOrder(widget.shopId);
    final shop = cartProvider.getShop(widget.shopId);

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
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summaryRow('Ara Toplam', subtotal),
            if (discount > 0) ...[
              const SizedBox(height: 8),
              _summaryRow('İndirim', -discount, isDiscount: true),
            ],
            const SizedBox(height: 8),
            _summaryRow('Teslimat', deliveryFee),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _summaryRow('Toplam', total, isTotal: true),
            if (!meetsMinOrder && shop != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Minimum sipariş tutarı ₺${shop.minOrderAmount.toStringAsFixed(2)} — ₺${remaining.toStringAsFixed(2)} daha ekleyin',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (items.isEmpty || !meetsMinOrder)
                    ? null
                    : () => _goToCheckout(context, cartProvider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  meetsMinOrder ? 'Siparişi Tamamla' : 'Minimum Tutar Yetersiz',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
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
            fontSize: isTotal ? 20 : 15,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
            color: isDiscount ? Colors.green : const Color(0xFF1A1A2E),
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
        content: const Text(
          'Bu mağazadan sepetinizdeki tüm ürünleri silmek istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text(
              'Temizle',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<CartProvider>().clearShopCart(widget.shopId);
    }
  }

  Future<void> _goToCheckout(
    BuildContext context,
    CartProvider cartProvider,
  ) async {
    await cartProvider.loadShopInfo();
    if (!cartProvider.meetsMinOrderAmount(widget.shopId)) return;
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          shopId: widget.shopId,
          shopName:
              widget.shopName ??
              cartProvider.getShop(widget.shopId)?.name ??
              'Dükkan',
          couponsByShop: cartProvider.couponsByShop,
        ),
      ),
    );
  }
}
