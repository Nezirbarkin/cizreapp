// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/shop_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/shop_review_model.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../services/product_service.dart';
import '../services/shop_review_service.dart';
import '../providers/cart_provider.dart';
import '../../shop/services/cart_service.dart';
import '../../seller/services/shop_analytics_service.dart';
import 'product_detail_screen.dart';
import '../../shop/screens/cart_screen.dart' as shop_cart;

class ShopDetailScreen extends StatefulWidget {
  final String shopId;

  const ShopDetailScreen({super.key, required this.shopId});

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  final ProductService _productService = ProductService();
  final CartService _cartService = CartService();
  final ShopReviewService _reviewService = ShopReviewService();
  final ShopAnalyticsService _analyticsService = ShopAnalyticsService();

  Shop? _shop;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<ShopReview> _reviews = [];
  ShopReview? _userReview;
  bool _isLoading = true;
  // ignore: unused_field
  bool _isLoadingReviews = false;
  bool _globalOrdersEnabled = true;
  final Set<String> _addingToCart = {};
  final Map<String, int> _cartQuantities = {};
  int _totalCartQuantity = 0;
  
  // Kuponlar
  List<Map<String, dynamic>> _shopCoupons = [];
  
  // Arama ve filtreleme
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategory;
  bool _showOnlyInStock = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadShopData();
    _loadCartQuantities();
    _loadReviews();
    _loadShopCoupons();
    // Mağaza ziyaretini kaydet
    _analyticsService.recordShopView(widget.shopId);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadShopCoupons() async {
    try {
      debugPrint('🎟️ KUPON: Yükleniyor... shopId: ${widget.shopId}');
      final coupons = await Supabase.instance.client
          .from('shop_coupons')
          .select()
          .eq('shop_id', widget.shopId)
          .eq('is_active', true)
          .order('minimum_order_amount', ascending: true);
      
      debugPrint('🎟️ KUPON: ${coupons.length} kupon bulundu');
      
      // Süresi dolmuş kuponları filtrele
      final now = DateTime.now();
      final activeCoupons = (coupons as List).where((c) {
        final endDate = c['end_date'] != null ? DateTime.tryParse(c['end_date'].toString()) : null;
        if (endDate != null && endDate.isBefore(now)) {
          debugPrint('🎟️ KUPON: ${c['code']} - süresi dolmuş, filtreden çıkarıldı');
          return false;
        }
        return true;
      }).toList();
      
      for (var c in activeCoupons) {
        debugPrint('🎟️ KUPON: ${c['code']} - ${c['discount_type']} ${c['discount_value']}');
      }
      
      if (mounted) {
        setState(() {
          _shopCoupons = List<Map<String, dynamic>>.from(activeCoupons);
        });
      }
    } catch (e) {
      debugPrint('❌ KUPON: Kupon yükleme hatası: $e');
    }
  }

  void _onSearchChanged() {
    setState(() {
      _applyFilters();
    });
  }

