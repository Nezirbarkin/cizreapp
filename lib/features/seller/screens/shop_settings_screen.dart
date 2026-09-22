// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_service.dart';
import '../../../core/models/address_model.dart';
import '../../market/screens/address_picker_screen.dart';
import '../widgets/common/seller_empty_state.dart';
import '../widgets/common/seller_section_card.dart';

class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }
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
  final _emailController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _freeDeliveryController = TextEditingController();
  final _deliveryTimeController = TextEditingController();
  final _deliveryFeeController = TextEditingController();

  // Kurye durumu
  bool _hasOwnCourier = false;

  // Admin fiyat müdahalesi (shops.pre_override_* dolu olduğunda aktif).
  // Müdahale açıkken canlı teslimat ücreti / min. sepet tutarı admin'in
  // belirlediği değerdir; bu ekrandaki alanlar satıcının kendi (müdahale
  // kalkınca geçerli olacak) değerini gösterir ve oraya yazar.
  double? _adminOverrideDeliveryFee;
  double? _adminOverrideMinOrder;
  String? _adminOverrideDeliveryTime;
  String? _adminOverrideNote;

  bool get _hasAdminPricingOverride =>
      _adminOverrideDeliveryFee != null ||
      _adminOverrideMinOrder != null ||
      _adminOverrideDeliveryTime != null;

  // Mağaza konumu (harita ile seçilir) ve "Gel Al" aktifliği
  double? _latitude;
  double? _longitude;
  bool _pickupEnabled = false;

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
    _emailController.dispose();
    _minOrderController.dispose();
    _freeDeliveryController.dispose();
    _deliveryTimeController.dispose();
    _deliveryFeeController.dispose();
    super.dispose();
  }

  Future<void> _loadShopData({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
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
        _emailController.text = shop['email'] ?? '';
        // Admin müdahalesi varsa alanlar satıcının KENDİ değerini gösterir
        // (pre_override_*); canlı fiyat admin'in koyduğu değerdir ve
        // aşağıdaki uyarı kutusunda ayrıca belirtilir.
        final sellerMinOrder = (shop['pre_override_min_order_amount'] as num?)
            ?.toDouble();
        final sellerDeliveryFee = (shop['pre_override_delivery_fee'] as num?)
            ?.toDouble();
        // Yedekteki boş dize "satıcının süresi yoktu" sentinel'idir.
        final sellerDeliveryTime =
            shop['pre_override_delivery_time'] as String?;
        _adminOverrideMinOrder = sellerMinOrder == null
            ? null
            : (shop['min_order_amount'] as num?)?.toDouble();
        _adminOverrideDeliveryFee = sellerDeliveryFee == null
            ? null
            : (shop['delivery_fee'] as num?)?.toDouble();
        _adminOverrideDeliveryTime = sellerDeliveryTime == null
            ? null
            : (shop['delivery_time'] as String? ?? '');
        _adminOverrideNote = shop['admin_pricing_override_note'] as String?;

        _minOrderController.text =
            (sellerMinOrder ?? shop['min_order_amount'] ?? 0).toString();
        _freeDeliveryController.text = (shop['free_delivery_min_amount'] ?? 0).toString();
        _deliveryTimeController.text =
            sellerDeliveryTime ?? shop['delivery_time'] ?? '30-45 dakika';
        _deliveryFeeController.text =
            (sellerDeliveryFee ?? shop['delivery_fee'] ?? 0).toString();
        _hasOwnCourier = shop['has_own_courier'] ?? false;
        _selectedCategoryId = shop['category_id'];
        _latitude = (shop['latitude'] as num?)?.toDouble();
        _longitude = (shop['longitude'] as num?)?.toDouble();
        _pickupEnabled = shop['pickup_enabled'] ?? false;

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
      if (mounted && showLoading) setState(() => _isLoading = false);
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

  /// Haritadan mağaza konumu seçtirir; dönen adresten lat/lng (ve adres
  /// boşsa tam adres metnini) alır. Yeni harita kodu yazmak yerine müşteri
  /// tarafındaki `AddressPickerScreen` aynen yeniden kullanılıyor.
  Future<void> _pickShopLocation() async {
    final result = await Navigator.push<Address>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          initialAddress: _addressController.text.trim(),
          warningBanner:
              'Lütfen dükkanınızın gerçek konumunu işaretleyin. Müşteriler ve kurye, siparişleri bu noktaya göre bulur; yanlış konum teslimatların ve "Gel Al" hizmetinin sorunlu çalışmasına yol açar.',
        ),
      ),
    );

    if (result == null) return;
    final lat = result.latitude;
    final lng = result.longitude;
    if (lat == null || lng == null) return;

    setState(() {
      _latitude = lat;
      _longitude = lng;
      if (_addressController.text.trim().isEmpty) {
        _addressController.text = result.fullAddress;
      }
    });
  }

  /// "Gel Al" switch'i: telefon/adres/konum tamamlanmadan açılmasına izin
  /// vermez — müşteri/kurye eksik bilgiyle mağazayı bulamaz.
  void _onPickupEnabledChanged(bool value) {
    if (value) {
      final missingInfo = _phoneController.text.trim().isEmpty ||
          _addressController.text.trim().isEmpty ||
          _latitude == null ||
          _longitude == null;
      if (missingInfo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gel Al\'ı aktif etmeden önce telefon, adres ve haritadan konum bilgisini eksiksiz girin',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    setState(() => _pickupEnabled = value);
  }

  Future<void> _saveBasicInfo() async {
    if (!_formKey.currentState!.validate()) return;

    // "Gel Al" aktifken konum zorunlu; switch açılırken de kontrol ediliyor
    // ama kaydetme anında da savunma amaçlı tekrar doğrulanıyor (ör. konum
    // sonradan temizlenmiş olabilir).
    if (_pickupEnabled && (_latitude == null || _longitude == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gel Al aktifken mağaza konumunu haritadan seçmelisiniz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      String? logoUrl;
      String? coverUrl;

      // Upload logo if selected
      if (_logoFile != null) {
        debugPrint('DEBUG shop_settings - Logo yükleniyor');
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
        email: _emailController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        pickupEnabled: _pickupEnabled,
      );
      

      // Yükleme başarılı: bekleyen yerel önizleme byte'larını temizle ki
      // ekran, sunucudan gelen güncel URL'i göstersin (eski görsel kalıntısı kalmasın).
      _logoFile = null;
      _coverFile = null;
      _logoBytes = null;
      _coverBytes = null;

      await _loadShopData(showLoading: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mağaza bilgileri güncellendi'), backgroundColor: Colors.green),
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

      // Kaydettikten sonra veriyi yeniden yükle
      await _loadShopData(showLoading: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Teslimat ayarları güncellendi'), backgroundColor: Colors.green),
        );
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

      await _loadShopData(showLoading: false);

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
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024);
      if (!mounted || image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;

      setState(() {
        if (isLogo) {
          _logoFile = image;
          _logoBytes = bytes;
        } else {
          _coverFile = image;
          _coverBytes = bytes;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Görsel seçildi. Kaydetmek için "Bilgileri Kaydet" butonuna basın.'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      debugPrint('🔴 SHOP SETTINGS DEBUG: Görsel seçilemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Görsel seçilemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mağaza Ayarları'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shopData == null
              ? const SellerEmptyState(
                  icon: Icons.store_mall_directory_outlined,
                  message: 'Mağazanız bulunamadı',
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
    
    final hasPendingImage = _coverFile != null || _logoFile != null;
    final primary = Theme.of(context).colorScheme.primary;

    return SellerSectionCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPendingImage)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Yeni görsel henüz kaydedilmedi. Aşağıdaki "Bilgileri Kaydet" butonuna basın.',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          // Cover Image
          Stack(
            children: [
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _coverFile != null ||
                          _shopData?['cover_image'] != null ||
                          _shopData?['banner_url'] != null
                      ? Colors.grey.shade300
                      : primary,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(SellerSectionCard.radius),
                  ),
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
                            Icon(Icons.store, size: 50, color: Colors.white.withValues(alpha: 0.9)),
                            const SizedBox(height: 8),
                            Text(
                              'Mağaza Kapak Fotoğrafı',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.9),
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
                  style: IconButton.styleFrom(backgroundColor: primary),
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
                          backgroundColor: primary,
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
                          Icon(Icons.star, size: 16, color: Colors.amber.shade700),
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
    final primary = Theme.of(context).colorScheme.primary;
    return SellerSectionCard(
      margin: EdgeInsets.zero,
      title: 'Temel Bilgiler',
      icon: Icons.info_outline,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              // Admin ve kurye müşteriye/dükkana ulaşabilsin diye telefon
              // artık zorunlu. Mevcut boş kayıtlar bloklanmaz, sadece bir
              // dahaki güncellemede doldurulması istenir.
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Telefon gerekli' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'E-posta',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'E-posta gerekli';
                if (!v.contains('@')) return 'Geçerli bir e-posta girin';
                return null;
              },
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
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Adres gerekli' : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickShopLocation,
              icon: const Icon(Icons.map_outlined),
              label: Text(
                _latitude != null && _longitude != null
                    ? 'Konum Seçildi — Değiştir'
                    : 'Haritadan Konum Seç',
              ),
            ),
            if (_latitude != null && _longitude != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Mağaza konumu kaydedildi',
                    style: TextStyle(color: Colors.green.shade700, fontSize: 13),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pickupEnabled,
              onChanged: _onPickupEnabledChanged,
              title: const Text('Gel Al (Mağazadan Teslim) Aktif'),
              subtitle: const Text(
                'Müşteriler siparişlerini kurye beklemeden mağazanızdan teslim alabilir',
              ),
              activeThumbColor: primary,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveBasicInfo,
                icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: const Text('Bilgileri Kaydet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
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

  Widget _buildCategorySection() {
    final primary = Theme.of(context).colorScheme.primary;
    return SellerSectionCard(
      margin: EdgeInsets.zero,
      title: 'Ana Kategori',
      icon: Icons.category_outlined,
      child: _isLoadingCategories
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
              ? const SellerEmptyState(
                  icon: Icons.category_outlined,
                  message: 'Henüz kategori bulunmuyor',
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
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
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
    final primary = Theme.of(context).colorScheme.primary;
    return SellerSectionCard(
      margin: EdgeInsets.zero,
      title: 'Teslimat Ayarları',
      icon: Icons.local_shipping,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Admin fiyat müdahalesi uyarısı: müdahale kaldırılana kadar
          // müşteriye gösterilen değer admin'in belirlediği değerdir.
          if (_hasAdminPricingOverride) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.campaign, color: Colors.amber.shade800),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yönetici fiyat müdahalesi açık',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Şu an müşterilere uygulanan: '
                          '${_adminOverrideDeliveryFee != null ? 'teslimat ₺${_adminOverrideDeliveryFee!.toStringAsFixed(2)}' : 'teslimat (değişmedi)'}'
                          ' • '
                          '${_adminOverrideMinOrder != null ? 'min. sepet ₺${_adminOverrideMinOrder!.toStringAsFixed(2)}' : 'min. sepet (değişmedi)'}'
                          ' • '
                          '${_adminOverrideDeliveryTime != null ? 'süre ${_adminOverrideDeliveryTime!.isEmpty ? '—' : _adminOverrideDeliveryTime!}' : 'süre (değişmedi)'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Aşağıda girdiğiniz değerler kaydedilir ve yönetici '
                          'müdahaleyi kaldırdığında otomatik olarak geçerli olur.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade800,
                          ),
                        ),
                        if (_adminOverrideNote != null &&
                            _adminOverrideNote!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Gerekçe: ${_adminOverrideNote!}',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

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
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkingHoursSection() {
    final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final primary = Theme.of(context).colorScheme.primary;

    return SellerSectionCard(
      margin: EdgeInsets.zero,
      title: 'Çalışma Saatleri',
      icon: Icons.access_time,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...days.map((day) => _buildDayRow(day)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveWorkingHours,
              icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: const Text('Çalışma Saatlerini Kaydet'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayRow(String day) {
    final dayData = _workingHours[day] as Map<String, dynamic>? ?? {'open': '09:00', 'close': '18:00', 'active': true};
    final isActive = dayData['active'] as bool? ?? true;
    final openTime = dayData['open'] as String? ?? '09:00';
    final closeTime = dayData['close'] as String? ?? '18:00';
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Switch(
            value: isActive,
            activeTrackColor: primary.withValues(alpha: 0.3),
            activeThumbColor: primary,
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
