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
import '../../../core/models/app_about_settings.dart';
import '../../../core/models/post_model.dart';
import '../../../core/models/daily_deal_model.dart';
import '../../../core/widgets/story_card.dart';
import '../../../core/widgets/product_extras_widgets.dart';
import '../../../core/widgets/html_iframe_widget.dart';
import '../../../core/widgets/animated_app_title.dart';
import '../../../core/widgets/floating_message_button.dart';
import '../../../core/widgets/settings_sidebar.dart';
import '../../../shared/widgets/flash_discount_badge.dart';
import '../../../shared/widgets/add_to_cart_fab.dart';
import '../widgets/flash_aware_price_row.dart';
import '../../../core/widgets/balance_header_widget.dart';
import '../../../core/services/balance_service.dart';
import '../../wallet/screens/wallet_screen.dart';
import '../../../core/services/favorite_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/order_availability_service.dart';
import '../../../core/widgets/closed_shop_badge.dart';
import '../services/category_service.dart';
import '../services/shop_service.dart';
import '../services/product_service.dart';
import '../services/cart_service.dart';
import '../services/daily_deal_service.dart';
import '../providers/cart_provider.dart';
import '../../social/services/story_service.dart';
import '../../../sehirici/sehirici.dart';
import '../../social/services/post_service.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/services/group_chat_service.dart';
import '../../news/services/news_service.dart';
import '../../news/screens/news_detail_screen.dart';
import '../../news/screens/news_screen.dart';
import 'shop_detail_screen.dart';
import 'category_shops_screen.dart';
import 'all_categories_screen.dart';
import 'all_discounted_products_screen.dart';
import 'all_shops_screen.dart';
import 'search_screen.dart';
import 'notifications_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../social/screens/story_viewer_screen.dart';
import 'product_detail_screen.dart';
import '../../../core/services/app_about_service.dart';
import '../../user_courier/screens/send_package_screen.dart';
import '../../../ilanlar/widgets/home_ilan_section.dart';
// import '../../news/widgets/news_section_widget.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  // Animasyon ayarları için service
  final _aboutService = AppAboutService();

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
  RealtimeChannel? _conversationsChannel;
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
  final Map<String, Future<int>> _couponCountCache = {};
  Map<String, int> _categoryShopCounts = {};
  int _unreadNotificationCount = 0;
  int _unreadChatCount = 0;
  bool _globalOrdersEnabled = true;
  // Anasayfa kategori kartlarında gösterilecek maksimum kategori sayısı.
  // Admin panelinden değiştirilebilir (app_about_settings.home_category_limit).
  int _homeCategoryLimit = 4;

  // Anasayfada gösterilecek maksimum haber kartı sayısı.
  // Admin panelinden değiştirilebilir (app_about_settings.home_news_limit).
  int _homeNewsLimit = 3;

  // Anasayfada gösterilecek maksimum dükkan sayısı.
  // Admin panelinden değiştirilebilir (app_about_settings.home_shop_limit).
  int _homeShopLimit = 8;

  // Haber listesi future'ı önbelleğe alınır. Eski kod future'ı build içinde
  // inline yaratıyordu — bu nedenle her rebuild (cart değişimi, scroll, setState)
  // yeni bir ağ isteği atıp FutureBuilder snapshot'ını sıfırlıyordu. Önbellek +
  // limit değişiminde null'lama ile tek sefer çekilir.
  Future<List<dynamic>>? _newsFuture;

  Future<List<dynamic>> _getNewsFuture() {
    return _newsFuture ??= NewsService().getLatestNews(limit: _homeNewsLimit);
  }

  // Animasyon ayarları
  String _appSlogan = 'Her an her kapıda!';
  int _animationPrimaryDurationMs = 6000;
  int _animationSecondaryDurationMs = 3000;
  int _animationTransitionDurationMs = 700;

  bool _isLoading = true;
  // ignore: unused_field
  String? _selectedCategoryId;
  bool _isStoriesCompact = false;
  final Set<String> _addingToCart = {};
  final Map<String, int> _cartQuantities = {};
  Timer? _dealTimer;
  // Sadece fırsat kartları geri sayımını tetikler; tüm ekranı rebuild ETMEZ.
  final ValueNotifier<int> _dealTick = ValueNotifier<int>(0);
  bool _courierServiceActive = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // ⚡ iOS PERFORMANCE: Başlatma işlemlerini PARALEL yap
    _loadData();
    _loadCourierServiceStatus();

    // Arka planda yükle - kullanıcıyı bekletmez
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Bağımsız yükleme işlemlerini paralel yap
      await Future.wait([
        _loadFavorites().catchError((_) {}),
        _loadNotificationCount().catchError((_) {}),
        _loadChatUnreadCount().catchError((_) {}),
      ]);
    });

    // Geri sayım için timer başlat (her saniye güncelle)
    _dealTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _dealTick.value++;
      }
    });

    // Mesaj badge'i REALTIME: conversations değişince okunmamış sayısını yenile.
    // Böylece kullanıcı market ekranındayken yeni mesaj gelince yüzen mesaj
    // butonundaki kırmızı sayı anında güncellenir (2026-07-03).
    _conversationsChannel = _chatService.subscribeToConversations((_) {
      _loadChatUnreadCount();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
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
    _dealTick.dispose();
    if (_conversationsChannel != null) {
      Supabase.instance.client.removeChannel(_conversationsChannel!);
    }
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

  Future<void> _loadCourierServiceStatus() async {
    try {
      final settings = await Supabase.instance.client
          .from('courier_service_settings')
          .select('enabled, allows_user_requests')
          .limit(1)
          .maybeSingle();
      final active =
          (settings?['enabled'] as bool? ?? false) &&
          (settings?['allows_user_requests'] as bool? ?? false);
      if (mounted) setState(() => _courierServiceActive = active);
    } catch (e) {
      debugPrint('Kurye servisi durumu yüklenemedi: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _couponCountCache.clear();

    try {
      // ⚡ iOS PERFORMANCE: Tüm bağımsız veri yükleme işlemlerini PARALEL yap
      final results = await Future.wait([
        // 1. Uygulama ayarları (AppAboutService — bellek cache'li). Global
        // sipariş durumu + slogan/animasyon/görünüm ayarları TEK sorguda
        // gelir; app_about_settings böylece açılışta 2 kez değil 1 kez
        // çekilir. (getAboutSettings içte hataları yakalar, null döner.)
        _aboutService.getAboutSettings(),
        // 2. Kategoriler
        _categoryService.getCategories().catchError((e) => <Category>[]),
        // 3. Dükkanlar
        _shopService.getShops().catchError((e) => <Shop>[]),
        // 4. Hikayeler
        _storyService.getStories().catchError((e) => <Story>[]),
        // 5. İndirimli ürünler
        _productService.getDiscountedProducts().catchError((e) => <Product>[]),
        // 6. Kategori dükkan sayıları
        _shopService.getShopsCountByCategory().catchError(
          (e) => <String, int>{},
        ),
        // 7. Fırsat kartları
        _dailyDealService.getActiveDeals().catchError((e) {
          debugPrint('Fırsat kartları yüklenirken hata: $e');
          return <DailyDeal>[];
        }),
      ]);

      // Sonuçları çıkar
      final appAbout = results[0] as AppAboutSettings?;
      final categories = results[1] as List<Category>;
      final shops = results[2] as List<Shop>;
      final stories = results[3] as List<Story>;
      final discountedProducts = results[4] as List<Product>;
      final categoryShopCounts = results[5] as Map<String, int>;
      final deals = results[6] as List<DailyDeal>;

      // Global sipariş durumu + animasyon/görünüm ayarları (tek sorgudan;
      // atanan alanlar alttaki büyük setState ile birlikte ekrana yansır)
      if (appAbout != null) {
        _globalOrdersEnabled = appAbout.globalOrdersEnabled;
        _appSlogan = appAbout.appSlogan;
        _animationPrimaryDurationMs = appAbout.animationPrimaryDurationMs;
        _animationSecondaryDurationMs = appAbout.animationSecondaryDurationMs;
        _animationTransitionDurationMs = appAbout.animationTransitionDurationMs;
        // Anasayfa kategori kartı sayısı limiti (admin panelinden ayarlanabilir)
        _homeCategoryLimit = appAbout.homeCategoryLimit;
        // Anasayfa haber kartı sayısı limiti (admin panelinden ayarlanabilir)
        _homeNewsLimit = appAbout.homeNewsLimit;
        // Anasayfa dükkan sayısı limiti (admin panelinden ayarlanabilir)
        _homeShopLimit = appAbout.homeShopLimit;
        // Limit değiştiyse haber future'ını yeniden oluştur (bir kez refetch).
        _newsFuture = null;
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
        _isLoading = false;
      });

      // Kritik olmayan "Son Gönderiler" bölümü ilk render'ı bloklamasın,
      // arka planda ayrı yüklenir.
      _loadRecentPosts();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      final errStr = e.toString();
      final isAuthError =
          errStr.contains('Geçersiz oturum') ||
          errStr.contains('status: 401') ||
          errStr.toLowerCase().contains('unauthorized') ||
          errStr.toLowerCase().contains('jwt expired');

      if (isAuthError) {
        // Oturum çökmüş — sessizce signOut tetikle, auth listener login'e yönlendirir.
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Oturumunuzun süresi dolmuş. Tekrar giriş yapın.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Veriler yüklenirken hata: $e')));
      }
    }
  }

  Future<void> _loadRecentPosts() async {
    try {
      final recentPosts = await _postService.getFeed(
        limit: 5,
        offset: 0,
        useCache: false,
      );

      Map<String, Map<String, dynamic>> postUsersMap = {};
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

      if (mounted) {
        setState(() {
          _recentPosts = recentPosts;
          _postUsersMap = postUsersMap;
        });
      }
    } catch (e) {
      debugPrint('Son gönderiler yüklenirken hata: $e');
    }
  }

  // Dükkan ID -> Shop haritası. Ürünlerin sipariş alınabilirliğini
  // hızlıca kontrol etmek için _shops listesinden türetilir.
  // _shops değişmediği sürece yeniden hesaplanmaz (her ürün kartı build'inde
  // O(n) map inşa etmemek için).
  Map<String, Shop>? _shopsByIdCache;
  List<Shop>? _shopsByIdSource;
  Map<String, Shop> get _shopsById {
    if (_shopsByIdSource != _shops) {
      _shopsByIdSource = _shops;
      _shopsByIdCache = {for (final s in _shops) s.id: s};
    }
    return _shopsByIdCache!;
  }

  // Bir ürünün sipariş alınıp alınamayacağını kontrol et.
  // Global kapatma veya dükkan geçici kapalıysa false.
  bool _isProductOrderable(Product product) {
    if (!_globalOrdersEnabled) return false;
    final shop = _shopsById[product.shopId];
    if (shop != null && !shop.isAcceptingOrders) return false;
    return true;
  }

  Future<void> _addToCart(Product product) async {
    // Sipariş alınabilirlik kontrolü (global + dükkan durumu)
    final orderable = _isProductOrderable(product);
    if (!orderable) {
      if (mounted) {
        final shop = _shopsById[product.shopId];
        final msg = OrderAvailabilityService.closedMessage(
          globalEnabled: _globalOrdersEnabled,
          shopAcceptingOrders: shop?.isAcceptingOrders ?? true,
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
      // Sepet quantities'i yenile
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
          builder: (context) =>
              StoryViewerScreen(stories: _stories, initialIndex: index),
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
        builder: (context) =>
            AllDiscountedProductsScreen(products: _discountedProducts),
      ),
    );
  }

  void _showAllShops(BuildContext context) {
    // Tüm dükkanları gösteren sayfaya git
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AllShopsScreen()),
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
                    decoration: const BoxDecoration(color: Color(0xFFF5F7FA)),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildContent(context),
                  ),
                ),
              ),
            ],
          ),

          // Moto kurye iconu (sohbet ikonunun üstünde) - sadece aktif olduğunda göster
          // Web ve mobilde sohbet ikonuyla aynı boşluğu koruması için
          // FloatingMessageButton'ın bottom + yüksekliğine (56) göre hesaplanır.
          if (_courierServiceActive)
            Positioned(
              right: kIsWeb ? 28 : 20,
              bottom: kIsWeb ? 170 : 210,
              child: FloatingActionButton(
                backgroundColor: const Color(0xFFFF6B00),
                elevation: 8,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SendPackageScreen(),
                    ),
                  );
                },
                tooltip: 'Paket Gönder',
                heroTag: 'courier_fab_market',
                child: const Icon(
                  Icons.two_wheeler,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),

          // Floating mesaj butonu
          FloatingMessageButton(
            show: true,
            unreadCount: _unreadChatCount,
            onTap: () {
              // Kullanıcı giriş yapmış mı kontrol et
              final currentUser = Supabase.instance.client.auth.currentUser;
              if (currentUser == null) {
                // Giriş yapmamışsa direkt giriş ekranına yönlendir
                Navigator.pushNamed(context, '/login');
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChatListScreen()),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AnimatedAppTitle.fromSettings(
                primaryText: 'CizreApp',
                secondaryText: _appSlogan,
                primaryDurationMs: _animationPrimaryDurationMs,
                secondaryDurationMs: _animationSecondaryDurationMs,
                transitionDurationMs: _animationTransitionDurationMs,
                primaryFontSize: 24,
                secondaryFontSize: 14,
                onTap: () {
                  // Sayfayı en üste scroll et
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // BAKİYE - İKONLARLA AYNI BOYUT VE HİZADA
                  SizedBox(
                    height: 30,
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          return _BalanceBadge(
                            onBalanceChanged: () {
                              if (mounted) {
                                setState(() {});
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  // Arama ikonu
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
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
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  // Bildirim ikonu
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: GestureDetector(
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
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                          // Bildirim badge'i
                          if (_unreadNotificationCount > 0)
                            Positioned(
                              top: -1,
                              right: -1,
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
                                  _unreadNotificationCount > 9
                                      ? '9+'
                                      : '$_unreadNotificationCount',
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
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      onPressed: () {
                        showSettingsSidebar(context);
                      },
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      constraints: const BoxConstraints(),
                    ),
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

          // Stories section - Dinamik boyut (Şehiriçi kartı içinde)
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

          // Fırsat Kartları - sadece geri sayım her saniye burada rebuild olur
          SliverToBoxAdapter(
            child: _deals.isEmpty
                ? const SizedBox.shrink()
                : ValueListenableBuilder<int>(
                    valueListenable: _dealTick,
                    builder: (context, _, __) => Column(
                      children: [
                        SizedBox(
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
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
          ),

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
                      'Tüm Kategoriler',
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
                // Admin panelinden ayarlanan _homeCategoryLimit kullanılır.
                // Eski hardcoded 4 değerinin yerine dinamik olarak güncellenir.
                childCount: _categories.length > _homeCategoryLimit
                    ? _homeCategoryLimit
                    : _categories.length,
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
                      Text('🏷️', style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _showAllDiscountedProducts(context),
                    child: Text(
                      'Tüm İndirimler',
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
          SliverToBoxAdapter(
            child: _discountedProducts.isEmpty
                ? const SizedBox.shrink()
                : SizedBox(
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
                      'Tüm Dükkanlar',
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (_shops.isEmpty) {
                    return const SizedBox(
                      height: 200,
                      child: Center(child: Text('Henüz dükkan bulunmuyor')),
                    );
                  }
                  final shop = _shops[index];
                  return _buildShopCard(shop);
                },
                childCount: _shops.isEmpty
                    ? 1
                    : (_shops.length > _homeShopLimit
                          ? _homeShopLimit
                          : _shops.length),
              ),
            ),
          ),

          // Cizreden Haberler
          SliverToBoxAdapter(child: _buildNewsSection()),

          // En Son Gönderiler
          SliverToBoxAdapter(
            child: _recentPosts.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const SizedBox(height: 16),
                      Padding(
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
                            const Text('✨', style: TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 196,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _recentPosts.length,
                          itemBuilder: (context, index) {
                            final post = _recentPosts[index];
                            return Container(
                              width: 140,
                              margin: const EdgeInsets.only(right: 10),
                              child: _buildRecentPostCard(post),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
          ),

          // İlan kategorileri ve en yeni ilanlar — "En Son Gönderiler" altı.
          const SliverToBoxAdapter(child: HomeIlanSection()),
        ],
      ),
    );
  }

  Widget _buildDealCard(
    String title,
    String desc,
    Color color,
    IconData icon, {
    VoidCallback? onTap,
  }) {
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
            colors: [color, color.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(16),
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
                  Icon(icon, size: 32, color: Colors.white),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
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
    if (deal.dealType == 'html' &&
        deal.htmlContent != null &&
        deal.htmlContent!.isNotEmpty) {
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
        remainingTime =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Arka plan resmi
            CachedNetworkImage(
              imageUrl: deal.imageUrl,
              fit: BoxFit.cover,
              // Görsel ~160px yükseklikte gösterilir; tam çözünürlükte decode
              // etmek feed belleğini şişirir. Gösterim boyutuna göre sınırla.
              memCacheWidth: 500,
              placeholder: (context, url) => Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade300,
                child: const Center(child: Icon(Icons.error_outline, size: 24)),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
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
      timeText =
          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
    debugPrint(
      'Deal tıklandı - linkType: ${deal.linkType}, linkId: ${deal.linkId}, linkUrl: ${deal.linkUrl}',
    );

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
            builder: (context) =>
                AllDiscountedProductsScreen(products: _discountedProducts),
          ),
        );
        break;
      case 'category':
        if (deal.linkId != null && deal.linkId!.isNotEmpty) {
          // Kategori ID ile ilgili kategoriyi bul
          final category = _categories
              .where((c) => c.id == deal.linkId)
              .firstOrNull;
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
              const SnackBar(
                content: Text('Bu fırsat kartı için URL tanımlanmamış'),
              ),
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
      final mode = kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication;
      final launched = await launchUrl(uri, mode: mode);
      if (!launched) {
        debugPrint('URL açılamadı: $url');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('URL açılamadı: $url')));
        }
      }
    } catch (e) {
      debugPrint('URL açılırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('URL açılırken hata: $e')));
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
              CachedNetworkImage(
                imageUrl: category.imageUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 250,
                errorWidget: (context, url, error) {
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
                      const Icon(Icons.store, size: 11, color: Colors.white70),
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
    final isOrderable = _isProductOrderable(product);
    final closedBadge = !isOrderable
        ? ClosedShopBadge(global: !_globalOrdersEnabled)
        : null;
    final theme = Theme.of(context);

    int cartQuantity;
    bool inCart;
    try {
      // select: sadece BU ürünün miktarı değiştiğinde bu kart rebuild olur
      // (watch tüm sepet değişikliklerinde tüm görünür kartları rebuild ederdi).
      cartQuantity = context.select<CartProvider, int>(
        (p) => p.getProductQuantityFromCache(product.id),
      );
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
                              fit: BoxFit.cover,
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
                                          cartQuantity < product.stockQuantity)
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
                                              cartQuantity <
                                                  product.stockQuantity)
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
    final bool isOrdersClosed =
        !_globalOrdersEnabled || !shop.isAcceptingOrders;

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
                    : (isOrdersClosed
                          ? Colors.red.shade100
                          : Colors.grey.shade100),
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
                              ? const Icon(
                                  Icons.store,
                                  size: 28,
                                  color: Colors.grey,
                                )
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
                                          color: shop.isOpen
                                              ? Colors.green
                                              : Colors.red,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                        future: _couponCountCache.putIfAbsent(
                                          shop.id,
                                          () => _getActiveCouponCount(shop.id),
                                        ),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData &&
                                              snapshot.data! > 0) {
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                left: 4,
                                              ),
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
                                  Icon(
                                    Icons.star,
                                    size: 14,
                                    color: Colors.amber.shade600,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    shop.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    Icons.local_shipping,
                                    size: 14,
                                    color: Colors.grey.shade600,
                                  ),
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
                                      fontWeight: shop.deliveryFee == 0
                                          ? FontWeight.w600
                                          : null,
                                    ),
                                  ),
                                  if (shop.minOrderAmount > 0) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.shopping_cart,
                                      size: 14,
                                      color: Colors.grey.shade600,
                                    ),
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
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.pause_circle_filled,
                              size: 14,
                              color: Colors.red.shade700,
                            ),
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
                child: const Icon(Icons.star, size: 12, color: Colors.white),
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
              onTimeout: () => throw TimeoutException(
                'Kupon sayısı sorgusu zaman aşımına uğradı',
              ),
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
          MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
        );
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gönderi resmi
            AspectRatio(
              aspectRatio: 1,
              child: post.images.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: post.images.first,
                      fit: BoxFit.cover,
                      memCacheWidth: 600,
                      errorWidget: (context, url, error) {
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(
                              Icons.image,
                              size: 32,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.15),
                            Theme.of(
                              context,
                            ).colorScheme.secondary.withOpacity(0.15),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Center(
                        child: Text(
                          post.content ?? 'Gönderi',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade800,
                            height: 1.3,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
            // Kullanıcı ve etkileşim bilgileri
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Kullanıcı info
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          final user = _postUsersMap[post.userId];
                          final avatarUrl = user?['avatar_url'] as String?;

                          return CircleAvatar(
                            radius: 9,
                            backgroundColor: Colors.grey.shade300,
                            backgroundImage:
                                avatarUrl != null && avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    size: 11,
                                    color: Colors.white,
                                  )
                                : null,
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final user = _postUsersMap[post.userId];
                            final username = user?['username'] as String?;
                            final fullName = user?['full_name'] as String?;
                            final displayName =
                                username ?? fullName ?? 'Kullanıcı';

                            return Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Etkileşim bilgileri
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 12,
                        color: Colors.red.shade400,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${post.likesCount}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.comment,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 3),
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
          ],
        ),
      ),
    );
  }

  Widget _buildNewsSection() {
    return FutureBuilder<List<dynamic>>(
      future: _getNewsFuture(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final news = snapshot.data!;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cizreden Haberler',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NewsScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'Tümünü Gör',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: news.map((newsItem) {
                  return _buildNewsCardItem(newsItem);
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNewsCardItem(dynamic newsItem) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NewsDetailScreen(news: newsItem),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: newsItem.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: newsItem.thumbnailUrl!,
                      width: 80,
                      height: 80,
                      memCacheWidth: 200,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey[300],
                      child: const Icon(Icons.newspaper, size: 32),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    newsItem.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    newsItem.summary ??
                        newsItem.content.substring(
                          0,
                          (newsItem.content.length > 80
                              ? 80
                              : newsItem.content.length),
                        ),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
          return Opacity(opacity: _animation.value, child: child);
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.confirmation_number, size: 11, color: Colors.white),
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

// BAKİYE BADGE - İKONSUZ, SADECE BAKİYE METNİ
class _BalanceBadge extends StatefulWidget {
  final VoidCallback? onBalanceChanged;

  const _BalanceBadge({this.onBalanceChanged});

  @override
  State<_BalanceBadge> createState() => _BalanceBadgeState();
}

class _BalanceBadgeState extends State<_BalanceBadge> {
  final BalanceService _balanceService = BalanceService();
  double? _balance;
  bool _isLoading = true;
  bool _showBalance = true;

  @override
  void initState() {
    super.initState();
    _checkShowBalance();
  }

  Future<void> _checkShowBalance() async {
    try {
      final shouldShow = await BalanceHeaderWidget.getShowBalance();
      if (mounted) {
        setState(() => _showBalance = shouldShow);
        if (shouldShow) {
          _loadBalance();
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadBalance() async {
    try {
      final balance = await _balanceService.getBalance();
      if (mounted) {
        setState(() {
          _balance = balance?.availableBalance ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      final errStr = e.toString();
      final isAuthError =
          errStr.contains('Geçersiz oturum') ||
          errStr.contains('status: 401') ||
          errStr.toLowerCase().contains('unauthorized') ||
          errStr.toLowerCase().contains('jwt expired');

      if (isAuthError) {
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
      }
    }
  }

  void _navigateToWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WalletScreen()),
    ).then((_) {
      _loadBalance();
      widget.onBalanceChanged?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Gizleme ayarı kapalıysa boş döndür
    if (!_showBalance) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }

    return GestureDetector(
      onTap: _navigateToWallet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '₺${(_balance ?? 0).toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
