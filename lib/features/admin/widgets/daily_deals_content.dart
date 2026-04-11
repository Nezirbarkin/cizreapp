// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/models/daily_deal_model.dart';
import '../../../core/models/category_model.dart';
import '../../../features/market/services/daily_deal_service.dart';

class DailyDealsContent extends StatefulWidget {
  const DailyDealsContent({super.key});

  @override
  State<DailyDealsContent> createState() => _DailyDealsContentState();
}

class _DailyDealsContentState extends State<DailyDealsContent> {
  final DailyDealService _dealService = DailyDealService();
  final ImagePicker _imagePicker = ImagePicker();
  
  List<DailyDeal> _deals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeals();
  }

  Future<void> _loadDeals() async {
    setState(() => _isLoading = true);
    try {
      final deals = await _dealService.getAllDeals();
      if (mounted) {
        setState(() {
          _deals = deals;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fırsatlar yüklenirken hata: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _pickAndUploadImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null && mounted) {
        final file = File(image.path);
        final fileName = 'deal_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final filePath = 'deals/$fileName';

        await Supabase.instance.client.storage
            .from('deals')
            .upload(filePath, file);

        final imageUrl = Supabase.instance.client.storage
            .from('deals')
            .getPublicUrl(filePath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Görsel başarıyla yüklendi')),
          );
        }
        return imageUrl;
      }
      return null;
    } catch (e) {
      debugPrint('Görsel yüklenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Görsel yüklenemedi: $e')),
        );
      }
      return null;
    }
  }

  // Mağaza seçme dialogu
  Future<Map<String, String>?> _showShopSelectionDialog() async {
    final shops = await _loadShops();
    String searchQuery = '';

    return await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mağaza Seç'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Mağaza Ara',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() => searchQuery = value);
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: shops.isEmpty
                      ? const Center(child: Text('Mağaza bulunamadı'))
                      : ListView.builder(
                          itemCount: shops.length,
                          itemBuilder: (context, index) {
                            final shop = shops[index];
                            final shopName = shop['name'] as String? ?? '';
                            final shopId = shop['id'] as String;
                            
                            if (searchQuery.isNotEmpty &&
                                !shopName.toLowerCase().contains(searchQuery.toLowerCase())) {
                              return const SizedBox.shrink();
                            }
                            
                            return ListTile(
                              leading: const Icon(Icons.store, color: Colors.orange),
                              title: Text(shopName),
                              subtitle: Text(
                                'ID: ${shopId.substring(0, 8)}...',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'ID\'yi Kopyala',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: shopId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ID kopyalandı')),
                                  );
                                },
                              ),
                              onTap: () {
                                Navigator.pop(context, {'id': shopId, 'name': shopName});
                              },
                            );
                          },
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
          ],
        ),
      ),
    );
  }

  // Ürün seçme dialogu
  Future<Map<String, String>?> _showProductSelectionDialog() async {
    final products = await _loadProducts();
    String searchQuery = '';

    return await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ürün Seç'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Ürün Ara',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() => searchQuery = value);
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: products.isEmpty
                      ? const Center(child: Text('Ürün bulunamadı'))
                      : ListView.builder(
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final product = products[index];
                            final productName = product['name'] as String? ?? '';
                            final productId = product['id'] as String;
                            final shopName = product['shops']?['name'] as String? ?? '';
                            
                            if (searchQuery.isNotEmpty &&
                                !productName.toLowerCase().contains(searchQuery.toLowerCase())) {
                              return const SizedBox.shrink();
                            }
                            
                            return ListTile(
                              leading: const Icon(Icons.shopping_bag, color: Colors.blue),
                              title: Text(productName),
                              subtitle: Text(
                                '$shopName\nID: ${productId.substring(0, 8)}...',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'ID\'yi Kopyala',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: productId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ID kopyalandı')),
                                  );
                                },
                              ),
                              onTap: () {
                                Navigator.pop(context, {'id': productId, 'name': productName});
                              },
                            );
                          },
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
          ],
        ),
      ),
    );
  }

  // Kategori seçme dialogu
  Future<Map<String, String>?> _showCategorySelectionDialog() async {
    final categories = await _loadCategories();
    String searchQuery = '';

    return await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kategori Seç'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Kategori Ara',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() => searchQuery = value);
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: categories.isEmpty
                      ? const Center(child: Text('Kategori bulunamadı'))
                      : ListView.builder(
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            final categoryName = category.name;
                            final categoryId = category.id;
                            
                            if (searchQuery.isNotEmpty &&
                                !categoryName.toLowerCase().contains(searchQuery.toLowerCase())) {
                              return const SizedBox.shrink();
                            }
                            
                            return ListTile(
                              leading: const Icon(Icons.category, color: Colors.green),
                              title: Text(categoryName),
                              subtitle: Text(
                                'ID: ${categoryId.substring(0, 8)}...',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'ID\'yi Kopyala',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: categoryId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ID kopyalandı')),
                                  );
                                },
                              ),
                              onTap: () {
                                Navigator.pop(context, {'id': categoryId, 'name': categoryName});
                              },
                            );
                          },
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
          ],
        ),
      ),
    );
  }

  // Veritabanından mağazaları yükle
  Future<List<Map<String, dynamic>>> _loadShops() async {
    try {
      final response = await Supabase.instance.client
          .from('shops')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Mağazalar yüklenirken hata: $e');
      return [];
    }
  }

  // Veritabanından ürünleri yükle
  Future<List<Map<String, dynamic>>> _loadProducts() async {
    try {
      final response = await Supabase.instance.client
          .from('products')
          .select('id, name, shops(name)')
          .eq('is_available', true)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Ürünler yüklenirken hata: $e');
      return [];
    }
  }

  // Veritabanından kategorileri yükle
  Future<List<Category>> _loadCategories() async {
    try {
      final response = await Supabase.instance.client
          .from('categories')
          .select()
          .eq('is_active', true)
          .order('name');
      return (response as List).map((json) => Category.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Kategoriler yüklenirken hata: $e');
      return [];
    }
  }

  Future<void> _showAddEditDealDialog({DailyDeal? deal}) async {
    final titleController = TextEditingController(text: deal?.title ?? '');
    final subtitleController = TextEditingController(text: deal?.subtitle ?? '');
    final linkUrlController = TextEditingController(text: deal?.linkUrl ?? '');
    final htmlContentController = TextEditingController(text: deal?.htmlContent ?? '');
    
    String imageUrl = deal?.imageUrl ?? '';
    String linkType = deal?.linkType ?? 'shop';
    String dealType = deal?.dealType ?? 'image'; // 'image' veya 'html'
    String? selectedLinkId = deal?.linkId;
    String selectedLinkName = ''; // Seçilen mağaza/ürün/kategori adı
    int sortOrder = deal?.sortOrder ?? _deals.length;
    bool isActive = deal?.isActive ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(deal == null ? 'Yeni Fırsat Ekle' : 'Fırsatı Düzenle'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    hintText: 'Örn: %50 İndirim',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Alt Başlık',
                    hintText: 'Örn: Sadece bugün',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Kart Tipi Seçimi
                const Text('Kart Tipi', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image, size: 16),
                            SizedBox(width: 4),
                            Text('Görsel'),
                          ],
                        ),
                        selected: dealType == 'image',
                        onSelected: (selected) {
                          if (selected) setDialogState(() => dealType = 'image');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.code, size: 16),
                            SizedBox(width: 4),
                            Text('HTML'),
                          ],
                        ),
                        selected: dealType == 'html',
                        onSelected: (selected) {
                          if (selected) setDialogState(() => dealType = 'html');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Görsel veya HTML içerik alanı
                if (dealType == 'image') ...[
                  // Görsel yükleme/gösterme
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: imageUrl.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_outlined, size: 40, color: Colors.grey),
                                Text('Görsel seçilmedi', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imageUrl,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Icon(Icons.error_outline, color: Colors.red),
                                    );
                                  },
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                  onPressed: () {
                                    setDialogState(() => imageUrl = '');
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final uploadedUrl = await _pickAndUploadImage();
                            if (uploadedUrl != null) {
                              setDialogState(() => imageUrl = uploadedUrl);
                            }
                          },
                          icon: const Icon(Icons.upload),
                          label: const Text('Görsel Yükle'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              imageUrl = 'https://via.placeholder.com/400x200?text=Fırsat+Görseli';
                            });
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('URL Gir'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // HTML İçerik Alanı
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
                            Icon(Icons.code, size: 18, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'HTML / İframe İçeriği',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: htmlContentController,
                          maxLines: 6,
                          decoration: InputDecoration(
                            hintText: '<iframe src="https://..." style="width:100%; height:180px; border:none;"></iframe>',
                            border: const OutlineInputBorder(),
                            fillColor: Colors.white,
                            filled: true,
                            hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                          ),
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Örnek: Nöbetçi eczane iframe kodu yapıştırın',
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                
                // Link Tipi Seçimi
                const Text('Link Tipi', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Row(children: [Icon(Icons.store, size: 16), SizedBox(width: 4), Text('Mağaza')]),
                      selected: linkType == 'shop',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => linkType = 'shop');
                      },
                    ),
                    ChoiceChip(
                      label: const Row(children: [Icon(Icons.shopping_bag, size: 16), SizedBox(width: 4), Text('Ürün')]),
                      selected: linkType == 'product',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => linkType = 'product');
                      },
                    ),
                    ChoiceChip(
                      label: const Row(children: [Icon(Icons.category, size: 16), SizedBox(width: 4), Text('Kategori')]),
                      selected: linkType == 'category',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => linkType = 'category');
                      },
                    ),
                    ChoiceChip(
                      label: const Row(children: [Icon(Icons.local_fire_department, size: 16), SizedBox(width: 4), Text('Kampanya')]),
                      selected: linkType == 'campaign',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => linkType = 'campaign');
                      },
                    ),
                    ChoiceChip(
                      label: const Row(children: [Icon(Icons.link, size: 16), SizedBox(width: 4), Text('URL')]),
                      selected: linkType == 'url',
                      onSelected: (selected) {
                        if (selected) setDialogState(() => linkType = 'url');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Link ID veya URL
                if (linkType == 'shop' || linkType == 'product' || linkType == 'category') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              linkType == 'shop' ? Icons.store :
                              linkType == 'product' ? Icons.shopping_bag :
                              Icons.category,
                              size: 20,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selectedLinkId == null
                                  ? linkType == 'shop'
                                      ? 'Mağaza seçilmedi'
                                      : linkType == 'product'
                                      ? 'Ürün seçilmedi'
                                      : 'Kategori seçilmedi'
                                  : selectedLinkName.isNotEmpty
                                      ? selectedLinkName
                                      : 'Seçildi',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selectedLinkId != null ? FontWeight.bold : FontWeight.normal,
                                  color: selectedLinkId != null ? Colors.blue.shade900 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (selectedLinkId != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'ID: ${selectedLinkId!.substring(0, 8)}...',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Map<String, String>? result;
                            if (linkType == 'shop') {
                              result = await _showShopSelectionDialog();
                            } else if (linkType == 'product') {
                              result = await _showProductSelectionDialog();
                            } else if (linkType == 'category') {
                              result = await _showCategorySelectionDialog();
                            }
                            
                            if (result != null) {
                              final id = result['id'] ?? '';
                              final name = result['name'] ?? '';
                              setDialogState(() {
                                selectedLinkId = id;
                                selectedLinkName = name;
                              });
                            }
                          },
                          icon: const Icon(Icons.search),
                          label: Text(
                            linkType == 'shop'
                                ? 'Mağaza Seç'
                                : linkType == 'product'
                                ? 'Ürün Seç'
                                : 'Kategori Seç',
                          ),
                        ),
                      ),
                      if (selectedLinkId != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            setDialogState(() {
                              selectedLinkId = null;
                              selectedLinkName = '';
                            });
                          },
                          icon: const Icon(Icons.close),
                          tooltip: 'Seçimi Temizle',
                        ),
                      ],
                    ],
                  ),
                ]
                else if (linkType == 'campaign')
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      '💡 Kampanya seçimi: İndirimli ürünler sayfasına yönlendirir',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  )
                else if (linkType == 'url')
                  TextField(
                    controller: linkUrlController,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                
                const SizedBox(height: 12),
                
                // Sıralama
                Row(
                  children: [
                    const Text('Sıralama: '),
                    IconButton(
                      icon: const Icon(Icons.remove_circle),
                      onPressed: sortOrder > 0
                          ? () => setDialogState(() => sortOrder--)
                          : null,
                    ),
                    Text('$sortOrder', style: const TextStyle(fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: () => setDialogState(() => sortOrder++),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Aktif/Pasif
                SwitchListTile(
                  title: const Text('Aktif'),
                  subtitle: const Text('Kullanıcılara göster'),
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
                ),
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                // Validasyon
                if (dealType == 'image' && imageUrl.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen görsel yükleyin')),
                  );
                  return;
                }
                if (dealType == 'html' && htmlContentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen HTML/iframe kodu girin')),
                  );
                  return;
                }

                try {
                  final dealData = {
                    'title': titleController.text.trim(),
                    'subtitle': subtitleController.text.trim(),
                    'image_url': dealType == 'image' ? imageUrl : '',
                    'deal_type': dealType,
                    'html_content': dealType == 'html' ? htmlContentController.text.trim() : null,
                    'link_type': linkType,
                    'link_id': (['shop', 'product', 'category'].contains(linkType) && selectedLinkId != null) ? selectedLinkId : null,
                    'link_url': (linkType == 'url' && linkUrlController.text.trim().isNotEmpty) ? linkUrlController.text.trim() : null,
                    'sort_order': sortOrder,
                    'is_active': isActive,
                  };

                  if (deal == null) {
                    // Yeni fırsat oluştur
                    await _dealService.createDeal(dealData);
                  } else {
                    // Mevcut fırsatı güncelle
                    await _dealService.updateDeal(deal.id, dealData);
                  }
                  if (mounted) {
                    // ignore: use_build_context_synchronously
                    Navigator.pop(context);
                    await _loadDeals();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(deal == null ? 'Fırsat eklendi' : 'Fırsat güncellendi'),
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
              },
              child: Text(deal == null ? 'Ekle' : 'Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDeal(DailyDeal deal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fırsatı Sil'),
        content: Text('${deal.title} fırsatını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _dealService.deleteDeal(deal.id);
        if (mounted) {
          await _loadDeals();
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fırsat silindi')),
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

  Future<void> _toggleActive(DailyDeal deal) async {
    try {
      await _dealService.updateDeal(deal.id, {
        'title': deal.title,
        'subtitle': deal.subtitle,
        'image_url': deal.imageUrl,
        'deal_type': deal.dealType,
        'html_content': deal.htmlContent,
        'link_type': deal.linkType,
        'link_id': deal.linkId,
        'link_url': deal.linkUrl,
        'sort_order': deal.sortOrder,
        'is_active': !deal.isActive,
      });
      await _loadDeals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Günün Fırsatları',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              FilledButton.icon(
                onPressed: () => _showAddEditDealDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Yeni Fırsat'),
              ),
            ],
          ),
        ),
        
        // Deals List
        Expanded(
          child: _deals.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_fire_department_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Henüz fırsat kartı yok',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Yeni fırsat eklemek için butona tıklayın',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _deals.length,
                  itemBuilder: (context, index) {
                    final deal = _deals[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Görsel
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                deal.imageUrl,
                                width: 70,
                                height: 55,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 70,
                                    height: 55,
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.error_outline, size: 24),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            
                            // İçerik
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Başlık ve Durum
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          deal.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: deal.isActive
                                              ? Colors.green.shade100
                                              : Colors.grey.shade300,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          deal.isActive ? 'Aktif' : 'Pasif',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: deal.isActive ? Colors.green.shade700 : Colors.grey.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Alt başlık
                                  if (deal.subtitle != null && deal.subtitle!.isNotEmpty)
                                    Text(
                                      deal.subtitle!,
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  // Link ve Sıra bilgisi
                                  Row(
                                    children: [
                                      Icon(Icons.link, size: 12, color: Colors.grey.shade500),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          '${_getLinkTypeLabel(deal.linkType)}${deal.linkId != null ? ': ${deal.linkId}' : ''}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(Icons.sort, size: 12, color: Colors.grey.shade500),
                                      const SizedBox(width: 3),
                                      Text(
                                        'S:${deal.sortOrder}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            
                            // Aksiyon butonları
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    deal.isActive ? Icons.visibility : Icons.visibility_off,
                                    size: 20,
                                  ),
                                  tooltip: deal.isActive ? 'Gizle' : 'Göster',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _toggleActive(deal),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  tooltip: 'Düzenle',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _showAddEditDealDialog(deal: deal),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  tooltip: 'Sil',
                                  color: Theme.of(context).colorScheme.error,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _deleteDeal(deal),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _getLinkTypeLabel(String linkType) {
    switch (linkType) {
      case 'shop':
        return 'Mağaza';
      case 'product':
        return 'Ürün';
      case 'campaign':
        return 'Kampanya';
      case 'category':
        return 'Kategori';
      case 'url':
        return 'URL';
      default:
        return linkType;
    }
  }
}