  void _applyFilters() {
    _filteredProducts = _products.where((product) {
      // Arama filtresi
      if (_searchController.text.isNotEmpty) {
        final query = _searchController.text.toLowerCase();
        if (!product.name.toLowerCase().contains(query) &&
            !(product.description?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }
      
      // Kategori filtresi
      if (_selectedCategory != null && product.category != _selectedCategory) {
        return false;
      }
      
      // Stok filtresi
      if (_showOnlyInStock && product.stockQuantity <= 0) {
        return false;
      }
      
      return true;
    }).toList();
  }

  Future<void> _loadReviews() async {
    setState(() => _isLoadingReviews = true);
    
    try {
      final reviews = await _reviewService.getShopReviews(widget.shopId);
      final userId = Supabase.instance.client.auth.currentUser?.id;
      
      ShopReview? userReview;
      if (userId != null) {
        userReview = await _reviewService.getUserReview(widget.shopId, userId);
      }
      
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _userReview = userReview;
          _isLoadingReviews = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Yorumlar yüklenirken hata: $e');
      if (mounted) {
        setState(() => _isLoadingReviews = false);
      }
    }
  }

  Future<void> _showReviewDialog() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yorum yapmak için giriş yapmalısınız')),
        );
      }
      return;
    }

    // Tamamlanmış sipariş kontrolü (yeni yorum yapacaksa)
    if (_userReview == null) {
      final hasOrder = await _reviewService.hasCompletedOrder(widget.shopId, userId);
      if (!mounted) return;
      
      if (!hasOrder) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu dükkana yorum yapabilmek için teslim edilmiş bir siparişiniz olmalı'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    int selectedRating = _userReview?.rating ?? 5;
    final commentController = TextEditingController(text: _userReview?.comment ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_userReview == null ? 'Değerlendirme & Yorum' : 'Yorumu Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Puanınız:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final star = index + 1;
                    return IconButton(
                      icon: Icon(
                        star <= selectedRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          selectedRating = star;
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 16),
                const Text('Yorumunuz:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: commentController,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: 'Deneyiminizi paylaşın...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (_userReview != null)
              TextButton(
                onPressed: () async {
                  try {
                    await _reviewService.deleteReview(_userReview!.id);
                    if (context.mounted) {
                      Navigator.pop(context, true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Yorum silindi')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppErrorHandler.handleError(e))),
                      );
                    }
                  }
                },
                child: const Text('Sil', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (commentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen bir yorum yazın')),
                  );
                  return;
                }

                try {
                  if (_userReview == null) {
                    await _reviewService.addReview(
                      shopId: widget.shopId,
                      userId: userId,
                      rating: selectedRating,
                      comment: commentController.text.trim(),
                    );
                  } else {
                    await _reviewService.updateReview(
                      reviewId: _userReview!.id,
                      rating: selectedRating,
                      comment: commentController.text.trim(),
                    );
                  }
                  
                  if (context.mounted) {
                    Navigator.pop(context, true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_userReview == null ? 'Yorum eklendi' : 'Yorum güncellendi')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppErrorHandler.handleError(e))),
                    );
                  }
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _loadReviews();
      await _loadShopData(); // Refresh shop rating
    }
  }

  Future<void> _loadCartQuantities() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('🏪 SHOP: Kullanıcı giriş yapmamış');
      return;
    }

    try {
      debugPrint('🏪 SHOP: Sepet miktarları yükleniyor... userId: $userId');
      
      final cartItems = await _cartService.getCartItems(userId);
      debugPrint('🏪 SHOP: ${cartItems.length} adet sepet öğesi bulundu');
      
      final quantities = <String, int>{};
      double total = 0;
      for (var item in cartItems) {
        quantities[item.productId] = item.quantity.toInt();
        total += item.quantity;
        debugPrint('🏪 SHOP: CartItem - productId: ${item.productId}, quantity: ${item.quantity}');
      }
      
      if (mounted) {
        setState(() {
          _cartQuantities.clear();
          _cartQuantities.addAll(quantities);
          _totalCartQuantity = total.toInt();
        });
      }
      
      debugPrint('🏪 SHOP: Sepet badge: $_totalCartQuantity ürün');
    } catch (e) {
      debugPrint('❌ SHOP: Sepet miktarları yüklenirken hata: $e');
    }
  }

  int _getCartQuantity(String productId) {
    return _cartQuantities[productId] ?? 0;
  }

  bool _isInCart(String productId) {
    return _getCartQuantity(productId) > 0;
  }

  Future<void> _addToCart(Product product) async {
    // Sipariş alma kontrolü
    if (!_globalOrdersEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sipariş alma şu anda kapalı'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    if (_shop != null && !_shop!.isAcceptingOrders) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu dükkan şu anda sipariş almıyor (Geçici Kapalı)'),
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
      debugPrint('🏪 SHOP: Sepete ekleniyor - productId: ${product.id}, userId: $userId');
      
      await _cartService.addToCart(
        userId: userId,
        productId: product.id,
        quantity: 1,
      );
      
      debugPrint('✅ SHOP: Sepete eklendi - ${product.name}');
      
      if (mounted) {
        try {
          context.read<CartProvider>().loadCart();
        } catch (e) {
          debugPrint('INFO: CartProvider bulunamadı (normal bir durum)');
        }
      }
      
      if (mounted) {
        setState(() {
          _cartQuantities[product.id] = 1;
          _totalCartQuantity++;
        });
      }
      
      if (mounted) {
        setState(() => _addingToCart.remove(product.id));
      }
      
      await _loadCartQuantities();
      
      debugPrint('🏪 SHOP: Sepet güncellendi - toplam badge: $_totalCartQuantity');
    } catch (e) {
      debugPrint('❌ SHOP: Sepete eklenirken hata: $e');
      if (mounted) {
        setState(() => _addingToCart.remove(product.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    }
  }

  Future<void> _updateQuantity(Product product, int newQuantity) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final cartItems = await _cartService.getCartItems(userId);
      final cartItem = cartItems.firstWhere(
        (item) => item.productId == product.id,
        orElse: () => throw Exception('Ürün sepette bulunamadı'),
      );
      
      if (newQuantity <= 0) {
        await _cartService.removeFromCart(cartItem.id);
        
        if (mounted) {
          try {
            context.read<CartProvider>().loadCart();
          } catch (e) {
            debugPrint('INFO: CartProvider bulunamadı (normal bir durum)');
          }
        }
        
        if (mounted) {
          setState(() {
            _cartQuantities.remove(product.id);
            _totalCartQuantity = _totalCartQuantity > 0 ? _totalCartQuantity - 1 : 0;
          });
        }
      } else {
        final oldQuantity = _cartQuantities[product.id] ?? 0;
        await _cartService.updateCartItemQuantity(cartItem.id, newQuantity);
        
        if (mounted) {
          try {
            context.read<CartProvider>().loadCart();
          } catch (e) {
            debugPrint('INFO: CartProvider bulunamadı (normal bir durum)');
          }
        }
        
        if (mounted) {
          setState(() {
            _cartQuantities[product.id] = newQuantity;
            _totalCartQuantity = _totalCartQuantity - oldQuantity + newQuantity;
          });
        }
      }
      
      await _loadCartQuantities();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    }
  }

  Future<void> _loadShopData() async {
    setState(() => _isLoading = true);

    try {
      // Shop verisini fresh olarak çek (cache bypass)
      final shopResponse = await Supabase.instance.client
          .from('shops')
          .select()
          .eq('id', widget.shopId)
          .maybeSingle();
      
      if (shopResponse == null) {
        throw Exception('Dükkan bulunamadı');
      }
      
      final shop = Shop.fromJson(shopResponse);
      final products = await _productService.getShopProducts(widget.shopId);

      // Global sipariş durumunu kontrol et
      try {
        final appSettings = await Supabase.instance.client
            .from('app_about_settings')
            .select('global_orders_enabled')
            .limit(1)
            .maybeSingle();
        if (appSettings != null) {
          _globalOrdersEnabled = appSettings['global_orders_enabled'] as bool? ?? true;
        }
      } catch (_) {}

      // DEBUG: Teslimat ayarlarını kontrol et
      debugPrint('🏪 SHOP DETAIL: Shop loaded - ID: ${shop.id}');
      debugPrint('🏪 SHOP DETAIL: isAcceptingOrders: ${shop.isAcceptingOrders}');
      debugPrint('🏪 SHOP DETAIL: globalOrdersEnabled: $_globalOrdersEnabled');

      setState(() {
        _shop = shop;
        _products = products;
        _filteredProducts = products;
        _isLoading = false;
      });
      
      // Ürünler yüklendikten sonra kategorileri çıkar
      _extractCategories();
    } catch (e) {
      debugPrint('❌ SHOP DETAIL: Hata: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dükkan bilgileri yüklenirken bir sorun oluştu. ${AppErrorHandler.handleError(e)}')),
        );
      }
    }
  }

  // Dükkandaki benzersiz kategorileri çıkar
  List<String> _availableCategories = [];
  
  void _extractCategories() {
    final categories = _products
        .map((p) => p.category)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    _availableCategories = categories..sort();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dükkan'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Shop header skeleton
            Skeletons.detailHeader(),
            const SizedBox(height: 24),
            // Products grid skeleton (shrinkWrap ile)
            Skeletons.grid(itemCount: 6),
          ],
        ),
      );
    }

    if (_shop == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Dükkan bulunamadı')),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with Banner
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ürün ara...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      border: InputBorder.none,
                    ),
                  )
                : null,
            actions: [
              // Mağaza paylaş butonu
              if (!_isSearching && _shop != null)
                IconButton(
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                  onPressed: () {
                    final shopUrl = 'https://cizreapp.com/s/${_shop!.slug}';
                    Clipboard.setData(ClipboardData(text: shopUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Mağaza linki kopyalandı: $shopUrl'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  tooltip: 'Mağazayı Paylaş',
                ),
              // Arama ikonu
              if (!_isSearching)
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _isSearching = true;
                    });
                  },
                )
              else
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _isSearching = false;
                    });
                  },
                ),
              
              // Mesaj ikonu geçici olarak gizli
              // IconButton(
              //   icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              //   onPressed: () async {
              //     if (_shop?.ownerId == null) return;
              //
              //     final currentUserId = Supabase.instance.client.auth.currentUser?.id;
              //     if (currentUserId == _shop!.ownerId) {
              //       ScaffoldMessenger.of(context).showSnackBar(
              //         const SnackBar(content: Text('Kendi mağazanıza mesaj gönderemezsiniz')),
              //       );
              //       return;
              //     }
              //
              //     // Chat konuşmasını aç veya oluştur
              //     final conversation = await _chatService.getOrCreateConversation(_shop!.ownerId);
              //     if (conversation != null && mounted) {
              //       // Satıcı bilgilerini al
              //       final sellerResponse = await Supabase.instance.client
              //           .from('profiles')
              //           .select('full_name, avatar_url')
              //           .eq('id', _shop!.ownerId)
              //           .maybeSingle();
              //
              //       if (mounted) {
              //         Navigator.push(
              //           context,
              //           MaterialPageRoute(
              //             builder: (context) => ChatDetailScreen(
              //               conversationId: conversation.id,
              //               otherUserId: _shop!.ownerId,
              //               otherUserName: sellerResponse?['full_name'] ?? _shop!.name,
              //               otherUserAvatar: sellerResponse?['avatar_url'],
              //             ),
              //           ),
              //         );
              //       }
              //     } else if (mounted) {
              //       ScaffoldMessenger.of(context).showSnackBar(
              //         const SnackBar(content: Text('Konuşma açılamadı')),
              //       );
              //     }
              //   },
              // ),
              
              // Sepet icon
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const shop_cart.CartScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          Icons.shopping_cart_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                        if (_totalCartQuantity > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF3D00),
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                _totalCartQuantity > 9 ? '9+' : '$_totalCartQuantity',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
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
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_shop!.name),
              background: _shop!.bannerUrl != null
                  ? Image.network(
                      _shop!.bannerUrl!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.store, size: 80),
                    ),
            ),
          ),

          // Geçici Kapalı veya Global Kapalı Banner
          if (!_globalOrdersEnabled || (_shop != null && !_shop!.isAcceptingOrders))
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.red.shade50,
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red.shade700, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            !_globalOrdersEnabled
                                ? '🚫 Sipariş Alma Geçici Olarak Kapalı'
                                : '🚫 Geçici Kapalı',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            !_globalOrdersEnabled
                                ? 'Tüm mağazalarda sipariş alma geçici olarak durduruldu.'
                                : 'Bu dükkan şu anda sipariş almıyor.',
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Shop Info
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                          image: _shop!.logoUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(_shop!.logoUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _shop!.logoUrl == null
                            ? const Icon(Icons.store, size: 40)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _shop!.name,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_shop!.isVerified) ...[
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.verified,
                                    size: 16,
                                    color: Colors.blue,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _shop!.isOpen ? Colors.green : Colors.red,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _shop!.isOpen ? 'Açık' : 'Kapalı',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Kompakt Değerlendirme
                                GestureDetector(
                                  onTap: () {
                                    if (_reviews.isEmpty) {
                                      _showReviewDialog();
                                    } else {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        builder: (context) => DraggableScrollableSheet(
                                          initialChildSize: 0.9,
                                          minChildSize: 0.5,
                                          maxChildSize: 0.95,
                                          expand: false,
                                          builder: (context, scrollController) {
                                            return Container(
                                              padding: const EdgeInsets.all(16),
                                              child: Column(
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        'Tüm Değerlendirmeler',
                                                        style: Theme.of(context).textTheme.titleLarge,
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.close),
                                                        onPressed: () => Navigator.pop(context),
                                                      ),
                                                    ],
                                                  ),
                                                  const Divider(),
                                                  Expanded(
                                                    child: ListView.separated(
                                                      controller: scrollController,
                                                      itemCount: _reviews.length,
                                                      separatorBuilder: (context, index) => const Divider(height: 24),
                                                      itemBuilder: (context, index) {
                                                        return _buildReviewCard(_reviews[index]);
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.amber.shade200, width: 0.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star, size: 10, color: Colors.amber),
                                        const SizedBox(width: 2),
                                        Text(
                                          _shop!.rating.toStringAsFixed(1),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '(${_reviews.length})',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
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
                  
                  if (_shop!.description != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _shop!.description!,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],

                  // Admin tarafından gizlendi (geçici)
                  // if (_shop!.address != null) ...[
                  //   const SizedBox(height: 16),
                  //   Row(
                  //     children: [
                  //       const Icon(Icons.location_on, size: 20),
                  //       const SizedBox(width: 8),
                  //       Expanded(
                  //         child: Text(_shop!.address!),
                  //       ),
                  //     ],
                  //   ),
                  // ],

                  // if (_shop!.phone != null) ...[
                  //   const SizedBox(height: 8),
                  //   Row(
                  //     children: [
                  //       const Icon(Icons.phone, size: 20),
                  //       const SizedBox(width: 8),
                  //       Text(_shop!.phone!),
                  //     ],
                  //   ),
                  // ],

                  // Teslimat Bilgileri - Kompakt
                  const SizedBox(height: 12),
                  
                  // Kompakt Teslimat Bilgileri
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.delivery_dining, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Teslimat',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (_shop!.deliveryTime != null)
                                    Text(
                                      _shop!.deliveryTime!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  if (_shop!.deliveryTime != null) const SizedBox(width: 8),
                                  Text(
                                    _shop!.deliveryFee > 0
                                        ? '₺${_shop!.deliveryFee.toStringAsFixed(0)}'
                                        : 'Ücretsiz',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _shop!.deliveryFee > 0
                                          ? Colors.orange.shade700
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                  if (_shop!.minOrderAmount > 0) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      'Min. ₺${_shop!.minOrderAmount.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_shop!.freeDeliveryMinAmount != null && _shop!.freeDeliveryMinAmount! > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '₺${_shop!.freeDeliveryMinAmount!.toStringAsFixed(0)} üzeri ücretsiz',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Kuponlar
                  if (_shopCoupons.isNotEmpty) ...[
                    SizedBox(
                      height: 62,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _shopCoupons.length,
                        // ignore: unnecessary_underscores
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final coupon = _shopCoupons[index];
                          final discountType = coupon['discount_type'] ?? 'fixed_amount';
                          final discountValue = (coupon['discount_value'] ?? 0).toDouble();
                          final minOrder = (coupon['minimum_order_amount'] ?? 0).toDouble();
                          final code = coupon['code'] ?? '';
                          final endDate = coupon['end_date'] != null ? DateTime.tryParse(coupon['end_date'].toString()) : null;
                          
                          // Kalan süreyi hesapla
                          String? remainingTime;
                          if (endDate != null) {
                            final diff = endDate.difference(DateTime.now());
                            if (diff.inHours < 24) {
                              remainingTime = '${diff.inHours}s ${diff.inMinutes % 60}dk kaldı';
                            } else if (diff.inDays < 7) {
                              remainingTime = '${diff.inDays} gün kaldı';
                            }
                          }
                          
                          return InkWell(
                            onTap: () {
                              // Kupon kodunu panoya kopyala
                              Clipboard.setData(ClipboardData(text: code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.white),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Kupon kodu kopyalandı: $code\nSepette indirim kutusuna yapıştırın!',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 3),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.orange.shade50,
                                    Colors.orange.shade100,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.shade300,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.confirmation_number,
                                    color: Colors.orange.shade700,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        discountType == 'percentage'
                                            ? '%${discountValue.toStringAsFixed(0)} İndirim'
                                            : '₺${discountValue.toStringAsFixed(0)} İndirim',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            minOrder > 0
                                                ? '₺${minOrder.toStringAsFixed(0)}+ | Kod: $code'
                                                : 'Kod: $code',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange.shade600,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.copy,
                                            size: 12,
                                            color: Colors.orange.shade600,
                                          ),
                                        ],
                                      ),
                                      if (remainingTime != null) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.access_time,
                                              size: 10,
                                              color: Colors.red.shade600,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              remainingTime,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.red.shade600,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Kategoriler - Yatay scroll
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Tümü
                        _buildCategoryChip(null, 'Tümü'),
                        const SizedBox(width: 6),
                        // Kategoriler
                        ..._availableCategories.map((cat) => _buildCategoryChip(cat, cat)),
                        const SizedBox(width: 6),
                        // Stok filtresi
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showOnlyInStock = !_showOnlyInStock;
                              _applyFilters();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _showOnlyInStock
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _showOnlyInStock
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showOnlyInStock ? Icons.check_circle : Icons.circle_outlined,
                                  size: 14,
                                  color: _showOnlyInStock ? Colors.white : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Stokta',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _showOnlyInStock ? Colors.white : Colors.grey.shade700,
                                    fontWeight: _showOnlyInStock ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Filtre sonucu - compact
                  if (_searchController.text.isNotEmpty ||
                      _selectedCategory != null ||
                      _showOnlyInStock) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '${_filteredProducts.length} ürün bulundu',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    'Ürünler (${_filteredProducts.length}/${_products.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),

          // Products Grid
          _filteredProducts.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ürün bulunamadı',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Filtreleri değiştirmeyi deneyin',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: 16 + MediaQuery.of(context).padding.bottom + 60,
                  ),
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
                        return _buildProductCard(product);
                      },
                      childCount: _filteredProducts.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ShopReview review) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: review.userAvatar != null
                  ? NetworkImage(review.userAvatar!)
                  : null,
              child: review.userAvatar == null
                  ? Text(
                      review.userName?.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    review.userName ?? 'Anonim',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < review.rating ? Icons.star : Icons.star_border,
                            size: 14,
                            color: Colors.amber,
                          );
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatFullDate(review.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (review.comment != null && review.comment!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            review.comment!,
            style: const TextStyle(fontSize: 14),
          ),
        ],
        // Satıcı cevabı
        if (review.hasSellerReply) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.store, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Satıcı Cevabı',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (review.sellerRepliedAt != null)
                      Text(
                        _formatFullDate(review.sellerRepliedAt!),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  review.sellerReply!,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// UTC tarihi Türkiye saatine çevir (UTC+3)
  DateTime _toTurkeyTime(DateTime utcDate) {
    return utcDate.isUtc ? utcDate.add(const Duration(hours: 3)) : utcDate;
  }

  String _formatDate(DateTime date) {
    // UTC ise Türkiye saatine çevir
    final turkeyTime = _toTurkeyTime(date);
    final now = DateTime.now();
    final diff = now.difference(turkeyTime);
    
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return 'Az önce';
        }
        return '${diff.inMinutes} dakika önce';
      }
      return '${diff.inHours} saat önce';
    } else if (diff.inDays == 1) {
      return 'Dün';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} gün önce';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()} hafta önce';
    } else if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()} ay önce';
    } else {
      return '${(diff.inDays / 365).floor()} yıl önce';
    }
  }

  /// Tam tarih formatı (Türkiye saati)
  String _formatFullDate(DateTime date) {
    final turkeyTime = _toTurkeyTime(date);
    final day = turkeyTime.day.toString().padLeft(2, '0');
    final month = turkeyTime.month.toString().padLeft(2, '0');
    final year = turkeyTime.year;
    final hour = turkeyTime.hour.toString().padLeft(2, '0');
    final minute = turkeyTime.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  Widget _buildProductCard(Product product) {
    final isAdding = _addingToCart.contains(product.id);
    final isInStock = product.inStock;
    final theme = Theme.of(context);
    
    final cartQuantity = _getCartQuantity(product.id);
    final inCart = _isInCart(product.id);
    
    // Mağaza geçici olarak sipariş almıyor mu kontrol et
    final isShopClosed = _shop != null && !_shop!.isAcceptingOrders;

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
                  // Mağaza kapalı overlay
                  if (isShopClosed)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.4),
                        child: const Center(
                          child: Text(
                            'Kapalı',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
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
                            onPressed: (isAdding || !isInStock || isShopClosed)
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

  Widget _buildCategoryChip(String? category, String label) {
    final isSelected = _selectedCategory == category;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = category;
          _applyFilters();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
