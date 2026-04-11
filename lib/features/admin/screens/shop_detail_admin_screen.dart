// ignore_for_file: unnecessary_underscores, deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Admin - Dükkan Detay Ekranı
/// 
/// Özellikler:
/// - Dükkan kazanç detayları (kapıda, online, komisyon)
/// - Kurye değiştirme
/// - Renk kodlaması (Yeşil: ödeme yapılacak, Kırmızı: borç var)
/// - Kurye geçiş logları
class ShopDetailAdminScreen extends StatefulWidget {
  final String shopId;

  const ShopDetailAdminScreen({super.key, required this.shopId});

  @override
  State<ShopDetailAdminScreen> createState() => _ShopDetailAdminScreenState();
}

class _ShopDetailAdminScreenState extends State<ShopDetailAdminScreen> {
  final _supabase = Supabase.instance.client;
  
  Map<String, dynamic>? _shop;
  Map<String, dynamic>? _shopOwner;
  bool _isLoading = true;
  
  // Kurye değişikliği logları
  List<Map<String, dynamic>> _courierChanges = [];
  
  // Sipariş istatistikleri
  int _totalOrders = 0;
  int _completedOrders = 0;
  int _pendingOrders = 0;
  int _preparingOrders = 0;
  int _cancelledOrders = 0;
  double _totalRevenue = 0.0;
  double _adminCommission = 0.0;
  double _shopNetEarnings = 0.0;
  
  // Ürün listesi
  List<Map<String, dynamic>> _products = [];
  
