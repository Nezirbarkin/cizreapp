// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/flash_sale_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/widgets/product_extras_widgets.dart';
import '../../market/services/flash_sale_service.dart';
import '../../market/services/product_service.dart';
import 'manage_product_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  final _productService = ProductService();

  bool _isLoading = true;
  List<Product> _products = [];
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, inStock, outOfStock

  // ── Çoklu seçim (toplu indirim) ────────────────────────────────────────────
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isBulkWorking = false;

  /// Seçili ID'lerden hâlâ listede olanların ürün nesneleri. Arama/filtre
  /// değişince seçim korunur ama silinmiş ürünler otomatik düşer.
  List<Product> get _selectedProducts =>
      _products.where((p) => _selectedIds.contains(p.id)).toList();

  /// Toplu indirim yalnızca fiziksel ürünlere uygulanır; dijital ürünlerin
  /// fiyatı 1000 adet bazlı hesaplandığı için `discount_price` mantığına girmez.
  List<Product> get _discountableSelection =>
      _selectedProducts.where((p) => !p.isDigital).toList();

  void _enterSelectionMode(Product product) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(product.id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(Product product) {
    setState(() {
      if (!_selectedIds.remove(product.id)) {
        _selectedIds.add(product.id);
      }
      // Son seçim de kaldırıldıysa seçim modundan çık.
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _selectAllVisible() {
    final visible = _filteredProducts;
    final allSelected = visible.every((p) => _selectedIds.contains(p.id));
    setState(() {
      if (allSelected) {
        for (final p in visible) {
          _selectedIds.remove(p.id);
        }
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.addAll(visible.map((p) => p.id));
      }
    });
  }

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
        if (!mounted) return;
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

      if (!mounted) return;
      setState(() {
        _products = (response as List)
            .map((json) => Product.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ürünler yüklenirken hata: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Product> get _filteredProducts {
    var filtered = _products;

    // Arama filtresi
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (p) =>
                p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                (p.description?.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) ??
                    false),
          )
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
      if (index != -1 && mounted) {
        setState(() {
          _products[index] = product.copyWith(
            sellerPinned: !product.sellerPinned,
          );
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              product.sellerPinned ? 'Sabitleme kaldırıldı' : 'Ürün sabitlendi',
            ),
            backgroundColor: product.sellerPinned
                ? Colors.orange
                : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
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
      if (index != -1 && mounted) {
        setState(() {
          _products[index] = product.copyWith(
            isAvailable: !product.isAvailable,
          );
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              product.isAvailable
                  ? 'Ürün satıştan kaldırıldı'
                  : 'Ürün satışa açıldı',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: Text(
          '${product.name} ürününü silmek istediğinizden emin misiniz?',
        ),
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
      final deleted = await _productService.deleteProduct(product.id);
      if (!mounted) return;
      setState(() {
        if (deleted) {
          _products.removeWhere((p) => p.id == product.id);
        } else {
          final index = _products.indexWhere((p) => p.id == product.id);
          if (index != -1) {
            _products[index] = _products[index].copyWith(isAvailable: false);
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              deleted
                  ? 'Ürün silindi'
                  : 'Bu ürüne ait sipariş geçmişi olduğu için silinemedi, bunun yerine devre dışı bırakıldı.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  // ── Toplu işlemler ─────────────────────────────────────────────────────────

  /// Toplu indirim akışı: satıcı oran/tutar/sabit fiyat seçer, sunucu hesaplar.
  Future<void> _showBulkDiscountDialog() async {
    final targets = _discountableSelection;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Seçili ürünlerin hiçbirine indirim uygulanamaz '
            '(dijital ürünlere indirim uygulanmaz)',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<_BulkDiscountResult>(
      context: context,
      builder: (context) => _BulkDiscountDialog(products: targets),
    );

    if (result == null || !mounted) return;

    final productIds = targets.map((p) => p.id).toList();
    final hasDiscount = result.mode != null && result.value != null;
    final hasCampaignChange = result.campaignEnabled != null;

    setState(() => _isBulkWorking = true);
    try {
      var updated = 0;
      if (hasDiscount) {
        updated += await _productService.bulkSetDiscount(
          productIds: productIds,
          mode: result.mode!,
          value: result.value!,
        );
      }
      if (hasCampaignChange) {
        updated += await _productService.bulkSetCampaignType(
          productIds: productIds,
          campaignType: result.campaignEnabled! ? 'buy2_get1_balance' : null,
        );
      }
      if (!mounted) return;

      final label = hasDiscount && hasCampaignChange
          ? 'ürün güncellendi (indirim + kampanya)'
          : hasCampaignChange
          ? 'üründe "2 Al 1 Bakiye" kampanyası güncellendi'
          : 'ürüne indirim uygulandı';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$updated $label'),
          backgroundColor: updated > 0 ? Colors.green : Colors.orange,
        ),
      );

      _exitSelectionMode();
      await _loadProducts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBulkWorking = false);
    }
  }

  Future<void> _confirmBulkClearDiscount() async {
    final targets = _discountableSelection
        .where((p) => p.discountPrice != null)
        .toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seçili ürünlerde kaldırılacak toplu indirim yok'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İndirimi Kaldır'),
        content: Text(
          '${targets.length} üründeki indirim kaldırılacak ve ürünler normal '
          'fiyatından satışa dönecek. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runBulkAction(
      action: () =>
          _productService.bulkClearDiscount(targets.map((p) => p.id).toList()),
      skipped: targets.length,
      successLabel: 'üründe indirim kaldırıldı',
    );
  }

  Future<void> _showBulkBadgeDialog() async {
    final targets = _selectedProducts;
    if (targets.isEmpty) return;

    // Tüm seçili ürünlerde ortak olan rozetleri başlangıç değeri yap.
    final common = targets
        .map((p) => p.badges.toSet())
        .reduce((a, b) => a.intersection(b));

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _BadgePickerDialog(
        initial: common,
        title: '${targets.length} ürüne rozet ata',
        subtitle:
            'Seçtiğiniz rozetler bu ürünlerin mevcut rozetlerinin yerine geçer. '
            'Hiç rozet seçmezseniz rozetler temizlenir.',
      ),
    );

    if (result == null || !mounted) return;

    await _runBulkAction(
      action: () => _productService.bulkSetBadges(
        productIds: targets.map((p) => p.id).toList(),
        badges: result,
      ),
      skipped: targets.length,
      successLabel: 'ürünün rozetleri güncellendi',
    );
  }

  /// Toplu işlemlerin ortak sarmalayıcısı: yükleniyor durumu, hata yakalama,
  /// listeyi tazeleme ve "kaç ürün etkilendi" geri bildirimi.
  Future<void> _runBulkAction({
    required Future<int> Function() action,
    required int skipped,
    required String successLabel,
  }) async {
    setState(() => _isBulkWorking = true);
    try {
      final updated = await action();
      if (!mounted) return;

      // Sunucu geçersiz sonuçları atladığı için güncellenen sayı seçilenden
      // az olabilir; satıcıya bunu açıkça söylüyoruz.
      final skippedCount = skipped - updated;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skippedCount > 0
                ? '$updated $successLabel. $skippedCount ürün değişmedi '
                      '(fiyat kuralına uymuyor ya da zaten aynıydı).'
                : '$updated $successLabel',
          ),
          backgroundColor: updated > 0 ? Colors.green : Colors.orange,
        ),
      );

      _exitSelectionMode();
      await _loadProducts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBulkWorking = false);
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
      MaterialPageRoute(builder: (context) => const ManageProductScreen()),
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
          child: _CategoryManagementSheet(categories: categories),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectionMode) return _buildSelectionScaffold();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürünlerim'),
        backgroundColor: Colors.orange.shade700,
        actions: [
          // Çoklu seçim moduna gir (toplu indirim vb.)
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Çoklu seçim',
            onPressed: _filteredProducts.isEmpty
                ? null
                : () => setState(() => _selectionMode = true),
          ),
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
              const PopupMenuItem(value: 'all', child: Text('Tümü')),
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
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAdd,
        backgroundColor: Colors.orange.shade700,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Ürün'),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
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
    );
  }

  /// Çoklu seçim modundaki ekran: aynı liste, farklı app bar + alt aksiyon çubuğu.
  Widget _buildSelectionScaffold() {
    final visible = _filteredProducts;
    final allVisibleSelected =
        visible.isNotEmpty && visible.every((p) => _selectedIds.contains(p.id));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelectionMode();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.orange.shade900,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Seçimden çık',
            onPressed: _exitSelectionMode,
          ),
          title: Text(
            _selectedIds.isEmpty
                ? 'Ürün seçin'
                : '${_selectedIds.length} ürün seçildi',
          ),
          actions: [
            TextButton.icon(
              onPressed: visible.isEmpty ? null : _selectAllVisible,
              icon: Icon(
                allVisibleSelected ? Icons.deselect : Icons.select_all,
                color: Colors.white,
              ),
              label: Text(
                allVisibleSelected ? 'Kaldır' : 'Tümü',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: _buildBulkActionBar(),
      ),
    );
  }

  Widget _buildBulkActionBar() {
    final hasSelection = _selectedIds.isNotEmpty;
    final discountable = _discountableSelection.length;
    final withDiscount = _discountableSelection
        .where((p) => p.discountPrice != null)
        .length;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isBulkWorking)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 3),
              )
            else if (hasSelection)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  discountable == _selectedIds.length
                      ? '$discountable ürüne indirim uygulanabilir'
                      : '$discountable ürüne indirim uygulanabilir '
                            '(${_selectedIds.length - discountable} dijital ürün hariç)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
              ),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (!hasSelection || _isBulkWorking)
                        ? null
                        : _showBulkDiscountDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.percent, size: 18),
                    label: const Text('İndirim Uygula'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (!hasSelection || _isBulkWorking)
                        ? null
                        : _showBulkBadgeDialog,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.local_offer_outlined, size: 18),
                    label: const Text('Rozet'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: (withDiscount == 0 || _isBulkWorking)
                      ? null
                      : _confirmBulkClearDiscount,
                  tooltip: 'İndirimi kaldır',
                  icon: const Icon(Icons.money_off),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.all(14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isEmpty
                ? Icons.inventory_2_outlined
                : Icons.search_off,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'Henüz ürün eklenmemiş' : 'Sonuç bulunamadı',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
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
    // Aktif flaş sale'i asenkron çek (ürün kartı zaten asenkron yüklemelere sahip).
    final flashService = FlashSaleService();

    final isSelected = _selectedIds.contains(product.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected ? Colors.orange.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: Colors.orange.shade700, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        // Seçim modunda dokunmak ürünü seçer, uzun basmak her zaman seçim
        // modunu açar — düzenleme akışı seçim modu dışında aynen korunur.
        onTap: _selectionMode
            ? () => _toggleSelection(product)
            : () => _navigateToEdit(product),
        onLongPress: _selectionMode ? null : () => _enterSelectionMode(product),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (_selectionMode) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(product),
                  activeColor: Colors.orange.shade700,
                ),
                const SizedBox(width: 4),
              ],
              // Resim
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: product.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _buildImagePlaceholder(),
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

                    // Fiyat ve indirim (flaş sale bilinçli)
                    FutureBuilder<FlashSale?>(
                      future: flashService.getActiveFlashSaleForProduct(
                        product.id,
                      ),
                      builder: (context, snap) {
                        final flash = snap.data;
                        if (flash != null) {
                          return _buildFlashSalePriceRow(flash);
                        }
                        return _buildNormalPriceRow(product, discountPercent);
                      },
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

                    // Rozetler ve ek özellik göstergeleri
                    _buildProductExtrasRow(product),
                  ],
                ),
              ),

              // Sabitle ve Düzenle butonları (seçim modunda gizlenir)
              if (!_selectionMode)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sabitle butonu
                    IconButton(
                      icon: Icon(
                        product.sellerPinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        color: product.sellerPinned
                            ? Colors.amber.shade700
                            : Colors.grey,
                      ),
                      onPressed: () => _toggleSellerPinned(product),
                      tooltip: product.sellerPinned
                          ? 'Sabitlemeyi Kaldır'
                          : 'Sabitle',
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

  /// Rozetler + kargo / hazırlık süresi / adet limiti göstergeleri.
  /// Hiçbiri tanımlı değilse hiç yer kaplamaz.
  Widget _buildProductExtrasRow(Product product) {
    final hasExtras =
        product.badgeDetails.isNotEmpty ||
        product.hasCustomShipping ||
        product.prepTimeLabel != null ||
        product.orderQuantityLabel != null;

    if (!hasExtras) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductBadgesWrap(product: product),
          if (product.badgeDetails.isNotEmpty) const SizedBox(height: 4),
          ProductLogisticsWrap(
            product: product,
            showShipping: !product.isDigital,
          ),
        ],
      ),
    );
  }

  /// Aktif flaş sale varken gösterilecek fiyat satırı (satıcı kendi ürünü).
  /// Flaş fiyat büyük, orijinal fiyat üstü çizili, "⚡ Flaş" etiketi.
  Widget _buildFlashSalePriceRow(FlashSale flash) {
    return Row(
      children: [
        // Flaş etiketi
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5252), Color(0xFFE53935)],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, color: Colors.white, size: 12),
              SizedBox(width: 2),
              Text(
                'Flaş',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Flaş fiyat
        Text(
          '₺${flash.flashPrice.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE53935),
          ),
        ),
        const SizedBox(width: 8),
        // Orijinal fiyat (üstü çizili)
        Text(
          '₺${flash.originalPrice.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade500,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(width: 4),
        // İndirim yüzdesi
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '%${flash.discountPercent.round()}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
        ),
      ],
    );
  }

  /// Flaş sale yoksa gösterilecek normal indirimli/düz fiyat satırı.
  Widget _buildNormalPriceRow(Product product, int? discountPercent) {
    return Row(
      children: [
        Text(
          '₺${product.effectivePrice.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.orange.shade700,
          ),
        ),
        if (product.displayOldPrice != null) ...[
          const SizedBox(width: 8),
          Text(
            '₺${product.displayOldPrice!.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(width: 4),
          if (discountPercent != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );
  }
}

/// Toplu indirim diyaloğunun sonucu.
///
/// [mode]/[value] `null` ise fiyat indirimi uygulanmaz (yalnızca kampanya
/// değişmiş olabilir). [campaignEnabled] `null` ise "2 Al 1 Bakiye" kampanyası
/// değiştirilmez; `true`/`false` ise seçili tüm ürünlerde açılır/kapatılır.
class _BulkDiscountResult {
  final BulkDiscountMode? mode;
  final double? value;
  final bool? campaignEnabled;

  const _BulkDiscountResult({this.mode, this.value, this.campaignEnabled});
}

/// Seçili ürünlere uygulanacak indirimi belirleyen diyalog.
///
/// Girilen değer sunucuya olduğu gibi gönderilir; indirimli fiyatı sunucu
/// hesaplar. Buradaki önizleme yalnızca satıcının ne olacağını görmesi içindir.
class _BulkDiscountDialog extends StatefulWidget {
  final List<Product> products;

  const _BulkDiscountDialog({required this.products});

  @override
  State<_BulkDiscountDialog> createState() => _BulkDiscountDialogState();
}

class _BulkDiscountDialogState extends State<_BulkDiscountDialog> {
  BulkDiscountMode _mode = BulkDiscountMode.percent;
  final _valueController = TextEditingController();
  String? _error;

  // Seçili ürünlerin hepsinde "2 Al Biri Bakiye" kampanyası zaten aktifse
  // başlangıç değeri açık gelir; karışık ya da hiçbirinde yoksa kapalı gelir.
  late final bool _initialCampaignEnabled = widget.products.isNotEmpty &&
      widget.products.every((p) => p.isBuy2Get1BalanceCampaign);
  late bool _campaignEnabled = _initialCampaignEnabled;

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  double? get _value =>
      double.tryParse(_valueController.text.trim().replaceAll(',', '.'));

  /// Bir ürün için indirimli fiyatı hesaplar. Sunucudaki kuralın aynısı:
  /// sonuç 0'dan büyük ve mevcut fiyattan küçük olmalı, aksi halde ürün atlanır.
  double? _previewPrice(Product p) {
    final v = _value;
    if (v == null || v <= 0) return null;

    final double raw;
    switch (_mode) {
      case BulkDiscountMode.percent:
        raw = p.price * (1 - v / 100);
      case BulkDiscountMode.amount:
        raw = p.price - v;
      case BulkDiscountMode.fixedPrice:
        raw = v;
    }

    final rounded = double.parse(raw.toStringAsFixed(2));
    if (rounded <= 0 || rounded >= p.price) return null;
    return rounded;
  }

  String? _validate() {
    final v = _value;
    if (v == null) return 'Geçerli bir sayı girin';
    if (v <= 0) return 'Değer 0\'dan büyük olmalı';
    if (_mode == BulkDiscountMode.percent && v > 95) {
      return 'Yüzde indirim en fazla %95 olabilir';
    }
    return null;
  }

  /// İndirim değeri girilmişse geçerli olmalı; girilmemişse yalnızca
  /// kampanya anahtarının değişmiş olması yeterlidir.
  bool _canSubmit(bool hasValue, List<Product> applicable) {
    if (hasValue) return applicable.isNotEmpty;
    return _campaignEnabled != _initialCampaignEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final applicable = widget.products
        .where((p) => _previewPrice(p) != null)
        .toList();
    final skipped = widget.products.length - applicable.length;
    final hasValue = _valueController.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text('${widget.products.length} ürüne indirim'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<BulkDiscountMode>(
                segments: const [
                  ButtonSegment(
                    value: BulkDiscountMode.percent,
                    label: Text('Yüzde'),
                    icon: Icon(Icons.percent, size: 16),
                  ),
                  ButtonSegment(
                    value: BulkDiscountMode.amount,
                    label: Text('Tutar'),
                    icon: Icon(Icons.remove_circle_outline, size: 16),
                  ),
                  ButtonSegment(
                    value: BulkDiscountMode.fixedPrice,
                    label: Text('Sabit'),
                    icon: Icon(Icons.sell_outlined, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              Text(switch (_mode) {
                BulkDiscountMode.percent =>
                  'Her ürünün fiyatından girdiğiniz yüzde kadar düşülür.',
                BulkDiscountMode.amount =>
                  'Her ürünün fiyatından aynı tutar düşülür.',
                BulkDiscountMode.fixedPrice =>
                  'Seçili tüm ürünler bu fiyata iner.',
              }, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 16),
              TextField(
                controller: _valueController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*[.,]?\d{0,2}'),
                  ),
                ],
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: _mode == BulkDiscountMode.percent
                      ? 'İndirim oranı'
                      : 'Tutar',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(
                    _mode == BulkDiscountMode.percent
                        ? Icons.percent
                        : Icons.attach_money,
                  ),
                  suffixText: _mode == BulkDiscountMode.percent ? '%' : '₺',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 16),

              // Önizleme: ilk birkaç ürünün yeni fiyatı
              if (hasValue) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: applicable.isEmpty
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: applicable.isEmpty
                          ? Colors.red.shade200
                          : Colors.green.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        applicable.isEmpty
                            ? 'Bu değerle hiçbir ürüne indirim uygulanamaz'
                            : '${applicable.length} ürüne uygulanacak'
                                  '${skipped > 0 ? ', $skipped ürün atlanacak' : ''}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: applicable.isEmpty
                              ? Colors.red.shade800
                              : Colors.green.shade800,
                        ),
                      ),
                      if (applicable.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final p in applicable.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  '₺${p.price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '₺${_previewPrice(p)!.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (applicable.length > 3)
                          Text(
                            've ${applicable.length - 3} ürün daha...',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                      if (skipped > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Atlanan ürünlerde indirimli fiyat 0\'ın altına '
                          'inecek ya da mevcut fiyattan düşük olmayacaktı.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('"2 Al Biri Bakiye" Kampanyası'),
                subtitle: Text(
                  'Seçili ${widget.products.length} üründe bu kampanya '
                  '${_campaignEnabled ? "açılacak" : "kapatılacak"}. '
                  '2 adet alan müşteriye 1 adedin tutarı bakiye olarak iade edilir.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                value: _campaignEnabled,
                onChanged: (value) => setState(() => _campaignEnabled = value),
                activeTrackColor: Colors.green.shade200,
                activeThumbColor: Colors.green.shade700,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: !_canSubmit(hasValue, applicable)
              ? null
              : () {
                  if (hasValue) {
                    final err = _validate();
                    if (err != null) {
                      setState(() => _error = err);
                      return;
                    }
                  }
                  final campaignChanged =
                      _campaignEnabled != _initialCampaignEnabled;
                  Navigator.pop(
                    context,
                    _BulkDiscountResult(
                      mode: hasValue ? _mode : null,
                      value: hasValue ? _value : null,
                      campaignEnabled: campaignChanged ? _campaignEnabled : null,
                    ),
                  );
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
          ),
          child: const Text('Uygula'),
        ),
      ],
    );
  }
}

/// Rozet seçme diyaloğu. Hem toplu atamada hem tek ürün formunda kullanılır.
class _BadgePickerDialog extends StatefulWidget {
  final Set<String> initial;
  final String title;
  final String subtitle;

  const _BadgePickerDialog({
    required this.initial,
    required this.title,
    required this.subtitle,
  });

  @override
  State<_BadgePickerDialog> createState() => _BadgePickerDialogState();
}

class _BadgePickerDialogState extends State<_BadgePickerDialog> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ProductBadge.all.map((badge) {
                  final isSelected = _selected.contains(badge.key);
                  // Sınıra ulaşıldığında seçili olmayanlar pasifleşir.
                  final atLimit =
                      !isSelected &&
                      _selected.length >= ProductBadge.maxPerProduct;

                  return FilterChip(
                    avatar: Icon(
                      badge.icon,
                      size: 16,
                      color: atLimit ? Colors.grey : badge.color,
                    ),
                    label: Text(badge.label),
                    selected: isSelected,
                    onSelected: atLimit
                        ? null
                        : (v) => setState(() {
                            if (v) {
                              _selected.add(badge.key);
                            } else {
                              _selected.remove(badge.key);
                            }
                          }),
                    selectedColor: badge.color.withValues(alpha: 0.18),
                    checkmarkColor: badge.color,
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                '${_selected.length}/${ProductBadge.maxPerProduct} rozet seçildi',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
          ),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

// Kategori yönetimi bottom sheet widget'ı
class _CategoryManagementSheet extends StatefulWidget {
  final List<String> categories;

  const _CategoryManagementSheet({required this.categories});

  @override
  State<_CategoryManagementSheet> createState() =>
      _CategoryManagementSheetState();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bu kategori zaten mevcut')));
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.category, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Kategoriler',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                            Icon(
                              Icons.category_outlined,
                              size: 40,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Henüz kategori yok',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: _categories.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.label,
                                  size: 14,
                                  color: Colors.orange.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    category,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _removeCategory(category),
                                  child: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.red.shade400,
                                  ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _categoryController,
                        decoration: InputDecoration(
                          hintText: 'Kategori adı girin',
                          hintStyle: const TextStyle(fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Kaydet',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
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
