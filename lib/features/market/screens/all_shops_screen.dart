import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/shop_model.dart';
import '../../../core/services/user_distance_service.dart';
import '../services/shop_service.dart';
import '../widgets/shop_card.dart';

class AllShopsScreen extends StatefulWidget {
  final List<Shop>? initialShops;

  const AllShopsScreen({super.key, this.initialShops});

  @override
  State<AllShopsScreen> createState() => _AllShopsScreenState();
}

class _AllShopsScreenState extends State<AllShopsScreen> {
  final ShopService _shopService = ShopService();
  bool _globalOrdersEnabled = true;
  List<Shop> _shops = [];
  bool _isLoading = true;
  String? _error;

  /// Şu an geçerli kuponu olan dükkanlar ("Kupon Var" rozeti). Liste başına
  /// TEK sorguyla dolar; eskiden her kart kendi sorgusunu atıyordu ve arama
  /// kutusuna yazılan her harf bütün kartlar için yeniden sorgu tetikliyordu.
  Set<String> _couponShopIds = {};

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

  /// Kartlarda uzaklık göstermek için kullanıcının konumu. İzin İSTENMEZ;
  /// yalnızca daha önce izin verilmişse okunur (market ekranındaki
  /// "uzaklığı göster" ile veya dükkan sayfasındaki rozetle verilebilir).
  Position? _userPosition;

  @override
  void initState() {
    super.initState();

    // İlk dükkanları yükle (varsa)
    if (widget.initialShops != null && widget.initialShops!.isNotEmpty) {
      _shops = List<Shop>.from(widget.initialShops!);
      _sortShops();
      _isLoading = false;
    }

    _loadData();
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

  void _sortShops() {
    _shops.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Global sipariş durumunu yükle
      final settingsResponse = await Supabase.instance.client
          .from('app_about_settings')
          .select('global_orders_enabled')
          .maybeSingle();

      if (settingsResponse != null && mounted) {
        setState(() {
          _globalOrdersEnabled =
              settingsResponse['global_orders_enabled'] as bool? ?? true;
        });
      }

      // Tüm dükkanları bağımsız olarak yükle
      final shops = await _shopService.getShops();

      if (mounted) {
        setState(() {
          _shops = shops;
          _sortShops();
          _isLoading = false;
          _error = null;
        });
        _loadCoupons(shops);
      }
    } catch (e) {
      debugPrint('AllShopsScreen: Dükkanlar yüklenirken hata: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
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
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Tüm Dükkanlar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            if (!_isLoading && _shops.isNotEmpty)
              Text(
                '${_shops.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else if (_error != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'Tekrar Dene',
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isLoading && _error == null && _shops.isNotEmpty)
            _buildSearchField(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Dönen çember yerine kartın iskeleti: liste gelince içerik zıplamaz.
    if (_isLoading && _shops.isEmpty) {
      return const ShopCardSkeletonList();
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Hata: $_error',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (_shops.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Henüz dükkan bulunmuyor',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredShops;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Arama sonucu bulunamadı',
              style: TextStyle(fontSize: 16, color: Colors.grey),
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
      padding: const EdgeInsets.all(16),
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