  // Sipariş listesi
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadShopData();
  }

  Future<void> _loadShopData() async {
    setState(() => _isLoading = true);
    
    try {
      // Dükkan bilgilerini al
      final shopResponse = await _supabase
          .from('shops')
          .select('*')
          .eq('id', widget.shopId)
          .single();

      _shop = Map<String, dynamic>.from(shopResponse);

      // Sahip bilgilerini al
      final ownerId = _shop!['owner_id'];
      if (ownerId != null) {
        final ownerResponse = await _supabase
            .from('profiles')
            .select('full_name, email, phone')
            .eq('id', ownerId)
            .maybeSingle();

        if (ownerResponse != null) {
          _shopOwner = Map<String, dynamic>.from(ownerResponse);
        }
      }

      // Kurye değişikliği loglarını al
      final logsResponse = await _supabase
          .from('courier_status_changes')
          .select('*')
          .eq('shop_id', widget.shopId)
          .order('changed_at', ascending: false)
          .limit(20);

      _courierChanges = List<Map<String, dynamic>>.from(logsResponse);

      // Ürünleri al
      final productsResponse = await _supabase
          .from('products')
          .select('id, name, description, price, discount_price, stock_quantity, is_available, image_url, category_id, shop_id')
          .eq('shop_id', widget.shopId)
          .order('created_at', ascending: false);

      _products = List<Map<String, dynamic>>.from(productsResponse);

      // Sipariş istatistiklerini al (admin_commission, commission_amount vs kolonlarıyla)
      final ordersResponse = await _supabase
          .from('orders')
          .select('''
            id, status, total, admin_commission, commission_amount, created_at,
            address_display, customer_phone, address_id,
            profiles!orders_user_id_fkey(id, username, full_name, email, avatar_url, phone)
          ''')
          .eq('shop_id', widget.shopId)
          .order('created_at', ascending: false);

      _orders = List<Map<String, dynamic>>.from(ordersResponse);
      _totalOrders = _orders.length;
      _completedOrders = _orders.where((order) => order['status'] == 'delivered').length;
      _pendingOrders = _orders.where((order) => order['status'] == 'pending').length;
      _preparingOrders = _orders.where((order) =>
        order['status'] == 'preparing' ||
        order['status'] == 'confirmed' ||
        order['status'] == 'on_the_way'
      ).length;
      _cancelledOrders = _orders.where((order) => order['status'] == 'cancelled').length;
      
      // Tamamlanan siparişlerden gelirler
      final deliveredOrders = _orders.where((order) => order['status'] == 'delivered');
      _totalRevenue = deliveredOrders.fold(0.0, (sum, order) => sum + ((order['total'] as num?)?.toDouble() ?? 0.0));
      _adminCommission = deliveredOrders.fold(0.0, (sum, order) {
        final commission = (order['admin_commission'] as num?)?.toDouble() ??
                          (order['commission_amount'] as num?)?.toDouble() ??
                          0.0;
        return sum + commission;
      });
      _shopNetEarnings = _totalRevenue - _adminCommission;

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Dükkan verileri yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Color _getShopStatusColor() {
    if (_shop == null) return Colors.grey;
    
    final adminCredit = (_shop!['admin_credit'] as num?)?.toDouble() ?? 0;
    final commissionDebt = (_shop!['commission_debt'] as num?)?.toDouble() ?? 0;
    final netBalance = adminCredit - commissionDebt;

    if (netBalance > 0) return Colors.green; // Admin satıcıya borçlu
    if (netBalance < 0) return Colors.red;   // Satıcı admin'e borçlu
    return Colors.grey; // Dengede
  }

  String _getShopStatusText() {
    if (_shop == null) return 'Yükleniyor...';
    
    final adminCredit = (_shop!['admin_credit'] as num?)?.toDouble() ?? 0;
    final commissionDebt = (_shop!['commission_debt'] as num?)?.toDouble() ?? 0;
    final netBalance = adminCredit - commissionDebt;

    if (netBalance > 0) {
      return 'Admin\'den ₺${netBalance.toStringAsFixed(2)} ödeme alacak';
    } else if (netBalance < 0) {
      return 'Admin\'e ₺${netBalance.abs().toStringAsFixed(2)} borçlu';
    } else {
      return 'Dengede';
    }
  }

  Future<void> _toggleCourierStatus() async {
    if (_shop == null) return;

    final newStatus = !(_shop!['has_own_courier'] as bool? ?? false);
    final statusText = newStatus ? 'Kuryeli' : 'Kuryesiz';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Kurye Durumu Değiştir'),
        content: Text(
          'Bu dükkanı $statusText sisteme geçirmek istediğinizden emin misiniz?\n\n'
          'Bu işlem mevcut bakiyeleri etkileyebilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet, Değiştir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase
            .from('shops')
            .update({'has_own_courier': newStatus})
            .eq('id', widget.shopId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kurye durumu $statusText olarak güncellendi'),
              backgroundColor: Colors.green,
            ),
          );
          _loadShopData();
        }
      } catch (e) {
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
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dükkan Detayı'),
          backgroundColor: Colors.orange.shade700,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_shop == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dükkan Detayı'),
          backgroundColor: Colors.orange.shade700,
        ),
        body: const Center(child: Text('Dükkan bulunamadı')),
      );
    }

    final statusColor = _getShopStatusColor();
    final statusText = _getShopStatusText();
    final hasCourier = _shop!['has_own_courier'] as bool? ?? false;
    final adminCredit = (_shop!['admin_credit'] as num?)?.toDouble() ?? 0;
    final commissionDebt = (_shop!['commission_debt'] as num?)?.toDouble() ?? 0;
    final cashRevenue = (_shop!['cash_payment_revenue'] as num?)?.toDouble() ?? 0;
    final onlineRevenue = (_shop!['online_payment_revenue'] as num?)?.toDouble() ?? 0;
    final totalCollected = (_shop!['total_collected_cash'] as num?)?.toDouble() ?? 0;
    final totalPaid = (_shop!['total_paid'] as num?)?.toDouble() ?? 0;

    // GERÇEK NET KAZANÇ HESAPLAMALARI
    // Kuryeli: Kapıda topladığı + Admin'den alacağı - Komisyon borcu - Ödenen
    // Kuryesiz: Admin'den alacağı - Ödenen
    double netBalance;
    double totalEarnings;

    if (hasCourier) {
      totalEarnings = cashRevenue + onlineRevenue;
      netBalance = cashRevenue + adminCredit - commissionDebt - totalPaid;
    } else {
      totalEarnings = onlineRevenue;
      netBalance = adminCredit - totalPaid;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_shop!['name'] ?? 'Dükkan Detayı'),
        backgroundColor: Colors.orange.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadShopData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Durum Kartı
            _buildStatusCard(statusColor, statusText),
            
            const SizedBox(height: 16),
            
            // Dükkan Bilgileri - Logo ile
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.store, size: 20, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text(
                          'Dükkan Bilgileri',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(),
                    // Logo ve temel bilgiler
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Dükkan logosu
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                            image: _shop!['logo_url'] != null
                                ? DecorationImage(
                                    image: NetworkImage(_shop!['logo_url']),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _shop!['logo_url'] == null
                              ? Icon(Icons.store, size: 36, color: Colors.grey.shade400)
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _shop!['name'] ?? '-',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (_shop!['description'] != null && (_shop!['description'] as String).isNotEmpty)
                                Text(
                                  _shop!['description'],
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _shop!['is_active'] == true
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _shop!['is_active'] == true ? 'Aktif' : 'Pasif',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _shop!['is_active'] == true
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildInfoRow('Sahibi', _shopOwner?['full_name'] ?? '-'),
                    _buildInfoRow('E-posta', _shopOwner?['email'] ?? '-'),
                    _buildInfoRow('Telefon', _shopOwner?['phone'] ?? '-'),
                    _buildInfoRow('Kategori', _shop!['category'] ?? '-'),
                    _buildInfoRow('Açık/Kapalı', _shop!['is_open'] == true ? 'Açık' : 'Kapalı'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Kurye Durumu
            _buildCourierCard(hasCourier),

            const SizedBox(height: 16),

            // Sipariş İstatistikleri
            _buildOrderStatsCard(),

            const SizedBox(height: 16),

            // Siparişler Listesi (Son 10)
            _buildOrdersListCard(),

            const SizedBox(height: 16),

            // Kazanç Detayları
            _buildRevenueCard(
              cashRevenue,
              onlineRevenue,
              adminCredit,
              commissionDebt,
              totalCollected,
              totalPaid,
              totalEarnings,
              netBalance,
              hasCourier,
            ),

            const SizedBox(height: 16),

            // Kurye Değişikliği Geçmişi
            if (_courierChanges.isNotEmpty) _buildCourierHistoryCard(),

            const SizedBox(height: 16),

            // Ürünler Listesi
            _buildProductsCard(),

            const SizedBox(height: 16),

            const SizedBox(height: 32),

            // İşlem Butonları
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleCourierStatus,
                    icon: Icon(hasCourier ? Icons.remove_circle : Icons.add_circle),
                    label: Text(hasCourier ? 'Kuryeyi Kaldır' : 'Kurye Ekle'),
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

  Widget _buildStatusCard(Color color, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.8),
            color,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                color == Colors.green ? Icons.trending_up : 
                color == Colors.red ? Icons.trending_down : 
                Icons.balance,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              Text(
                color == Colors.green ? 'Ödeme Yapılacak' : 
                color == Colors.red ? 'Borç Var' : 
                'Dengede',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
      ),
    );
  }

  Widget _buildCourierCard(bool hasCourier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasCourier ? Icons.local_shipping : Icons.delivery_dining,
                  color: hasCourier ? Colors.blue : Colors.purple,
                ),
                const SizedBox(width: 8),
                Text(
                  'Kurye Durumu',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasCourier ? Colors.blue.shade50 : Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasCourier ? Colors.blue.shade200 : Colors.purple.shade200,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    hasCourier ? Icons.local_shipping : Icons.delivery_dining,
                    size: 48,
                    color: hasCourier ? Colors.blue : Colors.purple,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasCourier ? 'Kendi Kuryesi' : 'Platform Kargo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: hasCourier ? Colors.blue : Colors.purple,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasCourier
                        ? 'Satıcı kendi teslimatını yapıyor. Kapıda ödemelerde sadece komisyon kesiliyor.'
                        : 'Platform kargo kullanılıyor. Her siparişten komisyon + teslimat ücreti kesiliyor.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shopping_bag, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Sipariş İstatistikleri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            // Sipariş durumları
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    'Toplam',
                    _totalOrders.toString(),
                    Icons.shopping_cart,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBox(
                    'Teslim',
                    _completedOrders.toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBox(
                    'Bekleyen',
                    _pendingOrders.toString(),
                    Icons.hourglass_empty,
                    Colors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    'Hazırlanan',
                    _preparingOrders.toString(),
                    Icons.restaurant,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBox(
                    'İptal',
                    _cancelledOrders.toString(),
                    Icons.cancel,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 16),
            
            // Ciro ve kazanç detayları
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    'Toplam Ciro',
                    '₺${_totalRevenue.toStringAsFixed(0)}',
                    Icons.attach_money,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBox(
                    'Admin Komisyonu',
                    '₺${_adminCommission.toStringAsFixed(0)}',
                    Icons.account_balance,
                    Colors.purple,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatBox(
                    'Net Kazanç',
                    '₺${_shopNetEarnings.toStringAsFixed(0)}',
                    Icons.storefront,
                    Colors.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard(
    double cashRevenue,
    double onlineRevenue,
    double adminCredit,
    double commissionDebt,
    double totalCollected,
    double totalPaid,
    double totalEarnings,
    double netBalance,
    bool hasCourier,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Kazanç Detayları',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // KAZANÇLAR BÖLÜMÜ
            Text(
              'KAZANÇLAR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            
            // Kapıda Ödeme Kazancı
            _buildRevenueRow('Kapıda Ödeme Kazancı', cashRevenue, Colors.green, Icons.money),
            const SizedBox(height: 8),
            
            // Online Ödeme Kazancı
            _buildRevenueRow('Online Ödeme Kazancı', onlineRevenue, Colors.blue, Icons.credit_card),
            const SizedBox(height: 8),
            
            // Toplam Kazanç
            _buildRevenueRow('Toplam Kazanç', totalEarnings, Colors.purple, Icons.trending_up, isBold: true),
            
            const Divider(height: 24),
            
            // TAHSİLAT VE BORÇLAR
            Text(
              'TAHSİLAT VE BORÇLAR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            
            // Toplam Nakit Tahsilat (sadece kuryeli için)
            if (hasCourier) ...[
              _buildRevenueRow('Satıcı Nakit Topladı', totalCollected, Colors.orange, Icons.payments),
              const SizedBox(height: 8),
            ],
            
            // Admin'den Alacak
            _buildRevenueRow('Admin\'den Alacak', adminCredit, Colors.teal, Icons.account_balance),
            const SizedBox(height: 8),
            
            // Komisyon Borcu
            _buildRevenueRow('Komisyon Borcu', commissionDebt, Colors.red, Icons.trending_down),
            const SizedBox(height: 8),
            
            // Toplam Ödenen
            _buildRevenueRow('Daha Önce Ödenen', totalPaid, Colors.grey, Icons.check_circle),
            
            const Divider(height: 24),
            
            // NET BAKİYE (Gerçek Kazanç)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: netBalance >= 0
                      ? [Colors.green.shade400, Colors.green.shade600]
                      : [Colors.red.shade400, Colors.red.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (netBalance >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    netBalance >= 0 ? Icons.account_balance_wallet : Icons.warning,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GERÇEK NET KAZANÇ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          netBalance >= 0
                              ? 'Satıcıya Ödenecek'
                              : 'Satıcı Borçlu',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₺${netBalance.abs().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            // Açıklama
            const SizedBox(height: 12),
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
                      hasCourier
                          ? 'Kuryeli: Nakit topladı + Admin alacağı - Komisyon - Ödenen'
                          : 'Kuryesiz: Admin alacağı - Ödenen',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueRow(String label, double amount, Color color, IconData icon, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isBold ? 14 : 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color.withValues(alpha: 0.9),
              ),
            ),
          ),
          Text(
            '₺${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourierHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Kurye Değişikliği Geçmişi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...(_courierChanges.map((change) {
              final previousStatus = change['previous_status'] as bool? ?? false;
              final newStatus = change['new_status'] as bool? ?? false;
              final changedAt = change['changed_at'] as String?;
              
              return ListTile(
                leading: Icon(
                  newStatus ? Icons.local_shipping : Icons.delivery_dining,
                  color: newStatus ? Colors.blue : Colors.purple,
                ),
                title: Text(
                  '${previousStatus ? "Kuryeli" : "Kuryesiz"} → ${newStatus ? "Kuryeli" : "Kuryesiz"}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  changedAt != null 
                      ? '${DateTime.parse(changedAt).day}.${DateTime.parse(changedAt).month}.${DateTime.parse(changedAt).year} ${DateTime.parse(changedAt).hour}:${DateTime.parse(changedAt).minute.toString().padLeft(2, '0')}'
                      : '-',
                ),
                trailing: Icon(
                  previousStatus == newStatus ? Icons.sync : Icons.swap_horiz,
                  color: Colors.grey,
                ),
              );
            }).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Ürünler',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Toplam: ${_products.length} ürün',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (_products.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'Bu dükkanıa henüz ürün eklenmemiş',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _products.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = _products[index];
                  final stockQty = (product['stock_quantity'] as num?)?.toInt() ?? 0;
                  final isAvailable = product['is_available'] as bool? ?? true;
                  final inStock = stockQty > 0 && isAvailable;
                  
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: product['image_url'] != null
                            ? DecorationImage(
                                image: NetworkImage(product['image_url']),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: product['image_url'] == null
                          ? Icon(Icons.image, color: Colors.grey.shade400)
                          : null,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            product['name'] ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          '₺${((product['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Icon(
                          inStock ? Icons.check_circle : Icons.cancel,
                          size: 14,
                          color: inStock ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          inStock ? 'Stok: $stockQty' : 'Stok Yok',
                          style: TextStyle(
                            fontSize: 12,
                            color: inStock ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                        if (!isAvailable) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Pasif',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _showEditProductDialog(product);
                            break;
                          case 'delete':
                            _showDeleteProductDialog(product);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Düzenle'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Sil', style: TextStyle(color: Colors.red)),
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
  }

  Widget _buildOrdersListCard() {
    final recentOrders = _orders.length > 10 ? _orders.sublist(0, 10) : _orders;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Son Siparişler (${recentOrders.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_orders.length > 10)
                  Text(
                    'Toplam: $_totalOrders',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (recentOrders.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('Henüz sipariş yok', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentOrders.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final order = recentOrders[index];
                  final status = order['status'] as String? ?? 'pending';
                  final totalAmount = (order['total'] as num?)?.toDouble() ?? 0;
                  final createdAt = DateTime.parse(order['created_at'] as String);
                  
                  final commission = (order['admin_commission'] as num?)?.toDouble() ??
                                     (order['commission_amount'] as num?)?.toDouble() ?? 0;
                  final netAmount = totalAmount - commission;
                  
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: _buildOrderStatusIcon(status),
                    title: Text('₺${totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${createdAt.day}.${createdAt.month}.${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        Text('#${(order['id'] as String).substring(0, 8)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        if (status == 'delivered' && commission > 0)
                          Text('Komisyon: ₺${commission.toStringAsFixed(2)} | Net: ₺${netAmount.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 11, color: Colors.purple.shade400)),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getOrderStatusColor(status),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getOrderStatusText(status),
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    onTap: () => _showOrderDetailDialog(order),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Color _getOrderStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'preparing': return Colors.blue;
      case 'on_the_way': return Colors.cyan;
      case 'processing': return Colors.blue;
      case 'confirmed': return Colors.purple;
      case 'delivered': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getOrderStatusText(String status) {
    switch (status) {
      case 'pending': return 'Beklemede';
      case 'processing': return 'İşleniyor';
      case 'confirmed': return 'Onaylandı';
      case 'preparing': return 'Hazırlanıyor';
      case 'on_the_way': return 'Yolda';
      case 'delivered': return 'Teslim';
      case 'cancelled': return 'İptal';
      default: return status;
    }
  }
  
  void _showOrderDetailDialog(Map<String, dynamic> order) {
    final totalAmount = (order['total'] as num?)?.toDouble() ?? 0;
    final commission = (order['admin_commission'] as num?)?.toDouble() ??
                       (order['commission_amount'] as num?)?.toDouble() ?? 0;
    final netAmount = totalAmount - commission;
    final status = order['status'] as String? ?? 'pending';
    final createdAt = DateTime.parse(order['created_at'] as String);
    final orderId = order['id'] as String;
    
    // Adres bilgisini asenkron olarak yükle
    final addressId = order['address_id'] as String?;
    Future<Map<String, dynamic>?> addressFuture;
    if (addressId != null && addressId.isNotEmpty) {
      addressFuture = _supabase
          .from('addresses')
          .select('id, title, full_name, phone, address_line1, address_line2, city, district, postal_code')
          .eq('id', addressId)
          .maybeSingle();
    } else {
      addressFuture = Future.value(null);
    }
    
    // Müşteri bilgisi
    final profile = order['profiles'] as Map<String, dynamic>?;
    final customerPhone = order['customer_phone'] as String? ?? profile?['phone'] as String?;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Sipariş Detayı'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Sipariş ID', '#${orderId.substring(0, 8)}'),
              _buildDetailRow('Durum', _getOrderStatusText(status)),
              _buildDetailRow('Tarih', '${createdAt.day}.${createdAt.month}.${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}'),
              const Divider(),
              _buildDetailRow('Toplam Tutar', '₺${totalAmount.toStringAsFixed(2)}', isAmount: true),
              if (commission > 0) ...[
                _buildDetailRow('Admin Komisyonu', '₺${commission.toStringAsFixed(2)}', isAmount: true, color: Colors.purple),
                _buildDetailRow('Dükkan Net Kazanç', '₺${netAmount.toStringAsFixed(2)}', isAmount: true, color: Colors.green),
              ],
              
              // Müşteri Bilgisi
              if (profile != null) ...[
                const Divider(),
                const Text('Müşteri Bilgisi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                _buildDetailRow('Ad Soyad', profile['full_name'] ?? profile['username'] ?? '-'),
                if (profile['email'] != null)
                  _buildDetailRow('E-posta', profile['email']),
              ],
              
              // Teslimat Adresi - asenkron olarak yükle
              FutureBuilder<Map<String, dynamic>?>(
                future: addressFuture,
                builder: (context, addressSnapshot) {
                  if (addressSnapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                    );
                  }
                  
                  // address_display alanını kontrol et
                  String displayAddress = order['address_display']?.toString() ?? '';
                  String addressPhone = '';
                  
                  if (addressSnapshot.hasData && addressSnapshot.data != null) {
                    final address = addressSnapshot.data!;
                    if (displayAddress.isEmpty) {
                      final parts = <String>[
                        address['address_line1'] as String? ?? '',
                        if (address['address_line2'] != null && (address['address_line2'] as String).isNotEmpty)
                          address['address_line2'] as String,
                        if (address['district'] != null && (address['district'] as String).isNotEmpty)
                          address['district'] as String,
                        address['city'] as String? ?? '',
                      ];
                      displayAddress = parts.where((p) => p.isNotEmpty).join(', ');
                    }
                    addressPhone = address['phone'] as String? ?? '';
                  }
                  
                  if (displayAddress.isEmpty && addressPhone.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      const Text('Teslimat Adresi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      if (displayAddress.isNotEmpty)
                        InkWell(
                          onTap: () => _openAddressInMap(displayAddress),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on, size: 16, color: Colors.green.shade700),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  displayAddress,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Icon(Icons.open_in_new, size: 12, color: Colors.green.shade700),
                            ],
                          ),
                        ),
                      if (addressPhone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.phone_android, size: 16, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Adres Tel: $addressPhone',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
              
              // Telefon
              if (customerPhone != null && customerPhone.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.phone, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        customerPhone,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {bool isAmount = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isAmount ? 15 : 13,
              fontWeight: isAmount ? FontWeight.bold : FontWeight.normal,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderStatusIcon(String status) {
    IconData icon;
    Color color;
    
    switch (status) {
      case 'pending': icon = Icons.schedule; color = Colors.orange; break;
      case 'processing': icon = Icons.autorenew; color = Colors.blue; break;
      case 'confirmed': icon = Icons.check_circle; color = Colors.purple; break;
      case 'delivered': icon = Icons.done_all; color = Colors.green; break;
      case 'cancelled': icon = Icons.cancel; color = Colors.red; break;
      default: icon = Icons.help_outline; color = Colors.grey;
    }
    
    return Container(
      width: 40,
      height: 40,
      // ignore: deprecated_member_use
      decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 20),
    );
  }

  /// Ürün düzenleme dialog'u
  void _showEditProductDialog(Map<String, dynamic> product) {
    final nameController = TextEditingController(text: product['name'] ?? '');
    final descriptionController = TextEditingController(text: product['description'] ?? '');
    final priceController = TextEditingController(text: product['price']?.toString() ?? '');
    final discountPriceController = TextEditingController(text: product['discount_price']?.toString() ?? '');
    final stockController = TextEditingController(text: product['stock_quantity']?.toString() ?? '');
    final imageUrlController = TextEditingController(text: product['image_url'] ?? '');
    bool isAvailable = product['is_available'] as bool? ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Text('Ürün Düzenle'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
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
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Resim URL - Opsiyonel',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Satışta'),
                    subtitle: Text(isAvailable ? 'Ürün satışta aktif' : 'Ürün pasif'),
                    value: isAvailable,
                    activeColor: Colors.green,
                    onChanged: (value) {
                      setDialogState(() => isAvailable = value);
                    },
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (nameController.text.isEmpty || priceController.text.isEmpty || stockController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen zorunlu alanları doldurun')),
                  );
                  return;
                }

                try {
                  final productData = <String, dynamic>{
                    'name': nameController.text.trim(),
                    'description': descriptionController.text.trim(),
                    'price': double.parse(priceController.text.trim()),
                    'stock_quantity': int.parse(stockController.text.trim()),
                    'is_available': isAvailable,
                  };

                  if (discountPriceController.text.isNotEmpty) {
                    productData['discount_price'] = double.parse(discountPriceController.text.trim());
                  } else {
                    productData['discount_price'] = null;
                  }

                  if (imageUrlController.text.isNotEmpty) {
                    productData['image_url'] = imageUrlController.text.trim();
                  }

                  await _supabase
                      .from('products')
                      .update(productData)
                      .eq('id', product['id']);

                  if (mounted) {
                    Navigator.pop(context);
                    _loadShopData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ürün başarıyla güncellendi'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
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
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  /// Ürün silme dialog'u
  void _showDeleteProductDialog(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('Ürün Sil'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${product['name'] ?? 'Bu ürün'}" ürününü silmek istediğinizden emin misiniz?',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu işlem geri alınamaz. Ürünle ilişkili siparişler etkilenebilir.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                await _supabase
                    .from('products')
                    .delete()
                    .eq('id', product['id']);

                if (mounted) {
                  Navigator.pop(context);
                  _loadShopData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ürün başarıyla silindi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Silinirken hata: $e'),
                      backgroundColor: Colors.red,
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

  // Adresi haritada aç
  Future<void> _openAddressInMap(String address) async {
    try {
      final encodedAddress = Uri.encodeComponent(address);
      final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Harita uygulaması açılamadı')),
          );
        }
      }
    } catch (e) {
      debugPrint('Harita açma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Harita açılırken hata: $e')),
        );
      }
    }
  }
}
