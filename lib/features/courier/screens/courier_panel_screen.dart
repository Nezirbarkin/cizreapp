// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/courier_assignment_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../market/screens/cart_screen.dart';
import '../../social/screens/social_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../market/providers/cart_provider.dart';

class CourierPanelScreen extends StatefulWidget {
  const CourierPanelScreen({super.key});

  @override
  State<CourierPanelScreen> createState() => _CourierPanelScreenState();
}

class _CourierPanelScreenState extends State<CourierPanelScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final NotificationService _notificationService = NotificationService();
  int _unreadNotificationCount = 0; // ignore: unused_field

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotificationCount();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Uygulama her ön plana geldiğinde verileri yenile
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  Future<void> _loadNotificationCount() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final count = await _notificationService.getUnreadCount(userId);
        if (mounted) {
          setState(() => _unreadNotificationCount = count);
        }
      } catch (e) {
        debugPrint('Bildirim sayısı yüklenirken hata: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return ChangeNotifierProvider(
      create: (_) => CartProvider(userId),
      child: Builder(
        builder: (context) {
          final cartProvider = context.watch<CartProvider>();

          return Scaffold(
            resizeToAvoidBottomInset: false,
            extendBody: true,
            body: IndexedStack(
              index: _selectedIndex,
              children: const [
                CourierHomeTab(),
                CourierOrdersTab(),
                CartScreen(isMainTab: true),
                SocialScreen(),
                ProfileScreen(),
              ],
            ),
            floatingActionButton: Stack(
              alignment: Alignment.topRight,
              children: [
                FloatingActionButton(
                  backgroundColor: const Color(0xFFEEFF41),
                  elevation: 8,
                  onPressed: () {
                    setState(() => _selectedIndex = 2);
                  },
                  child: Icon(
                    _selectedIndex == 2
                        ? Icons.shopping_cart
                        : Icons.shopping_cart_outlined,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
                if (cartProvider.itemCount > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3D00),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      child: Text(
                        cartProvider.itemCount > 9 ? '9+' : '${cartProvider.itemCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: BottomAppBar(
              shape: const CircularNotchedRectangle(),
              notchMargin: 8.0,
              elevation: 8,
              color: Colors.white,
              child: SizedBox(
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    _buildNavItem(
                      icon: Icons.two_wheeler_outlined,
                      activeIcon: Icons.two_wheeler,
                      label: "Kurye",
                      index: 0,
                      primaryColor: primaryColor,
                    ),
                    _buildNavItem(
                      icon: Icons.delivery_dining_outlined,
                      activeIcon: Icons.delivery_dining,
                      label: "Siparişler",
                      index: 1,
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(width: 40),
                    _buildNavItem(
                      icon: Icons.explore_outlined,
                      activeIcon: Icons.explore,
                      label: "Keşfet",
                      index: 3,
                      primaryColor: primaryColor,
                      notificationCount: 0,
                    ),
                    _buildNavItem(
                      icon: Icons.person_outline,
                      activeIcon: Icons.person,
                      label: "Profil",
                      index: 4,
                      primaryColor: primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required Color primaryColor,
    int notificationCount = 0,
  }) {
    final isSelected = _selectedIndex == index;

    return InkWell(
      onTap: () {
        setState(() => _selectedIndex = index);
        if (index == 3) {
          _loadNotificationCount();
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? primaryColor : Colors.grey.shade400,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? primaryColor : Colors.grey.shade400,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          if (notificationCount > 0)
            Positioned(
              top: -2,
              right: -12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  notificationCount > 9 ? '9+' : '$notificationCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== KURYE ANA SAYFA TAB ====================

class CourierHomeTab extends StatefulWidget {
  const CourierHomeTab({super.key});

  @override
  State<CourierHomeTab> createState() => _CourierHomeTabState();
}

class _CourierHomeTabState extends State<CourierHomeTab> {
  Map<String, dynamic>? _profile;
  double _feePerDelivery = 15.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Profil bilgilerini al
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      _profile = Map<String, dynamic>.from(profileData);

      // Kurye ücretini al
      final settings = await Supabase.instance.client
          .from('courier_settings')
          .select()
          .limit(1)
          .maybeSingle();
      if (settings != null) {
        _feePerDelivery = (settings['fee_per_delivery'] as num?)?.toDouble() ?? 15.0;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Veriler yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // Header
                  SliverAppBar(
                    expandedHeight: 180,
                    pinned: true,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.teal.shade600,
                              Colors.teal.shade800,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 30,
                                      backgroundColor: Colors.white,
                                      backgroundImage: _profile?['avatar_url'] != null
                                          ? NetworkImage(_profile!['avatar_url'])
                                          : null,
                                      child: _profile?['avatar_url'] == null
                                          ? Text(
                                              (_profile?['username'] ?? 'K')[0].toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal.shade700,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Merhaba,',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.8),
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            _profile?['full_name'] ?? _profile?['username'] ?? 'Kurye',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildStatItem(Icons.attach_money, '₺$_feePerDelivery', 'Paket Başı'),
                                      Container(width: 1, height: 40, color: Colors.white.withOpacity(0.3)),
                                      _buildStatItem(
                                        Icons.check_circle,
                                        '${_profile?['delivered_count'] ?? 0}',
                                        'Teslimat',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // İçerik
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const Text(
                          'Hızlı İşlemler',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildQuickActionCard(
                          icon: Icons.delivery_dining,
                          title: 'Mevcut Siparişler',
                          subtitle: 'Atanan siparişleri görüntüle',
                          color: Colors.orange,
                          onTap: () {
                            // Siparişler sekmesine git
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildQuickActionCard(
                          icon: Icons.history,
                          title: 'Teslimat Geçmişi',
                          subtitle: 'Tamamlanan teslimatlar',
                          color: Colors.blue,
                          onTap: () => _showDeliveryHistory(),
                        ),
                        const SizedBox(height: 12),
                        _buildQuickActionCard(
                          icon: Icons.account_balance_wallet,
                          title: 'Kazançlarım',
                          subtitle: 'Bekleyen ve ödenen kazançlar',
                          color: Colors.green,
                          onTap: () => _showEarnings(),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Nasıl Çalışır?',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildHowItWorksCard(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStepItem(Icons.notifications_active, '1', 'Sipariş Atanır', 'Kuryesi olmayan satıcıların siparişleri size atanır'),
            const Divider(),
            _buildStepItem(Icons.local_shipping, '2', 'Siparişi Al', 'Dükkanandan siparişi teslim al'),
            const Divider(),
            _buildStepItem(Icons.home, '3', 'Teslim Et', 'Müşteriye siparişi teslim et'),
            const Divider(),
            _buildStepItem(Icons.attach_money, '4', 'Kazanç Kazan', 'Paket başı ₺$_feePerDelivery kazan'),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(IconData icon, String step, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Colors.teal,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeliveryHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CourierDeliveryHistoryScreen(),
      ),
    );
  }

  void _showEarnings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CourierEarningsScreen(),
      ),
    );
  }
}

// ==================== KURYE SİPARİŞLER TAB ====================

class CourierOrdersTab extends StatefulWidget {
  const CourierOrdersTab({super.key});

  @override
  State<CourierOrdersTab> createState() => _CourierOrdersTabState();
}

class _CourierOrdersTabState extends State<CourierOrdersTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _availableOrders = [];
  List<Map<String, dynamic>> _myOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Atanabilir siparişleri yükle (kuryesi olmayan satıcıların siparişleri)
      final available = await Supabase.instance.client
          .from('orders')
          .select('''
            *,
            shops(name),
            order_items(*)
          ''')
          .eq('status', 'ready')
          .not('courier_assignments', 'cs', 'true')  // Henüz atanmamış
          .order('created_at', ascending: true)
          .limit(50);

      // Bu siparişlerin satıcılarının kuryesi var mı kontrol et
      final availableFiltered = [];
      for (final order in (available as List)) {
        final shopId = order['shop_id'];
        final shop = await Supabase.instance.client
            .from('shops')
            .select('has_own_courier')
            .eq('id', shopId)
            .maybeSingle();
        // Sadece kuryesi olmayan satıcıların siparişlerini göster
        if (shop != null && shop['has_own_courier'] != true) {
          availableFiltered.add(order);
        }
      }

      // Kuryenin atanmış siparişleri
      final assignments = await Supabase.instance.client
          .from('courier_assignments')
          .select('''
            *,
            orders(
              *,
              shops(name),
              order_items(*)
            )
          ''')
          .eq('courier_id', userId)
          .order('assigned_at', ascending: false);

      final myOrdersList = (assignments as List)
          .where((a) => a['status'] == 'assigned' || a['status'] == 'picked_up')
          .map((a) => a['orders'] as Map<String, dynamic>)
          .where((o) => o != null) // ignore: unnecessary_null_comparison
          .toList();

      setState(() {
        _availableOrders = List<Map<String, dynamic>>.from(availableFiltered);
        _myOrders = myOrdersList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Siparişler yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Siparişler'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Atanabilir (${_availableOrders.length})'),
            Tab(text: 'Siparişlerim (${_myOrders.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAvailableOrdersList(),
                _buildMyOrdersList(),
              ],
            ),
    );
  }

  Widget _buildAvailableOrdersList() {
    if (_availableOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Henüz atanabilir sipariş yok',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Satıcılar sipariş hazır olduğunda burada görünür',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _availableOrders.length,
        itemBuilder: (context, index) {
          final order = _availableOrders[index];
          return _buildAvailableOrderCard(order);
        },
      ),
    );
  }

  Widget _buildAvailableOrderCard(Map<String, dynamic> order) {
    final items = order['order_items'] as List? ?? [];
    final shopName = order['shops'] != null ? order['shops']['name'] : 'Dükkan';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '#${order['id'].toString().substring(0, 8)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '₺${order['total_amount']?.toStringAsFixed(2) ?? '0.00'}',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (order['delivery_address_text'] != null) ...[
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order['delivery_address_text'],
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '${items.length} ürün',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _acceptOrder(order),
                icon: const Icon(Icons.check),
                label: const Text('Siparişi Al'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
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

  Widget _buildMyOrdersList() {
    if (_myOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delivery_dining, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Henüz aktif siparişiniz yok',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Atanabilir siparişlerden birini alın',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myOrders.length,
        itemBuilder: (context, index) {
          final order = _myOrders[index];
          return _buildMyOrderCard(order);
        },
      ),
    );
  }

  Widget _buildMyOrderCard(Map<String, dynamic> order) {
    final items = order['order_items'] as List? ?? [];
    final shopName = order['shops'] != null ? order['shops']['name'] : 'Dükkan';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '#${order['id'].toString().substring(0, 8)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Teslim Edilecek',
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (order['delivery_address_text'] != null) ...[
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order['delivery_address_text'],
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (order['customer_phone'] != null) ...[
              Row(
                children: [
                  Icon(Icons.phone, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    order['customer_phone'],
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.phone, color: Colors.green),
                    onPressed: () => _callCustomer(order['customer_phone']),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '${items.length} ürün • ₺${order['total_amount']?.toStringAsFixed(2) ?? '0.00'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _navigateToAddress(order),
                    icon: const Icon(Icons.navigation),
                    label: const Text('Yol Tarifi'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _markAsDelivered(order),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Teslim Ettim'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
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

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Ücreti al
      final settings = await Supabase.instance.client
          .from('courier_settings')
          .select('fee_per_delivery')
          .limit(1)
          .maybeSingle();
      final fee = (settings?['fee_per_delivery'] as num?)?.toDouble() ?? 15.0;

      // Atamayı oluştur
      await Supabase.instance.client.from('courier_assignments').insert({
        'order_id': order['id'],
        'courier_id': userId,
        'status': 'assigned',
        'fee_amount': fee,
        'assigned_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sipariş alındı! Kazancınız: ₺${fee.toStringAsFixed(2)}'),
            backgroundColor: Colors.green,
          ),
        );
        _loadOrders();
      }
    } catch (e) {
      debugPrint('Sipariş alınırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sipariş alınamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markAsDelivered(Map<String, dynamic> order) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Atamayı bul ve güncelle
      final assignment = await Supabase.instance.client
          .from('courier_assignments')
          .select()
          .eq('order_id', order['id'])
          .eq('courier_id', userId)
          .eq('status', 'assigned')
          .single();

      await Supabase.instance.client.from('courier_assignments').update({
        'status': 'delivered',
        'delivered_at': DateTime.now().toIso8601String(),
      }).eq('id', assignment['id']);

      // Sipariş durumunu güncelle
      await Supabase.instance.client.from('orders').update({
        'status': 'delivered',
        'delivered_at': DateTime.now().toIso8601String(),
      }).eq('id', order['id']);

      // Teslimat sayısını artır
      await Supabase.instance.client.rpc('increment_delivered_count', params: {'uid': userId});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Teslimat tamamlandı!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadOrders();
      }
    } catch (e) {
      debugPrint('Teslimat işaretlenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İşlem başarısız: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _callCustomer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _navigateToAddress(Map<String, dynamic> order) async {
    final address = order['delivery_address_text'] ?? '';
    if (address.isEmpty) return;
    
    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ==================== TESLİMAT GEÇMİŞİ ====================

class CourierDeliveryHistoryScreen extends StatefulWidget {
  const CourierDeliveryHistoryScreen({super.key});

  @override
  State<CourierDeliveryHistoryScreen> createState() => _CourierDeliveryHistoryScreenState();
}

class _CourierDeliveryHistoryScreenState extends State<CourierDeliveryHistoryScreen> {
  List<Map<String, dynamic>> _deliveries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeliveries();
  }

  Future<void> _loadDeliveries() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('courier_assignments')
          .select('''
            *,
            orders(*, shops(name))
          ''')
          .eq('courier_id', userId)
          .eq('status', 'delivered')
          .order('delivered_at', ascending: false)
          .limit(50);

      setState(() {
        _deliveries = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Teslimat geçmişi yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teslimat Geçmişi'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deliveries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz teslimat geçmişiniz yok',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _deliveries.length,
                  itemBuilder: (context, index) {
                    final delivery = _deliveries[index];
                    final order = delivery['orders'];
                    final shopName = order?['shops']?['name'] ?? 'Dükkan';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check, color: Colors.green.shade700),
                        ),
                        title: Text(shopName),
                        subtitle: Text(
                          delivery['delivered_at'] != null
                              ? _formatDate(delivery['delivered_at'])
                              : '-',
                        ),
                        trailing: Text(
                          '₺${(delivery['fee_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    final date = DateTime.parse(dateStr);
    return '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// ==================== KAZANÇLAR ====================

class CourierEarningsScreen extends StatefulWidget {
  const CourierEarningsScreen({super.key});

  @override
  State<CourierEarningsScreen> createState() => _CourierEarningsScreenState();
}

class _CourierEarningsScreenState extends State<CourierEarningsScreen> {
  List<Map<String, dynamic>> _earnings = [];
  bool _isLoading = true;
  double _totalPending = 0;
  double _totalPaid = 0;

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('courier_earnings')
          .select()
          .eq('courier_id', userId)
          .order('created_at', ascending: false)
          .limit(100);

      final earnings = List<Map<String, dynamic>>.from(response);

      double pending = 0;
      double paid = 0;
      for (final e in earnings) {
        final amount = (e['amount'] as num?)?.toDouble() ?? 0;
        if (e['status'] == 'pending') {
          pending += amount;
        } else if (e['status'] == 'paid') {
          paid += amount;
        }
      }

      setState(() {
        _earnings = earnings;
        _totalPending = pending;
        _totalPaid = paid;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Kazançlar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kazançlarım'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade600, Colors.teal.shade800],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Toplam Bekleyen',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '₺${_totalPending.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildEarningStat('Teslimat', '${_earnings.where((e) => e['status'] == 'delivered').length}'),
                            Container(width: 1, height: 40, color: Colors.white24),
                            _buildEarningStat('Ödenen', '₺${_totalPaid.toStringAsFixed(2)}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Detaylar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                  ),
                ),
                if (_earnings.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'Henüz kazanç kaydınız yok',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final earning = _earnings[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: earning['status'] == 'paid'
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                earning['status'] == 'paid' ? Icons.check : Icons.hourglass_empty,
                                color: earning['status'] == 'paid' ? Colors.green : Colors.orange,
                              ),
                            ),
                            title: Text(
                              earning['status'] == 'paid' ? 'Ödendi' : 'Bekliyor',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(earning['created_at'] != null ? _formatDate(earning['created_at']) : '-'),
                            trailing: Text(
                              '₺${(earning['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: earning['status'] == 'paid' ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: _earnings.length,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildEarningStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    final date = DateTime.parse(dateStr);
    return '${date.day}.${date.month}.${date.year}';
  }
}
