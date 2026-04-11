// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/shop_model.dart';
import '../../../core/models/product_review_model.dart';
import '../../../core/providers/favorites_provider.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../services/product_service.dart';
import '../services/shop_service.dart';
import '../services/product_review_service.dart';
import '../providers/cart_provider.dart';
import '../../seller/services/shop_analytics_service.dart';
import 'cart_screen.dart';
import 'shop_detail_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ProductService _productService = ProductService();
  final ShopService _shopService = ShopService();
  final ShopAnalyticsService _analyticsService = ShopAnalyticsService();
  final ProductReviewService _reviewService = ProductReviewService();

  Product? _product;
  Shop? _shop;
  bool _isLoading = true;
  int _selectedImageIndex = 0;
  int _quantity = 1;
  bool _isFavorite = false;

  // Varyant seçimleri
  String? _selectedSize;
  int? _selectedShoeSize;
  ProductColor? _selectedColor;

  // Zoom için TransformationController
  final TransformationController _transformationController = TransformationController();

  // Review state
  List<ProductReview> _reviews = [];
  Map<String, dynamic> _ratingStats = {'average': 0.0, 'count': 0, 'distribution': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}};
  bool _isLoadingReviews = true;
  bool _canReview = false;
  ProductReview? _userReview;
  final GlobalKey _reviewsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadProductData();
    _checkFavoriteStatus();
    _loadReviews();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadProductData() async {
    setState(() => _isLoading = true);

    try {
      final product = await _productService.getProductById(widget.productId);
      
      // Ürün görüntülemeyi kaydet
      _analyticsService.recordProductView(widget.productId, product.shopId);
      final shop = await _shopService.getShopById(product.shopId);
      setState(() {
        _product = product;
        _shop = shop;
        _isLoading = false;
      });

      // Varyantlı ürünlerde varsayılan seçimleri yap
      if (product.productType == 'clothing' && product.sizes.isNotEmpty) {
        _selectedSize = product.sizes.first;
      }
      if (product.productType == 'shoes' && product.shoeSizes.isNotEmpty) {
        _selectedShoeSize = product.shoeSizes.first;
      }
      if (product.colors.isNotEmpty) {
        _selectedColor = product.colors.first;
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ürün bilgileri yüklenirken bir sorun oluştu. ${AppErrorHandler.handleError(e)}')),
        );
      }
    }
  }

  Future<void> _checkFavoriteStatus() async {
    if (!mounted) return;
    final favoritesProvider = context.read<FavoritesProvider>();
    final isFavorited = favoritesProvider.isProductFavorited(widget.productId);
    if (mounted) {
      setState(() => _isFavorite = isFavorited);
    }
  }

  Future<void> _toggleFavorite() async {
    final favoritesProvider = context.read<FavoritesProvider>();
    try {
      final isAdded = await favoritesProvider.toggleProductFavorite(widget.productId);
      setState(() => _isFavorite = isAdded);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAdded ? 'Favorilere eklendi' : 'Favorilerden çıkarıldı'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    }
  }

  // Reviews methods
  Future<void> _loadReviews({int offset = 0}) async {
    if (!mounted) return;
    
    setState(() => _isLoadingReviews = true);
    
    try {
      final reviews = await _reviewService.getProductReviews(widget.productId);
      final stats = await _reviewService.getProductRatingStats(widget.productId);
      
      final userId = Supabase.instance.client.auth.currentUser?.id;
      ProductReview? userReview;
      bool canReview = false;
      
      if (userId != null) {
        userReview = await _reviewService.getUserProductReview(widget.productId, userId);
        canReview = await _reviewService.hasPurchasedProduct(widget.productId, userId);
      }
      
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _ratingStats = stats;
          _userReview = userReview;
          _canReview = canReview;
          _isLoadingReviews = false;
        });
      }
    } catch (e) {
      debugPrint('Yorumlar yüklenirken hata: $e');
      if (mounted) {
        setState(() => _isLoadingReviews = false);
      }
    }
  }

  void _scrollToReviews() {
    final context = _reviewsSectionKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _showAddReviewDialog() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yorum yapmak için giriş yapmalısınız')),
        );
      }
      return;
    }

    if (!_canReview) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yorum yapmak için ürünü satın almış ve teslim almış olmanız gerekir')),
        );
      }
      return;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _buildAddReviewBottomSheet(existingReview: _userReview),
      ),
    );

    if (result != null && mounted) {
      try {
        if (_userReview != null) {
          await _reviewService.updateReview(
            reviewId: _userReview!.id,
            rating: result['rating'] as int,
            comment: result['comment'] as String?,
          );
        } else {
          await _reviewService.addReview(
            productId: widget.productId,
            userId: userId,
            rating: result['rating'] as int,
            comment: result['comment'] as String?,
          );
        }
        await _loadReviews();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_userReview != null ? 'Yorumunuz güncellendi' : 'Yorumunuz eklendi')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('İşlem başarısız: $e')),
          );
        }
      }
    }
  }

  bool get _canAddToCart {
    if (_product == null) return false;
    
    // Varyantlı ürün için seçim kontrolü
    if (_product!.hasVariants) {
      if (_product!.colors.isEmpty) return false;
      if (_selectedColor == null) return false;
      
      if (_product!.isClothing && _selectedSize == null) return false;
      if (_product!.isShoes && _selectedShoeSize == null) return false;
      
      // Seçilen rengin stoğu kontrolü
      if (_selectedColor!.stock <= 0) return false;
    }
    
    return _product!.stockQuantity > 0;
  }

  String get _cartButtonText {
    if (_product == null) return 'Sepete Ekle';
    
    if (!_product!.inStock) return 'Tükendi';
    
    if (_product!.hasVariants) {
      if (_selectedColor == null) return 'Renk Seçin';
      if (_selectedColor!.stock <= 0) return 'Stokta Yok';
      if (_product!.isClothing && _selectedSize == null) return 'Beden Seçin';
      if (_product!.isShoes && _selectedShoeSize == null) return 'Numara Seçin';
    }
    
    return 'Sepete Ekle';
  }

  Future<void> _addToCart() async {
    if (!_canAddToCart) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen giriş yapın')),
        );
      }
      return;
    }

    try {
      CartProvider cartProvider;
      try {
        cartProvider = context.read<CartProvider>();
      } catch (e) {
        cartProvider = CartProvider(userId);
      }

      // Varyant bilgilerini hazırla
      final variantData = <String, dynamic>{};
      if (_product!.hasVariants && _selectedColor != null) {
        variantData['color'] = _selectedColor!.name;
        if (_selectedSize != null) variantData['size'] = _selectedSize;
        if (_selectedShoeSize != null) variantData['shoeSize'] = _selectedShoeSize.toString();
      }

      await cartProvider.addToCart(
        _product!.id,
        quantity: _quantity,
        variantData: variantData.isNotEmpty ? variantData : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_quantity adet ${_product!.name} sepete eklendi'),
            action: SnackBarAction(
              label: 'Sepete Git',
              onPressed: _goToCart,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sepete eklenirken hata: $e')),
        );
      }
    }
  }

  void _goToCart() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (_) => CartProvider(userId),
          child: const CartScreen(),
        ),
      ),
    );
  }

  void _goToShop() {
    if (_shop == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopDetailScreen(shopId: _shop!.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ürün Detayı'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image skeleton
              SkeletonLoader.rect(height: 300, borderRadius: BorderRadius.circular(12)),
              const SizedBox(height: 24),
              // Product info skeleton
              SkeletonLoader.text(width: 200, height: 28),
              const SizedBox(height: 12),
              SkeletonLoader.text(width: 150, height: 20),
              const SizedBox(height: 16),
              SkeletonLoader.text(width: 100, height: 36),
              const SizedBox(height: 24),
              // Description skeleton
              SkeletonLoader.text(width: 120, height: 16),
              const SizedBox(height: 8),
              SkeletonLoader.text(height: 14),
              const SizedBox(height: 4),
              SkeletonLoader.text(height: 14),
              const SizedBox(height: 4),
              SkeletonLoader.text(width: 180, height: 14),
              const SizedBox(height: 24),
              // Shop info skeleton
              SkeletonLoader.text(width: 100, height: 16),
              const SizedBox(height: 12),
              Skeletons.listItem(),
              const SizedBox(height: 24),
              // Reviews section skeleton
              SkeletonLoader.text(width: 120, height: 16),
              const SizedBox(height: 12),
              Skeletons.comment(),
            ],
          ),
        ),
      );
    }

    if (_product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Ürün bulunamadı')),
      );
    }

    final product = _product!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürün Detayı'),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: Colors.red,
            ),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image Gallery with Zoom
                if (product.images.isNotEmpty) ...[
                  _buildImageGallery(product),
                ],

                // Product Info
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Name
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),

                      // Rating (Tıklanabilir - yorumlara kaydır)
                      InkWell(
                        onTap: _scrollToReviews,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Icon(Icons.star, size: 20, color: Colors.amber.shade600),
                            const SizedBox(width: 4),
                            Text(
                              '${product.rating.toStringAsFixed(1)} (${product.totalReviews} değerlendirme)',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade500),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Price - İndirim varsa eski fiyat üstü çizili, indirimli fiyat büyük gösterilir
                      if (product.hasDiscount) ...[
                        // Eski fiyat (üstü çizili)
                        if (product.displayOldPrice != null)
                          Text(
                            '₺${product.displayOldPrice!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        Row(
                          children: [
                            // İndirimli fiyat (effectivePrice - discount_price veya normal price)
                            Text(
                              '₺${product.effectivePrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '%${product.discountPercentage?.toStringAsFixed(0) ?? '0'} İndirim',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else
                        // İndirim yoksa normal fiyat
                        Text(
                          '₺${product.effectivePrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 28,
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Stock Status
                      if (product.stockQuantity > 0)
                        const Chip(
                          label: Text(
                            'Stokta Var',
                            style: TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.green,
                        )
                      else
                        const Chip(
                          label: Text(
                            'Tükendi',
                            style: TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.red,
                        ),

                      const SizedBox(height: 16),

                      // Description
                      if (product.description != null) ...[
                        Text(
                          'Ürün Açıklaması',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          product.description!,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Variant Selection
                      if (product.hasVariants) ...[
                        _buildVariantSelector(product),
                        const SizedBox(height: 16),
                      ],

                      // Shop Info (Tappable)
                      if (_shop != null) ...[
                        _buildShopInfo(),
                        const SizedBox(height: 24),
                      ],

                      // Quantity Selector
                      _buildQuantitySelector(product),
                    ],
                  ),
                ),

                // ========== Değerlendirmeler Bölümü ==========
                Padding(
                  key: _reviewsSectionKey,
                  padding: const EdgeInsets.all(16),
                  child: _buildReviewsSection(product),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _canAddToCart ? () => _addToCart() : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    icon: const Icon(Icons.shopping_cart),
                    label: Text(_cartButtonText),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _goToCart(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(Icons.shopping_bag),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageGallery(Product product) {
    return Container(
      color: Colors.grey.shade100,
      child: Column(
        children: [
          // Main Image with Zoom
          SizedBox(
            height: 350,
            width: double.infinity,
            child: GestureDetector(
              onDoubleTap: () {
                // Çift tıklama ile zoom yap
                final Matrix4 currentMatrix = _transformationController.value;
                if (currentMatrix.getMaxScaleOnAxis() == 1.0) {
                  // Zoom in - 2x
                  _transformationController.value = Matrix4.identity()..scale(2.0);
                } else {
                  // Zoom out
                  _transformationController.value = Matrix4.identity();
                }
              },
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1.0,
                maxScale: 4.0,
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                child: Image.network(
                  product.images[_selectedImageIndex],
                  fit: BoxFit.contain,
                  // ignore: unnecessary_underscores
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image, size: 64, color: Colors.grey),
                  ),
                  loadingBuilder: (_, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // Thumbnail Images
          if (product.images.length > 1)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: product.images.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedImageIndex = index);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedImageIndex == index
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            width: _selectedImageIndex == index ? 3 : 1,
                          ),
                          image: DecorationImage(
                            image: NetworkImage(product.images[index]),
                            fit: BoxFit.cover,
                          ),
                        ),
                        width: 80,
                      ),
                    );
                  },
                ),
              ),
            ),
          // Zoom hint
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Yakınlaştırmak için iki parmağınızla sıkıştırın veya resme iki kez dokunun',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantSelector(Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Renk Seçimi
        if (product.colors.isNotEmpty) ...[
          Text(
            'Renk: ${_selectedColor?.name ?? 'Seçin'}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: product.colors.map((color) {
              final isSelected = _selectedColor?.name == color.name;
              final isOutOfStock = color.stock <= 0;
              return GestureDetector(
                onTap: isOutOfStock ? null : () {
                  setState(() => _selectedColor = color);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOutOfStock
                        ? Colors.grey.shade200
                        : isSelected
                            ? Colors.orange.shade200
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.orange.shade700 : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        backgroundColor: Color(int.parse(color.hex.replaceFirst('#', '0xFF'))),
                        radius: 10,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${color.name} (${color.stock})',
                        style: TextStyle(
                          color: isOutOfStock ? Colors.grey.shade500 : Colors.black,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Beden Seçimi (Giyim)
        if (product.isClothing && product.sizes.isNotEmpty) ...[
          Text(
            'Beden: ${_selectedSize ?? 'Seçin'}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: product.sizes.map((size) {
              final isSelected = _selectedSize == size;
              return FilterChip(
                label: Text(size),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedSize = selected ? size : null);
                },
                selectedColor: Colors.orange.shade200,
                checkmarkColor: Colors.orange.shade700,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Numara Seçimi (Ayakkabı)
        if (product.isShoes && product.shoeSizes.isNotEmpty) ...[
          Text(
            'Numara: ${_selectedShoeSize ?? 'Seçin'}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: product.shoeSizes.map((size) {
              final isSelected = _selectedShoeSize == size;
              return FilterChip(
                label: Text(size.toString()),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedShoeSize = selected ? size : null);
                },
                selectedColor: Colors.orange.shade200,
                checkmarkColor: Colors.orange.shade700,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildShopInfo() {
    return GestureDetector(
      onTap: _goToShop,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                image: _shop!.logoUrl != null
                    ? DecorationImage(
                        image: NetworkImage(_shop!.logoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _shop!.logoUrl == null
                  ? const Icon(Icons.store, size: 24)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shop!.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Dükkanı Gör →',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade600,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantitySelector(Product product) {
    final maxQuantity = product.hasVariants && _selectedColor != null
        ? _selectedColor!.stock
        : product.stockQuantity;

    return Row(
      children: [
        Text(
          'Miktar:',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _quantity > 1
                    ? () {
                        setState(() => _quantity--);
                      }
                    : null,
              ),
              SizedBox(
                width: 40,
                child: Text(
                  _quantity.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _quantity < maxQuantity
                    ? () {
                        setState(() => _quantity++);
                      }
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (product.hasVariants && _selectedColor != null)
          Text(
            'Stok: $maxQuantity',
            style: TextStyle(color: Colors.grey.shade600),
          ),
      ],
    );
  }

  Widget _buildReviewsSection(Product product) {
    final distribution = _ratingStats['distribution'] as Map<int, int>? ?? {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    final average = _ratingStats['average'] as double? ?? 0.0;
    final count = _ratingStats['count'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Başlık
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Değerlendirmeler',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (_canReview)
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Yorum Ekle'),
                onPressed: _showAddReviewDialog,
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Ortalama Puan Özeti
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    average.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            Icons.star,
                            size: 20,
                            color: index < average.floor()
                                ? Colors.amber
                                : Colors.grey.shade300,
                          );
                        }),
                      ),
                      Text('$count değerlendirme'),
                      if (count > 0)
                        Text(' / ${count == 1 ? 'kişi' : 'kişi'}'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Puan Dağılımı (Bar Chart)
              ...List.generate(5, (starIndex) {
                final starLevel = 5 - starIndex; // 5, 4, 3, 2, 1
                final starCount = distribution[starLevel] ?? 0;
                final maxCount = count > 0 ? count : 1;
                final percentage = maxCount > 0 ? (starCount / maxCount * 100).clamp(0.0, 100.0) : 0.0;
                final barWidth = percentage * 3; // 300px max width

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // ignore: unnecessary_brace_in_string_interps
                          Text('${starLevel}'),
                          const SizedBox(width: 8),
                          Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Stack(
                              children: [
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 500),
                                  width: barWidth.toDouble(),
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.amber,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$starCount'),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Kullanıcının kendi yorumu varsa göster
        if (_userReview != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bu ürünü değerlendirdiniz',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      Text(
                        'Puanınız: ${_userReview!.rating} ★',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (_userReview!.comment != null)
                        Text(
                          _userReview!.comment!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Yorumu Sil'),
                        content: const Text('Yorumunuzu silmek istediğinizden emin misiniz?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('İptal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sil'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      try {
                        await _reviewService.deleteReview(_userReview!.id, widget.productId);
                        await _loadReviews();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Yorumunuz silindi')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Silme işlemi başarısız: $e')),
                          );
                        }
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Yorumlar Listesi
        if (_isLoadingReviews)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_reviews.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.reviews, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Henüz değerlendirme yok',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Bu ürünü satın alan ilk kişi değerlendirme yapabilir.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          ...List.generate(_reviews.length, (index) {
            final review = _reviews[index];
            return _ReviewCard(
              review: review,
              product: product,
              onReply: () async {
                // Satıcı cevap özelliği (opsiyonel)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Satıcı cevabı yakında eklenecek')),
                );
              },
            );
          }),

        // Daha fazla yükle butonu
        if (!_isLoadingReviews && _reviews.length >= 10)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () async {
                  await _loadReviews(offset: _reviews.length);
                },
                child: const Text('Daha fazla göster'),
              ),
            ),
          ),
      ],
    );
  }

  // Yorum Ekle Bottom Sheet
  Widget _buildAddReviewBottomSheet({required ProductReview? existingReview}) {
    final rating = existingReview?.rating ?? 0;
    final commentController = TextEditingController(text: existingReview?.comment ?? '');

    return StatefulBuilder(
      builder: (context, setBottomState) {
        int selectedRating = rating;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    existingReview != null ? 'Yorumunuzu Güncelleyin' : 'Değerlendirme Yapın',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Puan Seçimi
              Text(
                'Bu ürünü nasıl buldunuz?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (index) {
                  final starLevel = 5 - index;
                  return InkWell(
                    onTap: () {
                      setBottomState(() {
                        selectedRating = starLevel;
                      });
                    },
                    child: Column(
                      children: [
                        Icon(
                          Icons.star,
                          size: 32,
                          color: selectedRating >= starLevel
                              ? Colors.amber
                              : Colors.grey.shade300,
                        ),
                      ],
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // Yorum Metni
              TextField(
                controller: commentController,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'Deneyiminizi paylaşın...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                  ),
                  counterText: '${commentController.text.length}/500',
                ),
              ),
              const SizedBox(height: 16),

              // Gönder Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selectedRating > 0
                      ? () {
                          Navigator.pop(context, {
                            'rating': selectedRating,
                            'comment': commentController.text.trim().isEmpty
                                ? null
                                : commentController.text.trim(),
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: Text(
                    existingReview != null ? 'Değerlendirmeyi Güncelle' : 'Gönder',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Yorum Kartı Widget
class _ReviewCard extends StatelessWidget {
  final ProductReview review;
  final Product product;
  final VoidCallback? onReply;

  const _ReviewCard({
    required this.review,
    required this.product,
    this.onReply,
  });

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years yıl önce';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ay önce';
    } else if (difference.inDays > 7) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks hafta önce';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} gün önce';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} saat önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} dakika önce';
    } else {
      return 'Az önce';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Kullanıcı bilgisi ve puan
            Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundImage: review.userAvatar != null
                      ? NetworkImage(review.userAvatar!)
                      : null,
                  child: review.userName != null
                      ? Text(
                          review.userName![0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )
                      : const Icon(Icons.person),
                ),
                const SizedBox(width: 12),
                // Kullanıcı adı ve tarih
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.userName ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _formatTimeAgo(review.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Puan (yıldızlar)
                Row(
                  children: List.generate(5, (index) {
                    return Icon(
                      Icons.star,
                      size: 16,
                      color: index < review.rating ? Colors.amber : Colors.grey.shade300,
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Yorum metni
            if (review.comment != null && review.comment!.isNotEmpty)
              Text(
                review.comment!,
                style: const TextStyle(fontSize: 14),
              ),

            // Satıcı cevabı varsa
            if (review.hasSellerReply) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Satıcı Cevabı',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      review.sellerReply!,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      review.sellerRepliedAt != null
                          ? _formatTimeAgo(review.sellerRepliedAt!)
                          : '',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
