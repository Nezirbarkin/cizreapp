  // ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../market/screens/market_screen.dart';
import '../../market/screens/product_detail_screen.dart';
import '../../market/screens/all_discounted_products_screen.dart';
import '../../social/screens/social_screen.dart';
import '../../market/screens/cart_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../market/providers/cart_provider.dart';
import '../../market/services/product_service.dart';
import '../../../core/models/product_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/privacy_service.dart';
import '../../../core/services/order_availability_service.dart';
import '../../../core/widgets/closed_shop_badge.dart';
import '../../market/services/shop_service.dart';
import '../../market/widgets/pending_review_dialog.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/widgets/settings_sidebar.dart';
import '../../../core/widgets/balance_header_widget.dart';
import '../../../core/widgets/animated_app_title.dart';
import '../../wallet/screens/wallet_screen.dart';
import '../../market/screens/search_screen.dart';
import '../../market/screens/notifications_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final NotificationService _notificationService = NotificationService();
  final PrivacyService _privacyService = PrivacyService();
  int _unreadNotificationCount = 0;
  
  // ⚡ iOS PERFORMANCE: Sadece aktif sekmeyi oluştur, diğerlerini lazy yükle
  final Map<int, Widget> _cachedScreens = {};
  DateTime? _lastNotificationLoad; // Debounce bildirim yüklemesi

  Widget _getScreen(int index) {
    return _cachedScreens.putIfAbsent(index, () {
      switch (index) {
        case 0: return const MarketScreen();
        case 1: return const ProductsScreen();
        case 2: return const CartScreen(isMainTab: true);
        case 3: return const SocialScreen();
        case 4: return const ProfileScreen();
        default: return const MarketScreen();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Uygulama açıldığında çevrimiçi durumunu güncelle ve heartbeat başlat
    _privacyService.onAppResumed();
    // Uygulama yüklendikten sonra pending reviews kontrolü yap
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkStartupAnnouncement();
      PendingReviewChecker.checkAndShowPendingReviews(context);
      _loadNotificationCount();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Uygulama kapanırken çevrimdışı yap ve heartbeat durdur
    _privacyService.onAppPaused();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        // Uygulama ön plana geldi - çevrimiçi yap
        _privacyService.onAppResumed();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        // Uygulama arka plana geçti - çevrimdışı yap
        _privacyService.onAppPaused();
        break;
      default:
        break;
    }
  }

  Future<void> _checkStartupAnnouncement() async {
    try {
      final settings = await Supabase.instance.client
          .from('app_about_settings')
          .select()
          .limit(1)
          .maybeSingle();

      if (settings == null || !mounted) return;

      final announcementEnabled = settings['startup_announcement_enabled'] as bool? ?? false;
      if (!announcementEnabled) return;

      final title = settings['startup_announcement_title'] as String?;
      final message = settings['startup_announcement_message'] as String?;
      if (title == null || message == null || title.isEmpty || message.isEmpty) return;

      final type = settings['startup_announcement_type'] as String? ?? 'info';
      final buttonText = settings['startup_announcement_button_text'] as String? ?? 'Tamam';
      final updatedAt = settings['startup_announcement_updated_at'] as String?;

      // SharedPreferences'ta son gösterilen duyuruyu kontrol et
      if (updatedAt != null) {
        final prefs = await SharedPreferences.getInstance();
        final lastShownKey = 'last_shown_announcement';
        final lastShown = prefs.getString(lastShownKey);
        
        // Eğer duyuru güncellenmediyse tekrar gösterme
        if (lastShown == updatedAt) return;
        
        // Göster ve kaydet
        await prefs.setString(lastShownKey, updatedAt);
      }

      if (!mounted) return;

      // Dialog göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(_getAnnouncementIcon(type), color: _getAnnouncementColor(type), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: _getAnnouncementColor(type),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Açılış duyurusu kontrol hatası: $e');
    }
  }

  Color _getAnnouncementColor(String type) {
    switch (type) {
      case 'warning':
        return Colors.orange;
      case 'success':
        return Colors.green;
      case 'error':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  IconData _getAnnouncementIcon(String type) {
    switch (type) {
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'success':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // PERFORMANCE: Bildirim sayısını güncelle - debounce ile gereksiz yüklemeleri önle
    final now = DateTime.now();
    if (_lastNotificationLoad == null || now.difference(_lastNotificationLoad!).inSeconds >= 5) {
      _lastNotificationLoad = now;
      _loadNotificationCount();
    }
  }

  Future<void> _loadNotificationCount() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final count = await _notificationService.getUnreadCount(userId);
        if (mounted) {
          setState(() => _unreadNotificationCount = count);
        }
      } catch (e) {
        debugPrint('Bildirim sayısı yüklenirken hata: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tüm platformlarda Supabase'den kullanıcı ID'sini al
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    
    // CartProvider'ı tüm ekranlara sağla
    return ChangeNotifierProvider(
      create: (_) => CartProvider(userId),
      child: Builder(
        builder: (context) {
          final cartProvider = context.watch<CartProvider>();
          
          // PERFORMANCE: _screens önceden oluşturuldu, her build'de yeniden oluşturma
          final theme = Theme.of(context);
          final primaryColor = theme.colorScheme.primary;
          final cartCount = cartProvider.itemCount;

          return Scaffold(
            resizeToAvoidBottomInset: false,
            extendBody: true,
            // ⚡ iOS PERFORMANCE: IndexedStack yerine lazy loading
            // Sadece aktif ekranı oluşturur, bellek tasarrufu sağlar
            body: _getScreen(_selectedIndex),
            floatingActionButton: Stack(
              alignment: Alignment.topRight,
              children: [
                FloatingActionButton(
                  backgroundColor: const Color(0xFFEEFF41),
                  elevation: 8,
                  onPressed: () {
                    setState(() => _selectedIndex = 2);
                  },
                  child: Icon(
                    _selectedIndex == 2
                        ? Icons.shopping_cart
                        : Icons.shopping_cart_outlined,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
                if (cartCount > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3D00),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Text(
                        cartCount > 9 ? '9+' : '$cartCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: BottomAppBar(
              shape: const CircularNotchedRectangle(),
              notchMargin: 8.0,
              elevation: 8,
              color: Colors.white,
              child: SizedBox(
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    _buildNavItem(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home,
                      label: "AnaSayfa",
                      index: 0,
                      primaryColor: primaryColor,
                    ),
                    _buildNavItem(
                      icon: Icons.shopping_bag_outlined,
                      activeIcon: Icons.shopping_bag,
                      label: "Ürünler",
                      index: 1,
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(width: 40),
                    _buildNavItem(
                      icon: Icons.explore_outlined,
                      activeIcon: Icons.explore,
                      label: "Keşfet",
                      index: 3,
                      primaryColor: primaryColor,
                      notificationCount: 0, // Alt navigasyonda badge yok
                    ),
                    _buildNavItem(
                      icon: Icons.person_outline,
                      activeIcon: Icons.person,
                      label: "Profil",
                      index: 4,
                      primaryColor: primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required Color primaryColor,
    int notificationCount = 0,
  }) {
    final isSelected = _selectedIndex == index;
    
    return InkWell(
      onTap: () {
        // Misafir kontrolü - Keşfet ve Profil için
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId == null && (index == 3 || index == 4)) {
          // Misafir kullanıcı keşfet veya profile tıkladı
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                index == 3
                  ? 'Keşfet özelliklerini kullanmak için giriş yapmalısınız'
                  : 'Profil özelliklerini kullanmak için giriş yapmalısınız',
              ),
              action: SnackBarAction(
                label: 'Giriş Yap',
                onPressed: () {
                  Navigator.of(context).pushNamed('/login');
                },
              ),
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }
        setState(() => _selectedIndex = index);
        // Keşfet sekmesine geçince bildirim sayısını yenile
        if (index == 3) {
          _loadNotificationCount();
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? primaryColor : Colors.grey.shade400,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? primaryColor : Colors.grey.shade400,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          // Bildirim badge'i
          if (notificationCount > 0)
            Positioned(
              top: -2,
              right: -12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Text(
                  notificationCount > 9 ? '9+' : '$notificationCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Ürünler Ekranı
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final ProductService _productService = ProductService();
  final ShopService _shopService = ShopService();
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final Set<String> _addingToCart = {};

  // Sipariş alınabilirlik durumu
  bool _globalOrdersEnabled = true;
  final Map<String, bool> _shopAcceptingOrders = {};

  // Filtreleme seçenekleri
  String _sortBy = 'newest'; // newest, price_asc, price_desc
  String? _selectedCategory;
  // ignore: unused_field
  bool _showFilterSheet = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadGlobalOrdersEnabled();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cartProvider = context.read<CartProvider>();
      if (cartProvider.userId.isNotEmpty) {
        cartProvider.loadCart();
      }
    });
  }

  Future<void> _loadGlobalOrdersEnabled() async {
    final enabled = await OrderAvailabilityService.fetchGlobalOrdersEnabled();
    if (mounted) setState(() => _globalOrdersEnabled = enabled);
  }

  // Ürünlerin unique shopId'leri için dükkanların sipariş alma durumunu yükle.
  // ShopService 30 sn cache kullandığından tekrar sorgular ucuzdur.
  Future<void> _loadShopAcceptingOrdersForProducts(List<Product> products) async {
    final shopIds = products
        .map((p) => p.shopId)
        .where((id) => !_shopAcceptingOrders.containsKey(id))
        .toSet();
    if (shopIds.isEmpty) return;

    await Future.wait(shopIds.map((shopId) async {
      try {
        final shop = await _shopService.getShopById(shopId);
        final accepting = shop?.isAcceptingOrders ?? true;
        if (mounted) setState(() => _shopAcceptingOrders[shopId] = accepting);
      } catch (_) {
        if (mounted) setState(() => _shopAcceptingOrders[shopId] = true);
      }
    }));
  }

  // Bir ürünün sipariş alınıp alınamayacağını kontrol et.
  bool _isProductOrderable(Product product) {
    if (!_globalOrdersEnabled) return false;
    final accepting = _shopAcceptingOrders[product.shopId];
    if (accepting == false) return false;
    return true;
  }

  void _applyFilters() {
    _filteredProducts = List.from(_products);
    
    // Kategori filtresi
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      _filteredProducts = _filteredProducts
          .where((p) => p.category == _selectedCategory)
          .toList();
    }
    
    // Sponsor ve sponsor olmayan ürünleri ayır
    final pinnedProducts = _filteredProducts.where((p) => p.isPinned).toList();
    final nonPinnedProducts = _filteredProducts.where((p) => !p.isPinned).toList();
    
    // Sıralama (sadece sponsor olmayanlara uygulanır)
    switch (_sortBy) {
      case 'price_asc':
        nonPinnedProducts.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'price_desc':
        nonPinnedProducts.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'newest':
      default:
        // Sponsor olmayanlar zaten shuffle edilmiş durumda kalacak
        break;
    }
    
    // Sponsorlar + sıralanmış sponsor olmayanlar
    _filteredProducts = [...pinnedProducts, ...nonPinnedProducts];
    
    setState(() {});
  }

  List<String> _getAvailableCategories() {
    final categories = _products.map((p) => p.category).where((c) => c != null).cast<String>().toSet().toList();
    categories.sort();
    return categories;
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
          SnackBar(
            content: const Text('Sepete eklemek için giriş yapmanız gerekiyor'),
            action: SnackBarAction(
              label: 'Giriş Yap',
              onPressed: () {
                Navigator.of(context).pushNamed('/login');
              },
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() => _addingToCart.add(product.id));

    try {
      final cartProvider = context.read<CartProvider>();
      await cartProvider.addToCart(product.id, quantity: 1);
      
      if (mounted) {
        setState(() => _addingToCart.remove(product.id));
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final products = _searchQuery.isEmpty
          ? await _productService.getAllProducts()
          : await _productService.searchProducts(_searchQuery);
      setState(() {
        _products = products;
        _filteredProducts = List.from(products);
        _applyFilters();
        _isLoading = false;
      });
      // Ürünlerin dükkanlarının sipariş alma durumunu arka planda yükle
      _loadShopAcceptingOrdersForProducts(products);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ürünler yüklenirken hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          // Üst Bar
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                ],
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              left: 12,
              right: 12,
              bottom: 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: AnimatedAppTitle(
                    primaryFontSize: 20,
                    secondaryFontSize: 12,
                  ),
                ),
                // BAKİYE - ikonlarla aynı hizada ve boyutta
                SizedBox(
                  height: 30,
                  child: Center(child: _ProductsBalanceBadge()),
                ),
                // Arama ikonu
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    icon: const Icon(Icons.search, color: Colors.white, size: 20),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SearchScreen()),
                      );
                    },
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    constraints: const BoxConstraints(),
                  ),
                ),
                // Bildirim ikonu
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 20),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                      );
                    },
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    constraints: const BoxConstraints(),
                  ),
                ),
                // Ayarlar ikonu
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                    onPressed: () => showSettingsSidebar(context),
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
          ),
          // Ürünler listesi
          Expanded(
            child: _buildProductsList(cartProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList(CartProvider cartProvider) {
    return CustomScrollView(
      slivers: [
          // Ürünler listesi
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                children: [
                  // Filtre ve Sıralama Butonları
                  Row(
                    children: [
                      // Filtre butonu
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showFilterBottomSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedCategory != null ? Colors.blue.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedCategory != null ? Colors.blue.shade300 : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.tune, size: 16, color: _selectedCategory != null ? Colors.blue.shade700 : Colors.grey.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedCategory ?? 'Filtrele',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _selectedCategory != null ? Colors.blue.shade700 : Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Sıralama Butonları
                      _SortChip(
                        label: 'Yeni',
                        isSelected: _sortBy == 'newest',
                        onTap: () {
                          setState(() { _sortBy = 'newest'; });
                          _applyFilters();
                        },
                      ),
                      const SizedBox(width: 4),
                      _SortChip(
                        label: '₺↗',
                        isSelected: _sortBy == 'price_asc',
                        onTap: () {
                          setState(() { _sortBy = 'price_asc'; });
                          _applyFilters();
                        },
                      ),
                      const SizedBox(width: 4),
                      _SortChip(
                        label: '₺↘',
                        isSelected: _sortBy == 'price_desc',
                        onTap: () {
                          setState(() { _sortBy = 'price_desc'; });
                          _applyFilters();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _isLoading
              ? SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              : _products.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_bag_outlined,
                              size: 48,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Henüz ürün yok'
                                  : 'Ürün bulunamadı',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 3,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final product = _filteredProducts[index];
                            return _buildProductCard(product, cartProvider);
                          },
                          childCount: _filteredProducts.length,
                        ),
                      ),
                  ),
                ],
              );
            }

  Widget _buildProductCard(Product product, CartProvider cartProvider) {
    final theme = Theme.of(context);
    final isAdding = _addingToCart.contains(product.id);
    final isInStock = product.inStock;
    final inCart = cartProvider.getProductQuantityFromCache(product.id) > 0;
    final cartQuantity = cartProvider.getProductQuantityFromCache(product.id);
    final isOrderable = _isProductOrderable(product);
    final closedBadge = !isOrderable
        ? ClosedShopBadge(global: !_globalOrdersEnabled)
        : null;

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
              // ignore: deprecated_member_use
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
                  // Sponsor badge
                  if (product.isPinned)
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
                          'Sponsor',
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
                    Positioned(
                      top: 4,
                      right: 4,
                      child: closedBadge,
                    ),
                  // Stokta yok overlay
                  if (!isInStock)
                    Positioned.fill(
                      child: Container(
                        // ignore: deprecated_member_use
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
                            '₺${product.effectivePrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.displayOldPrice != null) ...[
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              '₺${product.displayOldPrice!.toStringAsFixed(2)}',
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
                            onPressed: (isAdding || !isInStock || !isOrderable)
                                ? null
                                : () => _addToCart(product),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
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
                                : Text(
                                    !isOrderable
                                        ? (_globalOrdersEnabled ? 'Geçici Kapalı' : 'Kapalı')
                                        : 'Sepete Ekle',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
                                  onTap: (isInStock && isOrderable)
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

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filtrele & Sırala',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      setModalState(() {
                        _sortBy = 'newest';
                        _selectedCategory = null;
                      });
                      setState(() {
                        _sortBy = 'newest';
                        _selectedCategory = null;
                        _applyFilters();
                      });
                    },
                    child: const Text('Temizle'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Sıralama
              const Text(
                'Sıralama',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip(
                    label: 'En Yeni',
                    value: 'newest',
                    groupValue: _sortBy,
                    onSelected: (value) {
                      setModalState(() => _sortBy = value);
                      setState(() {
                        _sortBy = value;
                        _applyFilters();
                      });
                    },
                  ),
                  _buildFilterChip(
                    label: 'Fiyat Artan',
                    value: 'price_asc',
                    groupValue: _sortBy,
                    onSelected: (value) {
                      setModalState(() => _sortBy = value);
                      setState(() {
                        _sortBy = value;
                        _applyFilters();
                      });
                    },
                  ),
                  _buildFilterChip(
                    label: 'Fiyat Azalan',
                    value: 'price_desc',
                    groupValue: _sortBy,
                    onSelected: (value) {
                      setModalState(() => _sortBy = value);
                      setState(() {
                        _sortBy = value;
                        _applyFilters();
                      });
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Kategori
              const Text(
                'Kategori',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip(
                    label: 'Tümü',
                    value: null,
                    groupValue: _selectedCategory,
                    onSelected: (value) {
                      setModalState(() => _selectedCategory = value);
                      setState(() {
                        _selectedCategory = value;
                        _applyFilters();
                      });
                    },
                  ),
                  ..._getAvailableCategories().map((cat) => _buildFilterChip(
                    label: cat,
                    value: cat,
                    groupValue: _selectedCategory,
                    onSelected: (value) {
                      setModalState(() => _selectedCategory = value);
                      setState(() {
                        _selectedCategory = value;
                        _applyFilters();
                      });
                    },
                  )),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Uygula butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Tamam', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip<T>({
    required String label,
    required T value,
    required T? groupValue,
    required Function(T) onSelected,
  }) {
    final isSelected = groupValue == value;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 13)),
      selected: isSelected,
      onSelected: (selected) => onSelected(value),
      selectedColor: Colors.blue.shade100,
      checkmarkColor: Colors.blue.shade700,
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? Colors.blue.shade300 : Colors.transparent,
        ),
      ),
    );
  }
}

// Keşfet ekranı için bakiye badge
class _ProductsBalanceBadge extends StatefulWidget {
  const _ProductsBalanceBadge();

  @override
  State<_ProductsBalanceBadge> createState() => _ProductsBalanceBadgeState();
}

class _ProductsBalanceBadgeState extends State<_ProductsBalanceBadge> {
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
      if (mounted) setState(() => _isLoading = false);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WalletScreen()),
    ).then((_) => _loadBalance());
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBalance) return const SizedBox.shrink();

    if (_isLoading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return GestureDetector(
      onTap: _navigateToWallet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Text(
          '₺${(_balance ?? 0).toStringAsFixed(2)}',
          style: TextStyle(
            color: Colors.blue.shade700,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// Sıralama Butonu Widget'ı
class _SortChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
