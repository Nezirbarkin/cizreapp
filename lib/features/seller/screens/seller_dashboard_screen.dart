// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/payout_service.dart';
import '../widgets/balance_status_card.dart';
import 'shop_settings_screen.dart';
import 'products_screen.dart';
import 'seller_orders_screen.dart';
import 'seller_return_requests_screen.dart';
import 'seller_reviews_screen.dart';
import 'seller_reports_screen.dart';
import 'coupons_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final PayoutService _payoutService;
  late TabController _tabController;
  
  bool _isLoading = true;
  bool _isAcceptingOrders = true;
  
  // Dashboard verileri
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _topProducts = [];
  
  // Ödeme verileri (YENİ MANTIK)
  List<Map<String, dynamic>> _payoutRequests = [];
  double _pendingPayout = 0.0;       // Net ödenebilir tutar
  double _totalPaid = 0.0;           // Toplam ödenen
  double _commissionDebt = 0.0;      // Komisyon borcu (kuryesi olan için)
  double _adminCredit = 0.0;         // Admin'den alacak
  double _cashPaymentRevenue = 0.0;  // Kapıda ödeme kazancı
  double _onlinePaymentRevenue = 0.0;// Online ödeme kazancı
  double _pendingRequestsTotal = 0.0;
  double _availablePayout = 0.0;
  bool _hasOwnCourier = false;       // Kurye durumu
  Map<String, dynamic>? _shopInfo;
  Map<String, dynamic>? _revenueSummary;  // Gelir özeti

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _payoutService = PayoutService(_supabase);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Satıcının mağazasını bul
      final shopResponse = await _supabase
          .from('shops')
          .select('id, name, iban, bank_name, account_holder_name, pending_payout, total_paid, commission_rate, has_own_courier, delivery_fee, logo_url, is_accepting_orders')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse == null) {
        setState(() {
          _stats = {'hasShop': false};
          _isLoading = false;
        });
        return;
      }

      final shopId = shopResponse['id'];
      _shopInfo = Map<String, dynamic>.from(shopResponse);
      _hasOwnCourier = shopResponse['has_own_courier'] as bool? ?? false;
      _isAcceptingOrders = shopResponse['is_accepting_orders'] as bool? ?? true;

      // İstatistikleri yükle
      final ordersResult = await _supabase
          .from('orders')
          .select('id')
          .eq('shop_id', shopId);
      
      final productsResult = await _supabase
          .from('products')
          .select('id')
          .eq('shop_id', shopId);

      // Son siparişler
      final orders = await _supabase
          .from('orders')
          .select('*, profiles(full_name)')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false)
          .limit(5);

      // En çok satılan ürünler
      final products = await _supabase
          .from('products')
          .select('*')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false)
          .limit(5);

      // Gelir özeti (YENİ - tek sorgu ile tüm gelir verileri)
      _revenueSummary = await _payoutService.getRevenueSummary(shopId);
      _pendingPayout = await _payoutService.getPendingPayoutAmount(shopId);
      _totalPaid = await _payoutService.getTotalPaidAmount(shopId);
      
      // Değişkenleri ata
      _adminCredit = (_revenueSummary!['admin_credit'] as num?)?.toDouble() ?? 0;
      _commissionDebt = (_revenueSummary!['commission_debt'] as num?)?.toDouble() ?? 0;
      _cashPaymentRevenue = (_revenueSummary!['cash_payment_revenue'] as num?)?.toDouble() ?? 0;
      _onlinePaymentRevenue = (_revenueSummary!['online_payment_revenue'] as num?)?.toDouble() ?? 0;

      // Ödeme isteklerini yükle
      _payoutRequests = await _payoutService.getPayoutRequests(userId);

      // Bekleyen ödeme isteklerinin toplam tutarını hesapla
      _pendingRequestsTotal = await _payoutService.getPendingPayoutRequestsTotal(userId);
      
      // Kullanılabilir ödeme tutarı
      _availablePayout = _pendingPayout - _pendingRequestsTotal;
      if (_availablePayout < 0) _availablePayout = 0;

      setState(() {
        _stats = {
          'hasShop': true,
          'ordersCount': (ordersResult as List).length,
          'productsCount': (productsResult as List).length,
        };
        _recentOrders = List<Map<String, dynamic>>.from(orders);
        _topProducts = List<Map<String, dynamic>>.from(products);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Dashboard verileri yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Satıcı Paneli'),
        backgroundColor: Colors.orange.shade700,
        actions: [
          // Raporlar butonu
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Raporlar',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SellerReportsScreen(),
                ),
              );
            },
          ),
          // Ana sayfaya dön butonu
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Ana Sayfaya Dön',
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/',
                (route) => false,
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stats['hasShop'] == false
              ? _buildNoShopView()
              : _buildTabbedDashboard(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          // Drawer Header
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade700, Colors.orange.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            accountName: Text(
              _shopInfo?['name'] ?? 'Mağaza Adı',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            accountEmail: Text(
              _supabase.auth.currentUser?.email ?? '',
              style: const TextStyle(fontSize: 14),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: _shopInfo?['logo_url'] != null
                  ? NetworkImage(_shopInfo!['logo_url'])
                  : null,
              child: _shopInfo?['logo_url'] == null
                  ? Icon(Icons.store, size: 40, color: Colors.orange.shade700)
                  : null,
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  icon: Icons.dashboard_outlined,
                  title: 'Genel Bakış',
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(0);
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.inventory_2_outlined,
                  title: 'Ürünlerim',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProductsScreen(),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.category_outlined,
                  title: 'Kategori Ekle',
                  onTap: () {
                    Navigator.pop(context);
                    _showCategoryManagement();
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.confirmation_number_outlined,
                  title: 'Kuponlar',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CouponsScreen(),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Siparişler',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SellerOrdersScreen(),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.assignment_return_outlined,
                  title: 'İade Talepleri',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SellerReturnRequestsScreen(),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.rate_review_outlined,
                  title: 'Yorumlar',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SellerReviewsScreen(),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.payments_outlined,
                  title: 'Ödemeler',
                  onTap: () {
                    Navigator.pop(context);
                    _tabController.animateTo(1);
                  },
                ),
                const Divider(),
                _buildDrawerItem(
                  icon: Icons.settings_outlined,
                  title: 'Mağaza Ayarları',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ShopSettingsScreen(),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.help_outline,
                  title: 'Yardım',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Yardım ekranı yakında eklenecek')),
                    );
                  },
                ),
              ],
            ),
          ),

          // Footer
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: Colors.red.shade700),
            title: Text(
              'Ana Sayfaya Dön',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/',
                (route) => false,
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
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

    if (shopResponse == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mağaza bulunamadı')),
        );
      }
      return;
    }

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

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.orange.shade700),
      title: Text(title),
      onTap: onTap,
      hoverColor: Colors.orange.shade50,
    );
  }

  Widget _buildNoShopView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.store_outlined,
              size: 120,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              'Henüz Mağazanız Yok',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Satış yapmaya başlamak için önce bir mağaza oluşturmalısınız.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showCreateShopDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Mağaza Oluştur'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Komisyon Oranı Kartı
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.percent,
                            color: Colors.purple.shade700,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Komisyon Oranı',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '%${(_shopInfo?['commission_rate'] ?? 10.0).toStringAsFixed(1)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Her satıştan',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    // Kuryesi olmayanlar için teslimat ücreti bilgisi
                    if (_shopInfo?['has_own_courier'] == false) ...[
                      const Divider(height: 24),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.local_shipping,
                              color: Colors.orange.shade700,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Teslimat Ücreti',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₺${(_shopInfo?['delivery_fee'] ?? 0).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Her siparişten',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Admin kurye ile teslimat yapılır',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                ),
              ),
              
              // Sipariş Alma Kontrol Kartı
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isAcceptingOrders ? Colors.green.shade100 : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isAcceptingOrders ? Icons.store_outlined : Icons.store_mall_directory_outlined,
                          color: _isAcceptingOrders ? Colors.green.shade700 : Colors.red.shade700,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isAcceptingOrders ? 'Sipariş Alıyor' : 'Sipariş Kapalı',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _isAcceptingOrders ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isAcceptingOrders
                                  ? 'Müşteriler sipariş verebilir'
                                  : 'Müşteriler sipariş veremez (Geçici Kapalı)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isAcceptingOrders,
                        onChanged: (value) => _toggleAcceptingOrders(value),
                        // ignore: deprecated_member_use
                        activeColor: Colors.green.shade700,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // İstatistik Kartları
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Toplam Sipariş',
                    '${_stats['ordersCount'] ?? 0}',
                    Icons.shopping_bag_outlined,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Ürün Sayısı',
                    '${_stats['productsCount'] ?? 0}',
                    Icons.inventory_2_outlined,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    _hasOwnCourier ? 'Kapıda Ödeme Kazancı' : 'Kapıda Kazanç',
                    '₺${_cashPaymentRevenue.toStringAsFixed(2)}',
                    Icons.money,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    _hasOwnCourier ? 'Online Ödeme Kazancı' : 'Online Alacak',
                    '₺${_onlinePaymentRevenue.toStringAsFixed(2)}',
                    Icons.credit_card,
                    Colors.blue,
                  ),
                ),
              ],
            ),
            if (_hasOwnCourier) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Admin\'den Alacak',
                      '₺${_adminCredit.toStringAsFixed(2)}',
                      Icons.account_balance,
                      Colors.teal,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      'Komisyon Borcu',
                      '₺${_commissionDebt.toStringAsFixed(2)}',
                      Icons.trending_down,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
            if (!_hasOwnCourier) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Admin\'den Alacak',
                      '₺${_adminCredit.toStringAsFixed(2)}',
                      Icons.account_balance,
                      Colors.teal,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      'Kurye Durumu',
                      'Platform Kargo',
                      Icons.local_shipping,
                      Colors.purple,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),

            // Son Siparişler
            Text(
              'Son Siparişler',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            if (_recentOrders.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Text(
                      'Henüz sipariş yok',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentOrders.length,
                itemBuilder: (context, index) {
                  final order = _recentOrders[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade100,
                        child: Icon(
                          Icons.shopping_cart,
                          color: Colors.orange.shade700,
                        ),
                      ),
                      title: Text(
                        'Sipariş #${order['id'].toString().substring(0, 8)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        order['profiles']?['full_name'] ?? 'Bilinmeyen',
                      ),
                      trailing: Chip(
                        label: Text(
                          _getStatusLabel(order['status']),
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: _getStatusColor(order['status']),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 32),

            // En Çok Satılan Ürünler
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ürünlerim',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProductsScreen(),
                      ),
                    ).then((_) => _loadDashboardData());
                  },
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('Tümünü Gör'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_topProducts.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Text(
                      'Henüz ürün eklenmemiş',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _topProducts.length,
                itemBuilder: (context, index) {
                  final product = _topProducts[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: product['image_url'] != null
                            ? Image.network(
                                product['image_url'],
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                // ignore: unnecessary_underscores
                                errorBuilder: (_, __, ___) => Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.image),
                                ),
                              )
                            : Container(
                                width: 56,
                                height: 56,
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.image),
                              ),
                      ),
                      title: Text(
                        product['name'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '₺${product['price'] ?? 0}',
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                      trailing: Text(
                        'Stok: ${product['stock_quantity'] ?? product['stock'] ?? 0}',
                        style: TextStyle(
                          color: (product['stock_quantity'] ?? product['stock'] ?? 0) > 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabbedDashboard() {
    return Column(
      children: [
        // Tab Bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            onTap: (index) => setState(() {}),
            indicatorColor: Colors.orange.shade700,
            labelColor: Colors.orange.shade700,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Genel Bakış'),
              Tab(icon: Icon(Icons.payments_outlined), text: 'Ödemeler'),
              Tab(icon: Icon(Icons.history), text: 'Geçmiş'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDashboard(),
              _buildPayoutsTab(),
              _buildPayoutHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPayoutsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Borç/Alacak Durumu Card
          if (_shopInfo != null)
            BalanceStatusCard(
              shopId: _shopInfo!['id'],
              payoutService: _payoutService,
            ),
          const SizedBox(height: 16),

          // Özet Kartları
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Bekleyen Ödeme',
                  '₺${_pendingPayout.toStringAsFixed(2)}',
                  Icons.account_balance_wallet_outlined,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Toplam Ödenen',
                  '₺${_totalPaid.toStringAsFixed(2)}',
                  Icons.check_circle_outline,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // IBAN Bilgileri
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.credit_card, color: Colors.orange.shade700),
                          const SizedBox(width: 12),
                          const Text(
                            'IBAN Bilgileri',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: _showIbanEditDialog,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Düzenle'),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (_shopInfo?['iban'] != null && _shopInfo!['iban'].toString().isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow('IBAN', _formatIban(_shopInfo!['iban'])),
                        const SizedBox(height: 12),
                        _buildInfoRow('Banka', _shopInfo!['bank_name'] ?? '-'),
                        const SizedBox(height: 12),
                        _buildInfoRow('Hesap Sahibi', _shopInfo!['account_holder_name'] ?? '-'),
                      ],
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'IBAN bilgisi girmelisiniz. Ödeme talebi oluşturabilmek için lütfen bilgilerinizi ekleyin.',
                              style: TextStyle(color: Colors.orange.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Kuryesi olmayan satıcılar için Bilgilendirme Kartı
          if (!_hasOwnCourier)
            Card(
              color: Colors.purple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.purple.shade700),
                        const SizedBox(width: 12),
                        const Text(
                          'Platform Kargo Kullanıyorsunuz',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      'Ödenebilir Tutar',
                      '₺${_adminCredit.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, size: 18, color: Colors.purple.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kuryeniz olmadığı için her siparişten komisyon ve teslimat ücreti otomatik düşülür. Kalan tutar ödeme alabilirsiniz.',
                              style: TextStyle(color: Colors.purple.shade900, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_hasOwnCourier)
            const SizedBox(height: 24),

          // Bekleyen Ödeme İstekleri
          if (_payoutRequests.any((p) => p['status'] == 'pending'))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Bekleyen Ödeme İstekleri',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_payoutRequests.where((p) => p['status'] == 'pending').length}',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._payoutRequests
                    .where((p) => p['status'] == 'pending')
                    .map((p) => _buildPayoutRequestCard(p)),
              ],
            ),

          const SizedBox(height: 24),

          // Yeni Ödeme İsteği Butonu
          if (_availablePayout > 0)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showCreatePayoutDialog,
                icon: const Icon(Icons.request_quote_outlined),
                label: Text('Ödeme İsteği Oluştur (₺${_availablePayout.toStringAsFixed(2)} kullanılabilir)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _pendingRequestsTotal > 0
                            ? 'Tüm bekleyen ödemeniz için zaten talep oluşturdunuz. Admin onayı bekleyin.'
                            : 'Kullanılabilir ödeme tutarınız bulunmamaktadır.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPayoutHistoryTab() {
    final completedRequests = _payoutRequests.where((p) =>
      p['status'] != 'pending');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ödeme Geçmişi',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          if (completedRequests.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz ödeme geçmişi yok',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ...completedRequests.map((p) => _buildPayoutRequestCard(p)),
        ],
      ),
    );
  }

  Widget _buildPayoutRequestCard(Map<String, dynamic> payout) {
    final status = payout['status'] as String? ?? 'pending';
    final statusColor = PayoutService.getStatusColorValue(status);
    final statusText = PayoutService.getStatusText(status);
    final amount = (payout['total_amount'] as num?)?.toDouble() ?? 0.0;

    String? rejectionReason;
    if (status == 'rejected' && payout['rejection_reason'] != null) {
      rejectionReason = payout['rejection_reason'].toString();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₺${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color(statusColor).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: Color(statusColor),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildPayoutInfoRow('Talep Tarihi', _formatDate(payout['requested_at'])),
            if (payout['reviewed_at'] != null)
              _buildPayoutInfoRow('İnceleme Tarihi', _formatDate(payout['reviewed_at'])),
            if (payout['paid_at'] != null)
              _buildPayoutInfoRow('Ödeme Tarihi', _formatDate(payout['paid_at'])),
            if (rejectionReason != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Red Sebebi: $rejectionReason',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _cancelPayoutRequest(payout['id']),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('İptal Et'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.shade300),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayoutInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }


  String _formatIban(String iban) {
    if (iban.length != 26) return iban;
    return '${iban.substring(0, 2)} ${iban.substring(2, 6)} ${iban.substring(6, 10)} ${iban.substring(10, 14)} ${iban.substring(14, 18)} ${iban.substring(18, 22)} ${iban.substring(22, 26)}';
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    final dateTime = date is String ? DateTime.parse(date) : date as DateTime;
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showIbanEditDialog() {
    final ibanController = TextEditingController(text: _shopInfo?['iban'] ?? '');
    final bankController = TextEditingController(text: _shopInfo?['bank_name'] ?? '');
    final holderController = TextEditingController(text: _shopInfo?['account_holder_name'] ?? '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('IBAN Bilgileri'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ibanController,
                    decoration: const InputDecoration(
                      labelText: 'IBAN',
                      hintText: 'TRXX XXXX XXXX XXXX XXXX XXXX XX',
                      prefixIcon: Icon(Icons.credit_card),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: bankController,
                    decoration: const InputDecoration(
                      labelText: 'Banka Adı',
                      hintText: 'Örn: Ziraat Bankası',
                      prefixIcon: Icon(Icons.account_balance),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: holderController,
                    decoration: const InputDecoration(
                      labelText: 'Hesap Sahibi Adı',
                      hintText: 'Ad Soyad',
                      prefixIcon: Icon(Icons.person),
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
                  final iban = ibanController.text.trim();
                  final bankName = bankController.text.trim();
                  final holderName = holderController.text.trim();

                  if (iban.isEmpty || bankName.isEmpty || holderName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Tüm alanları doldurmalısınız')),
                    );
                    return;
                  }

                  try {
                    await _payoutService.updateShopIban(
                      shopId: _shopInfo!['id'],
                      iban: iban,
                      bankName: bankName,
                      accountHolderName: holderName,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('IBAN bilgileri güncellendi')),
                      );
                      _loadDashboardData();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreatePayoutDialog() {
    if (_shopInfo?['iban'] == null || _shopInfo!['iban'].toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce IBAN bilgilerinizi girmelisiniz')),
      );
      return;
    }

    // Gelir verileri
    final hasCourier = _revenueSummary?['has_courier'] as bool? ?? false;
    final cashRevenue = (_revenueSummary?['cash_payment_revenue'] as num?)?.toDouble() ?? 0;
    final onlineRevenue = (_revenueSummary?['online_payment_revenue'] as num?)?.toDouble() ?? 0;
    final commissionDebt = (_revenueSummary?['commission_debt'] as num?)?.toDouble() ?? 0;
    final deliveryFee = (_revenueSummary?['delivery_fee'] as num?)?.toDouble() ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Tüm Bakiyeyi Çek'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gelir Hesaplama Detayı
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
                        Icon(Icons.calculate, color: Colors.blue.shade700, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Kazanç Hesaplama',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    // Kuryeli/Kuryesiz durumu
                    if (hasCourier)
                      _buildCalculationRow('Kendi Kurye', '', Colors.blue.shade700, isBold: true)
                    else
                      _buildCalculationRow('Platform Kargos', '', Colors.purple.shade700, isBold: true),
                    
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    
                    // Online gelir
                    if (onlineRevenue > 0)
                      _buildCalculationRow('Online Ödeme', '+₺${onlineRevenue.toStringAsFixed(2)}', Colors.green),
                    
                    // Kapıda ödeme geliri
                    if (cashRevenue > 0)
                      _buildCalculationRow('Kapıda Ödeme', '+₺${cashRevenue.toStringAsFixed(2)}', Colors.green),
                    
                    // Komisyon borcu (sadece kuryeli için)
                    if (hasCourier && commissionDebt > 0) ...[
                      const SizedBox(height: 4),
                      _buildCalculationRow('Komisyon Borcu', '-₺${commissionDebt.toStringAsFixed(2)}', Colors.red),
                    ],
                    
                    // Teslimat ücreti (sadece kuryesiz için)
                    if (!hasCourier && deliveryFee > 0) ...[
                      const SizedBox(height: 4),
                      _buildCalculationRow('Teslimat Kesintisi', 'Dahil', Colors.orange.shade700),
                    ],
                    
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    
                    // Net hesaplama
                    _buildCalculationRow(
                      'Net Kazanç',
                      '₺${_pendingPayout.toStringAsFixed(2)}',
                      Colors.blue.shade900,
                      isBold: true,
                      fontSize: 15,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Bekleyen istekler varsa göster
              if (_pendingRequestsTotal > 0) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.pending_actions, color: Colors.orange.shade700, size: 16),
                          const SizedBox(width: 6),
                          const Text('Bekleyen İstekler:', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                      Text(
                        '-₺${_pendingRequestsTotal.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
              ],
              
              // Kullanılabilir tutar - BÜYÜK VE BELİRGİN
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade700, Colors.green.shade500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Çekilecek Tutar',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₺${_availablePayout.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tüm kullanılabilir bakiyeniz çekilecek',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Bilgilendirme mesajı
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ödeme isteğiniz admin onayından sonra IBAN\'ınıza aktarılacaktır.',
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
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
          ElevatedButton.icon(
            onPressed: () async {
              try {
                await _payoutService.createPayoutRequest(
                  sellerId: _supabase.auth.currentUser!.id,
                  shopId: _shopInfo!['id'],
                  amount: _availablePayout, // Her zaman tüm bakiye
                );

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ödeme isteği oluşturuldu')),
                  );
                  _loadDashboardData();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('Onaylıyorum, Çek'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelPayoutRequest(String payoutId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ödeme İsteğini İptal Et'),
        content: const Text('Ödeme isteğini iptal etmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hayır'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Evet, İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _payoutService.cancelPayoutRequest(payoutId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ödeme isteği iptal edildi')),
          );
          _loadDashboardData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 32),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalculationRow(
    String label,
    String value,
    Color color, {
    bool isBold = false,
    double fontSize = 13,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateShopDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mağaza Oluştur'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Mağaza Adı',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mağazanız oluşturulduktan sonra admin onayı bekleyecektir.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mağaza adı gerekli')),
                );
                return;
              }
              
              try {
                final userId = Supabase.instance.client.auth.currentUser?.id;
                if (userId == null) throw Exception('Kullanıcı bulunamadı');
                
                await Supabase.instance.client.from('shops').insert({
                  'owner_id': userId,
                  'name': name,
                  'slug': name.toLowerCase().replaceAll(' ', '-'),
                  'description': description.isEmpty ? null : description,
                  'is_active': true,
                  'is_approved': false, // Admin onayı bekleyecek
                  'is_verified': false,
                  'commission_rate': 10.0,
                  'min_order_amount': 0.0,
                  'delivery_fee': 0.0,
                });
                
                  // ignore: use_build_context_synchronously
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mağaza oluşturuldu! Admin onayı bekleniyor...'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {
                    _loadDashboardData();
                  });
                }
              } catch (e) {
                debugPrint('Mağaza oluşturulurken hata: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAcceptingOrders(bool value) async {
    try {
      if (_shopInfo == null) return;

      await _supabase
          .from('shops')
          .update({'is_accepting_orders': value})
          .eq('id', _shopInfo!['id']);

      setState(() {
        _isAcceptingOrders = value;
        _shopInfo!['is_accepting_orders'] = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Sipariş alma açıldı'
                  : 'Sipariş alma kapatıldı (Müşteriler "Geçici Kapalı" görecek)',
            ),
            backgroundColor: value ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Sipariş alma durumu değiştirilemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'delivered':
      case 'completed':
        return Colors.green.shade100;
      case 'cancelled':
        return Colors.red.shade100;
      case 'confirmed':
      case 'processing':
        return Colors.blue.shade100;
      case 'preparing':
        return Colors.purple.shade100;
      case 'ready':
        return Colors.indigo.shade100;
      case 'on_the_way':
        return Colors.orange.shade100;
      default:
        return Colors.amber.shade100;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'Beklemede';
      case 'confirmed':
        return 'Onaylandı';
      case 'preparing':
        return 'Hazırlanıyor';
      case 'ready':
        return 'Hazır';
      case 'on_the_way':
        return 'Yolda';
      case 'delivered':
        return 'Teslim Edildi';
      case 'cancelled':
        return 'İptal Edildi';
      case 'completed':
        return 'Tamamlandı';
      case 'processing':
        return 'İşlemde';
      default:
        return status ?? 'Bilinmiyor';
    }
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
