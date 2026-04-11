// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_service.dart';

class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  final _supabase = Supabase.instance.client;
  late final ShopService _shopService;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _shopData;
  
  // Kategoriler
  List<Map<String, dynamic>> _categories = [];
  String? _selectedCategoryId;
  bool _isLoadingCategories = false;

  // Form Controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _freeDeliveryController = TextEditingController();
  final _deliveryTimeController = TextEditingController();
  final _deliveryFeeController = TextEditingController();

  // Kurye durumu
  bool _hasOwnCourier = false;

  // Working hours
  Map<String, dynamic> _workingHours = {};

  // Image files (XFile - Web ve Mobile uyumlu)
  XFile? _logoFile;
  XFile? _coverFile;
  // Önizleme için bellekte tutulacak byte'lar
  Uint8List? _logoBytes;
  Uint8List? _coverBytes;

  @override
  void initState() {
    super.initState();
    _shopService = ShopService(_supabase);
    _loadShopData();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _minOrderController.dispose();
    _freeDeliveryController.dispose();
    _deliveryTimeController.dispose();
    _deliveryFeeController.dispose();
    super.dispose();
  }

  Future<void> _loadShopData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('🔴 SHOP SETTINGS DEBUG: Kullanıcı giriş yapmamış');
        return;
      }

      debugPrint('🔵 SHOP SETTINGS DEBUG: Mağaza verileri yükleniyor, userId: $userId');
      final shop = await _shopService.getShop(userId);
      if (shop != null) {
        _shopData = shop;
        debugPrint('🔵 SHOP SETTINGS DEBUG: Mağaza bulundu');
        debugPrint('🔵 SHOP SETTINGS DEBUG: cover_image: ${shop['cover_image']}');
        debugPrint('🔵 SHOP SETTINGS DEBUG: logo_url: ${shop['logo_url']}');
        
        _nameController.text = shop['name'] ?? '';
        _descriptionController.text = shop['description'] ?? '';
        _phoneController.text = shop['phone'] ?? '';
        _addressController.text = shop['address'] ?? '';
        _minOrderController.text = (shop['min_order_amount'] ?? 0).toString();
        _freeDeliveryController.text = (shop['free_delivery_min_amount'] ?? 0).toString();
        _deliveryTimeController.text = shop['delivery_time'] ?? '30-45 dakika';
        _deliveryFeeController.text = (shop['delivery_fee'] ?? 0).toString();
        _hasOwnCourier = shop['has_own_courier'] ?? false;
        _selectedCategoryId = shop['category_id'];

        _workingHours = shop['working_hours'] != null
            ? Map<String, dynamic>.from(shop['working_hours'])
            : _shopService.getDefaultWorkingHours();
      } else {
        debugPrint('🔴 SHOP SETTINGS DEBUG: Mağaza bulunamadı!');
      }
    } catch (e) {
      debugPrint('🔴 SHOP SETTINGS DEBUG: Hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veri yüklenemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final categories = await _shopService.getCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoadingCategories = false;
        });
      }
    } catch (e) {
      debugPrint('Kategoriler yüklenirken hata: $e');
      if (mounted) {
        setState(() => _isLoadingCategories = false);
      }
    }
  }

  Future<void> _saveCategory() async {
    if (_selectedCategoryId == null) return;
    
    setState(() => _isSaving = true);
    try {
      await _shopService.updateShopCategory(
        shopId: _shopData!['id'],
        categoryId: _selectedCategoryId!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ana kategori güncellendi'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveBasicInfo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      String? logoUrl;
      String? coverUrl;

      // Upload logo if selected
      if (_logoFile != null) {
        // ignore: avoid_print
        print('DEBUG shop_settings - Logo yükleniyor');
        logoUrl = await _shopService.uploadLogo(_shopData!['id'], _logoFile!);
      }

      // Upload cover if selected
      if (_coverFile != null) {
        coverUrl = await _shopService.uploadCoverImage(_shopData!['id'], _coverFile!);
      }


      await _shopService.updateShop(
        shopId: _shopData!['id'],
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        logoUrl: logoUrl,
        coverImage: coverUrl,
      );
      

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mağaza bilgileri güncellendi'), backgroundColor: Colors.green),
        );
        _loadShopData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveDeliverySettings() async {
    setState(() => _isSaving = true);
    
    // DEBUG: Kaydedilecek değerleri yazdır
    final minOrderAmount = double.tryParse(_minOrderController.text) ?? 0;
    final freeDeliveryMinAmount = double.tryParse(_freeDeliveryController.text) ?? 0;
    final deliveryTime = _deliveryTimeController.text.trim();
    final deliveryFee = _hasOwnCourier ? (double.tryParse(_deliveryFeeController.text) ?? 0) : null;
    
    debugPrint('🔧 SELLER PANEL: Teslimat ayarları kaydediliyor...');
    debugPrint('🔧 SELLER PANEL: shopId: ${_shopData!['id']}');
    debugPrint('🔧 SELLER PANEL: minOrderAmount: $minOrderAmount');
    debugPrint('🔧 SELLER PANEL: freeDeliveryMinAmount: $freeDeliveryMinAmount');
    debugPrint('🔧 SELLER PANEL: deliveryTime: "$deliveryTime"');
    debugPrint('🔧 SELLER PANEL: deliveryFee: $deliveryFee');
    
    try {
      await _shopService.updateDeliverySettings(
        shopId: _shopData!['id'],
        minOrderAmount: minOrderAmount,
        freeDeliveryMinAmount: freeDeliveryMinAmount,
        deliveryTime: deliveryTime,
        deliveryFee: deliveryFee,
        // hasOwnCourier parametresi kaldırıldı - sadece admin değiştirebilir
      );

      debugPrint('✅ SELLER PANEL: Teslimat ayarları başarıyla kaydedildi!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Teslimat ayarları güncellendi'), backgroundColor: Colors.green),
        );
        // Kaydettikten sonra veriyi yeniden yükle
        _loadShopData();
      }
    } catch (e) {
      debugPrint('❌ SELLER PANEL: Hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveWorkingHours() async {
    setState(() => _isSaving = true);
    try {
      await _shopService.updateWorkingHours(
        shopId: _shopData!['id'],
        workingHours: _workingHours,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Çalışma saatleri güncellendi'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickImage(bool isLogo) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        if (isLogo) {
          _logoFile = image;
          _logoBytes = bytes;
        } else {
          _coverFile = image;
          _coverBytes = bytes;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mağaza Ayarları'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shopData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.store_mall_directory_outlined, size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('Mağazanız bulunamadı', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCoverSection(),
                      const SizedBox(height: 24),
                      _buildBasicInfoSection(),
                      const SizedBox(height: 24),
                      _buildCategorySection(),
                      const SizedBox(height: 24),
                      _buildDeliverySection(),
                      const SizedBox(height: 24),
                      _buildWorkingHoursSection(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCoverSection() {
    debugPrint('🔵 SHOP SETTINGS DEBUG: _buildCoverSection çağrıldı');
    debugPrint('🔵 SHOP SETTINGS DEBUG: _coverFile: $_coverFile');
    debugPrint('🔵 SHOP SETTINGS DEBUG: _shopData?["cover_image"]: ${_shopData?['cover_image']}');
    
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover Image
          Stack(
            children: [
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _coverFile != null ||
                            _shopData?['cover_image'] != null ||
                            _shopData?['banner_url'] != null
                        ? [Colors.transparent, Colors.transparent]
                        : [Colors.orange.shade400, Colors.orange.shade700],
                  ),
                  color: Colors.grey.shade300,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  image: _coverBytes != null
                      ? DecorationImage(image: MemoryImage(_coverBytes!), fit: BoxFit.cover)
                      : _shopData?['cover_image'] != null
                          ? DecorationImage(image: NetworkImage(_shopData!['cover_image']), fit: BoxFit.cover)
                          : _shopData?['banner_url'] != null
                              ? DecorationImage(image: NetworkImage(_shopData!['banner_url']), fit: BoxFit.cover)
                              : null,
                ),
                child: _coverFile == null && _shopData?['cover_image'] == null && _shopData?['banner_url'] == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.store, size: 50, color: Colors.white.withOpacity(0.9)),
                            const SizedBox(height: 8),
                            Text(
                              'Mağaza Kapak Fotoğrafı',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      )
                    : null,
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: IconButton.filled(
                  onPressed: () => _pickImage(false),
                  icon: const Icon(Icons.camera_alt),
                  style: IconButton.styleFrom(backgroundColor: Colors.orange.shade700),
                ),
              ),
            ],
          ),

          // Logo
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: _logoBytes != null
                          ? MemoryImage(_logoBytes!)
                          : _shopData?['logo_url'] != null
                              ? NetworkImage(_shopData!['logo_url']) as ImageProvider
                              : null,
                      child: _logoBytes == null && _shopData?['logo_url'] == null
                          ? const Icon(Icons.store, size: 40, color: Colors.grey)
                          : null,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: IconButton.filled(
                        onPressed: () => _pickImage(true),
                        icon: const Icon(Icons.camera_alt, size: 16),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          minimumSize: const Size(28, 28),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_shopData?['name'] ?? 'Mağaza Adı', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star, size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 4),
                          Text('${(_shopData?['rating'] ?? 0).toStringAsFixed(1)} (${_shopData?['review_count'] ?? 0} yorum)'),
                        ],
                      ),
                      if (_shopData?['is_verified'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.verified, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 4),
                              const Text('Doğrulanmış Mağaza', style: TextStyle(fontSize: 12, color: Colors.blue)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Text('Temel Bilgiler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Mağaza Adı',
                  prefixIcon: Icon(Icons.store),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty ?? true ? 'Mağaza adı gerekli' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Mağaza Açıklaması',
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefon',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Adres',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveBasicInfo,
                  icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  label: const Text('Bilgileri Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.category_outlined, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Ana Kategori', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            
            _isLoadingCategories
                ? const Center(child: CircularProgressIndicator())
                : _categories.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Henüz kategori bulunmuyor'),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Mağazanızın ana kategorisini seçin. Bu kategori, uygulamanın market ekranında mağazınızın görüneceği bölümü belirler.',
                                    style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          DropdownButtonFormField<String>(
                            value: _selectedCategoryId,
                            decoration: InputDecoration(
                              labelText: 'Ana Kategori',
                              prefixIcon: const Icon(Icons.category),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            hint: const Text('Kategori seçin'),
                            items: _categories.map((category) {
                              return DropdownMenuItem<String>(
                                value: category['id'] as String,
                                child: Row(
                                  children: [
                                    if (category['icon'] != null) ...[
                                      Text(
                                        _getCategoryIcon(category['icon'] as String),
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(category['name'] as String),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedCategoryId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveCategory,
                              icon: _isSaving
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save),
                              label: const Text('Kategoriyi Kaydet'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
          ],
        ),
      ),
    );
  }

  String _getCategoryIcon(String iconName) {
    // Basit icon mapping
    final iconMap = {
      'utensils': '🍽️',
      'shopping-bag': '🛍️',
      'zap': '⚡',
      'tshirt': '👕',
      'cake': '🍰',
      'car': '🚗',
      'phone': '📱',
      'book': '📚',
      'music': '🎵',
      'game': '🎮',
    };
    return iconMap[iconName] ?? '📁';
  }

  Widget _buildDeliverySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_shipping, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Teslimat Ayarları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            
            // Kurye durumu gösterimi (sadece okuma)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _hasOwnCourier ? Colors.green.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hasOwnCourier ? Colors.green.shade200 : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasOwnCourier ? Icons.check_circle : Icons.info_outline,
                    color: _hasOwnCourier ? Colors.green.shade700 : Colors.grey.shade600,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasOwnCourier ? 'Kuryeniz Var' : 'Kuryeniz Yok',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _hasOwnCourier ? Colors.green.shade900 : Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _hasOwnCourier
                            ? 'Kendi teslimat ücretinizi belirleyebilirsiniz'
                            : 'Kurye durumunuzu değiştirmek için admin ile iletişime geçin',
                          style: TextStyle(
                            fontSize: 13,
                            color: _hasOwnCourier ? Colors.green.shade700 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _minOrderController,
              decoration: const InputDecoration(
                labelText: 'Minimum Sipariş Tutarı (₺)',
                prefixIcon: Icon(Icons.money),
                border: OutlineInputBorder(),
                hintText: '0 = Limit yok',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _freeDeliveryController,
              decoration: const InputDecoration(
                labelText: 'Ücretsiz Teslimat için Min. Tutar (₺)',
                prefixIcon: Icon(Icons.local_offer),
                border: OutlineInputBorder(),
                hintText: '0 = Her zaman ücretsiz',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            // Kuryesi varsa teslimat ücreti alanını göster
            if (_hasOwnCourier) ...[
              TextField(
                controller: _deliveryFeeController,
                decoration: const InputDecoration(
                  labelText: 'Teslimat Ücreti (₺)',
                  prefixIcon: Icon(Icons.delivery_dining),
                  border: OutlineInputBorder(),
                  hintText: '0',
                  helperText: 'Kendi kuryeniz için teslimat ücreti',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Kuryeniz olmadığı için teslimat ücretini admin belirler. Admin\'in kuryeleri siparişlerinizi teslim edecektir.',
                        style: TextStyle(color: Colors.orange.shade900, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _deliveryTimeController,
              decoration: const InputDecoration(
                labelText: 'Tahmini Teslimat Süresi',
                prefixIcon: Icon(Icons.timer),
                border: OutlineInputBorder(),
                hintText: 'örn: 30-45 dakika',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveDeliverySettings,
                icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: const Text('Teslimat Ayarlarını Kaydet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkingHoursSection() {
    final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Çalışma Saatleri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            ...days.map((day) => _buildDayRow(day)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveWorkingHours,
                icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: const Text('Çalışma Saatlerini Kaydet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayRow(String day) {
    final dayData = _workingHours[day] as Map<String, dynamic>? ?? {'open': '09:00', 'close': '18:00', 'active': true};
    final isActive = dayData['active'] as bool? ?? true;
    final openTime = dayData['open'] as String? ?? '09:00';
    final closeTime = dayData['close'] as String? ?? '18:00';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
        Switch(
          value: isActive,
          activeTrackColor: Colors.orange.shade200,
          activeThumbColor: Colors.orange.shade700,
          onChanged: (value) {
              setState(() {
                _workingHours[day] = {
                  ...dayData,
                  'active': value,
                };
              });
            },
          ),
          SizedBox(
            width: 90,
            child: Text(
              ShopService.dayNamesTurkish[day] ?? day,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.black : Colors.grey,
              ),
            ),
          ),
          const Spacer(),
          if (isActive) ...[
            _buildTimeButton(day, 'open', openTime),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('-'),
            ),
            _buildTimeButton(day, 'close', closeTime),
          ] else
            Text('Kapalı', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildTimeButton(String day, String type, String time) {
    return InkWell(
      onTap: () async {
        final initialTime = TimeOfDay(
          hour: int.tryParse(time.split(':')[0]) ?? 9,
          minute: int.tryParse(time.split(':')[1]) ?? 0,
        );

        final picked = await showTimePicker(
          context: context,
          initialTime: initialTime,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            );
          },
        );

        if (picked != null) {
          final newTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          setState(() {
            _workingHours[day] = {
              ...(_workingHours[day] as Map<String, dynamic>? ?? {}),
              type: newTime,
            };
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(time),
      ),
    );
  }
}
