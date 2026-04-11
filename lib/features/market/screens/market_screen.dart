// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/category_model.dart';
import '../../../core/models/shop_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/post_model.dart';
import '../../../core/models/daily_deal_model.dart';
import '../../../core/widgets/story_card.dart';
import '../../../core/widgets/html_iframe_widget.dart';
import '../../../core/widgets/floating_message_button.dart';
import '../../../core/widgets/settings_sidebar.dart';
import '../../../core/services/favorite_service.dart';
import '../../../core/services/notification_service.dart';
// ignore: duplicate_import
import '../../../core/models/daily_deal_model.dart';
import '../services/category_service.dart';
import '../services/shop_service.dart';
import '../services/product_service.dart';
import '../services/cart_service.dart';
import '../services/daily_deal_service.dart';
import '../providers/cart_provider.dart';
import '../../social/services/story_service.dart';
import '../../social/services/post_service.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/services/group_chat_service.dart';
import 'shop_detail_screen.dart';
import 'category_shops_screen.dart';
import 'all_categories_screen.dart';
import 'all_discounted_products_screen.dart';
import 'all_shops_screen.dart';
import 'search_screen.dart';
import 'notifications_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../social/screens/story_viewer_screen.dart';
// ignore: unused_import
import '../../shop/screens/cart_screen.dart' as shop_cart;
import 'product_detail_screen.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final CategoryService _categoryService = CategoryService();
  final ShopService _shopService = ShopService();
  final ProductService _productService = ProductService();
  final StoryService _storyService = StoryService();
  final PostService _postService = PostService();
  final CartService _cartService = CartService();
  final FavoriteService _favoriteService = FavoriteService();
  final NotificationService _notificationService = NotificationService();
  final ChatService _chatService = ChatService();
  final GroupChatService _groupChatService = GroupChatService();
  final DailyDealService _dailyDealService = DailyDealService();
  final ScrollController _scrollController = ScrollController();

  List<Category> _categories = [];
  List<Shop> _shops = [];
  List<Product> _discountedProducts = [];
  List<Story> _stories = [];
  List<DailyDeal> _deals = [];
  List<Post> _recentPosts = [];
  Map<String, Map<String, dynamic>> _postUsersMap = {}; // userId -> user data
  Set<String> _favoriteProductIds = {};
  Map<String, int> _categoryShopCounts = {};
  int _unreadNotificationCount = 0;
  int _unreadChatCount = 0;
  bool _globalOrdersEnabled = true;
  
  bool _isLoading = true;
  // ignore: unused_field
  String? _selectedCategoryId;
  bool _isStoriesCompact = false;
  final Set<String> _addingToCart = {};
  final Map<String, int> _cartQuantities = {};
  Timer? _dealTimer;
  // ignore: unused_field
  int _timerTick = 0; // Her saniye güncellenir, widget'ları rebuild eder

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadFavorites();
    _loadNotificationCount();
    _loadChatUnreadCount();
    _scrollController.addListener(_onScroll);
    // Geri sayım için timer başlat (her saniye güncelle)
    _dealTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _timerTick++);
      }
    });
  }

  Future<void> _loadFavorites() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final favorites = await _favoriteService.getProductFavorites();
      if (mounted) {
        _favoriteProductIds = favorites.map((f) => f.productId).toSet();
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

    // Önce state'i güncelle (optimistic update)
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
      // Hata durumunda state'i geri al
      setState(() {
        if (wasFavorite) {
          _favoriteProductIds.add(product.id);
        } else {
          _favoriteProductIds.remove(product.id);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }

  Future<void> _loadNotificationCount() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final count = await _notificationService.getUnreadCount(userId);
      if (mounted) {
        setState(() => _unreadNotificationCount = count);
      }
    } catch (e) {
      debugPrint('Bildirim sayısı yüklenirken hata: $e');
    }
  }

  Future<void> _loadChatUnreadCount() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final directCount = await _chatService.getUnreadCount();
      final groupCount = await _groupChatService.getTotalUnreadCount();
      final totalCount = directCount + groupCount;
      
      if (mounted) {
        setState(() => _unreadChatCount = totalCount);
      }
    } catch (e) {
      // Hata durumunda sessizce geç
    }
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
        _cartQuantities.clear();
        _cartQuantities.addAll(quantities);
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

  @override
  void dispose() {
    _dealTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Aşağı scroll offset 100'den fazlaysa compact yap
    if (_scrollController.offset > 100 && !_isStoriesCompact) {
      setState(() => _isStoriesCompact = true);
    } else if (_scrollController.offset <= 100 && _isStoriesCompact) {
      setState(() => _isStoriesCompact = false);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Global sipariş durumunu yükle
      try {
        final settingsResponse = await Supabase.instance.client
            .from('app_about_settings')
            .select('global_orders_enabled')
            .maybeSingle();
        
        if (settingsResponse != null) {
          _globalOrdersEnabled = settingsResponse['global_orders_enabled'] as bool? ?? true;
        }
      } catch (e) {
        debugPrint('Global sipariş durumu yüklenirken hata: $e');
        _globalOrdersEnabled = true;
      }
      
      final categories = await _categoryService.getCategories();
      final shops = await _shopService.getShops();
      final stories = await _storyService.getStories();
      final discountedProducts = await _productService.getDiscountedProducts();
      final categoryShopCounts = await _shopService.getShopsCountByCategory();
      
      // Fırsat kartlarını yükle
      List<DailyDeal> deals = [];
      try {
        deals = await _dailyDealService.getActiveDeals();
      } catch (e) {
        debugPrint('Fırsat kartları yüklenirken hata: $e');
      }
      
      // Son gönderileri yükle (5 adet)
      List<Post> recentPosts = [];
      Map<String, Map<String, dynamic>> postUsersMap = {};
      try {
        recentPosts = await _postService.getFeed(limit: 5, offset: 0, useCache: false);
        
        // Kullanıcı bilgilerini çek
        if (recentPosts.isNotEmpty) {
          final userIds = recentPosts.map((p) => p.userId).toSet().toList();
          final usersResponse = await Supabase.instance.client
              .from('profiles')
              .select('id, full_name, username, avatar_url')
              .inFilter('id', userIds);
          
          for (var user in usersResponse) {
            postUsersMap[user['id']] = user;
          }
        }
      } catch (e) {
        debugPrint('Recent Posts yüklenirken hata: $e');
      }

      // Her yenilemede farklı sıralama için ürünleri karıştır (dükkanlar karıştırılmaz - sponsorlar en üstte)
      discountedProducts.shuffle();
      // Sponsor dükkanları en üstte tut
      shops.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });

      setState(() {
        _categories = categories;
        _shops = shops;
        _stories = stories;
        _discountedProducts = discountedProducts;
        _categoryShopCounts = categoryShopCounts;
        _deals = deals;
        _recentPosts = recentPosts;
        _postUsersMap = postUsersMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenirken hata: $e')),
        );
      }
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
      // Sepet quantities'i yenile
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

  void _navigateToDealCategory(String categoryName) {
    // Kategoriler arasında arama yap
    final category = _categories.firstWhere(
      (cat) => cat.name.toLowerCase() == categoryName.toLowerCase(),
      orElse: () => _categories.isNotEmpty
          ? _categories.first
          : Category(
              id: '',
              name: categoryName,
              slug: categoryName.toLowerCase().replaceAll(' ', '-'),
              createdAt: DateTime.now(),
            ),
    );
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryShopsScreen(category: category),
      ),
    );
  }

  Future<void> _viewStory(int index) async {
    if (_stories.isEmpty) return;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId != null && _stories[index].userId != currentUserId) {
      await _storyService.viewStory(_stories[index].id, currentUserId);
    }

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StoryViewerScreen(
            stories: _stories,
            initialIndex: index,
          ),
        ),
      );
      // Story görüntülendikten sonra verileri yenile
      _loadData();
    }
  }

  void _showAllCategories(BuildContext context) {
    // Tüm kategorileri gösteren sayfaya git
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AllCategoriesScreen(categories: _categories),
      ),
    );
  }

  void _showAllDiscountedProducts(BuildContext context) {
    // Tüm indirimli ürünleri gösteren sayfaya git
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AllDiscountedProductsScreen(products: _discountedProducts),
      ),
    );
  }

  void _showAllShops(BuildContext context) {
    // Tüm dükkanları gösteren sayfaya git
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AllShopsScreen(),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _filterByCategory(String? categoryId) async {
    setState(() {
      _selectedCategoryId = categoryId;
      _isLoading = true;
    });

    try {
      final shops = categoryId == null
          ? await _shopService.getShops()
          : await _shopService.getShopsByCategory(categoryId);

      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          // Ana içerik
          Column(
            children: [
              // Özel header - tasarım.php'deki gibi
              _buildCustomHeader(context, primaryColor),
              
              // İçerik alanı - yuvarlak köşeli beyaz arka plan
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(40),
                    topRight: Radius.circular(40),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5F7FA),
                    ),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildContent(context),
                  ),
                ),
              ),
            ],
          ),
          
          // Floating mesaj butonu
          FloatingMessageButton(
            show: true,
            unreadCount: _unreadChatCount,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatListScreen(),
                ),
              ).then((_) => _loadChatUnreadCount());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCustomHeader(BuildContext context, Color primaryColor) {
    // Platform ve cihaza göre üst padding hesapla
    final screenSize = MediaQuery.of(context).size;
    final isMobileWeb = kIsWeb && screenSize.width <= 600;
    
    double topPadding;
    if (isMobileWeb) {
      // Mobil web: minimal padding
      topPadding = 8.0;
    } else if (kIsWeb) {
      // Desktop web: normal padding
      topPadding = 40.0;
    } else {
      // Mobil uygulama: SafeArea padding + minimal padding
      final safePadding = MediaQuery.of(context).padding.top;
      topPadding = safePadding + 8.0;
    }
    
    return Container(
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık ve aksiyonlar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  // Sayfayı en üste scroll et
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                },
                child: const Text(
                  'CizreApp',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Arama ikonu
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SearchScreen(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.search_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    constraints: const BoxConstraints(),
                  ),
                  // Bildirim ikonu
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      ).then((_) {
                        _loadNotificationCount();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                          // Bildirim badge'i
                          if (_unreadNotificationCount > 0)
                            Positioned(
                              top: -3,
                              right: -3,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF3D00),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 13,
                                  minHeight: 13,
                                ),
                                child: Text(
                                  _unreadNotificationCount > 9 ? '9+' : '$_unreadNotificationCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Ayarlar ikonu
                  IconButton(
                    onPressed: () {
                      showSettingsSidebar(context);
                    },
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Story başlığı - Scroll durumuna göre gizle
          if (!_isStoriesCompact) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Çevrende Neler Oluyor?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          
          // Stories section - Dinamik boyut
          StoriesSection(
            isCompact: false,
            forceCompact: _isStoriesCompact,
            onStoryTap: _viewStory,
          ),
          SizedBox(height: _isStoriesCompact ? 2 : 4),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Üst boşluk
          const SliverToBoxAdapter(child: SizedBox(height: 4)),

          // Fırsat Kartları
          if (_deals.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _deals.length,
                  itemBuilder: (context, index) {
                    final deal = _deals[index];
                    return Container(
                      width: 300,
                      margin: const EdgeInsets.only(right: 12),
                      child: _buildDynamicDealCard(deal),
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          ],

          // Kategoriler
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Kategoriler',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showAllCategories(context),
                    child: Text(
                      'Tümü',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Kategori kartları - Grid
          if (_categories.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final category = _categories[index];
                    return _buildCategoryCard(category);
                  },
                  childCount: _categories.length > 4 ? 4 : _categories.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // İndirimdekiler
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'İndirimdekiler',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '🏷️',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _showAllDiscountedProducts(context),
                    child: Text(
                      'Tümü',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // İndirimdekiler - Horizontal Scroll (Gerçek indirimli ürünler)
          if (_discountedProducts.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 170,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _discountedProducts.length,
                  itemBuilder: (context, index) {
                    final product = _discountedProducts[index];
                    return Container(
                      width: 130,
                      margin: const EdgeInsets.only(right: 8),
                      child: _buildDiscountedProductCard(product),
                    );
                  },
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // Dükkanlar başlığı
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dükkanlar',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showAllShops(context),
                    child: Text(
                      'Tümü',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Dükkan listesi
          if (_shops.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text('Henüz dükkan bulunmuyor'),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final shop = _shops[index];
                    return _buildShopCard(shop);
                  },
                  childCount: _shops.length,
                ),
              ),
            ),

            // En Son Gönderiler
            if (_recentPosts.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text(
                        'En Son Gönderiler',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '✨',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 280,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _recentPosts.length,
                    itemBuilder: (context, index) {
                      final post = _recentPosts[index];
                      return Container(
                        width: 200,
                        margin: const EdgeInsets.only(right: 12),
                        child: _buildRecentPostCard(post),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 120,
                ),
              ),
            ] else
              // Gönderi yoksa da alt padding ekle (bottom navigation için)
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDealCard(String title, String desc, Color color, IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        height: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              color.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // İkon
                  Icon(
                    icon,
                    size: 32,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  // Başlık
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Alt metin
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicDealCard(DailyDeal deal) {
    // HTML deal türü kontrolü
    if (deal.dealType == 'html' && deal.htmlContent != null && deal.htmlContent!.isNotEmpty) {
      return _buildHtmlDealCard(deal);
    }
    
    // Kalan süreyi hesapla
    String? remainingTime;
    if (deal.endDate != null) {
      final diff = deal.endDate!.difference(DateTime.now());
      if (diff.isNegative) {
        remainingTime = 'Bitti';
      } else if (diff.inHours < 24) {
        final hours = diff.inHours;
        final minutes = diff.inMinutes % 60;
        final seconds = diff.inSeconds % 60;
        remainingTime = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      } else if (diff.inDays < 7) {
        remainingTime = '${diff.inDays}g ${diff.inHours % 24}sa';
      } else {
        remainingTime = '${diff.inDays} gün';
      }
    }
    
    return GestureDetector(
      onTap: () => _navigateToDeal(deal),
      child: Container(
        width: 180,
        height: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Arka plan resmi
            CachedNetworkImage(
              imageUrl: deal.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade300,
                child: const Center(
                  child: Icon(Icons.error_outline, size: 24),
                ),
              ),
            ),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.6),
                  ],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
            // İçerik
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    deal.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (deal.subtitle != null && deal.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      deal.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.9),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Geri sayım (süre bitiyorsa)
            if (remainingTime != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: remainingTime == 'Bitti'
                        ? Colors.black.withOpacity(0.75)
                        : Colors.red.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    remainingTime,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHtmlDealCard(DailyDeal deal) {
    // HTML deal kartı - web için iframe, mobil için webview
    return GestureDetector(
      onTap: () => _navigateToDeal(deal),
      child: Container(
        width: 180,
        height: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // HTML içeriği
            Positioned.fill(
              child: HtmlIframeWidget(
                htmlContent: deal.htmlContent!,
                width: 180,
                height: 140,
              ),
            ),
            // Kalan süre göstergesi (opsiyonel)
            if (deal.endDate != null)
              Positioned(
                top: 8,
                right: 8,
                child: _buildRemainingTimeBadge(deal.endDate!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemainingTimeBadge(DateTime endDate) {
    final diff = endDate.difference(DateTime.now());
    String timeText;
    Color bgColor;
    
    if (diff.isNegative) {
      timeText = 'Bitti';
      bgColor = Colors.black.withOpacity(0.75);
    } else if (diff.inHours < 24) {
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      final seconds = diff.inSeconds % 60;
      timeText = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      bgColor = Colors.red.withOpacity(0.9);
    } else if (diff.inDays < 7) {
      timeText = '${diff.inDays}g ${diff.inHours % 24}sa';
      bgColor = Colors.orange.withOpacity(0.9);
    } else {
      timeText = '${diff.inDays} gün';
      bgColor = Colors.blue.withOpacity(0.9);
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        timeText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _navigateToDeal(DailyDeal deal) {
    debugPrint('Deal tıklandı - linkType: ${deal.linkType}, linkId: ${deal.linkId}, linkUrl: ${deal.linkUrl}');
    
    switch (deal.linkType) {
      case 'shop':
        if (deal.linkId != null && deal.linkId!.isNotEmpty) {
          _navigateToShopById(deal.linkId!);
        } else {
          debugPrint('Mağaza ID boş');
        }
        break;
      case 'campaign':
        // İndirimli ürünler sayfasına yönlendir
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AllDiscountedProductsScreen(products: _discountedProducts),
          ),
        );
        break;
      case 'category':
        if (deal.linkId != null && deal.linkId!.isNotEmpty) {
          // Kategori ID ile ilgili kategoriyi bul
          final category = _categories.where((c) => c.id == deal.linkId).firstOrNull;
          if (category != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CategoryShopsScreen(category: category),
              ),
            );
          } else {
            debugPrint('Kategori bulunamadı: ${deal.linkId}');
          }
        }
        break;
      case 'product':
        if (deal.linkId != null && deal.linkId!.isNotEmpty) {
          _navigateToProductById(deal.linkId!);
        } else {
          debugPrint('Ürün ID boş');
        }
        break;
      case 'url':
        if (deal.linkUrl != null && deal.linkUrl!.isNotEmpty) {
          _launchURL(deal.linkUrl!);
        } else {
          debugPrint('URL boş');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bu fırsat kartı için URL tanımlanmamış')),
            );
          }
        }
        break;
      default:
        debugPrint('Bilinmeyen link tipi: ${deal.linkType}');
        // linkUrl varsa URL olarak aç
        if (deal.linkUrl != null && deal.linkUrl!.isNotEmpty) {
          _launchURL(deal.linkUrl!);
        }
        break;
    }
  }

  Future<void> _navigateToShopById(String shopId) async {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ShopDetailScreen(shopId: shopId),
        ),
      );
    } catch (e) {
      debugPrint('Mağaza yüklenirken hata: $e');
    }
  }

  Future<void> _navigateToProductById(String productId) async {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailScreen(productId: productId),
        ),
      );
    } catch (e) {
      debugPrint('Ürün yüklenirken hata: $e');
    }
  }

  Future<void> _launchURL(String url) async {
    try {
      final uri = Uri.parse(url);
      // Web'de platformDefault, mobilde externalApplication kullan
      final mode = kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;
      final launched = await launchUrl(uri, mode: mode);
      if (!launched) {
        debugPrint('URL açılamadı: $url');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('URL açılamadı: $url')),
          );
        }
      }
    } catch (e) {
      debugPrint('URL açılırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL açılırken hata: $e')),
        );
      }
    }
  }

  Widget _buildCategoryCard(Category category) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CategoryShopsScreen(category: category),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.grey.shade200,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Kategori resmi veya placeholder
            if (category.imageUrl != null && category.imageUrl!.isNotEmpty)
              Image.network(
                category.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).primaryColor.withOpacity(0.8),
                          Theme.of(context).primaryColor.withOpacity(0.6),
                        ],
                      ),
                    ),
                  );
                },
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).primaryColor.withOpacity(0.8),
                      Theme.of(context).primaryColor.withOpacity(0.6),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.category,
                    size: 40,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            // Kategori bilgileri
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.store,
                        size: 11,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${_categoryShopCounts[category.id] ?? 0} Dükkan',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
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

  Widget _buildDiscountedProductCard(Product product) {
    final isAdding = _addingToCart.contains(product.id);
    final isInStock = product.inStock;
    final theme = Theme.of(context);
    
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

  Widget _buildShopCard(Shop shop) {
    // Sipariş alma durumu kontrolü
    final bool isOrdersClosed = !_globalOrdersEnabled || !shop.isAcceptingOrders;
    
    return Opacity(
      opacity: isOrdersClosed ? 0.55 : 1.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        clipBehavior: Clip.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: shop.isPinned
                ? Colors.amber.shade400
                : (isOrdersClosed ? Colors.red.shade100 : Colors.grey.shade100),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShopDetailScreen(shopId: shop.id),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(
                  children: [
                    // Logo
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                        image: shop.logoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(shop.logoUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: shop.logoUrl == null
                          ? const Icon(Icons.store, size: 28, color: Colors.grey)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    
                    // Bilgiler
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Dükkan adı ve verified
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        shop.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (shop.isVerified) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.verified,
                                        size: 16,
                                        color: Colors.blue,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Sağ tarafta etiketler
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Açık/Kapalı etiketi
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: shop.isOpen ? Colors.green : Colors.red,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      shop.isOpen ? 'Açık' : 'Kapalı',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  // Kupon var etiketi
                                  FutureBuilder<int>(
                                    future: _getActiveCouponCount(shop.id),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData && snapshot.data! > 0) {
                                        return Padding(
                                          padding: const EdgeInsets.only(left: 4),
                                          child: _BlinkingCouponBadge(),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shop.description ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.star, size: 14, color: Colors.amber.shade600),
                              const SizedBox(width: 3),
                              Text(
                                shop.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.local_shipping, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 3),
                              Text(
                                shop.deliveryFee > 0
                                    ? '${shop.deliveryFee.toStringAsFixed(0)}₺'
                                    : 'Ücretsiz',
                                style: TextStyle(
                                  color: shop.deliveryFee > 0
                                      ? Colors.grey.shade600
                                      : Colors.green.shade600,
                                  fontSize: 11,
                                  fontWeight: shop.deliveryFee == 0 ? FontWeight.w600 : null,
                                ),
                              ),
                              if (shop.minOrderAmount > 0) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.shopping_cart, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 3),
                                Text(
                                  'Min ${shop.minOrderAmount.toStringAsFixed(0)}₺',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Geçici Kapalı banner
                if (isOrdersClosed) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pause_circle_filled, size: 14, color: Colors.red.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Geçici Kapalı - Sipariş Alınmıyor',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
          if (shop.isPinned)
            Positioned(
              top: -8,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.star,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<int> _getActiveCouponCount(String shopId) async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount <= maxRetries) {
      try {
        final response = await Supabase.instance.client
            .from('shop_coupons')
            .select('id')
            .eq('shop_id', shopId)
            .eq('is_active', true)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException('Kupon sayısı sorgusu zaman aşımına uğradı'),
            );
        return (response as List).length;
      } catch (e) {
        retryCount++;
        if (retryCount > maxRetries) {
          debugPrint('Kupon sayısı alınırken hata (max retry aşımı): $e');
          return 0;
        }
        // Exponential backoff ile yeniden dene
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }
    return 0;
  }

  Widget _buildRecentPostCard(Post post) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(post: post),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gönderi resmi
            Expanded(
              flex: 60,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  color: Colors.grey.shade100,
                ),
                child: post.images.isNotEmpty
                    ? ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: Image.network(
                          post.images.first,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(Icons.image, size: 40, color: Colors.grey),
                              ),
                            );
                          },
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.primary.withOpacity(0.15),
                              Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: Text(
                            post.content ?? 'Gönderi',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                              height: 1.4,
                            ),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
              ),
            ),
            // Kullanıcı ve etkileşim bilgileri
            Expanded(
              flex: 40,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 10, top: 10, bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Kullanıcı info
                    Row(
                      children: [
                        Builder(
                          builder: (context) {
                            final user = _postUsersMap[post.userId];
                            final avatarUrl = user?['avatar_url'] as String?;
                            
                            return CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl == null || avatarUrl.isEmpty
                                  ? const Icon(Icons.person, size: 12, color: Colors.white)
                                  : null,
                            );
                          }
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final user = _postUsersMap[post.userId];
                              final username = user?['username'] as String?;
                              final fullName = user?['full_name'] as String?;
                              final displayName = username ?? fullName ?? 'Kullanıcı';
                              
                              return Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              );
                            }
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Etkileşim bilgileri
                    Row(
                      children: [
                        Icon(Icons.favorite, size: 12, color: Colors.red.shade400),
                        const SizedBox(width: 2),
                        Text(
                          '${post.likesCount}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.comment, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Text(
                          '${post.commentsCount}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
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

/// Sabit container, içindeki yazı ve ikon sürekli yanıp söner
// ignore: must_be_immutable
class _BlinkingCouponBadge extends StatefulWidget {
  const _BlinkingCouponBadge();

  @override
  State<_BlinkingCouponBadge> createState() => _BlinkingCouponBadgeState();
}

class _BlinkingCouponBadgeState extends State<_BlinkingCouponBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFFF8C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Opacity(
            opacity: _animation.value,
            child: child,
          );
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.confirmation_number,
              size: 11,
              color: Colors.white,
            ),
            SizedBox(width: 3),
            Text(
              'Kupon Var',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
