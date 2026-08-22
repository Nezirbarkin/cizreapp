// Bu dosya `part of admin_dashboard_screen.dart` oldugu icin ana dosyadaki
// ignore_for_file direktifleri buraya UYGULANMAZ; her part kendi listesini
// tasimak zorundadir.
//
// invalid_use_of_protected_member: bu part'lar `extension on
// _AdminDashboardScreenState` deseniyle yazildi; setState/mounted analiz
// acisindan sinif disindan cagrilmis gorunur ama calisma zamaninda
// State'in kendi uyesidir. Tek gercek false positive budur ve yalniz o
// susturulur - dosyalarin analizden komple cikarilmasi (analysis_options
// exclude) dead_code/tip hatalarini da gizliyordu.
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: use_build_context_synchronously, deprecated_member_use
part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Urunler + ekleme/duzenleme/silme dialoglari
  // ==========================================================================

  // --- _buildProductsContent ---
  Widget _buildProductsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadProducts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final products = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tüm Ürünler',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showAddProductDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Ürün'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (products.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Ürün bulunamadı',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final isProductPinned = product['is_pinned'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: isProductPinned ? 3 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isProductPinned
                              ? BorderSide(
                                  color: Colors.amber.shade400,
                                  width: 2,
                                )
                              : BorderSide.none,
                        ),
                        child: Stack(
                          children: [
                            if (isProductPinned)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.push_pin,
                                        size: 12,
                                        color: Colors.amber.shade800,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Sabitlendi',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.amber.shade800,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.grey.shade100,
                                ),
                                child: product['image_url'] != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: product['image_url'],
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) {
                                            return const Icon(
                                              Icons.image,
                                              size: 30,
                                              color: Colors.grey,
                                            );
                                          },
                                        ),
                                      )
                                    : const Icon(
                                        Icons.shopping_bag,
                                        size: 30,
                                        color: Colors.grey,
                                      ),
                              ),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product['name'] ?? '-',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (product['shops'] != null)
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.store,
                                          size: 12,
                                          color: Colors.orange.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            product['shops']['name'] ??
                                                'Bilinmeyen Satıcı',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (product['product_type'] == 'digital')
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          product['is_points_eligible'] == true
                                              ? 'Puan kullanımına uygun'
                                              : 'Puan kullanımına kapalı',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                product['is_points_eligible'] ==
                                                    true
                                                ? Colors.green
                                                : Colors.grey,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.inventory_2,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                        Text(
                                          ' Stok: ${product['stock_quantity'] ?? 0}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(
                                          Icons.category,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                        Expanded(
                                          child: Text(
                                            ' ${product['category_id'] ?? '-'}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                        Text(
                                          ' ${_formatDate(product['created_at'])}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₺${product['price'] ?? 0}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green,
                                        ),
                                      ),
                                      if (product['discount_price'] != null)
                                        Text(
                                          '₺${product['discount_price']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red.shade700,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                    ],
                                  ),
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: Colors.grey.shade700,
                                    ),
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'pin':
                                          _togglePin(
                                            'products',
                                            product['id'],
                                            !isProductPinned,
                                          );
                                          break;
                                        case 'edit':
                                          _showEditProductDialog(product);
                                          break;
                                        case 'delete':
                                          _showDeleteProductDialog(product);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'pin',
                                        child: Row(
                                          children: [
                                            Icon(
                                              isProductPinned
                                                  ? Icons.push_pin_outlined
                                                  : Icons.push_pin,
                                              size: 18,
                                              color: Colors.amber.shade700,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              isProductPinned
                                                  ? 'Sabitlemeyi Kaldır'
                                                  : 'Sabitle',
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, size: 18),
                                            SizedBox(width: 8),
                                            Text('Düzenle'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Sil',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _showAddProductDialog ---
  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController();
    final discountPriceController = TextEditingController();
    final stockController = TextEditingController();
    final imageUrlController = TextEditingController();
    String? selectedShopId;
    String? selectedCategoryId;

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: Future.wait([
          _loadShops(),
          _loadCategories(),
        ]).then((results) => {'shops': results[0], 'categories': results[1]}),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final shops =
              (snapshot.data?['shops'] as List<Map<String, dynamic>>?) ?? [];
          final categories =
              (snapshot.data?['categories'] as List<Map<String, dynamic>>?) ??
              [];

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Yeni Ürün Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Ürün Adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      decoration: const InputDecoration(
                        labelText: 'Fiyat (₺)',
                        border: OutlineInputBorder(),
                        prefixText: '₺',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: discountPriceController,
                      decoration: const InputDecoration(
                        labelText: 'İndirimli Fiyat (₺) - Opsiyonel',
                        border: OutlineInputBorder(),
                        prefixText: '₺',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockController,
                      decoration: const InputDecoration(
                        labelText: 'Stok Adedi',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedShopId,
                      decoration: const InputDecoration(
                        labelText: 'Satıcı/Mağaza',
                        border: OutlineInputBorder(),
                      ),
                      items: shops.map((shop) {
                        return DropdownMenuItem(
                          value: shop['id'] as String,
                          child: Text(shop['name'] ?? '-'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedShopId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: categories.map((category) {
                        return DropdownMenuItem(
                          value: category['id'] as String,
                          child: Text(category['name'] ?? '-'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedCategoryId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Resim URL - Opsiyonel',
                        border: OutlineInputBorder(),
                        hintText: 'https://example.com/image.jpg',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        priceController.text.isEmpty ||
                        stockController.text.isEmpty ||
                        selectedShopId == null ||
                        selectedCategoryId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lütfen tüm zorunlu alanları doldurun'),
                        ),
                      );
                      return;
                    }

                    try {
                      final productData = {
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'price': double.parse(priceController.text.trim()),
                        'stock_quantity': int.parse(
                          stockController.text.trim(),
                        ),
                        'shop_id': selectedShopId,
                        'category_id': selectedCategoryId,
                      };

                      if (discountPriceController.text.isNotEmpty) {
                        productData['discount_price'] = double.parse(
                          discountPriceController.text.trim(),
                        );
                      }

                      if (imageUrlController.text.isNotEmpty) {
                        productData['image_url'] = imageUrlController.text
                            .trim();
                      }

                      await Supabase.instance.client
                          .from('products')
                          .insert(productData);

                      if (mounted) {
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ürün başarıyla eklendi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ürün eklenirken hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Ekle'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- _showEditProductDialog ---
  void _showEditProductDialog(Map<String, dynamic> product) {
    final nameController = TextEditingController(text: product['name']);
    final descriptionController = TextEditingController(
      text: product['description'],
    );
    final priceController = TextEditingController(
      text: product['price']?.toString() ?? '',
    );
    final discountPriceController = TextEditingController(
      text: product['discount_price']?.toString() ?? '',
    );
    final stockController = TextEditingController(
      text: product['stock_quantity']?.toString() ?? '',
    );
    final imageUrlController = TextEditingController(
      text: product['image_url'],
    );
    String? selectedShopId = product['shop_id'];
    String? selectedCategoryId = product['category_id'];
    final isDigital = product['product_type'] == 'digital';
    bool isPointsEligible = isDigital && product['is_points_eligible'] == true;

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: Future.wait([
          _loadShops(),
          _loadCategories(),
        ]).then((results) => {'shops': results[0], 'categories': results[1]}),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final shops =
              (snapshot.data?['shops'] as List<Map<String, dynamic>>?) ?? [];
          final categories =
              (snapshot.data?['categories'] as List<Map<String, dynamic>>?) ??
              [];

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Ürün Düzenle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Ürün Adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (isDigital) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Puan kullanımına uygun'),
                        subtitle: const Text(
                          'Nihai uygunluk sunucuda doğrulanır.',
                        ),
                        value: isPointsEligible,
                        onChanged: (value) =>
                            setDialogState(() => isPointsEligible = value),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      decoration: const InputDecoration(
                        labelText: 'Fiyat (₺)',
                        border: OutlineInputBorder(),
                        prefixText: '₺',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: discountPriceController,
                      decoration: const InputDecoration(
                        labelText: 'İndirimli Fiyat (₺) - Opsiyonel',
                        border: OutlineInputBorder(),
                        prefixText: '₺',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockController,
                      decoration: const InputDecoration(
                        labelText: 'Stok Adedi',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedShopId,
                      decoration: const InputDecoration(
                        labelText: 'Satıcı/Mağaza',
                        border: OutlineInputBorder(),
                      ),
                      items: shops.map((shop) {
                        return DropdownMenuItem(
                          value: shop['id'] as String,
                          child: Text(shop['name'] ?? '-'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedShopId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: categories.map((category) {
                        return DropdownMenuItem(
                          value: category['id'] as String,
                          child: Text(category['name'] ?? '-'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedCategoryId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Resim URL - Opsiyonel',
                        border: OutlineInputBorder(),
                        hintText: 'https://example.com/image.jpg',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        priceController.text.isEmpty ||
                        stockController.text.isEmpty ||
                        selectedShopId == null ||
                        selectedCategoryId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lütfen tüm zorunlu alanları doldurun'),
                        ),
                      );
                      return;
                    }

                    try {
                      debugPrint('📝 Ürün güncelleniyor: ${product['id']}');

                      final productData = {
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'price': double.parse(priceController.text.trim()),
                        'stock_quantity': int.parse(
                          stockController.text.trim(),
                        ),
                        'shop_id': selectedShopId,
                        'category_id': selectedCategoryId,
                        'is_points_eligible': isDigital
                            ? isPointsEligible
                            : false,
                      };

                      if (discountPriceController.text.isNotEmpty) {
                        productData['discount_price'] = double.parse(
                          discountPriceController.text.trim(),
                        );
                      }

                      if (imageUrlController.text.isNotEmpty) {
                        productData['image_url'] = imageUrlController.text
                            .trim();
                      }

                      final response = await Supabase.instance.client
                          .from('products')
                          .update(productData)
                          .eq('id', product['id'])
                          .select();

                      debugPrint('✅ Ürün güncelleme yanıtı: $response');

                      if (mounted) {
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ürün başarıyla güncellendi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e, stackTrace) {
                      debugPrint('❌ Ürün güncellenirken hata: $e');
                      debugPrint('📍 Stack trace: $stackTrace');

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ürün güncellenirken hata: $e'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- _showDeleteProductDialog ---
  void _showDeleteProductDialog(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: Text(
          '${product['name']} ürününü silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                debugPrint(
                  '🗑️ Ürün siliniyor: ${product['id']} (${product['name']})',
                );

                final response = await Supabase.instance.client
                    .from('products')
                    .delete()
                    .eq('id', product['id'])
                    .select();

                debugPrint('✅ Ürün silme yanıtı: $response');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ürün başarıyla silindi'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Ürün silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (e is PostgrestException && e.code == '23503') {
                  try {
                    await Supabase.instance.client
                        .from('products')
                        .update({'is_available': false})
                        .eq('id', product['id']);

                    if (mounted) {
                      Navigator.pop(context);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bu ürüne ait sipariş geçmişi olduğu için silinemedi, bunun yerine devre dışı bırakıldı.',
                          ),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }
                  } catch (e2) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Ürün devre dışı bırakılırken hata: $e2',
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                  return;
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ürün silinirken hata: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
