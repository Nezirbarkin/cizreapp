// ignore_for_file: unused_field

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/category_model.dart' as category_model;
import '../../market/services/product_service.dart';
import '../../market/services/category_service.dart';
import '../../../core/widgets/color_picker_widget.dart';

class ManageProductScreen extends StatefulWidget {
  final Product? product;

  const ManageProductScreen({
    super.key,
    this.product,
  });

  @override
  State<ManageProductScreen> createState() => _ManageProductScreenState();
}

class _ManageProductScreenState extends State<ManageProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  final _productService = ProductService();
  final _categoryService = CategoryService();

  // Komisyon oranı
  double _commissionRate = 10.0;
  bool _isLoadingCommission = false;

  // Form controllers
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _oldPriceController;
  late final TextEditingController _stockController;

  // State
  bool _isLoading = false;
  bool _isUploadingImage = false;
  List<category_model.Category> _categories = [];
  List<String> _sellerCategories = []; // Satıcının kendi kategorileri
  String? _selectedCategory;
  
  // Çoklu görsel desteği
  List<String> _imageUrls = [];
  List<XFile> _selectedImages = [];
  final int _maxImages = 5;
  bool _hasDiscount = false;

  // Varyant state
  String _productType = 'normal';
  final List<String> _availableSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL'];
  final Set<String> _selectedSizes = {};
  final List<int> _availableShoeSizes = [36, 37, 38, 39, 40, 41, 42, 43, 44, 45];
  final Set<int> _selectedShoeSizes = {};
  final List<ProductColor> _colors = [];

  // Renk picker için global key
  final GlobalKey<_ColorPickerWidgetState> _colorPickerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _descriptionController = TextEditingController(text: widget.product?.description ?? '');
    _priceController = TextEditingController(
      text: widget.product?.price.toString() ?? '',
    );
    _oldPriceController = TextEditingController(
      text: widget.product?.oldPrice?.toString() ?? '',
    );
    _stockController = TextEditingController(
      text: widget.product?.stockQuantity.toString() ?? '',
    );

    _selectedCategory = widget.product?.category;
    
    // Mevcut görselleri yükle
    if (widget.product?.imageUrl != null) {
      _imageUrls.add(widget.product!.imageUrl!);
    }
    if (widget.product?.additionalImages != null) {
      _imageUrls.addAll(widget.product!.additionalImages);
    }
    
    _hasDiscount = widget.product?.hasDiscount ?? false;

    // Varyant verilerini yükle
    if (widget.product != null) {
      _productType = widget.product!.productType;
      _selectedSizes.addAll(widget.product!.sizes);
      _selectedShoeSizes.addAll(widget.product!.shoeSizes);
      _colors.addAll(widget.product!.colors);
    }

    _loadCategories();
    _loadCommissionRate();
  }

  /// Mağaza komisyon oranını yükle
  Future<void> _loadCommissionRate() async {
    setState(() => _isLoadingCommission = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final shopResponse = await _supabase
          .from('shops')
          .select('commission_rate')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse != null && shopResponse['commission_rate'] != null) {
        setState(() {
          _commissionRate = (shopResponse['commission_rate'] as num).toDouble();
        });
      }
    } catch (e) {
      debugPrint('Komisyon oranı yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCommission = false);
    }
  }

  /// Komisyon tutarı hesapla
  double _calculateCommission(double price) {
    return price * _commissionRate / 100;
  }

  /// Net kazanç hesapla
  double _calculateNetEarnings(double price) {
    return price - _calculateCommission(price);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _oldPriceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      // Admin kategorilerini yükle
      final categories = await _categoryService.getCategories();
      
      // Satıcının kendi kategorilerini yükle
      await _loadSellerCategories();
      
      if (mounted) {
        setState(() {
          _categories = categories;
          
          // Seçili kategori satıcının listesinde var mı kontrol et
          if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
            // Eğer satıcının kategorileri arasında yoksa, null yap (yeni kategori seçilmeli)
            if (!_sellerCategories.contains(_selectedCategory)) {
              debugPrint('⚠️ Mevcut kategori ($_selectedCategory) satıcının kategorilerinde yok, temizleniyor');
              _selectedCategory = null;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Kategoriler yüklenemedi: $e');
    }
  }

  Future<void> _loadSellerCategories() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Satıcının mağazasını bul
      final shopResponse = await _supabase
          .from('shops')
          .select('seller_categories')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse != null && shopResponse['seller_categories'] != null) {
        if (mounted) {
          setState(() {
            _sellerCategories = List<String>.from(shopResponse['seller_categories'] as List);
          });
        }
      }
    } catch (e) {
      debugPrint('Satıcı kategorileri yüklenemedi: $e');
    }
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length + _imageUrls.length >= _maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('En fazla $_maxImages resim ekleyebilirsiniz')),
      );
      return;
    }

    try {
      final picker = ImagePicker();
      
      List<XFile> pickedFiles;
      
      if (kIsWeb) {
        // Web'de pickMultiImage desteklenmiyor, tek tek seç
        final file = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 85,
        );
        if (file != null) {
          pickedFiles = [file];
        } else {
          pickedFiles = [];
        }
      } else {
        // Mobile'da çoklu seçim
        pickedFiles = await picker.pickMultiImage(
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 85,
        );
      }

      if (pickedFiles.isNotEmpty && mounted) {
        final remainingSlots = _maxImages - (_selectedImages.length + _imageUrls.length);
        final filesToAdd = pickedFiles.take(remainingSlots).toList();
        
        setState(() {
          _selectedImages.addAll(filesToAdd);
        });

        if (pickedFiles.length > remainingSlots) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('En fazla $_maxImages resim ekleyebilirsiniz. ${pickedFiles.length - remainingSlots} resim eklenmedi.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resim seçme hatası: $e')),
        );
      }
    }
  }

  void _removeImage(int index, {bool isUrl = false}) {
    setState(() {
      if (isUrl) {
        _imageUrls.removeAt(index);
      } else {
        _selectedImages.removeAt(index);
      }
    });
  }

  Future<List<String>> _uploadImages(String shopId) async {
    final uploadedUrls = List<String>.from(_imageUrls);

    if (_selectedImages.isEmpty) return uploadedUrls;

    setState(() => _isUploadingImage = true);

    try {
      for (final image in _selectedImages) {
        // Web ve mobile için ortak yaklaşım: XFile'dan byte array al
        final imageBytes = await image.readAsBytes();
        final fileExt = image.name.split('.').last.toLowerCase();
        final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}_${uploadedUrls.length}.$fileExt';
        final filePath = 'shops/$shopId/$fileName';

        await _supabase.storage.from('shop-images').uploadBinary(
              filePath,
              imageBytes,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: false,
              ),
            );

        final url = _supabase.storage.from('shop-images').getPublicUrl(filePath);
        uploadedUrls.add(url);
      }

      return uploadedUrls;
    } catch (e) {
      debugPrint('Resim yükleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resim yüklenemedi: $e')),
        );
      }
      return uploadedUrls;
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _removeColor(int index) {
    setState(() => _colors.removeAt(index));
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    // Görsel kontrolü
    if (_selectedImages.isEmpty && _imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir ürün resmi eklemelisiniz')),
      );
      return;
    }

    // Varyantlı ürün için validasyon
    if (_productType != 'normal') {
      if (_colors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('En az bir renk eklemelisiniz')),
        );
        return;
      }
      if (_productType == 'clothing' && _selectedSizes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('En az bir beden seçmelisiniz')),
        );
        return;
      }
      if (_productType == 'shoes' && _selectedShoeSizes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('En az bir numara seçmelisiniz')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Kullanıcı oturumu bulunamadı');

      final shopResponse = await _supabase
          .from('shops')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse == null) {
        throw Exception('Mağaza bulunamadı');
      }

      final shopId = shopResponse['id'] as String;

      final imageUrls = await _uploadImages(shopId);
      final primaryImageUrl = imageUrls.isNotEmpty ? imageUrls.first : null;
      final additionalImageUrls = imageUrls.length > 1 ? imageUrls.sublist(1) : <String>[];

      final price = double.parse(_priceController.text);
      final oldPrice = _hasDiscount && _oldPriceController.text.isNotEmpty
          ? double.parse(_oldPriceController.text)
          : null;
      final stock = int.parse(_stockController.text);

      // Renkleri JSON formatına çevir
      final colorsJson = _colors.map((c) => c.toJson()).toList();

      if (widget.product == null) {
        await _productService.addProduct(
          shopId: shopId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          price: price,
          oldPrice: oldPrice,
          stockQuantity: stock,
          imageUrl: primaryImageUrl,
          additionalImages: additionalImageUrls,
          category: _selectedCategory,
          productType: _productType,
          sizes: _selectedSizes.toList(),
          shoeSizes: _selectedShoeSizes.toList(),
          colors: colorsJson,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ürün başarıyla eklendi'), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        }
      } else {
        await _productService.updateProduct(
          productId: widget.product!.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          price: price,
          oldPrice: oldPrice,
          stockQuantity: stock,
          imageUrl: primaryImageUrl,
          additionalImages: additionalImageUrls,
          category: _selectedCategory,
          productType: _productType,
          sizes: _selectedSizes.toList(),
          shoeSizes: _selectedShoeSizes.toList(),
          colors: colorsJson,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ürün başarıyla güncellendi'), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint('Ürün kaydetme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.product != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Ürünü Düzenle' : 'Yeni Ürün Ekle'),
        backgroundColor: Colors.orange.shade700,
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _isLoading ? null : _deleteProduct,
              tooltip: 'Ürünü Sil',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildImagePicker(),
                  const SizedBox(height: 24),
                  _buildBasicInfoSection(),
                  const SizedBox(height: 24),
                  _buildVariantSection(),
                  const SizedBox(height: 24),
                  _buildPricingSection(),
                  const SizedBox(height: 32),
                  _buildSaveButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildImagePicker() {
    final totalImages = _imageUrls.length + _selectedImages.length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Ürün Resimleri',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '$totalImages/$_maxImages',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Resim grid
        if (totalImages > 0) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: totalImages,
            itemBuilder: (context, index) {
              final isUrl = index < _imageUrls.length;
              
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: isUrl
                        ? Image.network(
                            _imageUrls[index],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            // ignore: unnecessary_underscores
                            errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          )
                        : FutureBuilder<Uint8List>(
                            future: _selectedImages[index - _imageUrls.length].readAsBytes(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                );
                              }
                              return _buildPlaceholder();
                            },
                          ),
                  ),
                  // Sil butonu
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () => _removeImage(
                        isUrl ? index : index - _imageUrls.length,
                        isUrl: isUrl,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  // Ana resim badge
                  if (index == 0)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Ana',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        
        // Resim ekle butonu
        if (totalImages < _maxImages)
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _pickImages,
            icon: const Icon(Icons.add_photo_alternate),
            label: Text(totalImages == 0 ? 'Resim Ekle' : 'Daha Fazla Resim Ekle'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        
        const SizedBox(height: 4),
        Text(
          'En fazla $_maxImages resim ekleyebilirsiniz. İlk resim ana resim olacaktır.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade300,
      child: const Center(
        child: Icon(Icons.image, color: Colors.grey, size: 32),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Temel Bilgiler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Ürün Adı *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.shopping_bag),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Ürün adı gerekli' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Açıklama *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              validator: (value) => value?.isEmpty ?? true ? 'Açıklama gerekli' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _sellerCategories.contains(_selectedCategory) ? _selectedCategory : null,
              decoration: const InputDecoration(
                labelText: 'Kategori',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: _sellerCategories.isEmpty
                  ? [
                      const DropdownMenuItem<String>(
                        value: null,
                        enabled: false,
                        child: Text('Henüz kategori eklenmedi', style: TextStyle(color: Colors.grey)),
                      ),
                    ]
                  : _sellerCategories.map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(cat),
                      );
                    }).toList(),
              onChanged: _sellerCategories.isEmpty ? null : (value) => setState(() => _selectedCategory = value),
              validator: (value) => value == null || value.isEmpty ? 'Kategori seçin' : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Sadece kendi eklediğiniz kategoriler gösterilir. Kategori eklemek için ürünler sayfasından "Kategori Ekle" butonuna tıklayın.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Varyantlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            
            // Ürün Tipi Seçimi
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'normal', label: Text('Normal'), icon: Icon(Icons.widgets)),
                ButtonSegment(value: 'clothing', label: Text('Giyim'), icon: Icon(Icons.checkroom)),
                ButtonSegment(value: 'shoes', label: Text('Ayakkabı'), icon: Icon(Icons.sports_football)),
              ],
              selected: {_productType},
              onSelectionChanged: (Set<String> value) {
                setState(() => _productType = value.first);
              },
            ),
            const SizedBox(height: 16),

            // Giyim - Beden Seçimi
            if (_productType == 'clothing') ...[
              const Text('Bedenler', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSizes.map((size) {
                  final isSelected = _selectedSizes.contains(size);
                  return FilterChip(
                    label: Text(size),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedSizes.add(size);
                        } else {
                          _selectedSizes.remove(size);
                        }
                      });
                    },
                    selectedColor: Colors.orange.shade200,
                    checkmarkColor: Colors.orange.shade700,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Ayakkabı - Numara Seçimi
            if (_productType == 'shoes') ...[
              const Text('Numaralar', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableShoeSizes.map((size) {
                  final isSelected = _selectedShoeSizes.contains(size);
                  return FilterChip(
                    label: Text(size.toString()),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedShoeSizes.add(size);
                        } else {
                          _selectedShoeSizes.remove(size);
                        }
                      });
                    },
                    selectedColor: Colors.orange.shade200,
                    checkmarkColor: Colors.orange.shade700,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Renkler (tüm varyant tipleri için)
            if (_productType != 'normal') ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Renkler', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _showAddColorDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Renk Ekle'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_colors.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('Henüz renk eklenmedi', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_colors.length, (index) {
                    final color = _colors[index];
                    return Chip(
                      avatar: CircleAvatar(
                        backgroundColor: Color(int.parse(color.hex.replaceFirst('#', '0xFF'))),
                      ),
                      label: Text('${color.name} (Stok: ${color.stock})'),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => _removeColor(index),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddColorDialog() {
    String? selectedColorName;
    String? selectedColorHex;
    final stockController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Renk Ekle'),
            contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Renk Picker Widget
                    _ColorPickerWidget(
                      key: _colorPickerKey,
                      onColorSelected: (colorName, hexCode) {
                        setDialogState(() {
                          selectedColorName = colorName;
                          selectedColorHex = hexCode;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    // Stok Input
                    TextField(
                      controller: stockController,
                      decoration: const InputDecoration(
                        labelText: 'Stok *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.inventory),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              ElevatedButton(
                onPressed: () {
                  if (selectedColorName == null || selectedColorHex == null) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lütfen bir renk seçin')),
                    );
                    return;
                  }
                  
                  final stock = int.tryParse(stockController.text) ?? 0;
                  
                  setState(() {
                    _colors.add(ProductColor(
                      name: selectedColorName!,
                      hex: selectedColorHex!,
                      stock: stock,
                    ));
                  });
                  
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                ),
                child: const Text('Ekle'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPricingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fiyatlandırma', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            
            // Komisyon oranı bilgisi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Platform Komisyon Oranı: %${_commissionRate.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Fiyat *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                      suffixText: '₺',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Fiyat gerekli';
                      final price = double.tryParse(value);
                      if (price == null || price <= 0) return 'Geçerli bir fiyat girin';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _stockController,
                    decoration: const InputDecoration(
                      labelText: 'Stok *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.inventory),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Stok gerekli';
                      final stock = int.tryParse(value);
                      if (stock == null || stock < 0) return 'Geçerli bir stok girin';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            
            // Fiyat girildiğinde canlı hesaplama göster
            if (_priceController.text.isNotEmpty && double.tryParse(_priceController.text) != null) ...[
              const SizedBox(height: 16),
              _buildCommissionCalculation(),
            ],
            
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('İndirim Var'),
              value: _hasDiscount,
              onChanged: (value) => setState(() => _hasDiscount = value),
              activeTrackColor: Colors.orange.shade200,
              activeThumbColor: Colors.orange.shade700,
            ),
            if (_hasDiscount) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _oldPriceController,
                decoration: const InputDecoration(
                  labelText: 'İndirim Öncesi Fiyat',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.discount),
                  suffixText: '₺',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                validator: (value) {
                  if (_hasDiscount && (value == null || value.isEmpty)) {
                    return 'İndirim öncesi fiyat gerekli';
                  }
                  if (_hasDiscount && value != null && value.isNotEmpty) {
                    final oldPrice = double.tryParse(value);
                    final currentPrice = double.tryParse(_priceController.text);
                    if (oldPrice != null && currentPrice != null && oldPrice <= currentPrice) {
                      return 'Eski fiyat şimdiki fiyattan büyük olmalı';
                    }
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Komisyon hesaplama kartı
  Widget _buildCommissionCalculation() {
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final commission = _calculateCommission(price);
    final netEarnings = _calculateNetEarnings(price);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade50, Colors.green.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Kazanç Hesaplaması',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildCalculationRow('Satış Fiyatı', price, Colors.grey),
          const SizedBox(height: 8),
          _buildCalculationRow(
            'Platform Komisyonu (%${_commissionRate.toStringAsFixed(1)})',
            -commission,
            Colors.red,
          ),
          const Divider(height: 16),
          _buildCalculationRow(
            'Net Kazanç (Sizin Payınız)',
            netEarnings,
            Colors.green,
            bold: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.green.shade700, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bu ürün satıldığında ₺${netEarnings.toStringAsFixed(2)} kazanç elde edersiniz.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculationRow(String label, double value, Color color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          '${value >= 0 ? '+' : '-'}₺${value.abs().toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading || _isUploadingImage ? null : _saveProduct,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      child: _isUploadingImage
          ? const Text('Resimler Yükleniyor...')
          : Text(widget.product != null ? 'Değişiklikleri Kaydet' : 'Ürünü Ekle'),
    );
  }

  Future<void> _deleteProduct() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: const Text('Bu ürünü silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
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

    setState(() => _isLoading = true);

    try {
      await _productService.deleteProduct(widget.product!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün silindi')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// Özel Renk Picker Widget (inline)
class _ColorPickerWidget extends StatefulWidget {
  final Function(String colorName, String hexCode) onColorSelected;
  
  const _ColorPickerWidget({
    super.key,
    required this.onColorSelected,
  });

  @override
  State<_ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<_ColorPickerWidget> {
  final List<Map<String, dynamic>> predefinedColors = [
    {'name': 'Kırmızı', 'hex': '#FF0000', 'color': const Color(0xFFFF0000)},
    {'name': 'Mavi', 'hex': '#0000FF', 'color': const Color(0xFF0000FF)},
    {'name': 'Yeşil', 'hex': '#00AA00', 'color': const Color(0xFF00AA00)},
    {'name': 'Sarı', 'hex': '#FFFF00', 'color': const Color(0xFFFFFF00)},
    {'name': 'Siyah', 'hex': '#000000', 'color': const Color(0xFF000000)},
    {'name': 'Beyaz', 'hex': '#FFFFFF', 'color': const Color(0xFFFFFFFF)},
    {'name': 'Turuncu', 'hex': '#FFA500', 'color': const Color(0xFFFFA500)},
    {'name': 'Mor', 'hex': '#800080', 'color': const Color(0xFF800080)},
    {'name': 'Pembe', 'hex': '#FFC0CB', 'color': const Color(0xFFFFC0CB)},
    {'name': 'Gri', 'hex': '#808080', 'color': const Color(0xFF808080)},
    {'name': 'Turkuaz', 'hex': '#40E0D0', 'color': const Color(0xFF40E0D0)},
    {'name': 'Kahverengi', 'hex': '#A52A2A', 'color': const Color(0xFFA52A2A)},
  ];

  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Renk Seç',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: predefinedColors.length,
          itemBuilder: (context, index) {
            final color = predefinedColors[index];
            final isSelected = _selectedIndex == index;

            return GestureDetector(
              onTap: () {
                setState(() => _selectedIndex = index);
                widget.onColorSelected(color['name'], color['hex']);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: color['color'],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? Colors.orange.shade700 : Colors.grey.shade300,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 32)
                    : null,
              ),
            );
          },
        ),
        if (_selectedIndex != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: predefinedColors[_selectedIndex!]['color'],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      predefinedColors[_selectedIndex!]['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      predefinedColors[_selectedIndex!]['hex'],
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
