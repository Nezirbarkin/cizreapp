// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shop_detail_admin_screen.dart';

/// Admin - Dükkan Yönetim Ekranı
/// 
/// Renk Kodlaması:
/// - YEŞİL: Satıcıdan admin'e ödeme gelecek (pozitif bakiye)
/// - KIRMIZI: Admin'den satıcıya ödeme yapılacak (komisyon borcu var)
/// - GRİ: Bakiye dengede (ödeme yok)
class ShopsManagementScreen extends StatefulWidget {
  const ShopsManagementScreen({super.key});

  @override
  State<ShopsManagementScreen> createState() => _ShopsManagementScreenState();
}

class _ShopsManagementScreenState extends State<ShopsManagementScreen> {
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _shops = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, needs_payment, will_pay

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    setState(() => _isLoading = true);
    
    try {
      debugPrint('🔍 [SHOPS] Dükkanlar yükleniyor...');
      final response = await _supabase
          .from('shops')
          .select('''
            *,
            profiles!shops_owner_id_fkey(full_name, email)
          ''')
          .order('created_at', ascending: false);

      debugPrint('🔍 [SHOPS] ${(response as List).length} dükkan bulundu');

      // Her dükkan için istatistikleri yükle
      final shopsWithStats = await Future.wait(
        response.map((shop) async {
          final shopId = shop['id'] as String;
          final shopName = shop['name'] as String? ?? 'Bilinmeyen';
          
          // Ürün sayısı
          int productsCount = 0;
          try {
            final productsRes = await _supabase
                .from('products')
                .select('id')
                .eq('shop_id', shopId);
            productsCount = (productsRes as List).length;
            debugPrint('🔍 [SHOPS] $shopName - Ürünler: $productsCount');
          } catch (e) {
            debugPrint('❌ [SHOPS] $shopName - Ürün yükleme hatası: $e');
          }
          
          // Sipariş istatistikleri
          int totalOrders = 0;
          int completedOrders = 0;
          int cancelledOrders = 0;
          int pendingOrders = 0;
          double totalRevenue = 0;
          double totalCouponDiscount = 0;
          
          try {
            final ordersData = await _supabase
                .from('orders')
                .select('status, total, coupon_discount')
                .eq('shop_id', shopId);
            
            totalOrders = (ordersData as List).length;
            completedOrders = ordersData.where((o) => o['status'] == 'delivered').length;
            cancelledOrders = ordersData.where((o) => o['status'] == 'cancelled').length;
            pendingOrders = ordersData.where((o) =>
              o['status'] != 'delivered' && o['status'] != 'cancelled'
            ).length;
            totalRevenue = ordersData
                .where((o) => o['status'] == 'delivered')
                .fold<double>(0, (sum, o) => sum + ((o['total'] as num?)?.toDouble() ?? 0));
            totalCouponDiscount = ordersData
                .where((o) => o['status'] == 'delivered')
                .fold<double>(0, (sum, o) => sum + ((o['coupon_discount'] as num?)?.toDouble() ?? 0));
            debugPrint('🔍 [SHOPS] $shopName - Siparişler: $totalOrders, Tamamlanan: $completedOrders, Gelir: $totalRevenue');
          } catch (e) {
            debugPrint('❌ [SHOPS] $shopName - Sipariş yükleme hatası: $e');
          }
          
          return {
            ...Map<String, dynamic>.from(shop),
            'stats': {
              'products_count': productsCount,
              'total_orders': totalOrders,
              'completed_orders': completedOrders,
              'cancelled_orders': cancelledOrders,
              'pending_orders': pendingOrders,
              'total_revenue': totalRevenue,
              'total_coupon_discount': totalCouponDiscount,
            }
          };
        }).toList(),
      );

      debugPrint('✅ [SHOPS] Tüm istatistikler yüklendi');
      setState(() {
        _shops = shopsWithStats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Dükkanlar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Color _getShopStatusColor(Map<String, dynamic> shop) {
    final adminCredit = (shop['admin_credit'] as num?)?.toDouble() ?? 0;
    final commissionDebt = (shop['commission_debt'] as num?)?.toDouble() ?? 0;
    final netBalance = adminCredit - commissionDebt;

    if (netBalance > 0) return Colors.green; // Admin satıcıya borçlu
    if (netBalance < 0) return Colors.red;   // Satıcı admin'e borçlu
    return Colors.grey; // Dengede
  }

  String _getShopStatusText(Map<String, dynamic> shop) {
    final adminCredit = (shop['admin_credit'] as num?)?.toDouble() ?? 0;
    final commissionDebt = (shop['commission_debt'] as num?)?.toDouble() ?? 0;
    final netBalance = adminCredit - commissionDebt;

    if (netBalance > 0) {
      return 'Ödeme Yapılacak: ₺${netBalance.toStringAsFixed(2)}';
    } else if (netBalance < 0) {
      return 'Borç Var: ₺${netBalance.abs().toStringAsFixed(2)}';
    } else {
      return 'Dengede';
    }
  }

  List<Map<String, dynamic>> get _filteredShops {
    var filtered = _shops;

    // Arama filtresi
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((shop) {
        final name = (shop['name'] as String?)?.toLowerCase() ?? '';
        final ownerName = (shop['profiles']?['full_name'] as String?)?.toLowerCase() ?? '';
        final query = _searchQuery.toLowerCase();
        
        return name.contains(query) || ownerName.contains(query);
      }).toList();
    }

    // Durum filtresi
    if (_filterStatus == 'needs_payment') {
      filtered = filtered.where((shop) {
        final color = _getShopStatusColor(shop);
        return color == Colors.green;
      }).toList();
    } else if (_filterStatus == 'will_pay') {
      filtered = filtered.where((shop) {
        final color = _getShopStatusColor(shop);
        return color == Colors.red;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dükkan Yönetimi'),
        backgroundColor: Colors.orange.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _loadShops,
          ),
        ],
      ),
      body: Column(
        children: [
          // Arama ve Filtre
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                // Arama
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Dükkan veya sahip ara...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
                const SizedBox(height: 12),
                // Filtre Butonları
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterChip(
                        'Tümü',
                        'all',
                        Icons.store,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFilterChip(
                        'Ödeme Yapılacak',
                        'needs_payment',
                        Icons.payment,
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFilterChip(
                        'Borç Var',
                        'will_pay',
                        Icons.warning,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // İstatistikler
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatChip(
                  'Toplam',
                  _shops.length.toString(),
                  Colors.blue,
                ),
                _buildStatChip(
                  'Ödeme Yapılacak',
                  _shops.where((s) => _getShopStatusColor(s) == Colors.green).length.toString(),
                  Colors.green,
                ),
                _buildStatChip(
                  'Borç Var',
                  _shops.where((s) => _getShopStatusColor(s) == Colors.red).length.toString(),
                  Colors.red,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Dükkan Listesi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredShops.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.store_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Henüz dükkan yok'
                                  : 'Sonuç bulunamadı',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadShops,
                        child: ListView.builder(
                          itemCount: _filteredShops.length,
                          itemBuilder: (context, index) {
                            final shop = _filteredShops[index];
                            return _buildShopCard(shop);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon, Color color) {
    final isSelected = _filterStatus == value;
    
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : color,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterStatus = value);
      },
      selectedColor: color,
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopCard(Map<String, dynamic> shop) {
    final statusColor = _getShopStatusColor(shop);
    final statusText = _getShopStatusText(shop);
    final hasCourier = shop['has_own_courier'] as bool? ?? false;
    final ownerName = shop['profiles']?['full_name'] as String? ?? 'Bilinmeyen';
    final shopName = shop['name'] as String? ?? 'Adsız Dükkan';
    final isActive = shop['is_active'] as bool? ?? false;
    
    // Gerçek istatistikler
    final stats = shop['stats'] as Map<String, dynamic>? ?? {};
    final productsCount = stats['products_count'] as int? ?? 0;
    final totalOrders = stats['total_orders'] as int? ?? 0;
    final completedOrders = stats['completed_orders'] as int? ?? 0;
    final pendingOrders = stats['pending_orders'] as int? ?? 0;
    final totalRevenue = (stats['total_revenue'] as num?)?.toDouble() ?? 0;
    final adminCredit = (shop['admin_credit'] as num?)?.toDouble() ?? 0;
    final commissionDebt = (shop['commission_debt'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3), width: 2),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShopDetailAdminScreen(shopId: shop['id']),
            ),
          ).then((_) => _loadShops());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst kısım: Dükkan adı, sahip, durum
              Row(
                children: [
                  // Dükkan logosu
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: statusColor.withOpacity(0.5), width: 2),
                      image: shop['logo_url'] != null
                          ? DecorationImage(
                              image: NetworkImage(shop['logo_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: shop['logo_url'] == null
                        ? Icon(Icons.store, size: 24, color: Colors.grey.shade400)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Dükkan Adı
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ownerName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Aktif Durumu + Kurye + Durum Etiketi
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isActive ? 'Aktif' : 'Pasif',
                          style: TextStyle(
                            fontSize: 10,
                            color: isActive ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasCourier ? Icons.local_shipping : Icons.delivery_dining,
                            size: 12,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            hasCourier ? 'Kendi Kuryesi' : 'Platform',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Durum Etiketi (Badge)
                      _buildStatusBadge(statusColor, statusText),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // İstatistik satırı
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildMiniStat(
                      Icons.inventory_2_outlined,
                      '$productsCount',
                      'Ürün',
                      Colors.blue,
                    ),
                    _buildVerticalDivider(),
                    _buildMiniStat(
                      Icons.shopping_bag_outlined,
                      '$totalOrders',
                      'Sipariş',
                      Colors.purple,
                    ),
                    _buildVerticalDivider(),
                    _buildMiniStat(
                      Icons.check_circle_outline,
                      '$completedOrders',
                      'Teslim',
                      Colors.green,
                    ),
                    _buildVerticalDivider(),
                    _buildMiniStat(
                      Icons.pending_outlined,
                      '$pendingOrders',
                      'Bekleyen',
                      Colors.orange,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Kazanç bilgileri
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildFinanceStat(
                            'Toplam Ciro',
                            '₺${totalRevenue.toStringAsFixed(0)}',
                            Colors.indigo,
                          ),
                        ),
                        Expanded(
                          child: _buildFinanceStat(
                            'Admin Alacak',
                            '₺${adminCredit.toStringAsFixed(0)}',
                            Colors.green.shade700,
                          ),
                        ),
                        Expanded(
                          child: _buildFinanceStat(
                            'Komisyon Borç',
                            '₺${commissionDebt.toStringAsFixed(0)}',
                            Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Durum satırı
                    Row(
                      children: [
                        Icon(
                          statusColor == Colors.green
                              ? Icons.arrow_upward
                              : statusColor == Colors.red
                                  ? Icons.arrow_downward
                                  : Icons.remove,
                          size: 16,
                          color: statusColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 35,
      color: Colors.grey.shade300,
    );
  }

  Widget _buildFinanceStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(Color statusColor, String statusText) {
    IconData icon;
    String shortLabel;

    if (statusColor == Colors.green) {
      icon = Icons.arrow_upward;
      shortLabel = 'Ödeme';
    } else if (statusColor == Colors.red) {
      icon = Icons.arrow_downward;
      shortLabel = 'Borç';
    } else {
      icon = Icons.balance;
      shortLabel = 'Dengede';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: statusColor),
          const SizedBox(width: 3),
          Text(
            shortLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}
