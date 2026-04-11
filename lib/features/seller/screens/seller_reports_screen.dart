// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_analytics_service.dart';

/// Satıcı Raporlar Ekranı - Modern ve kapsamlı istatistikler
class SellerReportsScreen extends StatefulWidget {
  const SellerReportsScreen({super.key});

  @override
  State<SellerReportsScreen> createState() => _SellerReportsScreenState();
}

class _SellerReportsScreenState extends State<SellerReportsScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _analyticsService = ShopAnalyticsService();
  
  bool _isLoading = true;
  String? _shopId;
  late TabController _tabController;

  // İstatistik verileri
  Map<String, dynamic> _salesStats = {};
  int _totalViews = 0;
  int _todayViews = 0;
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _topCustomers = [];
  List<Map<String, dynamic>> _weeklySales = [];
  List<Map<String, dynamic>> _productPerformance = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('🔴 SHOP VISIT DEBUG: Kullanıcı giriş yapmamış');
        return;
      }
      debugPrint('🔵 SHOP VISIT DEBUG: Kullanıcı ID: $userId');

      // Mağaza ID'sini al
      final shopResponse = await _supabase
          .from('shops')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse == null) {
        debugPrint('🔴 SHOP VISIT DEBUG: Mağaza bulunamadı');
        setState(() => _isLoading = false);
        return;
      }

      _shopId = shopResponse['id'];
      debugPrint('🔵 SHOP VISIT DEBUG: Mağaza ID: $_shopId');

      // Paralel yükleme
      debugPrint('🔵 SHOP VISIT DEBUG: Veriler yükleniyor...');
      final results = await Future.wait([
        _analyticsService.getSalesStats(_shopId!),
        _analyticsService.getShopTotalViews(_shopId!),
        _analyticsService.getShopTodayViews(_shopId!),
        _analyticsService.getTopViewedProducts(_shopId!),
        _analyticsService.getTopCustomers(_shopId!),
        _analyticsService.getWeeklySalesData(_shopId!),
        _analyticsService.getProductPerformance(_shopId!),
      ]);

      if (mounted) {
        setState(() {
          _salesStats = results[0] as Map<String, dynamic>;
          _totalViews = results[1] as int;
          _todayViews = results[2] as int;
          debugPrint('🟢 SHOP VISIT DEBUG: Toplam views: $_totalViews, Bugün: $_todayViews');
          _topProducts = results[3] as List<Map<String, dynamic>>;
          _topCustomers = results[4] as List<Map<String, dynamic>>;
          _weeklySales = results[5] as List<Map<String, dynamic>>;
          _productPerformance = results[6] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('🔴 SHOP VISIT DEBUG: Rapor yükleme hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Raporlar', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFF97316),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFFF97316),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Genel'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Ürünler'),
            Tab(icon: Icon(Icons.people_outline), text: 'Müşteriler'),
            Tab(icon: Icon(Icons.trending_up), text: 'Trendler'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF97316)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildProductsTab(),
                _buildCustomersTab(),
                _buildTrendsTab(),
              ],
            ),
    );
  }

  // Genel Bakış Tab
  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFF97316),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Özet kartları - 2x2 grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _buildStatCard(
                  title: 'Toplam Satış',
                  value: '₺${(_salesStats['total_sales'] ?? 0).toStringAsFixed(0)}',
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF10B981),
                ),
                _buildStatCard(
                  title: 'Sipariş Sayısı',
                  value: '${_salesStats['total_orders'] ?? 0}',
                  icon: Icons.shopping_bag_outlined,
                  color: const Color(0xFF3B82F6),
                ),
                _buildStatCard(
                  title: 'Mağaza Ziyareti',
                  value: '$_totalViews',
                  subtitle: 'Bugün: $_todayViews',
                  icon: Icons.visibility_outlined,
                  color: const Color(0xFF8B5CF6),
                ),
                _buildStatCard(
                  title: 'Müşteri Sayısı',
                  value: '${_salesStats['unique_customers'] ?? 0}',
                  icon: Icons.people_outline,
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Bugün ve Bu Ay
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    title: 'Bugünkü Satış',
                    value: '₺${(_salesStats['today_sales'] ?? 0).toStringAsFixed(2)}',
                    icon: Icons.today,
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                    title: 'Bu Ay Satış',
                    value: '₺${(_salesStats['month_sales'] ?? 0).toStringAsFixed(2)}',
                    icon: Icons.calendar_month,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Ortalama Sipariş Değeri
            _buildInfoCard(
              title: 'Ortalama Sipariş Değeri',
              value: '₺${(_salesStats['avg_order_value'] ?? 0).toStringAsFixed(2)}',
              icon: Icons.analytics_outlined,
              color: const Color(0xFF8B5CF6),
              fullWidth: true,
            ),
            const SizedBox(height: 20),

            // Haftalık satış grafiği
            _buildSectionTitle('Haftalık Satış Grafiği'),
            const SizedBox(height: 12),
            _buildWeeklySalesChart(),
          ],
        ),
      ),
    );
  }

  // Ürünler Tab
  Widget _buildProductsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFF97316),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('En Çok Görüntülenen Ürünler'),
            const SizedBox(height: 12),
            _topProducts.isEmpty
                ? _buildEmptyState('Henüz görüntüleme verisi yok')
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _topProducts.length,
                    itemBuilder: (context, index) {
                      final product = _topProducts[index];
                      return _buildProductViewCard(
                        rank: index + 1,
                        name: product['product_name'] ?? 'Ürün',
                        views: product['view_count'] ?? 0,
                      );
                    },
                  ),
            const SizedBox(height: 24),
            
            _buildSectionTitle('Ürün Satış Performansı'),
            const SizedBox(height: 12),
            _productPerformance.isEmpty
                ? _buildEmptyState('Henüz satış verisi yok')
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _productPerformance.length,
                    itemBuilder: (context, index) {
                      final product = _productPerformance[index];
                      return _buildProductPerformanceCard(
                        rank: index + 1,
                        name: product['product_name'] ?? 'Ürün',
                        sold: product['total_sold'] ?? 0,
                        revenue: (product['total_revenue'] ?? 0).toDouble(),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  // Müşteriler Tab
  Widget _buildCustomersTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFF97316),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Müşteri özeti
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.people_outline, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Toplam Müşteri',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        Text(
                          '${_salesStats['unique_customers'] ?? 0}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('En Çok Sipariş Veren Müşteriler'),
            const SizedBox(height: 12),
            _topCustomers.isEmpty
                ? _buildEmptyState('Henüz müşteri verisi yok')
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _topCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = _topCustomers[index];
                      return _buildCustomerCard(
                        rank: index + 1,
                        name: customer['full_name'] ?? 'Müşteri',
                        orderCount: customer['order_count'] ?? 0,
                        totalSpent: (customer['total_spent'] ?? 0).toDouble(),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  // Trendler Tab
  Widget _buildTrendsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFF97316),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Satış Trendi (Son 7 Gün)'),
            const SizedBox(height: 12),
            _buildWeeklySalesChart(),
            const SizedBox(height: 24),

            _buildSectionTitle('Performans Göstergeleri'),
            const SizedBox(height: 12),
            _buildTrendIndicator(
              title: 'Ortalama Günlük Satış',
              value: _weeklySales.isNotEmpty
                  ? '₺${(_weeklySales.map((e) => e['sales'] as double).reduce((a, b) => a + b) / 7).toStringAsFixed(2)}'
                  : '₺0',
              icon: Icons.show_chart,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: 12),
            _buildTrendIndicator(
              title: 'Günlük Ortalama Ziyaret',
              // ignore: unnecessary_string_interpolations
              value: _totalViews > 0 ? '${(_totalViews / 30).toStringAsFixed(0)}' : '0',
              icon: Icons.visibility_outlined,
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 12),
            _buildTrendIndicator(
              title: 'Dönüşüm Oranı',
              value: _totalViews > 0
                  ? '%${((_salesStats['total_orders'] ?? 0) / _totalViews * 100).toStringAsFixed(1)}'
                  : '%0',
              icon: Icons.swap_horiz,
              color: const Color(0xFF3B82F6),
            ),
          ],
        ),
      ),
    );
  }

  // Widget bileşenleri
  Widget _buildStatCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  title,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool fullWidth = false,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E293B),
      ),
    );
  }

  Widget _buildWeeklySalesChart() {
    if (_weeklySales.isEmpty) {
      return _buildEmptyState('Henüz satış verisi yok');
    }

    final maxSales = _weeklySales.map((e) => e['sales'] as double).reduce((a, b) => a > b ? a : b);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _weeklySales.map((data) {
                final height = maxSales > 0 ? (data['sales'] as double) / maxSales * 120 : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: height.toDouble(),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF97316), Color(0xFFFB923C)],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data['date'],
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductViewCard({
    required int rank,
    required String name,
    required int views,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: rank <= 3 ? const Color(0xFFF97316) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: rank <= 3 ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 4),
              Text(
                '$views',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductPerformanceCard({
    required int rank,
    required String name,
    required int sold,
    required double revenue,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: rank <= 3 ? const Color(0xFF10B981) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: rank <= 3 ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text('$sold adet satıldı', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text(
            '₺${revenue.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard({
    required int rank,
    required String name,
    required int orderCount,
    required double totalSpent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: rank <= 3 ? const Color(0xFFF59E0B) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: rank <= 3
                  ? Icon(
                      rank == 1 ? Icons.emoji_events : (rank == 2 ? Icons.workspace_premium : Icons.military_tech),
                      color: Colors.white,
                      size: 20,
                    )
                  : Text(
                      '$rank',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text('$orderCount sipariş', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text(
            '₺${totalSpent.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendIndicator({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.insert_chart_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
