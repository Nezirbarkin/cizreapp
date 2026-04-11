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
import '../../market/widgets/pending_review_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final NotificationService _notificationService = NotificationService();
  final PrivacyService _privacyService = PrivacyService();
  // ignore: unused_field
  int _unreadNotificationCount = 0;

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
    // Sayfa değiştiğinde bildirim sayısını güncelle
    _loadNotificationCount();
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
          
          // Ekranları her seferinde oluştur (late initialization hatası önleme)
          final List<Widget> screens = [
            const MarketScreen(),
            const ProductsScreen(),
            const CartScreen(isMainTab: true),
            const SocialScreen(),
            const ProfileScreen(),
          ];

          final theme = Theme.of(context);
          final primaryColor = theme.colorScheme.primary;
          final cartCount = cartProvider.itemCount;

          return Scaffold(
            resizeToAvoidBottomInset: false,
            extendBody: true,
            body: screens[_selectedIndex],
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
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final Set<String> _addingToCart = {};
  
  // Filtreleme seçenekleri
  String _sortBy = 'newest'; // newest, price_asc, price_desc
  String? _selectedCategory;
  // ignore: unused_field
  bool _showFilterSheet = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cartProvider = context.read<CartProvider>();
      if (cartProvider.userId.isNotEmpty) {
        cartProvider.loadCart();
      }
    });
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
      // Her yenilemede farklı sıralama için ürünleri karıştır
      products.shuffle();
      setState(() {
        _products = products;
        _filteredProducts = List.from(products);
        _applyFilters();
        _isLoading = false;
      });
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
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.white,
            expandedHeight: 80,
            collapsedHeight: 60,
            flexibleSpace: const FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 16, bottom: 12),
              title: Text(
                'Ürünler',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            actions: [
              // Filtre butonu
              IconButton(
                icon: Icon(Icons.tune, size: 20, color: Colors.grey.shade700),
                onPressed: () => _showFilterBottomSheet(context),
                tooltip: 'Filtrele',
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  // Arama
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Ürün ara...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  setState(() => _searchQuery = '');
                                  _loadProducts();
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (value) {
                        _searchQuery = value;
                        _loadProducts();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Aktif filtre göstergesi
                  if (_selectedCategory != null || _sortBy != 'newest')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Filtre',
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.filter_list, size: 14, color: Colors.blue.shade700),
                        ],
                      ),
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
      ),
    );
  }

  Widget _buildProductCard(Product product, CartProvider cartProvider) {
    final theme = Theme.of(context);
    final isAdding = _addingToCart.contains(product.id);
    final isInStock = product.inStock;
    final inCart = cartProvider.getProductQuantityFromCache(product.id) > 0;
    final cartQuantity = cartProvider.getProductQuantityFromCache(product.id);

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

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(20),
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
