// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/category_model.dart';
import '../../../core/models/shop_model.dart';
import '../../../core/services/user_distance_service.dart';
import '../services/shop_service.dart';
import '../widgets/shop_card.dart';

class CategoryShopsScreen extends StatefulWidget {
  final Category category;

  const CategoryShopsScreen({super.key, required this.category});

  @override
  State<CategoryShopsScreen> createState() => _CategoryShopsScreenState();
}

class _CategoryShopsScreenState extends State<CategoryShopsScreen> {
  final ShopService _shopService = ShopService();
  List<Shop> _shops = [];
  bool _isLoading = true;
  bool _globalOrdersEnabled = true;

  /// Şu an geçerli kuponu olan dükkanlar ("Kupon Var" rozeti). Liste başına
  /// TEK sorguyla dolar (eskiden her kart kendi sorgusunu atıyordu).
  Set<String> _couponShopIds = {};

  /// Kartlarda uzaklık göstermek için kullanıcının konumu. İzin İSTENMEZ;
  /// yalnızca daha önce izin verilmişse okunur.
  Position? _userPosition;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Shop> get _filteredShops {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _shops;
    return _shops.where((shop) {
      final name = shop.name.toLowerCase();
      final description = (shop.description ?? '').toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadShops();
    _loadUserPosition();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserPosition() async {
    final position = await UserDistanceService.positionIfAllowed();
    if (!mounted || position == null) return;
    setState(() => _userPosition = position);
  }

  /// "850 m" / "1,2 km"; konum ya da dükkan koordinatı yoksa null.
  String? _distanceLabel(Shop shop) {
    final meters = UserDistanceService.distanceMeters(
      from: _userPosition,
      targetLat: shop.latitude,
      targetLng: shop.longitude,
    );
    return meters == null ? null : UserDistanceService.format(meters);
  }

  Future<void> _loadShops() async {
    setState(() => _isLoading = true);

    try {
      // Global sipariş durumunu yükle
      try {
        final settingsResponse = await Supabase.instance.client
            .from('app_about_settings')
            .select('global_orders_enabled')
            .maybeSingle();

        if (settingsResponse != null) {
          _globalOrdersEnabled =
              settingsResponse['global_orders_enabled'] as bool? ?? true;
        }
      } catch (e) {
        debugPrint('Global sipariş durumu yüklenirken hata: $e');
      }

      final shops = await _shopService.getShopsByCategory(widget.category.id);
      // Sponsor dükkanları en üste sabitle
      shops.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
      _loadCoupons(shops);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dükkanlar yüklenirken hata: $e')),
        );
      }
    }
  }

  /// Rozetler ilk çizimi bekletmesin diye ayrı yüklenir.
  Future<void> _loadCoupons(List<Shop> shops) async {
    final ids = await _shopService.getShopIdsWithActiveCoupons(
      shops.map((s) => s.id),
    );
    if (mounted) setState(() => _couponShopIds = ids);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.category.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        // Yüklenirken "0 Dükkan" yazmasın.
                        _isLoading ? 'Yükleniyor...' : '${_shops.length} Dükkan',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
              child: Container(
                color: const Color(0xFFF5F7FA),
                child: Column(
                  children: [
                    if (!_isLoading && _shops.isNotEmpty) _buildSearchField(),
                    Expanded(
                      child: _isLoading
                          ? const ShopCardSkeletonList(
                              padding: EdgeInsets.all(20),
                            )
                          : _buildShopsList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Dükkan ara...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
    );
  }

  Widget _buildShopsList() {
    if (_shops.isEmpty) {
      return const Center(
        child: Text('Bu kategoride henüz dükkan bulunmuyor'),
      );
    }

    final filtered = _filteredShops;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Arama sonucu bulunamadı',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              icon: const Icon(Icons.clear),
              label: const Text('Aramayı Temizle'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final shop = filtered[index];
        return ShopCard(
          shop: shop,
          globalOrdersEnabled: _globalOrdersEnabled,
          hasCoupon: _couponShopIds.contains(shop.id),
          distanceLabel: _distanceLabel(shop),
        );
      },
    );
  }
}
