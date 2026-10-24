// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/shop_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/category_model.dart';
import '../../../core/services/order_availability_service.dart';
import '../../../core/widgets/closed_shop_badge.dart';
import '../../../core/widgets/product_extras_widgets.dart';
import '../../../shared/widgets/flash_discount_badge.dart';
import '../../../shared/widgets/add_to_cart_fab.dart';
import '../widgets/flash_aware_price_row.dart';
import '../services/shop_service.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import '../services/cart_service.dart';
import '../providers/cart_provider.dart';
import '../../profile/services/profile_service.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../widgets/shop_card.dart';
import 'category_shops_screen.dart';
import 'product_detail_screen.dart';
import '../../../core/utils/image_url.dart';
import '../../../core/utils/hashtags.dart';
import '../../../core/models/post_model.dart';
import '../../../core/widgets/social_rich_text.dart';
import '../../social/services/post_service.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../social/screens/hashtag_feed_screen.dart';
import '../../social/widgets/social_post_card.dart' show formatSocialCount;
import '../services/recent_searches_store.dart';

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
  // Şu an geçerli kuponu olan arama sonucu dükkanları ("Kupon Var" rozeti).
  Set<String> _couponShopIds = {};
  List<Product> _productResults = [];
  List<Category> _categoryResults = [];
  List<Map<String, dynamic>> _userResults = [];
  List<Post> _postResults = [];
  bool _isSearching = false;
  int _selectedTabIndex =
      0; // 0: Tümü, 1: Dükkanlar, 2: Ürünler, 3: Kategoriler, 4: Kişiler, 5: Gönderiler

  final PostService _postService = PostService();
  final RecentSearchesStore _recentStore = RecentSearchesStore();
  List<String> _recentSearches = [];
  List<MapEntry<String, int>> _trendingTags = [];
  // Yazarken her tuşta istek gitmesin; eski sorgunun geç gelen cevabı yok sayılır.
  Timer? _debounce;
  int _searchGeneration = 0;

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  // Sipariş alınabilirlik durumu: global flag + ürünlerin dükkan durumu cache
  bool _globalOrdersEnabled = true;
  // shopId -> isAcceptingOrders (ürünlerin dükkanları için lazy yüklü)
  final Map<String, bool> _shopAcceptingOrders = {};
  // Bilinmeyen shopId'ler için yükleme devam ediyor mu
  final Set<String> _loadingShopIds = {};

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
    _loadSuggestions();
  }

  /// Boş arama ekranı: son aramalar (cihazda) + gündemdeki etiketler (üyeye).
  Future<void> _loadSuggestions() async {
    final recent = await _recentStore.load(_uid);
    if (mounted) setState(() => _recentSearches = recent);
    if (_uid == null) return;
    final tags = await _postService.getTrendingHashtags(days: 7, limit: 12);
    if (mounted) setState(() => _trendingTags = tags);
  }

  Future<void> _rememberQuery([String? query]) async {
    final q = (query ?? _searchController.text).trim();
    if (q.length < 2) return;
    final list = await _recentStore.add(_uid, q);
    if (mounted) setState(() => _recentSearches = list);
  }

  void _openHashtag(String tag) {
    _rememberQuery('#$tag');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HashtagFeedScreen(tag: tag)),
    );
  }

  void _onSubmitted(String value) {
    final q = value.trim();
    if (q.startsWith('#') && isValidHashtag(q)) {
      _openHashtag(foldHashtag(q));
      return;
    }
    _rememberQuery(q);
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
    // Sipariş alınabilirlik kontrolü (global + dükkan durumu)
    if (!_isProductOrderable(product)) {
      if (mounted) {
        final accepting = _shopAcceptingOrders[product.shopId] ?? true;
        final msg = OrderAvailabilityService.closedMessage(
          globalEnabled: _globalOrdersEnabled,
          shopAcceptingOrders: accepting,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg ?? OrderAvailabilityService.shopClosedMessage),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sepete eklenirken hata: $e')));
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
          await _cartService.updateQuantity(
            cartItemId: cartItem.id,
            quantity: newQuantity,
          );
          if (mounted) {
            setState(() => _cartQuantities[product.id] = newQuantity);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
      }
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    if (_searchController.text.isEmpty) {
      _searchGeneration++;
      setState(() {
        _shopResults = [];
        _productResults = [];
        _categoryResults = [];
        _userResults = [];
        _postResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _performSearch(_searchController.text),
    );
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    final generation = ++_searchGeneration;

    setState(() => _isSearching = true);

    // "#etiket" aranırsa gönderilerde etiketli metin aranır; diğerleri düz metin.
    final postQuery = query.trim();

    try {
      // Paralel arama
      final results = await Future.wait([
        _shopService.searchShops(query),
        _productService.searchProducts(query),
        _categoryService.searchCategories(query),
        _profileService.searchUsers(query),
        // Gönderi araması yalnız üyeye (RLS: gizli hesap / engel süzülür).
        _uid == null
            ? Future.value(<Post>[])
            : _postService.searchPosts(postQuery).catchError((Object e) => <Post>[]),
      ]);

      if (mounted && generation == _searchGeneration) {
        setState(() {
          _shopResults = results[0] as List<Shop>;
          _productResults = results[1] as List<Product>;
          _categoryResults = results[2] as List<Category>;
          _userResults = results[3] as List<Map<String, dynamic>>;
          _postResults = results[4] as List<Post>;
          _isSearching = false;
        });

        // Global sipariş flag'ını ve ürünlerin dükkan durumlarını paralel yükle
        _loadGlobalOrdersEnabled();
        _loadShopCoupons(_shopResults);
        _loadShopAcceptingOrdersForProducts(_productResults);
      }
    } catch (e) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _isSearching = false);
      }
    }
  }

  /// Arama sonucu dükkanların kupon rozetleri. Kullanıcı bu arada yeni bir
  /// arama yaptıysa (liste değiştiyse) eski sorgunun cevabı yok sayılır.
  Future<void> _loadShopCoupons(List<Shop> shops) async {
    final ids = await _shopService.getShopIdsWithActiveCoupons(
      shops.map((s) => s.id),
    );
    if (mounted && identical(shops, _shopResults)) {
      setState(() => _couponShopIds = ids);
    }
  }

  Future<void> _loadGlobalOrdersEnabled() async {
    final enabled = await OrderAvailabilityService.fetchGlobalOrdersEnabled();
    if (mounted) setState(() => _globalOrdersEnabled = enabled);
  }

  // Ürünlerin unique shopId'leri için dükkanların sipariş alma durumunu yükle.
  // ShopService 30 sn cache kullandığından tekrar sorgular ucuzdur.
  Future<void> _loadShopAcceptingOrdersForProducts(
    List<Product> products,
  ) async {
    final shopIds = products
        .map((p) => p.shopId)
        .where(
          (id) =>
              !_shopAcceptingOrders.containsKey(id) &&
              !_loadingShopIds.contains(id),
        )
        .toSet();

    if (shopIds.isEmpty) return;

    setState(() => _loadingShopIds.addAll(shopIds));

    await Future.wait(
      shopIds.map((shopId) async {
        try {
          final shop = await _shopService.getShopById(shopId);
          final accepting = shop?.isAcceptingOrders ?? true;
          if (mounted) {
            setState(() {
              _shopAcceptingOrders[shopId] = accepting;
              _loadingShopIds.remove(shopId);
            });
          }
        } catch (_) {
          // Hata durumunda dükkan açık varsay (müşteriyi yanlış engelleme)
          if (mounted) {
            setState(() {
              _shopAcceptingOrders[shopId] = true;
              _loadingShopIds.remove(shopId);
            });
          }
        }
      }),
    );
  }

  // Bir ürünün sipariş alınıp alınamayacağını kontrol et.
  bool _isProductOrderable(Product product) {
    if (!_globalOrdersEnabled) return false;
    final accepting = _shopAcceptingOrders[product.shopId];
    // Henüz yüklenmediyse açık varsay (yükleme tamamlanınca UI yenilenir)
    if (accepting == false) return false;
    return true;
  }

  int get _totalResults =>
      _shopResults.length +
      _productResults.length +
      _categoryResults.length +
      _userResults.length +
      _postResults.length;

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
      case 5:
        return _postResults;
      default:
        return [
          ..._shopResults,
          ..._productResults,
          ..._categoryResults,
          ..._userResults,
          ..._postResults,
        ];
    }
  }

  /// "#etiket" yazıldıysa sonuçların başında etiket akışına kısayol.
  String? get _typedHashtag {
    final q = _searchController.text.trim();
    return q.startsWith('#') && isValidHashtag(q) ? foldHashtag(q) : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
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
                        textInputAction: TextInputAction.search,
                        onSubmitted: _onSubmitted,
                        decoration: const InputDecoration(
                          hintText: 'Dükkan, ürün, kişi, gönderi veya #etiket ara...',
                          prefixIcon: Icon(Icons.search, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
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
                      if (_uid != null)
                        _buildTab('Gönderiler (${_postResults.length})', 5),
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
                  : _getFilteredResults().isEmpty && _typedHashtag == null
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
    if (_recentSearches.isNotEmpty || _trendingTags.isNotEmpty) {
      return _buildSuggestions();
    }
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
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  /// Son aramalar + gündemdeki etiketler.
  Widget _buildSuggestions() {
    final primary = Theme.of(context).colorScheme.primary;
    Widget header(String title, {VoidCallback? onClear}) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              if (onClear != null)
                TextButton(onPressed: onClear, child: const Text('Temizle')),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          header('Son aramalar', onClear: () async {
            await _recentStore.clear(_uid);
            if (mounted) setState(() => _recentSearches = []);
          }),
          for (final q in _recentSearches)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(Icons.history, color: Colors.grey.shade500),
              title: Text(q),
              trailing: IconButton(
                tooltip: 'Kaldır',
                icon: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
                onPressed: () async {
                  final list = await _recentStore.remove(_uid, q);
                  if (mounted) setState(() => _recentSearches = list);
                },
              ),
              onTap: () {
                if (q.startsWith('#') && isValidHashtag(q)) {
                  _openHashtag(foldHashtag(q));
                  return;
                }
                _searchController.text = q;
                _searchController.selection = TextSelection.collapsed(offset: q.length);
                _rememberQuery(q);
              },
            ),
          const SizedBox(height: 12),
        ],
        if (_trendingTags.isNotEmpty) ...[
          header('Gündemdeki etiketler'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _trendingTags)
                ActionChip(
                  avatar: Icon(Icons.tag_rounded, size: 16, color: primary),
                  label: Text('${t.key} · ${t.value}'),
                  onPressed: () => _openHashtag(t.key),
                ),
            ],
          ),
        ],
      ],
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
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 3,
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
          if (_typedHashtag != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _buildHashtagShortcut(_typedHashtag!),
              ),
            ),
          // Diğer sonuçlar (Dükkanlar, Kategoriler, Kişiler, Gönderiler)
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
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
              } else if (item is Post) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildPostTile(item),
                );
              }
              return const SizedBox.shrink();
            }, childCount: nonProducts.length),
          ),
          // Ürünler başlığı
          SliverToBoxAdapter(
            child: products.isEmpty
                ? const SizedBox.shrink()
                : Padding(
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
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 3,
                childAspectRatio: 0.68,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                return _buildProductCardForGrid(products[index]);
              }, childCount: products.length),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      );
    }

    // Diğer sekmeler (dükkanlar, kategoriler, kişiler, gönderiler) - normal liste
    final shortcut = _selectedTabIndex == 5 ? _typedHashtag : null;
    final offset = shortcut != null ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length + offset,
      itemBuilder: (context, index) {
        if (shortcut != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildHashtagShortcut(shortcut),
          );
        }
        final item = results[index - offset];
        if (item is Shop) {
          return _buildShopTile(item);
        } else if (item is Category) {
          return _buildCategoryTile(item);
        } else if (item is Map<String, dynamic>) {
          return _buildUserTile(item);
        } else if (item is Post) {
          return _buildPostTile(item);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildHashtagShortcut(String tag) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(Icons.tag_rounded, color: color),
        ),
        title: Text('#$tag', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Bu etiketle paylaşılan gönderileri gör'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openHashtag(tag),
      ),
    );
  }

  /// Gönderi sonucu: yazar, metin (etiketler vurgulu), sayaçlar.
  Widget _buildPostTile(Post post) {
    final name = (post.authorFullName?.trim().isNotEmpty ?? false)
        ? post.authorFullName!.trim()
        : (post.authorUsername ?? 'Kullanıcı');
    final avatarUrl = post.authorAvatarUrl;
    final hasImage = post.images.isNotEmpty && post.images.first.isNotEmpty;
    final muted = TextStyle(fontSize: 12, color: Colors.grey.shade600);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _rememberQuery();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: avatarUrl != null ? avatarImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    SocialRichText(
                      post.content?.trim().isNotEmpty == true ? post.content!.trim() : 'Fotoğraf',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.favorite_border, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 3),
                        Text(formatSocialCount(post.likesCount), style: muted),
                        const SizedBox(width: 12),
                        Icon(Icons.mode_comment_outlined, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 3),
                        Text(formatSocialCount(post.commentsCount), style: muted),
                        if (post.viewsCount > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.visibility_outlined, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 3),
                          Text(formatSocialCount(post.viewsCount), style: muted),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: post.images.first,
                    width: 56,
                    height: 56,
                    memCacheWidth: 168,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: Colors.grey.shade200,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShopTile(Shop shop) {
    return ShopCard(
      shop: shop,
      globalOrdersEnabled: _globalOrdersEnabled,
      hasCoupon: _couponShopIds.contains(shop.id),
      margin: const EdgeInsets.only(bottom: 10),
    );
  }

  Widget _buildProductTile(Product product) {
    return _buildProductCardForGrid(product);
  }

  Widget _buildProductCardForGrid(Product product) {
    final theme = Theme.of(context);
    final isInStock = product.inStock;
    final isAdding = _addingToCart.contains(product.id);
    final isOrderable = _isProductOrderable(product);
    final closedBadge = !isOrderable
        ? ClosedShopBadge(global: !_globalOrdersEnabled)
        : null;

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
                          ? CachedNetworkImage(
                              imageUrl: product.images.first,
                              fit: productCardImageFit(product),
                              memCacheWidth: 400,
                              errorWidget: (context, url, error) {
                                return const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 24,
                                  ),
                                );
                              },
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
                  // İndirim badge - üst sol (flaş indirim veya normal indirim)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: FlashAwareDiscountBadge(product: product),
                  ),
                  if (product.isBuy2Get1BalanceCampaign)
                    const Positioned(
                      bottom: 4,
                      left: 4,
                      child: CampaignBadge(),
                    ),
                  // Satıcı rozetleri + ücretsiz kargo. Kampanya rozeti alt
                  // sol köşeyi kullandığı için o varken bir kat yukarı kayar.
                  Positioned(
                    bottom: product.isBuy2Get1BalanceCampaign ? 22 : 4,
                    left: 4,
                    right: 4,
                    child: ProductCardTagStrip(product: product),
                  ),
                  // Sabitlenmiş badge
                  if (product.sellerPinned)
                    Positioned(
                      top: 4,
                      left: product.hasDiscount ? 52 : 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
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
                  // Geçici Kapalı rozeti - üst sağ
                  if (closedBadge != null)
                    Positioned(top: 4, right: 4, child: closedBadge),
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

                  // Fiyat (flaş indirim bilinçli)
                  SizedBox(
                    height: 14,
                    child: FlashAwarePriceRow(
                      product: product,
                      priceStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: theme.colorScheme.primary,
                      ),
                      oldPriceStyle: TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey.shade400,
                        fontSize: 9,
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Buton
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: !inCart
                        ? Row(
                            children: [
                              if (!isOrderable)
                                Expanded(
                                  child: Text(
                                    _globalOrdersEnabled
                                        ? 'Geçici Kapalı'
                                        : 'Kapalı',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              else
                                const Spacer(),
                              AddToCartFab(
                                isLoading: isAdding,
                                onPressed:
                                    (isAdding || !isInStock || !isOrderable)
                                    ? null
                                    : () => _addToCart(product),
                              ),
                            ],
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
                                      ? () => _updateQuantity(
                                          product,
                                          cartQuantity - 1,
                                        )
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
                                  onTap:
                                      (isInStock &&
                                          isOrderable &&
                                          (product.isDigital ||
                                              cartQuantity <
                                                  product.maxCartQuantity))
                                      ? () => _updateQuantity(
                                          product,
                                          cartQuantity + 1,
                                        )
                                      : null,
                                  child: SizedBox(
                                    width: 32,
                                    height: 30,
                                    child: Icon(
                                      Icons.add,
                                      size: 14,
                                      color:
                                          (isInStock &&
                                              (product.isDigital ||
                                                  cartQuantity <
                                                      product.maxCartQuantity))
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
          backgroundImage: avatarUrl != null ? avatarImage(avatarUrl) : null,
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
          _rememberQuery();
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
