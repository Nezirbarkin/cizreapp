// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/product_model.dart';
import '../../market/services/product_service.dart';
import 'manage_product_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _supabase = Supabase.instance.client;
  final _productService = ProductService();

  bool _isLoading = true;
  List<Product> _products = [];
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, inStock, outOfStock

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Satıcının mağazasını bul
      final shopResponse = await _supabase
          .from('shops')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse == null) {
        setState(() {
          _products = [];
          _isLoading = false;
        });
        return;
      }

      final shopId = shopResponse['id'] as String;

      // Tüm ürünleri getir (stokta olmayanlar dahil)
      final response = await _supabase
          .from('products')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);

      setState(() {
        _products = (response as List)
            .map((json) => Product.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ürünler yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Product> get _filteredProducts {
    var filtered = _products;

    // Arama filtresi
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((p) =>
              p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (p.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false))
          .toList();
    }

    // Durum filtresi
    switch (_filterStatus) {
      case 'inStock':
        filtered = filtered.where((p) => p.inStock).toList();
        break;
      case 'outOfStock':
        filtered = filtered.where((p) => !p.inStock).toList();
        break;
      case 'hasDiscount':
        filtered = filtered.where((p) => p.hasDiscount).toList();
        break;
    }

    return filtered;
  }

  Future<void> _toggleSellerPinned(Product product) async {
    try {
      await _productService.toggleSellerPinned(
        product.id,
        !product.sellerPinned,
      );

      // Listeyi yenile
      final index = _products.indexWhere((p) => p.id == product.id);
      if (index != -1) {
        setState(() {
          _products[index] = product.copyWith(
            sellerPinned: !product.sellerPinned,
          );
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(product.sellerPinned ? 'Sabitleme kaldırıldı' : 'Ürün sabitlendi'),
            backgroundColor: product.sellerPinned ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  Future<void> _toggleAvailability(Product product) async {
    try {
      await _productService.toggleProductAvailability(
        product.id,
        !product.isAvailable,
      );

      // Listeyi yenile
      final index = _products.indexWhere((p) => p.id == product.id);
      if (index != -1) {
        setState(() {
          _products[index] = product.copyWith(
            isAvailable: !product.isAvailable,
          );
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(product.isAvailable ? 'Ürün satıştan kaldırıldı' : 'Ürün satışa açıldı'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: Text('${product.name} ürününü silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _productService.deleteProduct(product.id);
      setState(() {
        _products.removeWhere((p) => p.id == product.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün silindi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  void _navigateToEdit(Product product) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageProductScreen(product: product),
      ),
    );

    if (result == true) {
      _loadProducts();
    }
  }

  void _navigateToAdd() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManageProductScreen(),
      ),
    );

    if (result == true) {
      _loadProducts();
    }
  }

  void _showCategoryManagement() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Satıcının mağazasını bul
    final shopResponse = await _supabase
        .from('shops')
        .select('id, seller_categories')
        .eq('owner_id', userId)
        .maybeSingle();

    if (shopResponse == null) return;

    List<String> categories = [];
    if (shopResponse['seller_categories'] != null) {
      categories = List<String>.from(shopResponse['seller_categories'] as List);
    }

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: _CategoryManagementSheet(
            categories: categories,
          ),
        ),
      ),
    );

    if (result != null) {
      // Kategorileri güncelle
      try {
        await _supabase
            .from('shops')
            .update({'seller_categories': result})
            .eq('id', shopResponse['id']);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kategoriler güncellendi')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürünlerim'),
        backgroundColor: Colors.orange.shade700,
        actions: [
          // Kategori yönetimi butonu
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Kategoriler',
            onPressed: _showCategoryManagement,
          ),
          // Filtre butonu
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _filterStatus = value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('Tümü'),
              ),
              const PopupMenuItem(
                value: 'inStock',
                child: Text('Stokta Olanlar'),
              ),
              const PopupMenuItem(
                value: 'outOfStock',
                child: Text('Stokta Olmayanlar'),
              ),
              const PopupMenuItem(
                value: 'hasDiscount',
                child: Text('İndirimli Ürünler'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Arama çubuğu
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Ürün ara...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // Ürün listesi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadProducts,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            return _buildProductCard(product);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAdd,
        backgroundColor: Colors.orange.shade700,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Ürün'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'Henüz ürün eklenmemiş'
                : 'Sonuç bulunamadı',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _navigateToAdd,
              icon: const Icon(Icons.add),
              label: const Text('İlk Ürünü Ekle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final discountPercent = product.discountPercentage;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToEdit(product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Resim
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: product.imageUrl != null
                        ? Image.network(
                            product.imageUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildImagePlaceholder(),
                          )
                        : _buildImagePlaceholder(),
                  ),
                  // Sabitlenmiş badge
                  if (product.sellerPinned)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: const Icon(
                          Icons.push_pin,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Ürün bilgileri
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // İsim ve badge'ler
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.sellerPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.push_pin,
                              size: 14,
                              color: Colors.amber.shade700,
                            ),
                          ),
                        if (!product.isAvailable)
                          const Icon(
                            Icons.visibility_off,
                            size: 16,
                            color: Colors.grey,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Kategori
                    if (product.category != null)
                      Text(
                        product.category!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    const SizedBox(height: 8),

                    // Fiyat ve indirim
                    Row(
                      children: [
                        Text(
                          '₺${product.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                        if (product.hasDiscount) ...[
                          const SizedBox(width: 8),
                          Text(
                            '₺${product.oldPrice?.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '%$discountPercent',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Stok durumu
                    Row(
                      children: [
                        Icon(
                          product.inStock ? Icons.check_circle : Icons.cancel,
                          size: 14,
                          color: product.inStock ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          product.inStock
                              ? 'Stok: ${product.stockQuantity}'
                              : 'Stokta Yok',
                          style: TextStyle(
                            fontSize: 12,
                            color: product.inStock ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Sabitle ve Düzenle butonları
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sabitle butonu
                  IconButton(
                    icon: Icon(
                      product.sellerPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: product.sellerPinned ? Colors.amber.shade700 : Colors.grey,
                    ),
                    onPressed: () => _toggleSellerPinned(product),
                    tooltip: product.sellerPinned ? 'Sabitlemeyi Kaldır' : 'Sabitle',
                    iconSize: 20,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  // Düzenle butonu
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _navigateToEdit(product),
                    tooltip: 'Düzenle',
                    iconSize: 20,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: 80,
      height: 80,
      color: Colors.grey.shade300,
      child: const Icon(Icons.image, color: Colors.grey),
    );
  }
}

// Kategori yönetimi bottom sheet widget'ı
class _CategoryManagementSheet extends StatefulWidget {
  final List<String> categories;

  const _CategoryManagementSheet({required this.categories});

  @override
  State<_CategoryManagementSheet> createState() => _CategoryManagementSheetState();
}

class _CategoryManagementSheetState extends State<_CategoryManagementSheet> {
  late TextEditingController _categoryController;
  late List<String> _categories;

  @override
  void initState() {
    super.initState();
    _categories = List.from(widget.categories);
    _categoryController = TextEditingController();
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  void _addCategory() {
    final text = _categoryController.text.trim();
    if (text.isEmpty) return;
    
    if (_categories.contains(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu kategori zaten mevcut')),
      );
      return;
    }
    
    setState(() {
      _categories.add(text);
      _categoryController.clear();
    });
  }

  void _removeCategory(String category) {
    setState(() {
      _categories.remove(category);
    });
  }

  void _save() {
    Navigator.pop(context, _categories);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.white,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.category, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Kategoriler',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Kategori listesi
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: _categories.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.category_outlined, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text('Henüz kategori yok', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: _categories.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.label, size: 14, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    category,
                                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _removeCategory(category),
                                  child: Icon(Icons.close, size: 18, color: Colors.red.shade400),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              
              const Divider(height: 1),
              
              // Yeni kategori ekleme
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _categoryController,
                        decoration: InputDecoration(
                          hintText: 'Kategori adı girin',
                          hintStyle: const TextStyle(fontSize: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                        onSubmitted: (_) => _addCategory(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _addCategory,
                      icon: const Icon(Icons.add_circle, color: Colors.orange),
                      tooltip: 'Ekle',
                      iconSize: 28,
                    ),
                  ],
                ),
              ),
              
              // Kaydet butonu
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
