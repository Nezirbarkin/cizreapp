// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/product_model.dart';
import '../../../core/services/favorite_service.dart';
import '../services/cart_service.dart';
import 'product_detail_screen.dart';

class AllDiscountedProductsScreen extends StatefulWidget {
  final List<Product> products;

  const AllDiscountedProductsScreen({super.key, required this.products});

  @override
  State<AllDiscountedProductsScreen> createState() => _AllDiscountedProductsScreenState();
}

class _AllDiscountedProductsScreenState extends State<AllDiscountedProductsScreen> {
  final FavoriteService _favoriteService = FavoriteService();
  final CartService _cartService = CartService();
  final Set<String> _favoriteProductIds = {};
  final Set<String> _addingToCart = {};
  final Map<String, int> _cartQuantities = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadCartQuantities();
  }

  Future<void> _loadCartQuantities() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final cartItems = await _cartService.getCart(userId);
      final quantities = <String, int>{};
      for (var item in cartItems) {
        quantities[item.productId] = item.quantity;
      }
      if (mounted) {
        setState(() {
          _cartQuantities.addAll(quantities);
        });
      }
    } catch (e) {
      // Hata durumunda sessizce geç
    }
  }

  int _getCartQuantity(String productId) {
    return _cartQuantities[productId] ?? 0;
  }

  // ignore: unused_element
  bool _isInCart(String productId) {
    return _getCartQuantity(productId) > 0;
  }

  Future<void> _loadFavorites() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final favorites = await _favoriteService.getProductFavorites();
      if (mounted) {
        setState(() {
          _favoriteProductIds.addAll(favorites.map((f) => f.productId));
        });
      }
    } catch (e) {
      // Hata durumunda sessizce geç
    }
  }

  bool _isFavorite(String productId) {
    return _favoriteProductIds.contains(productId);
  }

  Future<void> _toggleFavorite(Product product) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen önce giriş yapın')),
        );
      }
      return;
    }

    final wasFavorite = _isFavorite(product.id);
    setState(() {
      if (wasFavorite) {
        _favoriteProductIds.remove(product.id);
      } else {
        _favoriteProductIds.add(product.id);
      }
    });

    try {
      await _favoriteService.toggleProductFavorite(product.id);
    } catch (e) {
      setState(() {
        if (wasFavorite) {
          _favoriteProductIds.add(product.id);
        } else {
          _favoriteProductIds.remove(product.id);
        }
      });
    }
  }

  Future<void> _addToCart(Product product) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen önce giriş yapın')),
        );
      }
      return;
    }

    setState(() => _addingToCart.add(product.id));

    try {
      await _cartService.addToCart(
        userId: userId,
        productId: product.id,
        quantity: 1,
      );

      if (mounted) {
        setState(() {
          _addingToCart.remove(product.id);
          _cartQuantities[product.id] = 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ürün sepete eklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _addingToCart.remove(product.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sepete eklenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _updateQuantity(Product product, int newQuantity) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final cartItems = await _cartService.getCart(userId);
      final cartItem = cartItems.firstWhere(
        (item) => item.productId == product.id,
        orElse: () => throw Exception('Ürün sepette bulunamadı'),
      );

      if (newQuantity <= 0) {
        await _cartService.removeFromCart(cartItem.id);
        if (mounted) {
          setState(() {
            _cartQuantities.remove(product.id);
          });
        }
      } else {
        await _cartService.updateQuantity(cartItemId: cartItem.id, quantity: newQuantity);
        if (mounted) {
          setState(() {
            _cartQuantities[product.id] = newQuantity;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'İndirimdeki Ürünler',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              '${widget.products.length}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: widget.products.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_offer_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'İndirimli ürün bulunmuyor',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 3,
                childAspectRatio: 0.68,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: widget.products.length,
              itemBuilder: (context, index) {
                final product = widget.products[index];
                return _buildProductCard(product, theme);
              },
            ),
    );
  }

  Widget _buildProductCard(Product product, ThemeData theme) {
    final isAdding = _addingToCart.contains(product.id);
    final cartQuantity = _getCartQuantity(product.id);
    final inCart = cartQuantity > 0;
    final isInStock = product.inStock;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(productId: product.id),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ürün görseli - sabit yükseklik
            SizedBox(
              height: 92,
              width: double.infinity,
              child: Stack(
                children: [
                  // Ürün resmi
                  Positioned.fill(
                    child: Container(
                      color: Colors.grey.shade100,
                      child: product.images.isNotEmpty
                          ? Image.network(
                              product.images.first,
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
                  // İndirim badge - üst sol
                  if (product.hasDiscount)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade500,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '%${product.discountPercentage}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // Sabitlenmiş badge (satıcı tarafından) - indirim varsa sağda
                  if (product.sellerPinned)
                    Positioned(
                      top: 4,
                      left: product.hasDiscount ? 52 : 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Sabit',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // Stokta yok overlay
                  if (!isInStock)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.6),
                        child: const Center(
                          child: Text(
                            'TÜKENDİ',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // Ürün bilgileri
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ürün adı - sabit yükseklik
                  SizedBox(
                    height: 14,
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 2),
                  
                  // Fiyat
                  SizedBox(
                    height: 14,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '₺${product.effectivePrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.hasDiscount) ...[
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              '₺${product.price.toStringAsFixed(0)}',
                              style: TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey.shade400,
                                fontSize: 9,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Buton - tam genişlik
                  SizedBox(
                    width: double.infinity,
                    height: 30,
                    child: !inCart
                        ? ElevatedButton(
                            onPressed: (isAdding || !isInStock)
                                ? null
                                : () => _addToCart(product),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              minimumSize: const Size(double.infinity, 30),
                            ),
                            child: isAdding
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Sepete Ekle',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                // Azalt butonu
                                InkWell(
                                  onTap: isInStock
                                      ? () => _updateQuantity(product, cartQuantity - 1)
                                      : null,
                                  child: SizedBox(
                                    width: 32,
                                    height: 30,
                                    child: Icon(
                                      Icons.remove,
                                      size: 14,
                                      color: isInStock
                                          ? theme.colorScheme.primary
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                // Miktar gösterimi
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      '$cartQuantity',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                // Artır butonu
                                InkWell(
                                  onTap: isInStock
                                      ? () => _updateQuantity(product, cartQuantity + 1)
                                      : null,
                                  child: SizedBox(
                                    width: 32,
                                    height: 30,
                                    child: Icon(
                                      Icons.add,
                                      size: 14,
                                      color: isInStock
                                          ? theme.colorScheme.primary
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
