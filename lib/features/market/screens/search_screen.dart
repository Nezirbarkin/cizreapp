// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/shop_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/category_model.dart';
import '../services/shop_service.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import '../services/cart_service.dart';
import '../providers/cart_provider.dart';
import '../../profile/services/profile_service.dart';
import '../../profile/screens/user_profile_screen.dart';
import 'shop_detail_screen.dart';
import 'category_shops_screen.dart';
import 'product_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ShopService _shopService = ShopService();
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();
  final ProfileService _profileService = ProfileService();
  final CartService _cartService = CartService();
  
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Shop> _shopResults = [];
  List<Product> _productResults = [];
  List<Category> _categoryResults = [];
  List<Map<String, dynamic>> _userResults = [];
  bool _isSearching = false;
  int _selectedTabIndex = 0; // 0: Tümü, 1: Dükkanlar, 2: Ürünler, 3: Kategoriler, 4: Kişiler
  
  final Set<String> _addingToCart = {};
  final Map<String, int> _cartQuantities = {};

  @override
  void initState() {
    super.initState();
    // Otomatik odaklan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
    _searchController.addListener(_onSearchChanged);
    _loadCartQuantities();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
    try {
      final cartProvider = context.read<CartProvider>();
      return cartProvider.getProductQuantityFromCache(productId);
    } catch (_) {
      return _cartQuantities[productId] ?? 0;
    }
  }

  bool _isInCart(String productId) {
    return _getCartQuantity(productId) > 0;
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
      try {
        final cartProvider = context.read<CartProvider>();
        await cartProvider.addToCart(product.id, quantity: 1);
      } catch (_) {
        await _cartService.addToCart(
          userId: userId,
          productId: product.id,
          quantity: 1,
        );
        if (mounted) {
          setState(() => _cartQuantities[product.id] = 1);
        }
      }

      if (mounted) {
        setState(() => _addingToCart.remove(product.id));
      }
      await _loadCartQuantities();
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
      try {
        final cartProvider = context.read<CartProvider>();
        final cartItems = cartProvider.items;
        final cartItem = cartItems.firstWhere(
          (item) => item.productId == product.id,
          orElse: () => throw Exception('Ürün sepette bulunamadı'),
        );

        if (newQuantity <= 0) {
          await cartProvider.removeFromCart(cartItem.id);
        } else {
          await cartProvider.updateQuantity(cartItem.id, newQuantity);
        }
      } catch (_) {
        final cartItems = await _cartService.getCart(userId);
        final cartItem = cartItems.firstWhere(
          (item) => item.productId == product.id,
          orElse: () => throw Exception('Ürün sepette bulunamadı'),
        );

        if (newQuantity <= 0) {
          await _cartService.removeFromCart(cartItem.id);
          if (mounted) {
            setState(() => _cartQuantities.remove(product.id));
          }
        } else {
          await _cartService.updateQuantity(cartItemId: cartItem.id, quantity: newQuantity);
          if (mounted) {
            setState(() => _cartQuantities[product.id] = newQuantity);
          }
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

  void _onSearchChanged() {
    if (_searchController.text.isEmpty) {
      setState(() {
        _shopResults = [];
        _productResults = [];
        _categoryResults = [];
        _userResults = [];
        _isSearching = false;
      });
      return;
    }
    _performSearch(_searchController.text);
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearching = true);

    try {
      // Paralel arama
      final results = await Future.wait([
        _shopService.searchShops(query),
        _productService.searchProducts(query),
        _categoryService.searchCategories(query),
        _profileService.searchUsers(query),
      ]);

      if (mounted) {
        setState(() {
          _shopResults = results[0] as List<Shop>;
          _productResults = results[1] as List<Product>;
          _categoryResults = results[2] as List<Category>;
          _userResults = results[3] as List<Map<String, dynamic>>;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  int get _totalResults => _shopResults.length + _productResults.length + _categoryResults.length + _userResults.length;

  List<dynamic> _getFilteredResults() {
    switch (_selectedTabIndex) {
      case 1:
        return _shopResults;
      case 2:
        return _productResults;
      case 3:
        return _categoryResults;
      case 4:
        return _userResults;
      default:
        return [..._shopResults, ..._productResults, ..._categoryResults, ..._userResults];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            // Arama barı
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                boxShadow: [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        decoration: const InputDecoration(
                          hintText: 'Dükkan, ürün veya kategori ara...',
                          prefixIcon: Icon(Icons.search, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        autofocus: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tablar
            if (_searchController.text.isNotEmpty && !_isSearching)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTab('Tümü ($_totalResults)', 0),
                      _buildTab('Dükkanlar (${_shopResults.length})', 1),
                      _buildTab('Ürünler (${_productResults.length})', 2),
                      _buildTab('Kategoriler (${_categoryResults.length})', 3),
                      _buildTab('Kişiler (${_userResults.length})', 4),
                    ],
                  ),
                ),
              ),

            // Sonuçlar
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _searchController.text.isEmpty
                      ? _buildEmptyState()
                      : _getFilteredResults().isEmpty
                          ? _buildNoResults()
                          : _selectedTabIndex == 2 && _productResults.isNotEmpty
                              ? _buildProductGrid()
                              : _buildResultsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Ne aramak istersiniz?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dükkan, kişi ,ürün veya kategori adı yazın',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Sonuç bulunamadı',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Farklı bir arama terimi deneyin',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 3,
        childAspectRatio: 0.68,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _productResults.length,
      itemBuilder: (context, index) {
        final product = _productResults[index];
        return _buildProductCardForGrid(product);
      },
    );
  }

  Widget _buildResultsList() {
    final results = _getFilteredResults();
    
    // "Tümü" sekmesinde: ürünler dışındakileri listele, ürünleri grid olarak göster
    if (_selectedTabIndex == 0) {
      final nonProducts = results.where((item) => item is! Product).toList();
      final products = results.whereType<Product>().toList();
      
      return CustomScrollView(
        slivers: [
          // Diğer sonuçlar (Dükkanlar, Kategoriler, Kişiler)
          if (nonProducts.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = nonProducts[index];
                  if (item is Shop) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildShopTile(item),
                    );
                  } else if (item is Category) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildCategoryTile(item),
                    );
                  } else if (item is Map<String, dynamic>) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildUserTile(item),
                    );
                  }
                  return const SizedBox.shrink();
                },
                childCount: nonProducts.length,
              ),
            ),
          // Ürünler başlığı
          if (products.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Ürünler (${products.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          // Ürünler grid
          if (products.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 3,
                  childAspectRatio: 0.68,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return _buildProductCardForGrid(products[index]);
                  },
                  childCount: products.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      );
    }
    
    // Diğer sekmeler (dükkanlar, kategoriler, kişiler) - normal liste
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        if (item is Shop) {
          return _buildShopTile(item);
        } else if (item is Category) {
          return _buildCategoryTile(item);
        } else if (item is Map<String, dynamic>) {
          return _buildUserTile(item);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildShopTile(Shop shop) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: shop.logoUrl != null
                ? DecorationImage(
                    image: NetworkImage(shop.logoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
            color: Colors.grey.shade200,
          ),
          child: shop.logoUrl == null
              ? const Icon(Icons.store, color: Colors.grey)
              : null,
        ),
        title: Text(
          shop.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(shop.description ?? ''),
        trailing: Icon(Icons.star, color: Colors.amber.shade600, size: 20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShopDetailScreen(shopId: shop.id),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductTile(Product product) {
    return _buildProductCardForGrid(product);
  }

  Widget _buildProductCardForGrid(Product product) {
    final theme = Theme.of(context);
    final isInStock = product.inStock;
    final isAdding = _addingToCart.contains(product.id);
    
    int cartQuantity;
    bool inCart;
    try {
      final cartProvider = context.watch<CartProvider>();
      cartQuantity = cartProvider.getProductQuantityFromCache(product.id);
      inCart = cartQuantity > 0;
    } catch (_) {
      cartQuantity = _getCartQuantity(product.id);
      inCart = _isInCart(product.id);
    }

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
                  // Sabitlenmiş badge
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

  Widget _buildCategoryTile(Category category) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            // ignore: deprecated_member_use
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          ),
          child: Icon(
            Icons.category,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CategoryShopsScreen(category: category),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final fullName = user['full_name'] ?? 'Kullanıcı';
    final username = user['username'] ?? 'user';
    final avatarUrl = user['avatar_url'] as String?;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnProfile = currentUserId == user['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: Theme.of(context).colorScheme.primary,
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? Text(
                  fullName.length >= 2
                      ? fullName.substring(0, 2).toUpperCase()
                      : fullName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                )
              : null,
        ),
        title: Text(
          fullName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('@$username'),
        trailing: isOwnProfile
            ? const Icon(Icons.account_circle, size: 20)
            : const Icon(Icons.chevron_right),
        onTap: () {
          if (isOwnProfile) {
            Navigator.pop(context);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(userId: user['id']),
              ),
            );
          }
        },
      ),
    );
  }
}
