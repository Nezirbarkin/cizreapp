// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unused_element, unnecessary_underscores

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/performance_monitoring_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../profile/screens/profile_screen.dart';
import '../../market/services/category_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/reports_content.dart';
import 'shop_detail_admin_screen.dart';
import '../widgets/support_tickets_content.dart';
import '../widgets/daily_deals_content.dart';
import '../widgets/notifications_content_v2.dart';
import '../widgets/groups_management_content.dart';
import 'about_settings_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _cacheService = CacheService();
  final _analyticsService = AnalyticsService();
  final _performanceService = PerformanceMonitoringService();
  final _connectivityService = ConnectivityService();
  // ignore: unused_field
  // ignore: unused_field
  final _categoryService = CategoryService();
  
  // Supabase'den gerçek veriler
  int _totalUsers = 0;
  int _totalPosts = 0;
  int _totalProducts = 0;
  int _totalOrders = 0;
  int _totalReports = 0;
  int _unansweredComplaintCount = 0; // Yanıtlanmamış şikayet sayısı
  int _unansweredTicketCount = 0; // Yanıtlanmamış destek talebi sayısı
  bool _isLoading = true;
  
  // Realtime subscriptions
  RealtimeChannel? _reportsChannel;
  RealtimeChannel? _ticketsChannel;
  String _selectedMenu = 'Dashboard';
  String _selectedPeriod = 'weekly'; // Raporlar için seçili dönem
  String _userSearchQuery = ''; // Kullanıcı arama sorgusu
  String? _selectedShopFilter; // Sipariş yönetiminde dükkan filtresi
  
  // Dükkan listesi - state değişkeni olarak saklanıyor
  List<Map<String, dynamic>> _shopsDetailed = [];
  bool _isLoadingShops = true;
  
  @override
  void initState() {
    super.initState();
    _loadRealData();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _reportsChannel?.unsubscribe();
    _ticketsChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    // user_reports tablosundaki INSERT ve UPDATE olaylarını dinle
    _reportsChannel = Supabase.instance.client
        .channel('admin_reports_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_reports',
          callback: (payload) {
            debugPrint('🆕 Yeni şikayet eklendi: ${payload.newRecord}');
            // Badge sayısını güncelle
            setState(() {
              _unansweredComplaintCount++;
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_reports',
          callback: (payload) {
            debugPrint('✏️ Şikayet güncellendi: ${payload.newRecord}');
            // Status değişikliğini kontrol et ve badge'i güncelle
            final oldStatus = payload.oldRecord['status'] as String?;
            final newStatus = payload.newRecord['status'] as String?;
            
            if ((oldStatus == 'pending' || oldStatus == 'reviewing') &&
                (newStatus != 'pending' && newStatus != 'reviewing')) {
              // Yanıtlandı, sayıyı azalt
              setState(() {
                if (_unansweredComplaintCount > 0) {
                  _unansweredComplaintCount--;
                }
              });
            } else if ((oldStatus != 'pending' && oldStatus != 'reviewing') &&
                       (newStatus == 'pending' || newStatus == 'reviewing')) {
              // Tekrar yanıtlanmamış duruma geçti, sayıyı artır
              setState(() {
                _unansweredComplaintCount++;
              });
            }
          },
        )
        .subscribe();

    // support_tickets tablosundaki INSERT ve UPDATE olaylarını dinle
    _ticketsChannel = Supabase.instance.client
        .channel('admin_tickets_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_tickets',
          callback: (payload) {
            debugPrint('🎫 Yeni destek talebi eklendi: ${payload.newRecord}');
            // Badge sayısını güncelle
            setState(() {
              _unansweredTicketCount++;
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_tickets',
          callback: (payload) {
            debugPrint('✏️ Destek talebi güncellendi: ${payload.newRecord}');
            // Status değişikliğini kontrol et ve badge'i güncelle
            final oldStatus = payload.oldRecord['status'] as String?;
            final newStatus = payload.newRecord['status'] as String?;
            
            if (oldStatus == 'open' && newStatus != 'open') {
              // Yanıtlandı, sayıyı azalt
              setState(() {
                if (_unansweredTicketCount > 0) {
                  _unansweredTicketCount--;
                }
              });
            } else if (oldStatus != 'open' && newStatus == 'open') {
              // Tekrar açık duruma geçti, sayıyı artır
              setState(() {
                _unansweredTicketCount++;
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadRealData() async {
    try {
      setState(() => _isLoading = true);
      
      final client = Supabase.instance.client;
      debugPrint('📊 Admin Dashboard veri yüklemesi başladı...');
      debugPrint('📊 Mevcut kullanıcı: ${client.auth.currentUser?.id}');
      debugPrint('📊 Mevcut kullanıcı email: ${client.auth.currentUser?.email}');
      
      // Kullanıcı sayısı - liste uzunluğu kullan
      final usersResponse = await client
          .from('profiles')
          .select('id');
      debugPrint('📊 Kullanıcı sayısı: ${usersResponse.length}');
      
      // Post sayısı
      final postsResponse = await client
          .from('posts')
          .select('id');
      debugPrint('📊 Post sayısı: ${postsResponse.length}');
      
      // Ürün sayısı
      final productsResponse = await client
          .from('products')
          .select('id');
      debugPrint('📊 Ürün sayısı: ${productsResponse.length}');
      
      // Sipariş sayısı
      final ordersResponse = await client
          .from('orders')
          .select('id');
      debugPrint('📊 Sipariş sayısı: ${ordersResponse.length}');
      
      // Şikayet sayısı - user_reports tablosu kullanıyoruz
      final reportsResponse = await client
          .from('user_reports')
          .select('id');
      debugPrint('📊 Şikayet sayısı: ${reportsResponse.length}');
      
      // Yanıtlanmamış şikayet sayısı
      final unansweredData = await client
          .from('user_reports')
          .select('id')
          .inFilter('status', ['pending', 'reviewing']);
      debugPrint('📊 Yanıtlanmamış şikayet: ${unansweredData.length}');
      
      // Yanıtlanmamış destek talebi sayısı
      final unansweredTicketsData = await client
          .from('support_tickets')
          .select('id')
          .eq('status', 'open');
      debugPrint('📊 Yanıtlanmamış destek talebi: ${unansweredTicketsData.length}');
      
      setState(() {
        _totalUsers = usersResponse.length;
        _totalPosts = postsResponse.length;
        _totalProducts = productsResponse.length;
        _totalOrders = ordersResponse.length;
        _totalReports = reportsResponse.length;
        _unansweredComplaintCount = unansweredData.length;
        _unansweredTicketCount = unansweredTicketsData.length;
        _isLoading = false;
      });
      
      debugPrint('✅ Admin Dashboard veri yükleme tamamlandı');
      debugPrint('📊 Sonuçlar - Users: $_totalUsers, Posts: $_totalPosts, Products: $_totalProducts, Orders: $_totalOrders');
    } catch (e, stackTrace) {
      debugPrint('❌ Veriler yüklenirken hata: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.purple.shade600,
                Colors.purple.shade800,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: Text(
              _selectedMenu,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            actions: [
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
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Yenile',
                onPressed: _loadRealData,
              ),
            ],
          ),
        ),
      ),
      drawer: _buildDrawer(context, currentUser),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildDrawer(BuildContext context, User? currentUser) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple.shade700,
              Colors.purple.shade900,
            ],
          ),
        ),
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.admin_panel_settings,
                      size: 40,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Admin Panel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      // ignore: deprecated_member_use
                    currentUser?.email ?? 'admin@cizreapp.com',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, thickness: 1),
            
            // Menu Items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    isSelected: _selectedMenu == 'Dashboard',
                    onTap: () {
                      setState(() => _selectedMenu = 'Dashboard');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.people_rounded,
                    title: 'Kullanıcılar',
                    isSelected: _selectedMenu == 'Kullanıcılar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Kullanıcılar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.post_add_rounded,
                    title: 'Gönderiler',
                    isSelected: _selectedMenu == 'Gönderiler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Gönderiler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.shopping_bag_rounded,
                    title: 'Ürünler',
                    isSelected: _selectedMenu == 'Ürünler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Ürünler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.category_rounded,
                    title: 'Kategoriler',
                    isSelected: _selectedMenu == 'Kategoriler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Kategoriler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.store_rounded,
                    title: 'Dükkanlar',
                    isSelected: _selectedMenu == 'Dükkanlar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Dükkanlar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.receipt_long_rounded,
                    title: 'Siparişler',
                    isSelected: _selectedMenu == 'Siparişler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Siparişler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.notifications_active_rounded,
                    title: 'Bildirimler',
                    isSelected: _selectedMenu == 'Bildirimler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Bildirimler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.groups_rounded,
                    title: 'Gruplar',
                    isSelected: _selectedMenu == 'Gruplar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Gruplar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.flag_rounded,
                    title: 'Şikayetler',
                    isSelected: _selectedMenu == 'Şikayetler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Şikayetler');
                      Navigator.pop(context);
                    },
                    badgeCount: _unansweredComplaintCount,
                  ),
                  _buildDrawerItem(
                    icon: Icons.support_agent_rounded,
                    title: 'Destek Talepleri',
                    isSelected: _selectedMenu == 'Destek Talepleri',
                    badgeCount: _unansweredTicketCount,
                    onTap: () {
                      setState(() => _selectedMenu = 'Destek Talepleri');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.payment_rounded,
                    title: 'Ödemeler',
                    isSelected: _selectedMenu == 'Ödemeler',
                    onTap: () {
                      setState(() => _selectedMenu = 'Ödemeler');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.assessment_rounded,
                    title: 'Raporlar',
                    isSelected: _selectedMenu == 'Raporlar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Raporlar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.local_fire_department_rounded,
                    title: 'Günün Fırsatları',
                    isSelected: _selectedMenu == 'Günün Fırsatları',
                    onTap: () {
                      setState(() => _selectedMenu = 'Günün Fırsatları');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.analytics_rounded,
                    title: 'Analitik',
                    isSelected: _selectedMenu == 'Analitik',
                    onTap: () {
                      setState(() => _selectedMenu = 'Analitik');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.api_rounded,
                    title: 'API Ayarları',
                    isSelected: _selectedMenu == 'API Ayarları',
                    onTap: () {
                      setState(() => _selectedMenu = 'API Ayarları');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.settings_rounded,
                    title: 'Ayarlar',
                    isSelected: _selectedMenu == 'Ayarlar',
                    onTap: () {
                      setState(() => _selectedMenu = 'Ayarlar');
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.info_outline_rounded,
                    title: 'Hakkında Ayarları',
                    isSelected: _selectedMenu == 'Hakkında Ayarları',
                    onTap: () {
                      setState(() => _selectedMenu = 'Hakkında Ayarları');
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            
            const Divider(color: Colors.white24, thickness: 1),
            
            // Ana Sayfaya Git
            ListTile(
              leading: const Icon(Icons.home, color: Colors.white),
              title: const Text(
                'Ana Sayfaya Dön',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/',
                  (route) => false,
                );
              },
            ),
            
            // Çıkış Yap
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white),
              title: const Text(
                'Çıkış Yap',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: Colors.white,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: badgeCount != null && badgeCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedMenu) {
      case 'Dashboard':
        return _buildDashboardContent();
      case 'Kullanıcılar':
        return _buildUsersContent();
      case 'Gönderiler':
        return _buildPostsContent();
      case 'Ürünler':
        return _buildProductsContent();
      case 'Kategoriler':
        return _buildCategoriesContent();
      case 'Dükkanlar':
        return _buildShopsContent();
      case 'Siparişler':
        return _buildOrdersContent();
      case 'Gruplar':
        return const GroupsManagementContent();
      case 'Bildirimler':
        return const NotificationsContentV2();
      case 'Şikayetler':
        return _buildReportsContent();
      case 'Destek Talepleri':
        return _buildSupportTicketsContent();
      case 'Ödemeler':
        return _buildPaymentsContent();
      case 'Raporlar':
        return _buildReportsPageContent();
      case 'Günün Fırsatları':
        return const DailyDealsContent();
      case 'Analitik':
        return _buildAnalyticsContent();
      case 'API Ayarları':
        return _buildAPISettingsContent();
      case 'Ayarlar':
        return _buildSettingsContent();
      case 'Hakkında Ayarları':
        return const AdminAboutSettingsScreen();
      default:
        return _buildComingSoon();
    }
  }

  Widget _buildUsersContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Kullanıcı bulunamadı'));
        }

        final allUsers = snapshot.data!;
        
        // Arama filtrelemesi
        final users = _userSearchQuery.isEmpty
            ? allUsers
            : allUsers.where((user) {
                final query = _userSearchQuery.toLowerCase();
                final username = (user['username'] as String?)?.toLowerCase() ?? '';
                final fullName = (user['full_name'] as String?)?.toLowerCase() ?? '';
                final email = (user['email'] as String?)?.toLowerCase() ?? '';
                
                return username.contains(query) ||
                       fullName.contains(query) ||
                       email.contains(query);
              }).toList();
        
        // İstatistikler (tüm kullanıcılar üzerinden)
        final totalUsers = allUsers.length;
        final adminCount = allUsers.where((u) => u['role'] == 'admin').length;
        final sellerCount = allUsers.where((u) => u['role'] == 'seller').length;
        final bannedCount = 0; // is_banned kolonu veritabanında mevcut değil
        
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kullanıcı Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                // Arama TextField
                TextField(
                  onChanged: (value) {
                    setState(() {
                      _userSearchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Kullanıcı ara (isim, email, kullanıcı adı)...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _userSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _userSearchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),
                
                // İstatistik Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.people,
                        title: 'Toplam',
                        value: '$totalUsers',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.admin_panel_settings,
                        title: 'Admin',
                        value: '$adminCount',
                        color: Colors.purple,
                        gradient: [Colors.purple.shade400, Colors.purple.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.store,
                        title: 'Satıcı',
                        value: '$sellerCount',
                        color: Colors.orange,
                        gradient: [Colors.orange.shade400, Colors.orange.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.block,
                        title: 'Banlı',
                        value: '$bannedCount',
                        color: Colors.red,
                        gradient: [Colors.red.shade400, Colors.red.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Filtrelenmiş sonuç bilgisi
                if (_userSearchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      '${users.length} kullanıcı bulundu',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),

                // Kullanıcı Listesi
                if (users.isEmpty && _userSearchQuery.isNotEmpty)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Arama sonucu bulunamadı',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _userSearchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('Aramayı Temizle'),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                    final user = users[index];
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundImage: user['avatar_url'] != null
                              ? NetworkImage(user['avatar_url'])
                              : null,
                          child: user['avatar_url'] == null
                              ? Text(
                                  (user['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                user['full_name'] ?? user['username'] ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _buildRoleBadge(user['role']),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.email, size: 12, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    user['email'] ?? '-',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.person, size: 12, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  '@${user['username'] ?? '-'}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                _showEditUserDialog(user);
                                break;
                              case 'change_role':
                                _showChangeRoleDialog(user);
                                break;
                              case 'delete':
                                _showDeleteUserDialog(user);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('Düzenle'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'change_role',
                              child: Row(
                                children: [
                                  Icon(Icons.admin_panel_settings, size: 18),
                                  SizedBox(width: 8),
                                  Text('Rol Değiştir'),
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
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleBadge(String? role) {
    Color color;
    IconData icon;
    String label;

    switch (role) {
      case 'admin':
        color = Colors.purple;
        icon = Icons.admin_panel_settings;
        label = 'Admin';
        break;
      case 'seller':
        color = Colors.orange;
        icon = Icons.store;
        label = 'Satıcı';
        break;
      default:
        color = Colors.blue;
        icon = Icons.person;
        label = 'Müşteri';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['full_name']);
    final usernameController = TextEditingController(text: user['username']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcı Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Ad Soyad',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Kullanıcı Adı',
                  border: OutlineInputBorder(),
                  prefixText: '@',
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
              try {
                await Supabase.instance.client
                    .from('profiles')
                    .update({
                      'full_name': nameController.text.trim(),
                      'username': usernameController.text.trim(),
                    })
                    .eq('id', user['id']);

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kullanıcı güncellendi')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
                  );
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showChangeRoleDialog(Map<String, dynamic> user) {
    String selectedRole = user['role'] ?? 'customer';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rol Değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${user['full_name'] ?? user['username']} için yeni rol seçin:'),
              const SizedBox(height: 16),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(Icons.person, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    const Text('Müşteri'),
                  ],
                ),
                value: 'customer',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(Icons.store, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    const Text('Satıcı'),
                  ],
                ),
                value: 'seller',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
              RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(Icons.admin_panel_settings, color: Colors.purple, size: 20),
                    const SizedBox(width: 8),
                    const Text('Admin'),
                  ],
                ),
                value: 'admin',
                groupValue: selectedRole,
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  debugPrint('🔄 Rol güncelleniyor: ${user['id']} -> $selectedRole');
                  
                  final response = await Supabase.instance.client
                      .from('profiles')
                      .update({'role': selectedRole})
                      .eq('id', user['id'])
                      .select();
                  
                  debugPrint('✅ Rol güncelleme yanıtı: $response');

                  // Önbelleği temizle - profil değiştiği için yeniden yüklenmeli
                  await _cacheService.clearCache();
                  debugPrint('🔄 Cache temizlendi - profiller yeniden yüklenecek');

                  if (mounted) {
                    Navigator.pop(context);
                    // Kullanıcı listesini yeniden yükle
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Rol güncellendi: $selectedRole'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e, stackTrace) {
                  debugPrint('❌ Rol güncellenirken hata: $e');
                  debugPrint('📍 Stack trace: $stackTrace');
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Rol güncellenirken hata: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
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

  // _toggleBanUser fonksiyonu kaldırıldı çünkü is_banned kolonu veritabanında mevcut değil

  void _showDeleteUserDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcıyı Sil'),
        content: Text(
          '${user['full_name'] ?? user['username']} kullanıcısını silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz ve kullanıcının tüm verileri silinecektir.',
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
                debugPrint('🗑️ Kullanıcı siliniyor: ${user['id']} (${user['username']})');
                
                final response = await Supabase.instance.client
                    .from('profiles')
                    .delete()
                    .eq('id', user['id'])
                    .select();
                
                debugPrint('✅ Kullanıcı silme yanıtı: $response');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kullanıcı başarıyla silindi'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Kullanıcı silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Kullanıcı silinirken hata: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
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

  Widget _buildPostsContent() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: Colors.purple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.purple,
              tabs: [
                Tab(icon: Icon(Icons.article), text: 'Gönderiler'),
                Tab(icon: Icon(Icons.auto_stories), text: 'Hikayeler'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildPostsList(),
                _buildStoriesList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Gönderi bulunamadı'));
        }

        final posts = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tüm Gönderiler',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () => _showAddPostDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Gönderi'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    final isPinned = post['is_pinned'] == true;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: isPinned ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isPinned ? BorderSide(color: Colors.amber.shade400, width: 2) : BorderSide.none,
                      ),
                      child: Stack(
                        children: [
                          if (isPinned)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.push_pin, size: 12, color: Colors.amber.shade800),
                                    const SizedBox(width: 2),
                                    Text('Sabitlendi', style: TextStyle(fontSize: 10, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundImage: post['profiles']?['avatar_url'] != null
                              ? NetworkImage(post['profiles']['avatar_url'])
                              : null,
                          child: post['profiles']?['avatar_url'] == null
                              ? Text(
                                  (post['profiles']?['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post['profiles']?['full_name'] ?? post['profiles']?['username'] ?? 'Bilinmeyen Kullanıcı',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (post['content'] as String?)?.substring(0, (post['content'] as String?)!.length > 80 ? 80 : (post['content'] as String?)!.length) ?? '-',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              Icon(Icons.favorite, size: 14, color: Colors.red),
                              Text(' ${post['likes_count'] ?? 0}', style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 12),
                              Icon(Icons.comment, size: 14, color: Colors.blue),
                              Text(' ${post['comments_count'] ?? 0}', style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 12),
                              Icon(Icons.access_time, size: 14, color: Colors.grey),
                              Text(' ${_formatDate(post['created_at'])}', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                          onSelected: (value) {
                            switch (value) {
                              case 'pin':
                                _togglePin('posts', post['id'], !isPinned);
                                break;
                              case 'edit':
                                _showEditPostDialog(post);
                                break;
                              case 'delete':
                                _showDeletePostDialog(post);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'pin',
                              child: Row(
                                children: [
                                  Icon(
                                    isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                                    size: 18,
                                    color: Colors.amber.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(isPinned ? 'Sabitlemeyi Kaldır' : 'Sabitle'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
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
      },
    );
  }

  Widget _buildStoriesList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadStories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        
        final stories = snapshot.data ?? [];
        
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tüm Hikayeler',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () => _showAddStoryDialog(),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Bilgi'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (stories.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz hikaye yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hikayeler mobil uygulama üzerinden oluşturulur',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: stories.length,
                    itemBuilder: (context, index) {
                      final story = stories[index];
                      final isStoryPinned = story['is_pinned'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: isStoryPinned ? 3 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isStoryPinned ? BorderSide(color: Colors.amber.shade400, width: 2) : BorderSide.none,
                        ),
                        child: Stack(
                          children: [
                            if (isStoryPinned)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.push_pin, size: 12, color: Colors.amber.shade800),
                                      const SizedBox(width: 2),
                                      Text('Sabitlendi', style: TextStyle(fontSize: 10, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundImage: story['media_url'] != null
                                    ? NetworkImage(story['media_url'])
                                    : null,
                                child: story['media_url'] == null
                                    ? const Icon(Icons.image, size: 24)
                                    : null,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.purple,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.auto_stories,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                story['profiles']?['full_name'] ?? story['profiles']?['username'] ?? 'Bilinmeyen Kullanıcı',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (story['caption'] != null && (story['caption'] as String).isNotEmpty)
                                Text(
                                  story['caption'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              children: [
                                Icon(Icons.visibility, size: 14, color: Colors.grey),
                                Text(' ${story['views_count'] ?? 0}', style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 12),
                                Icon(Icons.access_time, size: 14, color: Colors.grey),
                                Text(' ${_formatDate(story['created_at'])}', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                            onSelected: (value) {
                              switch (value) {
                                case 'pin':
                                  _togglePin('stories', story['id'], !isStoryPinned);
                                  break;
                                case 'delete':
                                  _showDeleteStoryDialog(story);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'pin',
                                child: Row(
                                  children: [
                                    Icon(
                                      isStoryPinned ? Icons.push_pin_outlined : Icons.push_pin,
                                      size: 18,
                                      color: Colors.amber.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(isStoryPinned ? 'Sabitlemeyi Kaldır' : 'Sabitle'),
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
      },
    );
  }

  Widget _buildProductsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadProducts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final products = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tüm Ürünler',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () => _showAddProductDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Ürün'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (products.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Ürün bulunamadı',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final isProductPinned = product['is_pinned'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: isProductPinned ? 3 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isProductPinned ? BorderSide(color: Colors.amber.shade400, width: 2) : BorderSide.none,
                        ),
                        child: Stack(
                          children: [
                            if (isProductPinned)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.push_pin, size: 12, color: Colors.amber.shade800),
                                      const SizedBox(width: 2),
                                      Text('Sabitlendi', style: TextStyle(fontSize: 10, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey.shade100,
                            ),
                            child: product['image_url'] != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      product['image_url'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Icon(Icons.image, size: 30, color: Colors.grey);
                                      },
                                    ),
                                  )
                                : const Icon(Icons.shopping_bag, size: 30, color: Colors.grey),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['name'] ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (product['shops'] != null)
                                Row(
                                  children: [
                                    Icon(Icons.store, size: 12, color: Colors.orange.shade700),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        product['shops']['name'] ?? 'Bilinmeyen Satıcı',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange.shade700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2, size: 14, color: Colors.grey.shade600),
                                    Text(' Stok: ${product['stock_quantity'] ?? 0}', style: const TextStyle(fontSize: 12)),
                                    const SizedBox(width: 12),
                                    Icon(Icons.category, size: 14, color: Colors.grey.shade600),
                                    Expanded(
                                      child: Text(
                                        ' ${product['category_id'] ?? '-'}',
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                                    Text(' ${_formatDate(product['created_at'])}', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₺${product['price'] ?? 0}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.green,
                                    ),
                                  ),
                                  if (product['discount_price'] != null)
                                    Text(
                                      '₺${product['discount_price']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.red.shade700,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                ],
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'pin':
                                      _togglePin('products', product['id'], !isProductPinned);
                                      break;
                                    case 'edit':
                                      _showEditProductDialog(product);
                                      break;
                                    case 'delete':
                                      _showDeleteProductDialog(product);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'pin',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isProductPinned ? Icons.push_pin_outlined : Icons.push_pin,
                                          size: 18,
                                          color: Colors.amber.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(isProductPinned ? 'Sabitlemeyi Kaldır' : 'Sabitle'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 18),
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
      },
    );
  }

  Widget _buildCategoriesContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadCategories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final categories = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Kategori Yönetimi',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddCategoryDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Kategori'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (categories.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz kategori yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return _buildCategoryCard(category);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    final iconData = Icons.category; // Varsayılan icon
    final color = Colors.purple; // Varsayılan renk
    final shopCount = category['shop_count'] ?? 0;
    final imageUrl = category['image_url'] as String?;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: IntrinsicHeight(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Resim varsa göster, yoksa ikon göster
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: imageUrl == null ? color.withOpacity(0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(iconData, color: color, size: 24);
                              },
                            ),
                          )
                        : Icon(iconData, color: color, size: 24),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditCategoryDialog(category);
                      } else if (value == 'delete') {
                        _showDeleteCategoryDialog(category);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Düzenle'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Sil', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                category['name'] ?? '-',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Dükkan sayısı gösterimi
              Row(
                children: [
                  Icon(Icons.store, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    '$shopCount dükkan',
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  category['description'] ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.sort, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    'Sıra: ${category['display_order'] ?? 0}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  if (category['is_active'] == true)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Aktif',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Pasif',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Sipariş bulunamadı',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        final orders = snapshot.data!;
        
        // Toplam istatistikler
        double totalRevenue = 0;
        double totalAdminCommission = 0;
        double totalSellerEarnings = 0;
        int completedOrders = 0;
        int pendingOrders = 0;
        int processingOrders = 0;
        int cancelledOrders = 0;
        
        for (var order in orders) {
          if (order['status'] != 'cancelled') {
            totalRevenue += (order['total'] as num?)?.toDouble() ?? 0;
            totalAdminCommission += (order['admin_commission'] as num?)?.toDouble() ?? 0;
            totalSellerEarnings += (order['seller_earnings'] as num?)?.toDouble() ?? 0;
          }
          switch (order['status']) {
            case 'delivered':
              completedOrders++;
              break;
            case 'pending':
              pendingOrders++;
              break;
            case 'preparing':
            case 'confirmed':
            case 'on_the_way':
              processingOrders++;
              break;
            case 'cancelled':
              cancelledOrders++;
              break;
          }
        }
        
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                const Text(
                  'Sipariş Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                // Dükkan Filtresi
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadShopsForFilter(),
                  builder: (context, shopSnapshot) {
                    if (shopSnapshot.hasData) {
                      final shops = shopSnapshot.data!;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.store, size: 20, color: Colors.orange),
                            const SizedBox(width: 8),
                            const Text('Dükkan:', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  value: _selectedShopFilter,
                                  isExpanded: true,
                                  hint: const Text('Tüm Dükkanlar'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Tüm Dükkanlar'),
                                    ),
                                    ...shops.map((shop) => DropdownMenuItem<String?>(
                                      value: shop['id'] as String,
                                      child: Text(shop['name'] as String? ?? 'Bilinmeyen'),
                                    )),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedShopFilter = value;
                                    });
                                  },
                                ),
                              ),
                            ),
                            if (_selectedShopFilter != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _selectedShopFilter = null;
                                  });
                                },
                                tooltip: 'Filtreyi temizle',
                              ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 12),
                
                // Durum İstatistikleri
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildOrderStatChip(
                        icon: Icons.pending_actions,
                        label: 'Bekleyen',
                        count: pendingOrders,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      _buildOrderStatChip(
                        icon: Icons.autorenew,
                        label: 'İşleniyor',
                        count: processingOrders,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      _buildOrderStatChip(
                        icon: Icons.check_circle,
                        label: 'Tamamlanan',
                        count: completedOrders,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      _buildOrderStatChip(
                        icon: Icons.cancel,
                        label: 'İptal',
                        count: cancelledOrders,
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Kazanç Kartları
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.analytics, color: Colors.purple.shade600),
                            const SizedBox(width: 8),
                            const Text(
                              'Kazanç Özeti',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _buildEarningsItem(
                                title: 'Toplam Ciro',
                                amount: totalRevenue,
                                color: Colors.blue,
                                icon: Icons.attach_money,
                              ),
                            ),
                            Expanded(
                              child: _buildEarningsItem(
                                title: 'Admin Komisyon',
                                amount: totalAdminCommission,
                                color: Colors.purple,
                                icon: Icons.admin_panel_settings,
                              ),
                            ),
                            Expanded(
                              child: _buildEarningsItem(
                                title: 'Satıcı Kazanç',
                                amount: totalSellerEarnings,
                                color: Colors.green,
                                icon: Icons.store,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Siparişler Listesi
                Text(
                  'Tüm Siparişler (${orders.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _buildOrderCard(order);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildOrderStatChip({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEarningsItem({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          '₺${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final profile = order['profiles'] as Map<String, dynamic>?;
    final shop = order['shops'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'pending';
    final totalAmount = (order['total'] as num?)?.toDouble() ?? 0;
    final adminCommission = (order['admin_commission'] as num?)?.toDouble() ?? 0;
    final sellerEarnings = (order['seller_earnings'] as num?)?.toDouble() ?? 0;
    final commissionRate = (order['commission_rate'] as num?)?.toDouble() ?? 10;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showOrderDetailDialog(order),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Kısım: Sipariş No ve Durum
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sipariş #${(order['id'] as String?)?.substring(0, 8) ?? '-'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(order['created_at']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(status),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showEditOrderDialog(order);
                          break;
                        case 'delete':
                          _showDeleteOrderDialog(order);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Durumu Değiştir'),
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
                ],
              ),
              const Divider(height: 16),
              
              // Müşteri Bilgisi
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.blue.shade100,
                    backgroundImage: profile?['avatar_url'] != null
                        ? NetworkImage(profile!['avatar_url'])
                        : null,
                    child: profile?['avatar_url'] == null
                        ? Text(
                            (profile?['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?['full_name'] ?? profile?['username'] ?? 'Bilinmeyen Müşteri',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          profile?['email'] ?? '-',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Müşteri Telefonu ve Adres
              Builder(
                builder: (context) {
                  final customerPhone = order['customer_phone'] as String? ?? profile?['phone'] as String?;
                  final addressDisplay = order['address_display'] as String?;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (customerPhone != null && customerPhone.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone, size: 14, color: Colors.green.shade700),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  customerPhone,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (addressDisplay != null && addressDisplay.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on, size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  addressDisplay,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              
              // Dükkan Bilgisi
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        shop?['name'] ?? 'Bilinmeyen Dükkan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              
              // Ürün Görselleri ve Bilgileri
              Builder(
                builder: (context) {
                  final orderItems = order['order_items'] as List? ?? [];
                  if (orderItems.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 60,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: orderItems.length > 5 ? 5 : orderItems.length,
                          itemBuilder: (context, index) {
                            final item = orderItems[index] as Map<String, dynamic>;
                            final imageUrl = item['product_image_url'] as String?;
                            final quantity = item['quantity'] as int? ?? 1;
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: Colors.grey.shade100,
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: imageUrl != null && imageUrl.isNotEmpty
                                          ? Image.network(
                                              imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Icon(Icons.image, size: 24, color: Colors.grey.shade400),
                                            )
                                          : Icon(Icons.shopping_bag, size: 24, color: Colors.grey.shade400),
                                    ),
                                  ),
                                  if (quantity > 1)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF97316),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'x$quantity',
                                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (orderItems.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '+${orderItems.length - 5} ürün daha',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  );
                },
              ),
              
              const Divider(height: 16),
              
              // Kazanç Bilgileri
              Row(
                children: [
                  Expanded(
                    child: _buildOrderAmountItem(
                      label: 'Toplam',
                      amount: totalAmount,
                      color: Colors.blue.shade700,
                      isBold: true,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.grey.shade300,
                  ),
                  Expanded(
                    child: _buildOrderAmountItem(
                      label: 'Komisyon (%${commissionRate.toStringAsFixed(0)})',
                      amount: adminCommission,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.grey.shade300,
                  ),
                  Expanded(
                    child: _buildOrderAmountItem(
                      label: 'Satıcı',
                      amount: sellerEarnings,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildOrderAmountItem({
    required String label,
    required double amount,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      children: [
        Text(
          '₺${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  Widget _buildStatusBadge(String status) {
    Color color;
    IconData icon;
    String label;
    
    switch (status) {
      case 'pending':
        color = Colors.orange;
        icon = Icons.pending_actions;
        label = 'Bekliyor';
        break;
      case 'processing':
        color = Colors.blue;
        icon = Icons.autorenew;
        label = 'İşleniyor';
        break;
      case 'completed':
      case 'delivered':
        color = Colors.green;
        icon = Icons.check_circle;
        label = 'Tamamlandı';
        break;
      case 'cancelled':
        color = Colors.red;
        icon = Icons.cancel;
        label = 'İptal';
        break;
      default:
        color = Colors.grey;
        icon = Icons.help;
        label = status;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showOrderDetailDialog(Map<String, dynamic> order) {
    final profile = order['profiles'] as Map<String, dynamic>?;
    final shop = order['shops'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'pending';
    final totalAmount = (order['total'] as num?)?.toDouble() ?? 0;
    final adminCommission = (order['admin_commission'] as num?)?.toDouble() ?? 0;
    final sellerEarnings = (order['seller_earnings'] as num?)?.toDouble() ?? 0;
    final commissionRate = (order['commission_rate'] as num?)?.toDouble() ?? 10;
    
    // Adres bilgisini asenkron olarak yükle
    final addressId = order['address_id'] as String?;
    Future<Map<String, dynamic>?> addressFuture;
    if (addressId != null && addressId.isNotEmpty) {
      addressFuture = Supabase.instance.client
          .from('addresses')
          .select('id, title, full_name, phone, address_line1, address_line2, city, district, postal_code')
          .eq('id', addressId)
          .maybeSingle();
    } else {
      addressFuture = Future.value(null);
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade400, Colors.purple.shade600],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sipariş #${(order['id'] as String?)?.substring(0, 8) ?? '-'}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    _formatDate(order['created_at']),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Durum
                Center(child: _buildStatusBadge(status)),
                const SizedBox(height: 16),
                
                // Müşteri Bilgisi
                const Text(
                  'Müşteri Bilgisi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.blue.shade200,
                          backgroundImage: profile?['avatar_url'] != null
                              ? NetworkImage(profile!['avatar_url'])
                              : null,
                          child: profile?['avatar_url'] == null
                              ? Text(
                                  (profile?['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade800,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?['full_name'] ?? profile?['username'] ?? 'Bilinmeyen',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                profile?['email'] ?? '-',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Dükkan Bilgisi
                const Text(
                  'Dükkan Bilgisi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.store, color: Colors.orange.shade800),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop?['name'] ?? 'Bilinmeyen Dükkan',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Komisyon Oranı: %${commissionRate.toStringAsFixed(1)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Kazanç Detayları
                const Text(
                  'Kazanç Detayları',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.grey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildDetailRow('Sipariş Tutarı', '₺${totalAmount.toStringAsFixed(2)}', Colors.blue),
                        const Divider(),
                        _buildDetailRow('Admin Komisyonu (%${commissionRate.toStringAsFixed(0)})', '₺${adminCommission.toStringAsFixed(2)}', Colors.purple),
                        const Divider(),
                        _buildDetailRow('Satıcı Kazancı', '₺${sellerEarnings.toStringAsFixed(2)}', Colors.green),
                      ],
                    ),
                  ),
                ),
                
                // Teslimat Adresi ve Telefon
                const SizedBox(height: 16),
                const Text(
                  'Teslimat Bilgileri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Adres - asenkron olarak yükle
                        FutureBuilder<Map<String, dynamic>?>(
                          future: addressFuture,
                          builder: (context, addressSnapshot) {
                            // Önce address_display alanını kontrol et
                            String displayAddress = order['address_display']?.toString() ?? '';
                            String addressPhone = '';
                            
                            // Eğer address_display boşsa ve addresses tablosundan veri geldiyse
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
                            
                            if (addressSnapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              );
                            }
                            
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (displayAddress.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () => _openAddressInMap(displayAddress),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Row(
                                      children: [
                                        Icon(Icons.location_on, color: Colors.green.shade700, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            displayAddress,
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                        Icon(Icons.open_in_new, color: Colors.green.shade700, size: 16),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                // Adresteki telefon bilgisi
                                if (addressPhone.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      Icon(Icons.phone_android, color: Colors.green.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Adres Tel: $addressPhone',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (displayAddress.isEmpty && !addressSnapshot.hasData)
                                  Row(
                                    children: [
                                      Icon(Icons.location_off, color: Colors.grey.shade500, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Adres bilgisi bulunamadı',
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                              ],
                            );
                          },
                        ),
                        // Telefon - orders tablosundan veya profilinden al
                        Builder(
                          builder: (context) {
                            final customerPhone = order['customer_phone'] as String? ??
                                                  profile?['phone'] as String?;
                            if (customerPhone != null && customerPhone.isNotEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.phone, color: Colors.green.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          customerPhone,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _callCustomerFromAdmin(customerPhone),
                                      icon: const Icon(Icons.call, size: 16),
                                      label: const Text('Müşteriyi Ara'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            // Telefon yoksa hiçbir şey gösterme
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showEditOrderDialog(order);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Durumu Değiştir'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, Color color) {
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
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showEditOrderDialog(Map<String, dynamic> order) {
    String selectedStatus = order['status'] ?? 'pending';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Sipariş Durumunu Değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sipariş #${(order['id'] as String?)?.substring(0, 8) ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Yeni durum seçin:'),
              const SizedBox(height: 12),
              _buildStatusOption(
                status: 'pending',
                label: 'Beklemede',
                icon: Icons.access_time,
                color: Colors.orange,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'pending'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'confirmed',
                label: 'Onaylandı',
                icon: Icons.check_circle_outline,
                color: Colors.blue,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'confirmed'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'preparing',
                label: 'Hazırlanıyor',
                icon: Icons.restaurant_menu,
                color: Colors.purple,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'preparing'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'ready',
                label: 'Hazır',
                icon: Icons.inventory_2,
                color: Colors.teal,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'ready'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'on_the_way',
                label: 'Yolda',
                icon: Icons.two_wheeler,
                color: Colors.indigo,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'on_the_way'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'delivered',
                label: 'Teslim Edildi',
                icon: Icons.task_alt,
                color: Colors.green,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'delivered'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'cancelled',
                label: 'İptal Edildi',
                icon: Icons.cancel,
                color: Colors.red,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'cancelled'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  debugPrint('📝 Sipariş durumu güncelleniyor: ${order['id']} -> $selectedStatus');
                  
                  await Supabase.instance.client
                      .from('orders')
                      .update({'status': selectedStatus})
                      .eq('id', order['id']);
                  
                  debugPrint('✅ Sipariş durumu başarıyla güncellendi');
                  
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sipariş durumu güncellendi: $selectedStatus'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Sipariş güncellenirken hata: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sipariş güncellenirken hata: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusOption({
    required String status,
    required String label,
    required IconData icon,
    required Color color,
    required String selectedStatus,
    required VoidCallback onTap,
  }) {
    final isSelected = status == selectedStatus;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.grey.shade700,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, color: color),
          ],
        ),
      ),
    );
  }
  
  void _showDeleteOrderDialog(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Siparişi Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sipariş #${(order['id'] as String?)?.substring(0, 8) ?? '-'} silinecek.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu işlem geri alınamaz. Sipariş ve ilişkili tüm veriler silinecektir.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade900,
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
                final orderId = order['id'];
                debugPrint('🗑️ Sipariş siliniyor: $orderId');
                
                // Siparişi sil (cascade delete order_items'i otomatik siler)
                final result = await Supabase.instance.client
                    .from('orders')
                    .delete()
                    .eq('id', orderId);
                
                debugPrint('✅ Sipariş silme başarılı: $result');
                
                if (mounted) {
                  Navigator.pop(context);
                  // Listeyi yenile
                  setState(() {});
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sipariş başarıyla silindi'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } on PostgrestException catch (e) {
                debugPrint('❌ PostgreSQL Hatası: ${e.message}');
                debugPrint('Hata kodu: ${e.code}');
                debugPrint('Detay: ${e.details}');
                
                if (mounted) {
                  String errorMessage = 'Bilinmeyen hata';
                  
                  // RLS policy hatası
                  if (e.code == '42501' || e.message.contains('policy')) {
                    errorMessage = 'Yetkilendirme hatası. Admin olduğunuzu kontrol edin.';
                  }
                  // Constraint hatası
                  else if (e.code == '23503') {
                    errorMessage = 'Sipariş ilişkili verilere sahip';
                  }
                  // Genel hata
                  else {
                    errorMessage = e.message;
                  }
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $errorMessage'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Sipariş silinirken hata: $e');
                debugPrint('Stack trace: $stackTrace');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
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


  Widget _buildReportsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final reports = snapshot.data ?? [];
        
        // İstatistikler
        final pendingCount = reports.where((r) => r['status'] == 'pending').length;
        final reviewingCount = reports.where((r) => r['status'] == 'reviewing').length;
        final resolvedCount = reports.where((r) => r['status'] == 'resolved').length;
        final rejectedCount = reports.where((r) => r['status'] == 'rejected').length;
        
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kullanıcı Şikayetleri Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                // İstatistik Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildReportStatCard(
                        icon: Icons.pending,
                        title: 'Bekleyen',
                        count: pendingCount,
                        status: 'pending',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildReportStatCard(
                        icon: Icons.visibility,
                        title: 'İnceleniyor',
                        count: reviewingCount,
                        status: 'reviewing',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildReportStatCard(
                        icon: Icons.check_circle,
                        title: 'Çözüldü',
                        count: resolvedCount,
                        status: 'resolved',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildReportStatCard(
                        icon: Icons.cancel,
                        title: 'Reddedildi',
                        count: rejectedCount,
                        status: 'rejected',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                if (reports.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Şikayet bulunamadı',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: reports.length,
                    itemBuilder: (context, index) {
                      final report = reports[index];
                      final reporter = report['reporter'] as Map<String, dynamic>?;
                      final reported = report['reported'] as Map<String, dynamic>?;
                      final status = report['status'] as String? ?? 'pending';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: _getReportStatusColor(status).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _showReportDetailDialog(report),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Başlık - Durum ve İşlemler
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _getReportStatusColor(status).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _getReportStatusIcon(status),
                                            size: 14,
                                            color: _getReportStatusColor(status),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _getReportStatusText(status),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _getReportStatusColor(status),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _showDeleteReportDialog(report),
                                      tooltip: 'Sil',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                
                                // Şikayet Eden
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundImage: reporter?['avatar_url'] != null
                                          ? NetworkImage(reporter!['avatar_url'])
                                          : null,
                                      child: reporter?['avatar_url'] == null
                                          ? Text(
                                              (reporter?['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade700,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.person, size: 12, color: Colors.blue.shade700),
                                              const SizedBox(width: 4),
                                              Text(
                                                reporter?['full_name'] ?? reporter?['username'] ?? 'Bilinmeyen',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            'Şikayet eden',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward, size: 16, color: Colors.grey.shade400),
                                    const SizedBox(width: 8),
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundImage: reported?['avatar_url'] != null
                                          ? NetworkImage(reported!['avatar_url'])
                                          : null,
                                      child: reported?['avatar_url'] == null
                                          ? Text(
                                              (reported?['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red.shade700,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.person_off, size: 12, color: Colors.red.shade700),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  reported?['full_name'] ?? reported?['username'] ?? 'Bilinmeyen',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            'Şikayet edilen',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                
                                // Şikayet Sebebi
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag, color: Colors.red.shade700, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          report['reason'] ?? '-',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red.shade900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                // Açıklama (varsa)
                                if (report['description'] != null && (report['description'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.description_outlined, color: Colors.grey.shade700, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            report['description'],
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 13,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                
                                const SizedBox(height: 12),
                                
                                // Tarih
                                Row(
                                  children: [
                                    Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDate(report['created_at']),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
      },
    );
  }
  
  Widget _buildReportStatCard({
    required IconData icon,
    required String title,
    required int count,
    required String status,
  }) {
    final color = _getReportStatusColor(status);
    
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Color _getReportStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'reviewing':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getReportStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending;
      case 'reviewing':
        return Icons.visibility;
      case 'resolved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
  
  String _getReportStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Bekliyor';
      case 'reviewing':
        return 'İnceleniyor';
      case 'resolved':
        return 'Çözüldü';
      case 'rejected':
        return 'Reddedildi';
      default:
        return status;
    }
  }

  // Dükkanı olmayan kullanıcıları yükle (dükkan ekleme için)
  Future<List<Map<String, dynamic>>> _loadUsersWithoutShop() async {
    try {
      debugPrint('🔍 Dükkanı olmayan kullanıcılar yükleniyor...');
      
      // Önce tüm dükkan sahiplerini al
      final shopsResponse = await Supabase.instance.client
          .from('shops')
          .select('owner_id');
      
      final shopOwnerIds = shopsResponse
          .map((shop) => shop['owner_id'] as String)
          .toSet();
      
      // Tüm kullanıcıları al
      final usersResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, username, full_name, email, role')
          .order('created_at', ascending: false);
      
      // Dükkanı olmayanları filtrele
      final usersWithoutShop = List<Map<String, dynamic>>.from(usersResponse)
          .where((user) => !shopOwnerIds.contains(user['id']))
          .toList();
      
      debugPrint('✅ Dükkanı olmayan ${usersWithoutShop.length} kullanıcı bulundu');
      
      return usersWithoutShop;
    } catch (e) {
      debugPrint('❌ Dükkanı olmayan kullanıcılar yüklenirken hata: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    try {
      debugPrint('🔍 Kullanıcılar yükleniyor...');
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, username, full_name, email, role, avatar_url, created_at')
          .order('created_at', ascending: false)
          .limit(50);
      
      debugPrint('✅ Kullanıcı sorgusu başarılı. Dönen veri tipi: ${response.runtimeType}');
      debugPrint('📊 Veri içeriği: $response');
      
      final users = List<Map<String, dynamic>>.from(response);
      debugPrint('✅ ${users.length} kullanıcı bulundu');
      
      return users;
    } catch (e, stackTrace) {
      debugPrint('❌ Kullanıcılar yüklenirken hata: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      
      // Hata mesajını kullanıcıya göster
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kullanıcılar yüklenirken hata oluştu: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Yeniden Dene',
                textColor: Colors.white,
                onPressed: () {
                  setState(() {});
                },
              ),
            ),
          );
        });
      }
      
      // Hata durumunda boş liste döndür
      return [];
    }
  }

  Future<void> _togglePin(String table, String id, bool pin) async {
    try {
      debugPrint('📌 Sabitleme işlemi: $table, $id -> $pin');
      
      // RPC fonksiyonu adını belirle
      String rpcFunction = 'admin_pin_$table';
      if (table == 'posts') {
        rpcFunction = 'admin_pin_post';
      } else if (table == 'stories') {
        rpcFunction = 'admin_pin_story';
      } else if (table == 'products') {
        rpcFunction = 'admin_pin_product';
      } else if (table == 'shops') {
        rpcFunction = 'admin_pin_shop';
      }
      
      // Önce RPC ile dene
      bool pinned = false;
      try {
        final rpcResponse = await Supabase.instance.client.rpc(
          rpcFunction,
          params: {
            '${table.substring(0, table.length - 1)}_id': id,
            'pinned': pin,
          },
        );
        debugPrint('✅ RPC sabitleme yanıtı: $rpcResponse');
        pinned = true;
      } catch (rpcError) {
        debugPrint('⚠️ RPC hatası (fonksiyon yok olabilir), doğrudan güncelleme deneniyor: $rpcError');
        // RPC başarısız olursa doğrudan güncelle
        final response = await Supabase.instance.client
            .from(table)
            .update({'is_pinned': pin})
            .eq('id', id)
            .select();
            
        debugPrint('✅ Doğrudan sabitleme yanıtı: $response');
        if (response.isNotEmpty) {
          pinned = true;
        }
      }
      
      if (mounted) {
        if (pinned) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(pin ? 'İçerik sabitlendi' : 'Sabitleme kaldırıldı'),
              backgroundColor: pin ? Colors.amber.shade700 : Colors.grey.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
          setState(() {});
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sabitleme yapılamadı - RLS izni kontrol edin'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Pin toggle hatası: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sabitleme hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadPosts() async {
    try {
      final response = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(id, username, full_name, avatar_url)')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Gönderiler yüklenirken hata: $e');
      // Mock veriler döndür
      return [
        {
          'id': '1',
          'content': 'Harika bir gün! Bugün yeni projeme başladım.',
          'likes_count': 42,
          'comments_count': 8,
          'created_at': DateTime.now().toIso8601String(),
          'profiles': {'username': 'ahmet', 'full_name': 'Ahmet Yılmaz', 'avatar_url': null}
        },
        {
          'id': '2',
          'content': 'Flutter öğrenmek çok eğlenceli. Her gün yeni bir şey keşfediyorum.',
          'likes_count': 128,
          'comments_count': 23,
          'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
          'profiles': {'username': 'ayse', 'full_name': 'Ayşe Demir', 'avatar_url': null}
        },
        {
          'id': '3',
          'content': 'Kahve mola zamanı ☕',
          'likes_count': 67,
          'comments_count': 12,
          'created_at': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
          'profiles': {'username': 'mehmet', 'full_name': 'Mehmet Kaya', 'avatar_url': null}
        },
        {
          'id': '4',
          'content': 'Bu hafta çok yoğundu ama bitirdik!',
          'likes_count': 234,
          'comments_count': 45,
          'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
          'profiles': {'username': 'zeynep', 'full_name': 'Zeynep Aksoy', 'avatar_url': null}
        },
      ];
    }
  }

  void _showAddPostDialog() {
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Gönderi Ekle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'İçerik',
                  border: OutlineInputBorder(),
                  hintText: 'Gönderi içeriği...',
                ),
                maxLines: 5,
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
              if (contentController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('İçerik gerekli')),
                );
                return;
              }

              try {
                await Supabase.instance.client.from('posts').insert({
                  'content': contentController.text.trim(),
                  'user_id': Supabase.instance.client.auth.currentUser?.id,
                });

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gönderi eklendi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gönderi eklenirken hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _showEditPostDialog(Map<String, dynamic> post) {
    final contentController = TextEditingController(text: post['content']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderi Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'İçerik',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
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
              if (contentController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('İçerik gerekli')),
                );
                return;
              }

              try {
                debugPrint('📝 Gönderi güncelleniyor: ${post['id']}');
                
                final response = await Supabase.instance.client
                    .from('posts')
                    .update({'content': contentController.text.trim()})
                    .eq('id', post['id'])
                    .select();
                
                debugPrint('✅ Gönderi güncelleme yanıtı: $response');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gönderi güncellendi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Gönderi güncellenirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gönderi güncellenirken hata: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showDeletePostDialog(Map<String, dynamic> post) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderiyi Sil'),
        content: Text(
          'Bu gönderiyi silmek istediğinizden emin misiniz?\n\n"${(post['content'] as String).substring(0, (post['content'] as String).length > 50 ? 50 : (post['content'] as String).length)}..."\n\nBu işlem geri alınamaz.',
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
                debugPrint('🗑️ Gönderi siliniyor: ${post['id']}');
                debugPrint('📋 Kullanıcı ID: ${Supabase.instance.client.auth.currentUser?.id}');
                debugPrint('📋 Kullanıcı rolü: ${Supabase.instance.client.auth.currentUser?.role}');
                debugPrint('📋 Kullanıcı meta: ${Supabase.instance.client.auth.currentUser?.userMetadata}');
                
                // Önce RPC ile dene (RLS bypass için)
                bool deleted = false;
                try {
                  await Supabase.instance.client.rpc('admin_delete_post', params: {'post_id': post['id']});
                  debugPrint('✅ Gönderi RPC ile silindi');
                  deleted = true;
                } catch (rpcError) {
                  debugPrint('⚠️ RPC hatası (fonksiyon yok olabilir), doğrudan silme deneniyor: $rpcError');
                  // RPC başarısız olursa doğrudan sil
                  final response = await Supabase.instance.client
                      .from('posts')
                      .delete()
                      .eq('id', post['id'])
                      .select();
                  
                  debugPrint('✅ Gönderi silme yanıtı: $response');
                  if (response.isNotEmpty) {
                    deleted = true;
                  }
                }

                if (mounted) {
                  if (deleted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Gönderi başarıyla silindi'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Gönderi silinemedi - RLS izni kontrol edin'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Gönderi silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Gönderi silinirken hata: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
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

  Future<List<Map<String, dynamic>>> _loadStories() async {
    try {
      final response = await Supabase.instance.client
          .from('stories')
          .select('*, profiles(id, username, full_name, avatar_url)')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Hikayeler yüklenirken hata: $e');
      return [];
    }
  }

  void _showAddStoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Hikaye Ekle'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('Hikaye resimleri yüklemek için uygulamadaki hikaye özelliğini kullanınız'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  void _showDeleteStoryDialog(Map<String, dynamic> story) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hikayeyi Sil'),
        content: Text(
          'Bu hikayeyi silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz.',
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
                debugPrint('🗑️ Hikaye siliniyor: ${story['id']}');
                debugPrint('📋 Kullanıcı ID: ${Supabase.instance.client.auth.currentUser?.id}');
                debugPrint('📋 Kullanıcı rolü: ${Supabase.instance.client.auth.currentUser?.role}');
                debugPrint('📋 Kullanıcı meta: ${Supabase.instance.client.auth.currentUser?.userMetadata}');
                
                // Önce RPC ile dene (RLS bypass için)
                bool deleted = false;
                try {
                  await Supabase.instance.client.rpc('admin_delete_story', params: {'story_id': story['id']});
                  debugPrint('✅ Hikaye RPC ile silindi');
                  deleted = true;
                } catch (rpcError) {
                  debugPrint('⚠️ RPC hatası (fonksiyon yok olabilir), doğrudan silme deneniyor: $rpcError');
                  // RPC başarısız olursa doğrudan sil
                  final response = await Supabase.instance.client
                      .from('stories')
                      .delete()
                      .eq('id', story['id'])
                      .select();
                  
                  debugPrint('✅ Hikaye silme yanıtı: $response');
                  if (response.isNotEmpty) {
                    deleted = true;
                  }
                }

                if (mounted) {
                  if (deleted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Hikaye başarıyla silindi'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Hikaye silinemedi - RLS izni kontrol edin'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Hikaye silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hikaye silinirken hata: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
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

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    try {
      final response = await Supabase.instance.client
          .from('products')
          .select('*, shops(id, name, owner_id)')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Ürünler yüklenirken hata: $e');
      // Hata durumunda boş liste döndür
      return [];
    }
  }

  Widget _buildShopsContent() {
    if (_isLoadingShops && _shopsDetailed.isEmpty) {
      _loadAndSetShops();
      return const Center(child: CircularProgressIndicator());
    }
    
    final shops = _shopsDetailed;
    
    return RefreshIndicator(
      onRefresh: () async {
        await _loadAndSetShops();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dükkan Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddShopDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Dükkan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (shops.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.store_outlined,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz dükkan yok',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shops.length,
                itemBuilder: (context, index) {
                  final shop = shops[index];
                  return _buildShopCard(shop);
                },
              ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _loadAndSetShops() async {
    setState(() { _isLoadingShops = true; });
    final shops = await _loadShopsWithDetails();
    if (mounted) {
      setState(() {
        _shopsDetailed = shops;
        _isLoadingShops = false;
      });
    }
  }

  Widget _buildShopCard(Map<String, dynamic> shop) {
    final ownerName = shop['profiles']?['full_name'] ?? shop['profiles']?['username'] ?? 'Bilinmeyen';
    final ownerEmail = shop['profiles']?['email'] ?? '-';
    final commission = (shop['commission_rate'] as num?)?.toDouble() ?? 10.0;
    final productCount = shop['product_count'] ?? 0;
    final totalEarnings = (shop['total_earnings'] as num?)?.toDouble() ?? 0.0;
    final netEarnings = (shop['net_earnings'] as num?)?.toDouble() ?? 0.0;
    final totalOrders = shop['total_orders'] ?? 0;
    final deliveredOrders = shop['delivered_orders'] ?? 0;
    final pendingOrders = shop['pending_orders'] ?? 0;
    final cancelledOrders = shop['cancelled_orders'] ?? 0;
    final isVerified = shop['is_verified'] as bool? ?? false;
    final isApproved = shop['is_approved'] as bool? ?? false;
    final isActive = shop['is_active'] as bool? ?? true;
    final isShopPinned = shop['is_pinned'] as bool? ?? false;
    final hasOwnCourier = shop['has_own_courier'] as bool? ?? true;
    final deliveryFee = (shop['delivery_fee'] as num?)?.toDouble() ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isShopPinned ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isShopPinned ? BorderSide(color: Colors.amber.shade400, width: 2) : BorderSide.none,
      ),
      child: Stack(
                        children: [
                          if (isShopPinned)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.push_pin, size: 12, color: Colors.amber.shade800),
                                    const SizedBox(width: 2),
                                    Text('Sabitlendi', style: TextStyle(fontSize: 10, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showShopDetailDialog(shop),
                            onLongPress: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (ctx) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: Icon(
                                          isShopPinned ? Icons.push_pin_outlined : Icons.push_pin,
                                          color: Colors.amber.shade700,
                                        ),
                                        title: Text(isShopPinned ? 'Sabitlemeyi Kaldır' : 'Dükkanı Sabitle'),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _togglePin('shops', shop['id'], !isShopPinned);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange.shade400, Colors.orange.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.store,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              shop['name'] ?? '-',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.verified,
                                size: 18,
                                color: Colors.blue,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isApproved ? Colors.green.shade100 : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isApproved ? 'Onaylı' : 'Onay Bekliyor',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isApproved ? Colors.green.shade700 : Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.blue.shade100 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isActive ? 'Aktif' : 'Pasif',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isActive ? Colors.blue.shade700 : Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Komisyon Durum Etiketi
                            Builder(builder: (context) {
                              final adminCredit = (shop['admin_credit'] as num?)?.toDouble() ?? 0;
                              final commissionDebt = (shop['commission_debt'] as num?)?.toDouble() ?? 0;
                              final netBalance = adminCredit - commissionDebt;
                              
                              Color badgeColor;
                              IconData badgeIcon;
                              String badgeText;
                              
                              if (netBalance > 0) {
                                badgeColor = Colors.green;
                                badgeIcon = Icons.arrow_upward;
                                badgeText = 'Ödeme';
                              } else if (netBalance < 0) {
                                badgeColor = Colors.red;
                                badgeIcon = Icons.arrow_downward;
                                badgeText = 'Borç';
                              } else {
                                badgeColor = Colors.grey;
                                badgeIcon = Icons.balance;
                                badgeText = 'Dengede';
                              }
                              
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: badgeColor.withOpacity(0.4), width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(badgeIcon, size: 10, color: badgeColor),
                                    const SizedBox(width: 2),
                                    Text(
                                      badgeText,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                ownerName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showEditShopDialog(shop);
                          break;
                        case 'toggle_verified':
                          _toggleShopVerification(shop);
                          break;
                        case 'toggle_approval':
                          _toggleShopApproval(shop);
                          break;
                        case 'toggle_active':
                          _toggleShopActive(shop);
                          break;
                        case 'delete':
                          _showDeleteShopDialog(shop);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Düzenle'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_approval',
                        child: Row(
                          children: [
                            Icon(
                              isApproved ? Icons.check_circle : Icons.pending,
                              size: 18,
                              color: isApproved ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(isApproved ? 'Onayı Kaldır' : 'Onayla'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_active',
                        child: Row(
                          children: [
                            Icon(
                              isActive ? Icons.visibility : Icons.visibility_off,
                              size: 18,
                              color: isActive ? Colors.blue : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(isActive ? 'Pasife Al' : 'Aktife Al'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_verified',
                        child: Row(
                          children: [
                            Icon(
                              isVerified ? Icons.verified : Icons.unpublished,
                              size: 18,
                              color: isVerified ? Colors.blue : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(isVerified ? 'Doğrulamayı Kaldır' : 'Doğrula'),
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
                ],
              ),
              const SizedBox(height: 16),
              
              // İstatistikler
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // Gelir İstatistikleri
                    Row(
                      children: [
                        Expanded(
                          child: _buildShopStat(
                            icon: Icons.inventory_2,
                            label: 'Ürün',
                            value: '$productCount',
                            color: Colors.blue,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: _buildShopStat(
                            icon: Icons.attach_money,
                            label: 'Kazanç',
                            value: '₺${totalEarnings.toStringAsFixed(0)}',
                            color: Colors.green,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: _buildShopStat(
                            icon: Icons.account_balance_wallet,
                            label: 'Net Kazanç',
                            value: '₺${netEarnings.toStringAsFixed(0)}',
                            color: Colors.teal,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: _buildShopStat(
                            icon: Icons.percent,
                            label: 'Komisyon',
                            value: '%${commission.toStringAsFixed(0)}',
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    // Sipariş İstatistikleri
                    Row(
                      children: [
                        Expanded(
                          child: _buildShopStat(
                            icon: Icons.shopping_bag,
                            label: 'Toplam Sipariş',
                            value: '$totalOrders',
                            color: Colors.indigo,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: _buildShopStat(
                            icon: Icons.check_circle,
                            label: 'Teslim Edilen',
                            value: '$deliveredOrders',
                            color: Colors.green,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: _buildShopStat(
                            icon: Icons.pending_actions,
                            label: 'Bekleyen',
                            value: '$pendingOrders',
                            color: Colors.amber,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: _buildShopStat(
                            icon: Icons.cancel,
                            label: 'İptal',
                            value: '$cancelledOrders',
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Kurye ve Teslimat Bilgisi
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasOwnCourier ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasOwnCourier ? Colors.green.shade200 : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasOwnCourier ? Icons.delivery_dining : Icons.local_shipping,
                      size: 16,
                      color: hasOwnCourier ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasOwnCourier ? 'Kendi Kuryesi' : 'Admin Kuryesi',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hasOwnCourier ? Colors.green.shade700 : Colors.orange.shade700,
                        ),
                      ),
                    ),
                    if (!hasOwnCourier) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '₺${deliveryFee.toStringAsFixed(2)}/teslimat',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Sahip Email
              Row(
                children: [
                  Icon(Icons.email, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ownerEmail,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
          ],
        ),
    );
  }

  Widget _buildShopStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _loadShopsWithDetails() async {
    try {
      debugPrint('🔍 Dükkanlar detaylı bilgilerle yükleniyor...');
      
      final response = await Supabase.instance.client
          .from('shops')
          .select('''
            id,
            name,
            slug,
            owner_id,
            commission_rate,
            is_verified,
            is_approved,
            is_active,
            is_pinned,
            has_own_courier,
            delivery_fee,
            created_at,
            admin_credit,
            commission_debt,
            total_collected_cash,
            total_paid,
            cash_payment_revenue,
            online_payment_revenue,
            profiles!shops_owner_id_fkey(id, email, username, full_name)
          ''')
          .order('is_pinned', ascending: false)
          .order('name', ascending: true);
      
      final shops = List<Map<String, dynamic>>.from(response);
      
      // Her dükkan için ürün sayısını ve kazanç toplamını hesapla
      for (var shop in shops) {
        try {
          // Ürün sayısı
          final productsCount = await Supabase.instance.client
              .from('products')
              .select('id')
              .eq('shop_id', shop['id'])
              .count();
          
          shop['product_count'] = productsCount.count;
          
          // Toplam kazanç (tamamlanan siparişlerden) ve sipariş sayıları
          final ordersResponse = await Supabase.instance.client
              .from('orders')
              .select('total, status, created_at')
              .eq('shop_id', shop['id']);
          
          double totalEarnings = 0.0;
          double weeklyEarnings = 0.0;
          double monthlyEarnings = 0.0;
          int totalOrders = (ordersResponse as List).length;
          int deliveredOrders = 0;
          int pendingOrders = 0;
          int cancelledOrders = 0;
          
          final now = DateTime.now();
          final weekAgo = now.subtract(const Duration(days: 7));
          final monthAgo = now.subtract(const Duration(days: 30));
          
          for (var order in ordersResponse) {
            final status = order['status'] as String?;
            if (status == 'delivered') {
              deliveredOrders++;
              final orderTotal = (order['total'] as num?)?.toDouble() ?? 0.0;
              totalEarnings += orderTotal;
              
              // Tarih bazlı kazanç hesaplama
              final createdAt = order['created_at'] != null
                  ? DateTime.tryParse(order['created_at'].toString())
                  : null;
              if (createdAt != null) {
                if (createdAt.isAfter(weekAgo)) {
                  weeklyEarnings += orderTotal;
                }
                if (createdAt.isAfter(monthAgo)) {
                  monthlyEarnings += orderTotal;
                }
              }
            } else if (status == 'cancelled') {
              cancelledOrders++;
            } else {
              pendingOrders++;
            }
          }
          
          // Komisyon hesaplaması
          final commissionRate = (shop['commission_rate'] as num?)?.toDouble() ?? 10.0;
          final adminCommission = totalEarnings * (commissionRate / 100);
          final netEarnings = totalEarnings - adminCommission;
          
          shop['total_earnings'] = totalEarnings;
          shop['weekly_earnings'] = weeklyEarnings;
          shop['monthly_earnings'] = monthlyEarnings;
          shop['admin_commission_total'] = adminCommission;
          shop['net_earnings'] = netEarnings;
          shop['total_orders'] = totalOrders;
          shop['delivered_orders'] = deliveredOrders;
          shop['pending_orders'] = pendingOrders;
          shop['cancelled_orders'] = cancelledOrders;
        } catch (e) {
          debugPrint('Dükkan istatistikleri yüklenirken hata (${shop['id']}): $e');
          shop['product_count'] = 0;
          shop['total_earnings'] = 0.0;
          shop['weekly_earnings'] = 0.0;
          shop['monthly_earnings'] = 0.0;
          shop['admin_commission_total'] = 0.0;
          shop['net_earnings'] = 0.0;
          shop['total_orders'] = 0;
          shop['delivered_orders'] = 0;
          shop['pending_orders'] = 0;
          shop['cancelled_orders'] = 0;
        }
      }
      
      debugPrint('✅ ${shops.length} dükkan yüklendi');
      return shops;
    } catch (e) {
      debugPrint('❌ Dükkanlar yüklenirken hata: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadShops() async {
    try {
      final response = await Supabase.instance.client
          .from('shops')
          .select('id, name, owner_id')
          .order('name', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Satıcılar yüklenirken hata: $e');
      return [];
    }
  }

  void _showAddShopDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final commissionController = TextEditingController(text: '10.0');
    String? selectedOwnerId;

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadUsersWithoutShop(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final users = snapshot.data ?? [];
          
          // Dükkanı olmayan kullanıcı yoksa uyar
          if (users.isEmpty) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.info, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Bilgilendirme'),
                ],
              ),
              content: const Text(
                'Dükkanı olmayan kullanıcı bulunamadı. Tüm kullanıcıların zaten bir dükkanı var.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tamam'),
                ),
              ],
            );
          }

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Yeni Dükkan Ekle'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Dükkan Adı *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.store),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commissionController,
                        decoration: const InputDecoration(
                          labelText: 'Komisyon Oranı (%) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.percent),
                          suffixText: '%',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedOwnerId,
                        decoration: const InputDecoration(
                          labelText: 'Dükkan Sahibi *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        items: users.map((user) {
                          return DropdownMenuItem(
                            value: user['id'] as String,
                            child: Text(user['full_name'] ?? user['username'] ?? '-'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() => selectedOwnerId = value);
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
                  onPressed: () async {
                    if (nameController.text.isEmpty || selectedOwnerId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lütfen tüm zorunlu alanları doldurun')),
                      );
                      return;
                    }

                    try {
                      debugPrint('📝 Yeni dükkan ekleniyor...');
                      
                      final shopData = {
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'owner_id': selectedOwnerId,
                        'commission_rate': double.tryParse(commissionController.text) ?? 10.0,
                      };

                      await Supabase.instance.client
                          .from('shops')
                          .insert(shopData);

                      debugPrint('✅ Dükkan başarıyla eklendi');

                      if (mounted) {
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Dükkan başarıyla eklendi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('❌ Dükkan eklenirken hata: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Dükkan eklenirken hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Ekle'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _toggleShopVerification(Map<String, dynamic> shop) async {
    final currentStatus = shop['is_verified'] as bool? ?? false;
    final newStatus = !currentStatus;
    
    try {
      await Supabase.instance.client
          .from('shops')
          .update({'is_verified': newStatus})
          .eq('id', shop['id']);
      
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? 'Dükkan doğrulandı' : 'Doğrulama kaldırıldı'),
            backgroundColor: newStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Doğrulama güncellenirken hata: $e');
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

  void _toggleShopApproval(Map<String, dynamic> shop) async {
    final currentStatus = shop['is_approved'] as bool? ?? false;
    final newStatus = !currentStatus;
    
    try {
      await Supabase.instance.client
          .from('shops')
          .update({'is_approved': newStatus})
          .eq('id', shop['id']);
      
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? 'Dükkan onaylandı - Müşterilere gösterilecek' : 'Dükkan onayı kaldırıldı - Müşterilerden gizlendi'),
            backgroundColor: newStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Onay durumu güncellenirken hata: $e');
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

  void _toggleShopActive(Map<String, dynamic> shop) async {
    final currentStatus = shop['is_active'] as bool? ?? true;
    final newStatus = !currentStatus;
    
    try {
      await Supabase.instance.client
          .from('shops')
          .update({'is_active': newStatus})
          .eq('id', shop['id']);
      
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? 'Dükkan aktif edildi' : 'Dükkan pasife alındı - Müşterilerden gizlendi'),
            backgroundColor: newStatus ? Colors.blue : Colors.grey,
          ),
        );
      }
    } catch (e) {
      debugPrint('Aktif durumu güncellenirken hata: $e');
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

  void _showEditShopDialog(Map<String, dynamic> shop) {
    final nameController = TextEditingController(text: shop['name']);
    final descriptionController = TextEditingController(text: shop['description'] ?? '');
    final commissionController = TextEditingController(text: shop['commission_rate']?.toString() ?? '10.0');
    final deliveryFeeController = TextEditingController(text: shop['delivery_fee']?.toString() ?? '0');
    String? selectedOwnerId = shop['owner_id'];
    bool hasOwnCourier = shop['has_own_courier'] ?? false;

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final users = snapshot.data ?? [];

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Dükkan Düzenle'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Dükkan Adı *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.store),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commissionController,
                        decoration: const InputDecoration(
                          labelText: 'Komisyon Oranı (%) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.percent),
                          suffixText: '%',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      // Kurye Durumu Switch'i (Admin kontrol edebilir)
                      SwitchListTile(
                        title: const Text('Kendi Kuryesi Var'),
                        subtitle: Text(
                          hasOwnCourier
                            ? 'Dükkan kendi teslimat ücretini belirler'
                            : 'Admin teslimat ücretini belirler',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: hasOwnCourier,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setDialogState(() => hasOwnCourier = value);
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                      // Kuryesi olmayan dükkanlar için teslimat ücreti alanı
                      if (!hasOwnCourier)
                        Column(
                          children: [
                            TextField(
                              controller: deliveryFeeController,
                              decoration: const InputDecoration(
                                labelText: 'Min. Teslimat Ücreti (₺) *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.delivery_dining),
                                suffixText: '₺',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      DropdownButtonFormField<String>(
                        value: selectedOwnerId,
                        decoration: const InputDecoration(
                          labelText: 'Dükkan Sahibi *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        items: users.map((user) {
                          return DropdownMenuItem(
                            value: user['id'] as String,
                            child: Text(user['full_name'] ?? user['username'] ?? '-'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() => selectedOwnerId = value);
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
                  onPressed: () async {
                    if (nameController.text.isEmpty || selectedOwnerId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lütfen tüm zorunlu alanları doldurun')),
                      );
                      return;
                    }

                    try {
                      debugPrint('📝 Dükkan güncelleniyor: ${shop['id']}');
                      
                      final shopData = {
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'owner_id': selectedOwnerId,
                        'commission_rate': double.tryParse(commissionController.text) ?? 10.0,
                        'has_own_courier': hasOwnCourier, // Admin tarafından kurye durumu belirlenir
                      };
                      
                      // Kuryesi olmayan dükkanlar için teslimat ücretini ekle
                      if (!hasOwnCourier) {
                        shopData['delivery_fee'] = double.tryParse(deliveryFeeController.text) ?? 0.0;
                      }

                      await Supabase.instance.client
                          .from('shops')
                          .update(shopData)
                          .eq('id', shop['id']);

                      debugPrint('✅ Dükkan başarıyla güncellendi');

                      if (mounted) {
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Dükkan başarıyla güncellendi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('❌ Dükkan güncellenirken hata: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Dükkan güncellenirken hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Güncelle'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDeleteShopDialog(Map<String, dynamic> shop) async {
    // Önce sipariş kontrolü yap
    try {
      final ordersResponse = await Supabase.instance.client
          .from('order_items')
          .select('id')
          .eq('shop_id', shop['id'])
          .limit(1);
      
      final hasOrders = ordersResponse.isNotEmpty;
      
      if (!mounted) return;
      
      if (hasOrders) {
        // Siparişi olan dükkanlar silinemez
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Dükkan Silinemez'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${shop['name']} dükkanı silinemez.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shopping_bag, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bu dükkana ait geçmiş siparişler bulunmaktadır. Veri bütünlüğü için siparişi olan dükkanlar silinemez.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Alternatif: Dükkanı pasif hale getirebilirsiniz (is_active = false).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('Sipariş kontrolü hatası: $e');
    }
    
    final productCount = shop['product_count'] ?? 0;
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dükkanı Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${shop['name']} dükkanını silmek istediğinizden emin misiniz?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (productCount > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu dükkana ait $productCount ürün var. Dükkanı silmek bu ürünleri de silecektir.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Bu işlem geri alınamaz.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
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
                debugPrint('🗑️ Dükkan siliniyor: ${shop['id']} (${shop['name']})');
                
                await Supabase.instance.client
                    .from('shops')
                    .delete()
                    .eq('id', shop['id']);

                debugPrint('✅ Dükkan başarıyla silindi');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dükkan başarıyla silindi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('❌ Dükkan silinirken hata: $e');
                
                String errorMessage = 'Dükkan silinirken hata oluştu';
                if (e.toString().contains('foreign key') || e.toString().contains('23503')) {
                  errorMessage = 'Bu dükkana ait siparişler var, silinemez';
                }
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
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

  void _showShopDetailDialog(Map<String, dynamic> shop) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade400, Colors.orange.shade600],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.store, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop['name'] ?? '-',
                    style: const TextStyle(fontSize: 18),
                  ),
                  Text(
                    'Dükkan Detayı',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sahip Bilgisi
                const Text(
                  'Dükkan Sahibi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.grey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'İsim',
                          shop['profiles']?['full_name'] ?? shop['profiles']?['username'] ?? '-',
                          Colors.grey.shade700,
                        ),
                        _buildInfoRow(
                          'Email',
                          shop['profiles']?['email'] ?? '-',
                          Colors.grey.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Komisyon Bilgisi
                const Text(
                  'Komisyon Bilgisi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildInfoRow(
                      'Komisyon Oranı',
                      '%${((shop['commission_rate'] as num?)?.toDouble() ?? 10.0).toStringAsFixed(1)}',
                      Colors.orange.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // İstatistikler
                const Text(
                  'İstatistikler',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.inventory_2,
                        title: 'Ürün',
                        value: '${shop['product_count'] ?? 0}',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.attach_money,
                        title: 'Kazanç',
                        value: '₺${((shop['total_earnings'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
                        color: Colors.green,
                        gradient: [Colors.green.shade400, Colors.green.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Kazanç Bilgileri (Periyodik)
                const Text(
                  'Kazanç Bilgileri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Toplam Kazanç',
                          '₺${((shop['total_earnings'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.teal.shade700,
                        ),
                        _buildInfoRow(
                          'Haftalık Kazanç',
                          '₺${((shop['weekly_earnings'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.blue.shade700,
                        ),
                        _buildInfoRow(
                          'Aylık Kazanç',
                          '₺${((shop['monthly_earnings'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.indigo.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Mali Bilgiler
                const Text(
                  'Mali Bilgiler',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Kapıda Ödeme Geliri',
                          '₺${((shop['cash_payment_revenue'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.green.shade700,
                        ),
                        _buildInfoRow(
                          'Online Gelir',
                          '₺${((shop['online_payment_revenue'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.blue.shade700,
                        ),
                        _buildInfoRow(
                          'Admin Alacak',
                          '₺${((shop['admin_credit'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.teal.shade700,
                        ),
                        _buildInfoRow(
                          'Komisyon Borcu',
                          '₺${((shop['commission_debt'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.red.shade700,
                        ),
                        _buildInfoRow(
                          'Toplanan Nakit',
                          '₺${((shop['total_collected_cash'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.orange.shade700,
                        ),
                        _buildInfoRow(
                          'Ödenen',
                          '₺${((shop['total_paid'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.grey.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Ödeme İşlemleri
                const Text(
                  'Ödeme İşlemleri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Ödeme Yapıldı Butonu (Admin dükkana ödeme yaptı)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: () async {
                        final adminCredit = (shop['admin_credit'] as num?)?.toDouble() ?? 0.0;
                        if (adminCredit <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ödeme yapılacak tutar yok')),
                          );
                          return;
                        }
                        
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Ödeme Yapıldı'),
                            content: Text('Dükkana ₺${adminCredit.toStringAsFixed(2)} ödeme yapıldı olarak işaretlensin mi?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('İptal'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Onayla'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          try {
                            await Supabase.instance.client
                                .from('shops')
                                .update({
                              'admin_credit': 0.0,
                              'total_paid': ((shop['total_paid'] as num?)?.toDouble() ?? 0.0) + adminCredit,
                            })
                                .eq('id', shop['id']);
                            
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ödeme yapıldı olarak işaretlendi')),
                              );
                              _loadAndSetShops();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Hata: $e')),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Ödeme Yapıldı'),
                    ),
                    
                    // Ödeme Alındı Butonu (Admin nakit topladı)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: () async {
                        final commissionDebt = (shop['commission_debt'] as num?)?.toDouble() ?? 0.0;
                        if (commissionDebt <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Tahsil edilecek tutar yok')),
                          );
                          return;
                        }
                        
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Ödeme Alındı'),
                            content: Text('Dükkanından ₺${commissionDebt.toStringAsFixed(2)} ödeme alındı olarak işaretlensin mi?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('İptal'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Onayla'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          try {
                            await Supabase.instance.client
                                .from('shops')
                                .update({
                              'commission_debt': 0.0,
                              'total_collected_cash': ((shop['total_collected_cash'] as num?)?.toDouble() ?? 0.0) + commissionDebt,
                            })
                                .eq('id', shop['id']);
                            
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ödeme alındı olarak işaretlendi')),
                              );
                              _loadAndSetShops();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Hata: $e')),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.account_balance_wallet, size: 18),
                      label: const Text('Ödeme Alındı'),
                    ),
                    
                    // Alacak/Verecek Kapat Butonu
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: () async {
                        final adminCredit = (shop['admin_credit'] as num?)?.toDouble() ?? 0.0;
                        final commissionDebt = (shop['commission_debt'] as num?)?.toDouble() ?? 0.0;
                        
                        if (adminCredit == 0 && commissionDebt == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kapanacak alacak/verecek yok')),
                          );
                          return;
                        }
                        
                        final balance = adminCredit - commissionDebt;
                        String message = '';
                        if (balance > 0) {
                          message = 'Admin dükkana ₺${balance.abs().toStringAsFixed(2)} borçlu. Tüm alacak/verecek kapatılsın mı?';
                        } else if (balance < 0) {
                          message = 'Dükkan admin\'e ₺${balance.abs().toStringAsFixed(2)} borçlu. Tüm alacak/verecek kapatılsın mı?';
                        } else {
                          message = 'Hesaplar denk. Tüm alacak/verecek kapatılsın mı?';
                        }
                        
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Alacak/Verecek Kapat'),
                            content: Text(message),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('İptal'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Kapat'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true) {
                          try {
                            await Supabase.instance.client
                                .from('shops')
                                .update({
                              'admin_credit': 0.0,
                              'commission_debt': 0.0,
                              'cash_payment_revenue': 0.0,
                              'online_payment_revenue': 0.0,
                              'total_collected_cash': 0.0,
                            })
                                .eq('id', shop['id']);
                            
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Alacak/verecek kapatıldı')),
                              );
                              // Dükkan kartlarındaki tüm istatistikleri sıfırla
                              setState(() {
                                shop['total_earnings'] = 0.0;
                                shop['weekly_earnings'] = 0.0;
                                shop['monthly_earnings'] = 0.0;
                                shop['net_earnings'] = 0.0;
                                shop['admin_commission_total'] = 0.0;
                                shop['total_orders'] = 0;
                                shop['delivered_orders'] = 0;
                                shop['pending_orders'] = 0;
                                shop['cancelled_orders'] = 0;
                              });
                              _loadAndSetShops();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Hata: $e')),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Alacak/Verecek Kapat'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Oluşturulma Tarihi
                if (shop['created_at'] != null)
                  _buildInfoRow(
                    'Oluşturulma Tarihi',
                    _formatDate(shop['created_at']),
                    Colors.grey.shade600,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShopDetailAdminScreen(shopId: shop['id']),
                ),
              );
            },
            icon: const Icon(Icons.info),
            label: const Text('Detaylı Görüntüle'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showEditShopDialog(shop);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Düzenle'),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController();
    final discountPriceController = TextEditingController();
    final stockController = TextEditingController();
    final imageUrlController = TextEditingController();
    String? selectedShopId;
    String? selectedCategoryId;

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: Future.wait([
          _loadShops(),
          _loadCategories(),
        ]).then((results) => {
          'shops': results[0],
          'categories': results[1],
        }),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final shops = (snapshot.data?['shops'] as List<Map<String, dynamic>>?) ?? [];
          final categories = (snapshot.data?['categories'] as List<Map<String, dynamic>>?) ?? [];

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Yeni Ürün Ekle'),
              content: SingleChildScrollView(
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
                    DropdownButtonFormField<String>(
                      value: selectedShopId,
                      decoration: const InputDecoration(
                        labelText: 'Satıcı/Mağaza',
                        border: OutlineInputBorder(),
                      ),
                      items: shops.map((shop) {
                        return DropdownMenuItem(
                          value: shop['id'] as String,
                          child: Text(shop['name'] ?? '-'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedShopId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: categories.map((category) {
                        return DropdownMenuItem(
                          value: category['id'] as String,
                          child: Text(category['name'] ?? '-'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedCategoryId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Resim URL - Opsiyonel',
                        border: OutlineInputBorder(),
                        hintText: 'https://example.com/image.jpg',
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
                    if (nameController.text.isEmpty ||
                        priceController.text.isEmpty ||
                        stockController.text.isEmpty ||
                        selectedShopId == null ||
                        selectedCategoryId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lütfen tüm zorunlu alanları doldurun')),
                      );
                      return;
                    }

                    try {
                      final productData = {
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'price': double.parse(priceController.text.trim()),
                        'stock_quantity': int.parse(stockController.text.trim()),
                        'shop_id': selectedShopId,
                        'category_id': selectedCategoryId,
                      };

                      if (discountPriceController.text.isNotEmpty) {
                        productData['discount_price'] = double.parse(discountPriceController.text.trim());
                      }

                      if (imageUrlController.text.isNotEmpty) {
                        productData['image_url'] = imageUrlController.text.trim();
                      }

                      await Supabase.instance.client
                          .from('products')
                          .insert(productData);

                      if (mounted) {
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ürün başarıyla eklendi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ürün eklenirken hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Ekle'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditProductDialog(Map<String, dynamic> product) {
    final nameController = TextEditingController(text: product['name']);
    final descriptionController = TextEditingController(text: product['description']);
    final priceController = TextEditingController(text: product['price']?.toString() ?? '');
    final discountPriceController = TextEditingController(text: product['discount_price']?.toString() ?? '');
    final stockController = TextEditingController(text: product['stock_quantity']?.toString() ?? '');
    final imageUrlController = TextEditingController(text: product['image_url']);
    String? selectedShopId = product['shop_id'];
    String? selectedCategoryId = product['category_id'];

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: Future.wait([
          _loadShops(),
          _loadCategories(),
        ]).then((results) => {
          'shops': results[0],
          'categories': results[1],
        }),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final shops = (snapshot.data?['shops'] as List<Map<String, dynamic>>?) ?? [];
          final categories = (snapshot.data?['categories'] as List<Map<String, dynamic>>?) ?? [];

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Ürün Düzenle'),
              content: SingleChildScrollView(
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
                    DropdownButtonFormField<String>(
                      value: selectedShopId,
                      decoration: const InputDecoration(
                        labelText: 'Satıcı/Mağaza',
                        border: OutlineInputBorder(),
                      ),
                      items: shops.map((shop) {
                        return DropdownMenuItem(
                          value: shop['id'] as String,
                          child: Text(shop['name'] ?? '-'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedShopId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: categories.map((category) {
                        return DropdownMenuItem(
                          value: category['id'] as String,
                          child: Text(category['name'] ?? '-'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedCategoryId = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Resim URL - Opsiyonel',
                        border: OutlineInputBorder(),
                        hintText: 'https://example.com/image.jpg',
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
                    if (nameController.text.isEmpty ||
                        priceController.text.isEmpty ||
                        stockController.text.isEmpty ||
                        selectedShopId == null ||
                        selectedCategoryId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lütfen tüm zorunlu alanları doldurun')),
                      );
                      return;
                    }

                    try {
                      debugPrint('📝 Ürün güncelleniyor: ${product['id']}');

                      final productData = {
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'price': double.parse(priceController.text.trim()),
                        'stock_quantity': int.parse(stockController.text.trim()),
                        'shop_id': selectedShopId,
                        'category_id': selectedCategoryId,
                      };

                      if (discountPriceController.text.isNotEmpty) {
                        productData['discount_price'] = double.parse(discountPriceController.text.trim());
                      }

                      if (imageUrlController.text.isNotEmpty) {
                        productData['image_url'] = imageUrlController.text.trim();
                      }

                      final response = await Supabase.instance.client
                          .from('products')
                          .update(productData)
                          .eq('id', product['id'])
                          .select();

                      debugPrint('✅ Ürün güncelleme yanıtı: $response');

                      if (mounted) {
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ürün başarıyla güncellendi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e, stackTrace) {
                      debugPrint('❌ Ürün güncellenirken hata: $e');
                      debugPrint('📍 Stack trace: $stackTrace');

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ürün güncellenirken hata: $e'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDeleteProductDialog(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: Text(
          '${product['name']} ürününü silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz.',
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
                debugPrint('🗑️ Ürün siliniyor: ${product['id']} (${product['name']})');

                final response = await Supabase.instance.client
                    .from('products')
                    .delete()
                    .eq('id', product['id'])
                    .select();

                debugPrint('✅ Ürün silme yanıtı: $response');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ürün başarıyla silindi'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Ürün silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ürün silinirken hata: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
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

  Future<List<Map<String, dynamic>>> _loadShopsForFilter() async {
    try {
      final response = await Supabase.instance.client
          .from('shops')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Dükkanlar yüklenirken hata: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadOrders() async {
    try {
      debugPrint('🔍 Siparişler yükleniyor... (Filtre: ${_selectedShopFilter ?? "Tümü"})');
      
      var query = Supabase.instance.client
          .from('orders')
          .select('''
            *,
            profiles!orders_user_id_fkey(id, username, full_name, email, avatar_url, phone),
            shops(id, name, owner_id, commission_rate),
            order_items(id, product_id, product_name, product_image_url, price, quantity)
          ''');
      
      // customer_phone alanını siparişlerden almak için ek sorgu gerekmiyor,
      // ancak address_display ve address_id alanları orders tablosundan gelmeli
      
      // Dükkan filtresi varsa ekle
      if (_selectedShopFilter != null && _selectedShopFilter != 'all') {
        query = query.eq('shop_id', _selectedShopFilter!);
      }
      
      final response = await query
          .order('created_at', ascending: false)
          .limit(100);
      
      final orders = List<Map<String, dynamic>>.from(response);
      debugPrint('✅ ${orders.length} sipariş yüklendi');
      
      // Her sipariş için kazanç hesaplaması yap ve adres alanını düzelt
      for (var order in orders) {
        final totalAmount = (order['total'] as num?)?.toDouble() ?? 0.0;
        final shop = order['shops'] as Map<String, dynamic>?;
        final commissionRate = (shop?['commission_rate'] as num?)?.toDouble() ?? 10.0;
        
        final adminCommission = totalAmount * (commissionRate / 100);
        final sellerEarnings = totalAmount - adminCommission;
        
        order['admin_commission'] = adminCommission;
        order['seller_earnings'] = sellerEarnings;
        order['commission_rate'] = commissionRate;
        
        // delivery_address_text varsa address_display'e kopyala
        if (order['delivery_address_text'] != null && order['address_display'] == null) {
          order['address_display'] = order['delivery_address_text'];
        }
      }
      
      return orders;
    } catch (e, stackTrace) {
      debugPrint('❌ Siparişler yüklenirken hata: $e');
      debugPrint('Stack trace: $stackTrace');
      // Hata durumunda boş liste döndür - gerçek hatanın görünmesi için
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadReports() async {
    try {
      debugPrint('🔍 Kullanıcı şikayetleri yükleniyor...');
      
      final response = await Supabase.instance.client
          .from('user_reports')
          .select('''
            *,
            reporter:profiles!user_reports_reporter_id_fkey(id, username, full_name, email, avatar_url),
            reported:profiles!user_reports_reported_user_id_fkey(id, username, full_name, email, avatar_url)
          ''')
          .order('created_at', ascending: false)
          .limit(100);
      
      final reports = List<Map<String, dynamic>>.from(response);
      debugPrint('✅ ${reports.length} şikayet yüklendi');
      return reports;
    } catch (e, stackTrace) {
      debugPrint('❌ Şikayetler yüklenirken hata: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadCategories() async {
    try {
      debugPrint('🔍 Kategoriler yükleniyor...');
      
      // TEK sorguda kategorileri ve dükkan sayılarını getir
      // Supabase RPC kullanarak daha verimli sorgu
      final response = await Supabase.instance.client.rpc(
        'get_categories_with_shop_count',
      );
      
      final categoriesList = List<Map<String, dynamic>>.from(response);
      
      debugPrint('✅ ${categoriesList.length} kategori yüklendi');
      for (var cat in categoriesList) {
        debugPrint('   - ${cat['name']}: ${cat['shop_count']} dükkan');
      }
      return categoriesList;
    } catch (e) {
      debugPrint('❌ Kategoriler yüklenirken hata: $e');
      
      // RPC yoksa manuel yöntemle dene
      try {
        debugPrint('🔄 Alternatif yöntem deneniyor...');
        
        // Kategorileri getir
        final categoriesResponse = await Supabase.instance.client
            .from('categories')
            .select()
            .order('display_order', ascending: true);
        
        final categoriesList = List<Map<String, dynamic>>.from(categoriesResponse).map((cat) => {
          'id': cat['id'] as String,
          'name': cat['name'] as String?,
          'description': cat['description'] as String?,
          'display_order': cat['display_order'] as int?,
          'is_active': cat['is_active'] as bool?,
          'image_url': cat['image_url'] as String?,
          'shop_count': 0,
        }).toList();
        
        // Tüm dükkanları getir ve kategorilere göre grupla
        final shopsResponse = await Supabase.instance.client
            .from('shops')
            .select('category_id');
        
        // Dükkan sayılarını hesapla
        final shopCounts = <String, int>{};
        for (var shop in shopsResponse) {
          final catId = shop['category_id'] as String?;
          if (catId != null) {
            shopCounts[catId] = (shopCounts[catId] ?? 0) + 1;
          }
        }
        
        // Kategorilere dükkan sayılarını ata
        for (var category in categoriesList) {
          category['shop_count'] = shopCounts[category['id']] ?? 0;
        }
        
        debugPrint('✅ ${categoriesList.length} kategori yüklendi (alternatif yöntem)');
        return categoriesList;
      } catch (e2) {
        debugPrint('❌ Alternatif yöntem de başarısız: $e2');
        
        // Mock veriler döndür
        return [
          {'id': '1', 'name': 'Market', 'description': 'Market alışverişi', 'display_order': 1, 'is_active': true, 'shop_count': 1, 'image_url': null},
          {'id': '2', 'name': 'Manav', 'description': 'Taze meyve sebze', 'display_order': 2, 'is_active': true, 'shop_count': 0, 'image_url': null},
          {'id': '3', 'name': 'Yemek', 'description': 'Restoran ve yemek siparişi', 'display_order': 3, 'is_active': true, 'shop_count': 0, 'image_url': null},
          {'id': '4', 'name': 'Fırın', 'description': 'Ekmek ve unlu mamuller', 'display_order': 4, 'is_active': true, 'shop_count': 0, 'image_url': null},
          {'id': '5', 'name': 'Tatlı', 'description': 'Tatlı ve pasta', 'display_order': 5, 'is_active': true, 'shop_count': 0, 'image_url': null},
        ];
      }
    }
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final sortOrderController = TextEditingController(text: '0');
    bool isActive = true;
    XFile? selectedImage;
    String? previewUrl;
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Yeni Kategori Ekle'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Görsel Yükleme Alanı
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 800,
                        maxHeight: 800,
                        imageQuality: 85,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedImage = picked;
                          previewUrl = picked.path;
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedImage != null ? Colors.purple.shade300 : Colors.grey.shade300,
                          width: selectedImage != null ? 2 : 1,
                        ),
                        image: previewUrl != null
                            ? DecorationImage(
                                image: previewUrl!.startsWith('http')
                                    ? NetworkImage(previewUrl!) as ImageProvider
                                    : AssetImage(previewUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: selectedImage == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey.shade500),
                                const SizedBox(height: 8),
                                Text(
                                  'Görsel Yükle',
                                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  'Dokunarak galeriden seçin',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                ),
                              ],
                            )
                          : Stack(
                              children: [
                                // Seçili resmi göster
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: Image.asset(
                                      previewUrl!,
                                      fit: BoxFit.cover,
                                      // ignore: unnecessary_underscores
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.check_circle, color: Colors.green, size: 40),
                                      ),
                                    ),
                                  ),
                                ),
                                // Sil butonu
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        selectedImage = null;
                                        previewUrl = null;
                                      });
                                    },
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
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Kategori Adı *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sortOrderController,
                    decoration: const InputDecoration(
                      labelText: 'Sıralama *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.sort),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Aktif'),
                    subtitle: const Text('Kategori kullanıcıya gösterilsin'),
                    value: isActive,
                    onChanged: (value) {
                      setDialogState(() => isActive = value);
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
              onPressed: isUploading ? null : () async {
                if (nameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kategori adı gerekli')),
                  );
                  return;
                }

                try {
                  setDialogState(() => isUploading = true);
                  debugPrint('📝 Yeni kategori ekleniyor...');
                  
                  String? imageUrl;
                  
                  // Görsel yükle
                  if (selectedImage != null) {
                    final bytes = await selectedImage!.readAsBytes();
                    final fileName = 'category_${DateTime.now().millisecondsSinceEpoch}.jpg';
                    final path = 'categories/$fileName';
                    
                    await Supabase.instance.client.storage
                        .from('category-images')
                        .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
                    
                    imageUrl = Supabase.instance.client.storage
                        .from('category-images')
                        .getPublicUrl(path);
                  }
                  
                  // Doğrudan Supabase ile ekle
                  final insertData = {
                    'name': nameController.text.trim(),
                    'slug': nameController.text.trim().toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), ''),
                    'description': descriptionController.text.trim(),
                    'display_order': int.tryParse(sortOrderController.text) ?? 0,
                    'is_active': isActive,
                  };
                  
                  // Resim URL varsa ekle
                  if (imageUrl != null) {
                    insertData['image_url'] = imageUrl;
                  }
                  
                  await Supabase.instance.client
                      .from('categories')
                      .insert(insertData);

                  debugPrint('✅ Kategori başarıyla eklendi');

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kategori başarıyla eklendi'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Kategori eklenirken hata: $e');
                  setDialogState(() => isUploading = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Kategori eklenirken hata: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: isUploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCategoryDialog(Map<String, dynamic> category) {
    final nameController = TextEditingController(text: category['name']);
    final descriptionController = TextEditingController(text: category['description'] ?? '');
    final sortOrderController = TextEditingController(text: category['display_order']?.toString() ?? '0');
    bool isActive = category['is_active'] ?? true;
    XFile? selectedImage;
    String? previewUrl = category['image_url'];
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kategoriyi Düzenle'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Kategori Adı *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sortOrderController,
                    decoration: const InputDecoration(
                      labelText: 'Sıralama *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.sort),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  // Resim seçimi
                  GestureDetector(
                    onTap: isUploading ? null : () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1024,
                        maxHeight: 1024,
                        imageQuality: 85,
                      );
                      
                      if (image != null) {
                        setDialogState(() {
                          selectedImage = image;
                          previewUrl = null; // Eski URL'yi temizle
                        });
                      }
                    },
                    child: Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[100],
                      ),
                      child: selectedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                selectedImage!.path,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Icon(Icons.error, size: 48, color: Colors.red),
                                  );
                                },
                              ),
                            )
                          : previewUrl != null && previewUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    previewUrl!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                                            SizedBox(height: 8),
                                            Text('Resim Seç', style: TextStyle(color: Colors.grey)),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                                      SizedBox(height: 8),
                                      Text('Resim Seç (İsteğe Bağlı)', style: TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Aktif'),
                    subtitle: const Text('Kategori kullanıcıya gösterilsin'),
                    value: isActive,
                    onChanged: (value) {
                      setDialogState(() => isActive = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isUploading ? null : () async {
                if (nameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kategori adı gerekli')),
                  );
                  return;
                }

                try {
                  setDialogState(() => isUploading = true);
                  
                  debugPrint('📝 Kategori güncelleniyor: ${category['id']}');
                  
                  String? imageUrl = category['image_url'];
                  
                  // Yeni resim seçildiyse yükle
                  if (selectedImage != null) {
                    debugPrint('📤 Resim yükleniyor...');
                    
                    final bytes = await selectedImage!.readAsBytes();
                    final fileExt = selectedImage!.path.split('.').last.toLowerCase();
                    // Dosya adındaki geçersiz karakterleri temizle (& ş ğ ü ö ç ı vb)
                    final safeName = nameController.text.trim().toLowerCase()
                        .replaceAll(' ', '_')
                        .replaceAll('&', 've')
                        .replaceAll('ş', 's').replaceAll('ğ', 'g')
                        .replaceAll('ü', 'u').replaceAll('ö', 'o')
                        .replaceAll('ç', 'c').replaceAll('ı', 'i')
                        .replaceAll('İ', 'i').replaceAll('Ş', 's')
                        .replaceAll('Ğ', 'g').replaceAll('Ü', 'u')
                        .replaceAll('Ö', 'o').replaceAll('Ç', 'c')
                        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
                    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$safeName.$fileExt';
                    final filePath = 'category-images/$fileName';
                    
                    // MIME type düzeltmesi: jpg -> jpeg
                    String contentType = 'image/$fileExt';
                    if (fileExt == 'jpg') {
                      contentType = 'image/jpeg';
                    }
                    
                    await Supabase.instance.client.storage
                        .from('category-images')
                        .uploadBinary(
                          filePath,
                          bytes,
                          fileOptions: FileOptions(
                            contentType: contentType,
                            upsert: false,
                          ),
                        );
                    
                    imageUrl = Supabase.instance.client.storage
                        .from('category-images')
                        .getPublicUrl(filePath);
                    
                    debugPrint('✅ Resim yüklendi: $imageUrl');
                  }
                  
                  // Kategoriyi güncelle
                  final updateData = {
                    'name': nameController.text.trim(),
                    'slug': nameController.text.trim().toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), ''),
                    'description': descriptionController.text.trim(),
                    'display_order': int.tryParse(sortOrderController.text) ?? 0,
                    'is_active': isActive,
                  };
                  
                  if (imageUrl != null && imageUrl.isNotEmpty) {
                    updateData['image_url'] = imageUrl;
                  }
                  
                  await Supabase.instance.client
                      .from('categories')
                      .update(updateData)
                      .eq('id', category['id']);

                  debugPrint('✅ Kategori başarıyla güncellendi');

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kategori başarıyla güncellendi'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Kategori güncellenirken hata: $e');
                  setDialogState(() => isUploading = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Kategori güncellenirken hata: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteCategoryDialog(Map<String, dynamic> category) {
    final shopCount = category['shop_count'] ?? 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategoriyi Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${category['name']} kategorisini silmek istediğinizden emin misiniz?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (shopCount > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu kategoriye ait $shopCount dükkan var. Kategoriyi silebilmek için önce bu dükkanları başka bir kategoriye taşımalısınız.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Bu işlem geri alınamaz.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          if (shopCount == 0)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  debugPrint('🗑️ Kategori siliniyor: ${category['id']} (${category['name']})');
                  
                  // Doğrudan Supabase ile sil (RLS sorunlarını önlemek için)
                  final response = await Supabase.instance.client
                      .from('categories')
                      .delete()
                      .eq('id', category['id'])
                      .select();

                  debugPrint('✅ Kategori silme yanıtı: $response');

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kategori başarıyla silindi'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Kategori silinirken hata: $e');
                  
                  String errorMessage = 'Kategori silinirken hata oluştu';
                  if (e.toString().contains('foreign key constraint')) {
                    errorMessage = 'Bu kategoriye ait dükkanlar var. Önce dükkanları başka bir kategoriye taşıyın.';
                  }
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(errorMessage),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
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

  // ignore: unused_field
  static const List<Color> _categoryColors = [
    Colors.purple,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.amber,
    Colors.cyan,
    Colors.lime,
    Colors.brown,
    Colors.deepOrange,
    Colors.lightBlue,
    Colors.lightGreen,
  ];

  // ignore: unused_element
  // ignore: unused_element
  Color _getCategoryColor(String? colorHex) {
    return _parseColor(colorHex);
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return Colors.purple;
    try {
      final colorValue = int.parse(colorHex.replaceFirst('#', '0xFF'));
      return Color(colorValue);
    } catch (e) {
      return Colors.purple;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return '-';
    }
  }

  Color _getOrderStatusColor(String? status) {
    switch (status) {
      case 'completed':
      case 'delivered':
        return Colors.green.shade100;
      case 'pending':
        return Colors.orange.shade100;
      case 'cancelled':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  Widget _buildDashboardContent() {
    return RefreshIndicator(
      onRefresh: _loadRealData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hoşgeldin Banner
            _buildWelcomeBanner(),
            const SizedBox(height: 24),
            
            // İstatistik Kartları Grid
            _buildStatsGrid(),
            const SizedBox(height: 24),
            
            // Network Status
            _buildNetworkStatusCard(),
            const SizedBox(height: 16),
            
            // Cache İstatistikleri
            _buildCacheStatisticsCard(),
            const SizedBox(height: 16),
            
            // Performance Metrics
            _buildPerformanceCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.shade600,
            Colors.purple.shade800,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hoşgeldiniz! 👋',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Admin panelinize erişim sağlandı',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.admin_panel_settings,
              size: 40,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive: 2 kolon mobilde, 3 kolon tablette
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _buildStatCard(
              icon: Icons.people_rounded,
              title: 'Kullanıcılar',
              value: '$_totalUsers',
              color: Colors.blue,
              gradient: [Colors.blue.shade400, Colors.blue.shade600],
            ),
            _buildStatCard(
              icon: Icons.post_add_rounded,
              title: 'Gönderiler',
              value: '$_totalPosts',
              color: Colors.green,
              gradient: [Colors.green.shade400, Colors.green.shade600],
            ),
            _buildStatCard(
              icon: Icons.shopping_bag_rounded,
              title: 'Ürünler',
              value: '$_totalProducts',
              color: Colors.orange,
              gradient: [Colors.orange.shade400, Colors.orange.shade600],
            ),
            _buildStatCard(
              icon: Icons.receipt_long_rounded,
              title: 'Siparişler',
              value: '$_totalOrders',
              color: Colors.purple,
              gradient: [Colors.purple.shade400, Colors.purple.shade600],
            ),
            _buildStatCard(
              icon: Icons.flag_rounded,
              title: 'Şikayetler',
              value: '$_totalReports',
              color: Colors.red,
              gradient: [Colors.red.shade400, Colors.red.shade600],
            ),
            _buildStatCard(
              icon: Icons.analytics_rounded,
              title: 'Events',
              value: '${_analyticsService.eventCount}',
              color: Colors.teal,
              gradient: [Colors.teal.shade400, Colors.teal.shade600],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required List<Color> gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkStatusCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.wifi,
                    color: Colors.blue.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Network Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              'Bağlantı',
              _connectivityService.isConnected ? 'Online' : 'Offline',
              _connectivityService.isConnected ? Colors.green : Colors.red,
            ),
            if (_connectivityService.isConnected)
              _buildInfoRow(
                'Tip',
                _connectivityService.connectionType,
                Colors.blue,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheStatisticsCard() {
    final lastCacheTime = _cacheService.getLastCacheTime();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.storage,
                    color: Colors.orange.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Cache İstatistikleri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Cached Posts', '${_cacheService.cacheSize}', Colors.grey.shade700),
            _buildInfoRow(
              'Son Güncelleme',
              lastCacheTime != null ? _formatDateTime(lastCacheTime) : 'Hiç',
              Colors.grey.shade700,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _cacheService.clearCache();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cache temizlendi')),
                    );
                    setState(() {});
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Cache Temizle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceCard() {
    final summary = _performanceService.getPerformanceSummary();
    final slowest = _performanceService.getSlowestEndpoints(limit: 3);
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.speed,
                    color: Colors.purple.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Performance Metrikleri',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Toplam API Çağrısı', '${summary['total_calls']}', Colors.grey.shade700),
            _buildInfoRow('Ort. Yanıt Süresi', '${summary['average_response_time_ms']}ms', Colors.grey.shade700),
            _buildInfoRow('Başarı Oranı', '${summary['success_rate'].toStringAsFixed(1)}%', Colors.green),
            _buildInfoRow('P95 Latency', '${summary['p95_latency_ms']}ms', Colors.grey.shade700),
            _buildInfoRow('P99 Latency', '${summary['p99_latency_ms']}ms', Colors.grey.shade700),
            if (slowest.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'En Yavaş Endpointler:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...slowest.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '  • ${e.key}: ${e.value}ms',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              )),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  _performanceService.clearMetrics();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Metrikler temizlendi')),
                    );
                    setState(() {});
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Metrikleri Temizle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsContent() {
    final metrics = _analyticsService.getEngagementMetrics();
    final mostViewed = _analyticsService.getMostViewedPosts(limit: 5);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.analytics,
                          color: Colors.green.shade600,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Analitik',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Toplam Etkinlik', '${_analyticsService.eventCount}', Colors.grey.shade700),
                  _buildInfoRow('Görüntülenme', '${metrics['views'] ?? 0}', Colors.blue),
                  _buildInfoRow('Beğeni', '${metrics['likes'] ?? 0}', Colors.red),
                  _buildInfoRow('Yorum', '${metrics['comments'] ?? 0}', Colors.orange),
                  _buildInfoRow('Paylaşım', '${metrics['shares'] ?? 0}', Colors.green),
                  _buildInfoRow('Hata', '${metrics['errors'] ?? 0}', Colors.red),
                  if (mostViewed.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'En Çok Görüntülenen Postlar:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...mostViewed.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '  • ${e.key.substring(0, 8)}... (${e.value} görüntülenme)',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    )),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _analyticsService.clearAllEvents();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Analitik verileri temizlendi')),
                          );
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Analitik Verilerini Temizle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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

  Widget _buildSettingsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sipariş Kontrol Bölümü
          const Text(
            'Sipariş Kontrol',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildOrderControlCard(),

          const SizedBox(height: 24),

          // Açılış Duyurusu Bölümü
          const Text(
            'Açılış Duyurusu',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildStartupAnnouncementCard(),

          const SizedBox(height: 24),

          // Sistem Ayarları
          const Text(
            'Sistem Ayarları',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services),
                  title: const Text('Tüm Cache Temizle'),
                  subtitle: const Text('Tüm önbelleği sil'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await _cacheService.clearCache();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cache temizlendi')),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Tüm Analytics Temizle'),
                  subtitle: const Text('Tüm analitik verilerini sil'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await _analyticsService.clearAllEvents();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Analytics temizlendi')),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Metrikleri Sıfırla'),
                  subtitle: const Text('Performance metriklerini sıfırla'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _performanceService.clearMetrics();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Metrikler sıfırlandı')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sipariş kontrol verilerini güvenli şekilde çek
  Future<Map<String, dynamic>> _loadOrderControlSettings() async {
    try {
      // Önce tüm sütunları çekmeyi dene
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select()
          .single();
      
      return {
        'global_orders_enabled': response['global_orders_enabled'] as bool? ?? true,
        'order_approval_code_enabled': response['order_approval_code_enabled'] as bool? ?? true,
      };
    } catch (e) {
      debugPrint('⚠️ app_about_settings yüklenirken hata: $e');
      // Sütun yoksa sadece global_orders_enabled'ı çekmeyi dene
      try {
        final response = await Supabase.instance.client
            .from('app_about_settings')
            .select('global_orders_enabled')
            .single();
        return {
          'global_orders_enabled': response['global_orders_enabled'] as bool? ?? true,
          'order_approval_code_enabled': true, // Sütun yoksa varsayılan true
        };
      } catch (e2) {
        debugPrint('⚠️ global_orders_enabled da yüklenemedi: $e2');
        return {
          'global_orders_enabled': true,
          'order_approval_code_enabled': true,
        };
      }
    }
  }

  Widget _buildOrderControlCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadOrderControlSettings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            elevation: 1,
            child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          );
        }

        if (snapshot.hasError) {
          return Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Hata: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            ),
          );
        }

        final isEnabled = snapshot.data?['global_orders_enabled'] ?? true;
        final approvalCodeEnabled = snapshot.data?['order_approval_code_enabled'] ?? true;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Global Sipariş Alma - Daha belirgin tasarım
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isEnabled ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isEnabled ? Colors.green : Colors.red,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Durum ikonu
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isEnabled ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isEnabled ? Icons.store : Icons.store_mall_directory,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Metin ve açıklama
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Global Sipariş Alma',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isEnabled
                                  ? '✅ Açık - Tüm satıcılar sipariş alabilir'
                                  : '❌ Kapalı - Sipariş alma durduruldu!',
                              style: TextStyle(
                                color: isEnabled ? Colors.green.shade700 : Colors.red.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Toggle switch
                      Switch(
                        value: isEnabled,
                        onChanged: (value) async {
                          try {
                            await Supabase.instance.client
                                .from('app_about_settings')
                                .update({'global_orders_enabled': value})
                                .eq('id', 1);
                            setState(() {});
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(value ? '✅ Sipariş alma açıldı' : '❌ Sipariş alma kapatıldı'),
                                  backgroundColor: value ? Colors.green : Colors.red,
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
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                  const Divider(height: 1),
                  // Sipariş Onay Kodu Toggle
                  SwitchListTile(
                    title: const Text(
                      'Sipariş Onay Kodu',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      approvalCodeEnabled
                          ? 'Sipariş verirken onay kodu gereklidir'
                          : 'Sipariş onay kodu zorunluluğu kapatıldı',
                      style: TextStyle(
                        color: approvalCodeEnabled ? Colors.blue : Colors.grey,
                      ),
                    ),
                    value: approvalCodeEnabled,
                    onChanged: (value) async {
                      try {
                        await Supabase.instance.client
                            .from('app_about_settings')
                            .update({'order_approval_code_enabled': value})
                            .eq('id', 1);
                        setState(() {});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(value ? 'Onay kodu açıldı' : 'Onay kodu kapatıldı'),
                              backgroundColor: value ? Colors.blue : Colors.orange,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    activeColor: Colors.blue,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (!isEnabled)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dikkat: Tüm mağazalarda sipariş alma durdurulmuş durumda. '
                            'Müşteriler hiçbir mağazadan sipariş veremez.',
                            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStartupAnnouncementCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client
          .from('app_about_settings')
          .select('startup_announcement_enabled, startup_announcement_title, startup_announcement_message, startup_announcement_type, startup_announcement_button_text')
          .single()
          .catchError((_) => <String, dynamic>{
                'startup_announcement_enabled': false,
                'startup_announcement_title': '',
                'startup_announcement_message': '',
                'startup_announcement_type': 'info',
                'startup_announcement_button_text': 'Tamam',
              }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            elevation: 1,
            child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          );
        }

        final announcementData = snapshot.data ?? {};
        final isEnabled = announcementData['startup_announcement_enabled'] ?? false;
        final title = (announcementData['startup_announcement_title'] ?? '') as String;
        final message = (announcementData['startup_announcement_message'] ?? '') as String;
        final type = (announcementData['startup_announcement_type'] ?? 'info') as String;
        final buttonText = (announcementData['startup_announcement_button_text'] ?? 'Tamam') as String;

        Color getColor(String t) {
          switch (t) {
            case 'warning': return Colors.orange;
            case 'success': return Colors.green;
            case 'error': return Colors.red;
            default: return Colors.blue;
          }
        }

        IconData getIcon(String t) {
          switch (t) {
            case 'warning': return Icons.warning;
            case 'success': return Icons.check_circle;
            case 'error': return Icons.error;
            default: return Icons.info;
          }
        }

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text(
                    'Duyuru Aktif',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Uygulama açılışında kullanıcılara bilgilendirme/not gösterilir',
                  ),
                  value: isEnabled,
                  onChanged: (value) async {
                    try {
                      await Supabase.instance.client
                          .from('app_about_settings')
                          .update({
                            'startup_announcement_enabled': value,
                            if (value) 'startup_announcement_updated_at': DateTime.now().toIso8601String(),
                          })
                          .eq('id', 1);
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Duyuru ${value ? "aktif" : "pasif"} edildi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  activeColor: Colors.orange,
                  contentPadding: EdgeInsets.zero,
                ),
                if (isEnabled) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  // Önizleme
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: getColor(type).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: getColor(type).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(getIcon(type), color: getColor(type), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Önizleme',
                              style: TextStyle(fontWeight: FontWeight.bold, color: getColor(type), fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title.isNotEmpty ? title : 'Başlık',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message.isNotEmpty ? message : 'Mesaj içeriği burada görünecek...',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Buton: $buttonText',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showEditAnnouncementDialog(title, message, type, buttonText),
                      icon: const Icon(Icons.edit),
                      label: const Text('Duyuruyu Düzenle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditAnnouncementDialog(String currentTitle, String currentMessage, String currentType, String currentButton) {
    final titleController = TextEditingController(text: currentTitle);
    final messageController = TextEditingController(text: currentMessage);
    final buttonController = TextEditingController(text: currentButton);
    String selectedType = currentType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Açılış Duyurusunu Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Duyuru Başlığı',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: 'Duyuru Mesajı',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.message),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: buttonController,
                  decoration: const InputDecoration(
                    labelText: 'Buton Metni (varsayılan: Tamam)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.smart_button),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Duyuru Tipi', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildTypeChip(selectedType, 'info', 'Bilgi', Icons.info, Colors.blue, (t) {
                      setDialogState(() => selectedType = t);
                    }),
                    _buildTypeChip(selectedType, 'warning', 'Uyarı', Icons.warning, Colors.orange, (t) {
                      setDialogState(() => selectedType = t);
                    }),
                    _buildTypeChip(selectedType, 'success', 'Başarılı', Icons.check_circle, Colors.green, (t) {
                      setDialogState(() => selectedType = t);
                    }),
                    _buildTypeChip(selectedType, 'error', 'Hata', Icons.error, Colors.red, (t) {
                      setDialogState(() => selectedType = t);
                    }),
                  ],
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
                try {
                  await Supabase.instance.client
                      .from('app_about_settings')
                      .update({
                        'startup_announcement_title': titleController.text.trim(),
                        'startup_announcement_message': messageController.text.trim(),
                        'startup_announcement_type': selectedType,
                        'startup_announcement_button_text': buttonController.text.trim().isEmpty ? 'Tamam' : buttonController.text.trim(),
                        'startup_announcement_updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', 1);
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Duyuru güncellendi'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
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

  Widget _buildTypeChip(String current, String type, String label, IconData icon, Color color, Function(String) onSelect) {
    final isSelected = current == type;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : color),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) onSelect(type);
      },
      selectedColor: color,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      checkmarkColor: Colors.white,
    );
  }

  Widget _buildComingSoon() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.construction,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Yakında...',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bu bölüm geliştiriliyor',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dk önce';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} saat önce';
    } else {
      return '${difference.inDays} gün önce';
    }
  }

  Future<List<Map<String, dynamic>>> _loadNotifications() async {
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(20);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Bildirimler yüklenirken hata: $e');
      // Mock veriler döndür
      return [
        {'title': 'Hoşgeldiniz!', 'body': 'Cizre Uygulamasına hoş geldiniz', 'status': 'sent', 'read_count': 245, 'created_at': DateTime.now().toIso8601String()},
        {'title': 'Yeni Özellik', 'body': 'Yeni özellikler ekledik!', 'status': 'sent', 'read_count': 189, 'created_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String()},
        {'title': 'Kampanya', 'body': 'İndirim fırsatlarını kaçırmayın', 'status': 'sent', 'read_count': 312, 'created_at': DateTime.now().subtract(const Duration(days: 5)).toIso8601String()},
        {'title': 'Bakım', 'body': 'Sistem bakımı yapılacaktır', 'status': 'pending', 'read_count': 0, 'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String()},
      ];
    }
  }

  Color _getNotificationStatusColor(String? status) {
    switch (status) {
      case 'sent':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _showSendNotificationDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String targetAudience = 'all';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bildirim Gönder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Mesaj',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: targetAudience,
                  decoration: const InputDecoration(
                    labelText: 'Hedef Kitle',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Tüm Kullanıcılar')),
                    DropdownMenuItem(value: 'customers', child: Text('Müşteriler')),
                    DropdownMenuItem(value: 'admins', child: Text('Adminler')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => targetAudience = value);
                    }
                  },
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
                if (titleController.text.isEmpty || bodyController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tüm alanları doldurun')),
                  );
                  return;
                }

                try {
                  // Bulk notification için tüm kullanıcılara gönder
                  final usersResponse = await Supabase.instance.client
                      .from('profiles')
                      .select('id');
                  
                  if (usersResponse.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kullanıcı bulunamadı')),
                    );
                    return;
                  }

                  for (var user in usersResponse) {
                    await Supabase.instance.client.from('notifications').insert({
                      'user_id': user['id'],
                      'type': 'shop', // Admin notification type
                      'title': titleController.text.trim(),
                      'content': bodyController.text.trim(),
                      'is_read': false,
                    });
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bildirim gönderildi')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: $e')),
                    );
                  }
                }
              },
              child: const Text('Gönder'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportTicketsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadSupportTickets(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final tickets = snapshot.data ?? [];
        final openTickets = tickets.where((t) => t['status'] == 'open').length;
        final inProgressTickets = tickets.where((t) => t['status'] == 'in_progress').length;
        final resolvedTickets = tickets.where((t) => t['status'] == 'resolved').length;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Destek Talepleri Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // İstatistik Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.pending_actions,
                        title: 'Bekleyen',
                        value: '$openTickets',
                        color: Colors.orange,
                        gradient: [Colors.orange.shade400, Colors.orange.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.hourglass_bottom,
                        title: 'İşlemi Devam',
                        value: '$inProgressTickets',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.done_all,
                        title: 'Çözüldü',
                        value: '$resolvedTickets',
                        color: Colors.green,
                        gradient: [Colors.green.shade400, Colors.green.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Talepler Listesi
                if (tickets.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.support_agent_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Destek talebi yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tickets.length,
                    itemBuilder: (context, index) {
                      final ticket = tickets[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getSupportTicketStatusColor(ticket['status']).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.support_agent,
                              color: _getSupportTicketStatusColor(ticket['status']),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            ticket['subject'] ?? 'Başlıksız',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                ticket['message'] ?? '-',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.email, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      ticket['user_email'] ?? '-',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(ticket['created_at']),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Chip(
                            label: Text(
                              _getSupportTicketStatusText(ticket['status']),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: _getSupportTicketStatusColor(ticket['status']).withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: _getSupportTicketStatusColor(ticket['status']),
                            ),
                          ),
                          onTap: () => _showSupportTicketDetailDialog(ticket),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadSupportTickets() async {
    try {
      final response = await Supabase.instance.client
          .from('support_tickets')
          .select('*, profiles(email, username)')
          .order('created_at', ascending: false)
          .limit(100);
      
      // Format ve user email ekle
      final tickets = List<Map<String, dynamic>>.from(response);
      for (var ticket in tickets) {
        if (ticket['profiles'] != null) {
          ticket['user_email'] = ticket['profiles']['email'] ?? '-';
        }
      }
      
      return tickets;
    } catch (e) {
      debugPrint('Destek talepleri yüklenirken hata: $e');
      // Mock veriler döndür
      return [
        {
          'id': '1',
          'subject': 'Ödeme sorunu',
          'message': 'Siparişim hala işleniyor.',
          'user_email': 'user1@example.com',
          'status': 'open',
          'created_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        },
        {
          'id': '2',
          'subject': 'Ürün teslimi',
          'message': 'Ürün ne zaman gelecek?',
          'user_email': 'user2@example.com',
          'status': 'in_progress',
          'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        },
        {
          'id': '3',
          'subject': 'İade işlemi',
          'message': 'Ürünü iade etmek istiyorum.',
          'user_email': 'user3@example.com',
          'status': 'resolved',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];
    }
  }

  Color _getSupportTicketStatusColor(String? status) {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getSupportTicketStatusText(String? status) {
    switch (status) {
      case 'open':
        return 'Açık';
      case 'in_progress':
        return 'İşlemi Devam';
      case 'resolved':
        return 'Çözüldü';
      case 'closed':
        return 'Kapalı';
      default:
        return 'Bilinmeyen';
    }
  }

  void _showSupportTicketDetailDialog(Map<String, dynamic> ticket) {
    showDialog(
      context: context,
      builder: (context) => _AdminTicketDetailDialog(
        ticket: ticket,
        onUpdate: () {
          _loadSupportTickets();
          setState(() {});
        },
      ),
    );
  }

  Widget _buildPaymentsContent() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadPaymentData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final data = snapshot.data ?? {};
        final payments = data['payments'] as List<Map<String, dynamic>>? ?? [];
        final stats = data['stats'] as Map<String, dynamic>? ?? {};

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ödeme Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // İstatistik Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.payments,
                        title: 'Toplam Gelir',
                        value: '₺${stats['total_revenue'] ?? 0}',
                        color: Colors.green,
                        gradient: [Colors.green.shade400, Colors.green.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.receipt_long,
                        title: 'Ödeme Sayısı',
                        value: '${stats['total_payments'] ?? 0}',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.check_circle,
                        title: 'Başarılı',
                        value: '${stats['completed_count'] ?? 0}',
                        color: Colors.teal,
                        gradient: [Colors.teal.shade400, Colors.teal.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.pending,
                        title: 'Bekleyen',
                        value: '${stats['pending_count'] ?? 0}',
                        color: Colors.orange,
                        gradient: [Colors.orange.shade400, Colors.orange.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.cancel,
                        title: 'İptal',
                        value: '${stats['cancelled_count'] ?? 0}',
                        color: Colors.red,
                        gradient: [Colors.red.shade400, Colors.red.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Ödeme Geçmişi
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Son Ödemeler',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        // Tümünü göster
                      },
                      icon: const Icon(Icons.filter_list),
                      label: const Text('Filtrele'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (payments.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.payment_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz ödeme yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: payments.length,
                    itemBuilder: (context, index) {
                      final payment = payments[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getPaymentStatusColor(payment['status']).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getPaymentIcon(payment['status']),
                              color: _getPaymentStatusColor(payment['status']),
                              size: 24,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  payment['shops']?['name'] ?? '-',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                '₺${payment['total_amount'] ?? 0}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.person, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      payment['shops']?['profiles']?['email'] ?? '-',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(payment['created_at']),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const Spacer(),
                                  Chip(
                                    label: Text(
                                      _getPaymentStatusText(payment['status']),
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                    backgroundColor: _getPaymentStatusColor(payment['status']).withOpacity(0.2),
                                    labelStyle: TextStyle(
                                      color: _getPaymentStatusColor(payment['status']),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _showPaymentDetailDialog(payment),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadPaymentData() async {
    try {
      // Ödeme isteklerini ve dükkan bilgilerini çek
      final payoutResponse = await Supabase.instance.client
          .from('payout_requests')
          .select('''
            *,
            shops(
              id,
              name,
              owner_id,
              profiles(email, username)
            )
          ''')
          .order('created_at', ascending: false)
          .limit(50);

      final payouts = List<Map<String, dynamic>>.from(payoutResponse);

      // İstatistikler
      final totalPayouts = payouts.length;
      final pendingPayouts =
          payouts.where((p) => p['status'] == 'pending').length;
      final approvedPayouts =
          payouts.where((p) => p['status'] == 'approved').length;
      final rejectedPayouts =
          payouts.where((p) => p['status'] == 'rejected').length;

      // Toplam tutar hesapla
      double totalAmount = 0;
      double pendingAmount = 0;
      double approvedAmount = 0;

      for (var payout in payouts) {
        final amount = (payout['total_amount'] as num?)?.toDouble() ?? 0.0;
        totalAmount += amount;

        if (payout['status'] == 'pending') {
          pendingAmount += amount;
        } else if (payout['status'] == 'approved') {
          approvedAmount += amount;
        }
      }

      return {
        'payments': payouts,
        'stats': {
          'total_revenue': totalAmount.toStringAsFixed(2),
          'total_payments': totalPayouts,
          'completed_count': approvedPayouts,
          'pending_count': pendingPayouts,
          'cancelled_count': rejectedPayouts,
          'pending_amount': pendingAmount.toStringAsFixed(2),
          'approved_amount': approvedAmount.toStringAsFixed(2),
        },
      };
    } catch (e) {
      debugPrint('Ödeme istekleri yüklenirken hata: $e');
      // Mock veriler döndür
      final now = DateTime.now();
      final mockPayments = [
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_1',
          'total_amount': 5000.00,
          'status': 'pending',
          'created_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
          'iban': 'TR12 3456 7890 1234 5678 9012 34',
          'account_holder_name': 'Ahmet Yılmaz',
          'notes': 'Ocak ayı kazancım',
          'shops': {
            'id': 'shop1',
            'name': 'Teknoloji Dükkanı',
            'owner_id': 'user1',
            'profiles': {'email': 'ahmet@example.com', 'username': 'ahmet_tech'},
          },
        },
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_2',
          'total_amount': 3250.50,
          'status': 'approved',
          'created_at': now.subtract(const Duration(hours: 5)).toIso8601String(),
          'iban': 'TR98 7654 3210 9876 5432 1098 76',
          'account_holder_name': 'Ayşe Demir',
          'notes': 'Haftalık ödeme',
          'reviewed_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
          'shops': {
            'id': 'shop2',
            'name': 'Moda Evi',
            'owner_id': 'user2',
            'profiles': {'email': 'ayse@example.com', 'username': 'ayse_moda'},
          },
        },
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_3',
          'total_amount': 7500.00,
          'status': 'pending',
          'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
          'iban': 'TR45 6789 0123 4567 8901 2345 67',
          'account_holder_name': 'Mehmet Kaya',
          'notes': 'Aralık ayı kazancı',
          'shops': {
            'id': 'shop3',
            'name': 'Spor Market',
            'owner_id': 'user3',
            'profiles': {'email': 'mehmet@example.com', 'username': 'mehmet_spor'},
          },
        },
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_4',
          'total_amount': 1500.00,
          'status': 'rejected',
          'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
          'iban': 'TR32 1098 7654 3210 9876 5432 10',
          'account_holder_name': 'Zeynep Şahin',
          'admin_notes': 'IBAN bilgileri hatalı',
          'reviewed_at': now.subtract(const Duration(days: 1)).toIso8601String(),
          'shops': {
            'id': 'shop4',
            'name': 'Kırtasiye Dünyası',
            'owner_id': 'user4',
            'profiles': {'email': 'zeynep@example.com', 'username': 'zeynep_kirtasiye'},
          },
        },
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_5',
          'total_amount': 4200.75,
          'status': 'pending',
          'created_at': now.subtract(const Duration(days: 3)).toIso8601String(),
          'iban': 'TR76 5432 1098 7654 3210 9876 54',
          'account_holder_name': 'Can Özkan',
          'shops': {
            'id': 'shop5',
            'name': 'Elektronik Market',
            'owner_id': 'user5',
            'profiles': {'email': 'can@example.com', 'username': 'can_electronik'},
          },
        },
      ];

      return {
        'payments': mockPayments,
        'stats': {
          'total_revenue': '21450.25',
          'total_payments': 5,
          'completed_count': 1,
          'pending_count': 3,
          'cancelled_count': 1,
          'pending_amount': '16700.75',
          'approved_amount': '3250.50',
        },
      };
    }
  }

  Color _getPaymentStatusColor(String? status) {
    switch (status) {
      case 'paid':
        return Colors.purple;
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getPaymentStatusText(String? status) {
    switch (status) {
      case 'paid':
        return 'Ödendi';
      case 'approved':
        return 'Onaylandı';
      case 'pending':
        return 'Bekliyor';
      case 'rejected':
        return 'Reddedildi';
      default:
        return 'Bilinmeyen';
    }
  }

  IconData _getPaymentIcon(String? status) {
    switch (status) {
      case 'paid':
        return Icons.payment;
      case 'approved':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.payment;
    }
  }

  /// Ödemeyi "Ödendi" olarak işaretler ve tüm bakiyeleri sıfırlar
  Future<void> _markPayoutAsPaid(Map<String, dynamic> payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.payment, color: Colors.purple),
            const SizedBox(width: 8),
            const Text('Ödemeyi Tamamla'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${payment['shops']?['name'] ?? 'Mağaza'} mağazasına ₺${(payment['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} TL ödeme yapıldı olarak işaretlenecek.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu işlem satıcının tüm bakiyelerini (kapıda kazanç, online kazanç ve komisyon borcu) sıfırlayacak.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('Evet, Ödendi'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final payoutId = payment['id'] as String;
        final shopId = payment['shop_id'] as String?;
        
        // Shop bilgilerini al
        final shop = await Supabase.instance.client
            .from('shops')
            .select('owner_id, name')
            .eq('id', shopId!)
            .single();
        
        // Ödeme durumunu 'paid' olarak güncelle
        // Trigger otomatik olarak bakiyeleri sıfırlayacak
        await Supabase.instance.client
            .from('payout_requests')
            .update({
              'status': 'paid',
              'paid_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', payoutId);

        // Satıcıya bildirim gönder
        final sellerId = shop['owner_id'];
        final shopName = shop['name'] ?? 'Mağazanız';
        final amount = (payment['total_amount'] as num?)?.toDouble() ?? 0.0;

        if (sellerId != null) {
          await Supabase.instance.client.from('notifications').insert({
            'user_id': sellerId,
            'type': 'shop',
            'title': 'Ödeme Yapıldı',
            'content': '$shopName için ₺${amount.toStringAsFixed(2)} TL ödemeniz yapıldı. Tüm bakiyeleriniz sıfırlandı.',
            'is_read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ödeme tamamlandı ve bakiyeler sıfırlandı'),
              backgroundColor: Colors.purple,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        debugPrint('❌ Ödeme tamamlama hatası: $e');
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
  }

  void _showPaymentDetailDialog(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getPaymentIcon(payment['status']),
              color: _getPaymentStatusColor(payment['status']),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ödeme Detayı', style: const TextStyle(fontSize: 18)),
                  Text(
                    '#${(payment['id'] as String?)?.substring(0, 8) ?? '-'}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Durum
              Card(
                color: _getPaymentStatusColor(payment['status']).withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Text(
                        'Durum:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(_getPaymentStatusText(payment['status'])),
                        backgroundColor: _getPaymentStatusColor(payment['status']).withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: _getPaymentStatusColor(payment['status']),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Dükkan Bilgisi
              const Text(
                'Dükkan Bilgisi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildInfoRow('Dükkan', payment['shops']?['name'] ?? '-', Colors.grey.shade700),
              _buildInfoRow('Email', payment['shops']?['profiles']?['email'] ?? '-', Colors.grey.shade700),
              const SizedBox(height: 16),

              // Ödeme İsteği Bilgisi
              const Text(
                'Ödeme İsteği Bilgisi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildInfoRow('Tutar', '₺${payment['total_amount'] ?? 0}', Colors.green.shade700),
              _buildInfoRow('İsteme Tarihi', _formatDate(payment['created_at']), Colors.grey.shade700),
              
              const SizedBox(height: 16),
              
              // Banka Bilgileri
              const Text(
                'Banka Bilgileri',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildInfoRow('IBAN', payment['iban'] ?? '-', Colors.grey.shade700),
              _buildInfoRow('Hesap Sahibi', payment['account_holder_name'] ?? '-', Colors.grey.shade700),
              
              if (payment['notes'] != null && (payment['notes'] as String).isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Satıcı Notu',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(payment['notes'] ?? '-'),
              ],
              
              if (payment['admin_notes'] != null && (payment['admin_notes'] as String).isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Admin Notu',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange.shade700),
                ),
                const SizedBox(height: 4),
                Text(payment['admin_notes'] ?? '-'),
              ],
              
              // İşleme Tarihi
              if (payment['updated_at'] != null && payment['status'] != 'pending') ...[
                const SizedBox(height: 16),
                _buildInfoRow('İşleme Tarihi', _formatDate(payment['updated_at']), Colors.grey.shade700),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          if (payment['status'] == 'pending') ...[
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showRejectPayoutDialog(payment['id']);
              },
              icon: const Icon(Icons.cancel, color: Colors.red),
              label: const Text('Reddet', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _processPayoutRequest(payment['id'], 'approved');
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Onayla'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
          if (payment['status'] == 'approved') ...[
            // Onaylandıysa - ÖDEME YAP butonu
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _markPayoutAsPaid(payment);
              },
              icon: const Icon(Icons.payment),
              label: const Text('Ödeme Yap'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _processPayoutRequest(String payoutId, String newStatus) async {
    try {
      // Önce payout request bilgilerini al (shop_id ve total_amount için)
      final payoutRequest = await Supabase.instance.client
          .from('payout_requests')
          .select('shop_id, total_amount')
          .eq('id', payoutId)
          .single();
      
      // Shop bilgisini al (owner_id, pending_payout ve total_paid için)
      final shop = await Supabase.instance.client
          .from('shops')
          .select('owner_id, name, pending_payout, total_paid')
          .eq('id', payoutRequest['shop_id'])
          .single();
      
      final sellerId = shop['owner_id'];
      final shopName = shop['name'];
      final amount = (payoutRequest['total_amount'] as num).toDouble();
      final shopId = payoutRequest['shop_id'] as String;
      
      // Ödeme isteğini güncelle
      await Supabase.instance.client
          .from('payout_requests')
          .update({
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', payoutId);
      
      // Eğer onaylandıysa shops tablosunu güncelle
      if (newStatus == 'approved') {
        final currentPendingPayout = (shop['pending_payout'] as num?)?.toDouble() ?? 0.0;
        final currentTotalPaid = (shop['total_paid'] as num?)?.toDouble() ?? 0.0;
        
        // pending_payout'tan düş, total_paid'e ekle
        final newPendingPayout = currentPendingPayout - amount;
        final newTotalPaid = currentTotalPaid + amount;
        
        await Supabase.instance.client
            .from('shops')
            .update({
              'pending_payout': newPendingPayout < 0 ? 0 : newPendingPayout,
              'total_paid': newTotalPaid,
            })
            .eq('id', shopId);
        
        debugPrint('✅ PAYOUT: Shops tablosu güncellendi');
        debugPrint('  └─ pending_payout: $currentPendingPayout -> ${newPendingPayout < 0 ? 0 : newPendingPayout}');
        debugPrint('  └─ total_paid: $currentTotalPaid -> $newTotalPaid');
      }
      
      // Satıcıya bildirim gönder
      final notificationMessage = newStatus == 'approved'
          ? '$shopName mağazanız için ${amount.toStringAsFixed(2)} TL tutarındaki ödeme isteğiniz onaylandı. Ödeme kısa süre içinde hesabınıza aktarılacaktır.'
          : '$shopName mağazanız için ${amount.toStringAsFixed(2)} TL tutarındaki ödeme isteğiniz reddedildi. Daha fazla bilgi için destek ekibiyle iletişime geçebilirsiniz.';
      
      await Supabase.instance.client
          .from('notifications')
          .insert({
            'user_id': sellerId,
            'type': 'shop', // Mevcut enum değerlerinden biri
            'title': newStatus == 'approved' ? 'Ödeme Onaylandı' : 'Ödeme Reddedildi',
            'content': notificationMessage,
            'is_read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus == 'approved'
                ? 'Ödeme isteği onaylandı ve satıcıya bildirim gönderildi'
                : 'Ödeme isteği reddedildi ve satıcıya bildirim gönderildi'),
            backgroundColor: newStatus == 'approved' ? Colors.green : Colors.red,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ PAYOUT: İşlem başarısız: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showRejectPayoutDialog(String payoutId) {
    final adminNotesController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ödeme İsteğini Reddet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Red sebebini belirtin:'),
            const SizedBox(height: 12),
            TextField(
              controller: adminNotesController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Red sebebi...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              if (adminNotesController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen red sebini girin'), backgroundColor: Colors.orange),
                );
                return;
              }
              
              Navigator.pop(context);
              
              try {
                await Supabase.instance.client
                    .from('payout_requests')
                    .update({
                      'status': 'rejected',
                      'admin_notes': adminNotesController.text.trim(),
                      'updated_at': DateTime.now().toIso8601String(),
                    })
                    .eq('id', payoutId);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ödeme isteği reddedildi'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setState(() {});
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('İşlem başarısız: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Reddet', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsPageContent() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadReportData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final data = snapshot.data ?? {};

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Raporlar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // Dönem Seçimi Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildPeriodCard(
                        title: 'Günlük',
                        icon: Icons.today,
                        color: Colors.blue,
                        isSelected: _selectedPeriod == 'daily',
                        onTap: () {
                          setState(() => _selectedPeriod = 'daily');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPeriodCard(
                        title: 'Haftalık',
                        icon: Icons.view_week,
                        color: Colors.green,
                        isSelected: _selectedPeriod == 'weekly',
                        onTap: () {
                          setState(() => _selectedPeriod = 'weekly');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPeriodCard(
                        title: 'Aylık',
                        icon: Icons.calendar_month,
                        color: Colors.orange,
                        isSelected: _selectedPeriod == 'monthly',
                        onTap: () {
                          setState(() => _selectedPeriod = 'monthly');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Özet İstatistikler
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.attach_money,
                        title: 'Toplam Kazanç',
                        value: '₺${data['totalRevenue'] ?? 0}',
                        color: Colors.green,
                        gradient: [Colors.green.shade400, Colors.green.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.shopping_cart,
                        title: 'Toplam Sipariş',
                        value: '${data['totalOrders'] ?? 0}',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.trending_up,
                        title: 'Ort. Sipariş',
                        value: '₺${data['avgOrder'] ?? 0}',
                        color: Colors.purple,
                        gradient: [Colors.purple.shade400, Colors.purple.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.people,
                        title: 'Aktif Müşteri',
                        value: '${data['activeCustomers'] ?? 0}',
                        color: Colors.teal,
                        gradient: [Colors.teal.shade400, Colors.teal.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Kazanç Grafiği
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Kazanç Grafiği',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '₺${data['totalRevenue'] ?? 0}',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildRevenueChart(data['revenueData'] as List<Map<String, dynamic>>? ?? []),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sipariş Grafiği
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sipariş Grafiği',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        _buildOrdersChart(data['ordersData'] as List<Map<String, dynamic>>? ?? []),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Kategori Dağılımı
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kategori Dağılımı',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        _buildCategoryDistribution(data['categoryData'] as List<Map<String, dynamic>>? ?? []),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeriodCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: isSelected ? color : color.withOpacity(0.1),
        elevation: isSelected ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : color,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRevenueChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.show_chart, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Veri yok',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final maxValue = data.fold<double>(0, (max, item) =>
      max > (item['value'] as num) ? max : (item['value'] as num).toDouble());
    
    return SizedBox(
      height: 200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((item) {
          final value = (item['value'] as num).toDouble();
          final height = maxValue > 0 ? (value / maxValue * 160) : 0.0;
          
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  '₺${value.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrdersChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Veri yok',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final maxValue = data.fold<int>(0, (max, item) =>
      max > (item['value'] as int) ? max : (item['value'] as int));
    
    return SizedBox(
      height: 200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((item) {
          final value = item['value'] as int;
          final height = maxValue > 0 ? (value / maxValue * 160) : 0;
          
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  height: height.toDouble(),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  '$value sipariş',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategoryDistribution(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.pie_chart, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Kategori verisi yok',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final total = data.fold<int>(0, (sum, item) => sum + (item['value'] as int));
    
    return Column(
      children: data.map((item) {
        final value = item['value'] as int;
        final percentage = total > 0 ? (value / total * 100) : 0.0;
        final color = item['color'] as Color? ?? Colors.grey;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item['label'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    '$value (${percentage.toStringAsFixed(1)}%)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: color.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<Map<String, dynamic>> _loadReportData() async {
    try {
      final now = DateTime.now();
      DateTime startDate;

      // Tarihe göre filtrele
      switch (_selectedPeriod) {
        case 'daily':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'weekly':
          startDate = now.subtract(const Duration(days: 30));
          break;
        case 'monthly':
        default:
          startDate = now.subtract(const Duration(days: 90));
          break;
      }

      // Siparişleri yükle
      final ordersResponse = await Supabase.instance.client
          .from('orders')
          .select()
          .gte('created_at', startDate.toIso8601String())
          .order('created_at', ascending: true);

      final orders = List<Map<String, dynamic>>.from(ordersResponse);

      // Toplam istatistikler
      double totalRevenue = 0;
      final customerIds = <String>{};

      for (var order in orders) {
        totalRevenue += (order['total'] as num?)?.toDouble() ?? 0.0;
        if (order['customer_id'] != null) {
          customerIds.add(order['customer_id'] as String);
        }
      }

      final avgOrder = orders.isNotEmpty ? totalRevenue / orders.length : 0.0;

      // Kazanç grafiği verisi
      final revenueData = <Map<String, dynamic>>[];
      final ordersData = <Map<String, dynamic>>[];

      // Veriyi grupla
      final groupedRevenue = <String, double>{};
      final groupedOrders = <String, int>{};

      for (var order in orders) {
        final date = DateTime.parse(order['created_at'] as String);
        String key;

        switch (_selectedPeriod) {
          case 'daily':
            key = '${date.day}/${date.month}';
            break;
          case 'weekly':
            final weekNum = ((date.day - 1) / 7).floor() + 1;
            key = 'H$weekNum';
            break;
          case 'monthly':
          default:
            key = '${date.month}/${date.year.toString().substring(2)}';
            break;
        }

        groupedRevenue[key] = (groupedRevenue[key] ?? 0.0) + ((order['total'] as num?)?.toDouble() ?? 0.0);
        groupedOrders[key] = (groupedOrders[key] ?? 0) + 1;
      }

      // Sıralı listeye çevir
      final sortedKeys = groupedRevenue.keys.toList()..sort();
      for (var key in sortedKeys.take(10)) {
        revenueData.add({'label': key, 'value': groupedRevenue[key] ?? 0});
        ordersData.add({'label': key, 'value': groupedOrders[key] ?? 0});
      }

      // Kategori dağılımı (ürün kategorilerine göre)
      final categoryData = <Map<String, dynamic>>[];
      final categoryColors = [
        Colors.purple,
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.red,
        Colors.teal,
      ];

      try {
        final productsResponse = await Supabase.instance.client
            .from('products')
            .select('category_id, categories(name)')
            .limit(100);

        final products = List<Map<String, dynamic>>.from(productsResponse);
        final categoryCounts = <String, int>{};

        for (var product in products) {
          final category = product['categories']?['name'] ?? 'Diğer';
          categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
        }

        int colorIndex = 0;
        categoryCounts.forEach((category, count) {
          categoryData.add({
            'label': category,
            'value': count,
            'color': categoryColors[colorIndex % categoryColors.length],
          });
          colorIndex++;
        });

        // Sırala
        categoryData.sort((a, b) => (b['value'] as int).compareTo(a['value'] as int));
      } catch (e) {
        debugPrint('Kategori verileri yüklenirken hata: $e');
      }

      return {
        'totalRevenue': totalRevenue.toStringAsFixed(2),
        'totalOrders': orders.length,
        'avgOrder': avgOrder.toStringAsFixed(2),
        'activeCustomers': customerIds.length,
        'revenueData': revenueData,
        'ordersData': ordersData,
        'categoryData': categoryData,
      };
    } catch (e) {
      debugPrint('Rapor verileri yüklenirken hata: $e');
      
      // Mock veriler döndür
      final categoryColors = [
        Colors.purple,
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.red,
        Colors.teal,
      ];

      final mockRevenueData = [
        {'label': 'Pzt', 'value': 4500.0},
        {'label': 'Sal', 'value': 5200.0},
        {'label': 'Çar', 'value': 3800.0},
        {'label': 'Per', 'value': 6100.0},
        {'label': 'Cum', 'value': 7500.0},
        {'label': 'Cmt', 'value': 8200.0},
        {'label': 'Paz', 'value': 5400.0},
      ];

      final mockOrdersData = [
        {'label': 'Pzt', 'value': 15},
        {'label': 'Sal', 'value': 18},
        {'label': 'Çar', 'value': 12},
        {'label': 'Per', 'value': 22},
        {'label': 'Cum', 'value': 28},
        {'label': 'Cmt', 'value': 31},
        {'label': 'Paz', 'value': 19},
      ];

      final mockCategoryData = [
        {'label': 'Elektronik', 'value': 45, 'color': categoryColors[0]},
        {'label': 'Giyim', 'value': 32, 'color': categoryColors[1]},
        {'label': 'Ev & Yaşam', 'value': 28, 'color': categoryColors[2]},
        {'label': 'Spor', 'value': 21, 'color': categoryColors[3]},
        {'label': 'Kitap', 'value': 15, 'color': categoryColors[4]},
      ];

      return {
        'totalRevenue': '40700.00',
        'totalOrders': 145,
        'avgOrder': '280.69',
        'activeCustomers': 89,
        'revenueData': mockRevenueData,
        'ordersData': mockOrdersData,
        'categoryData': mockCategoryData,
      };
    }
  }

  Widget _buildAPISettingsContent() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadAPISettings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? {};
        final apiKeys = data['apiKeys'] as List<Map<String, dynamic>>? ?? [];
        final settings = data['settings'] as Map<String, dynamic>? ?? {};

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık ve Yeni Anahtar Butonu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'API Ayarları',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateAPIKeyDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Anahtar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // API Anahtarları Bölümü
                const Text(
                  'API Anahtarları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (apiKeys.isEmpty)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.key_off, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'Henüz API anahtarı yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: apiKeys.length,
                    itemBuilder: (context, index) {
                      final key = apiKeys[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: key['is_active'] == true ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.vpn_key,
                              color: key['is_active'] == true ? Colors.green.shade600 : Colors.red.shade600,
                              size: 24,
                            ),
                          ),
                          title: Text(
                            key['name'] ?? 'API Anahtarı',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'pk_${(key['key'] as String?)?.substring(0, 20) ?? '-'}...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Oluşturuldu: ${_formatDate(key['created_at'])}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (key['last_used_at'] != null)
                                    Row(
                                      children: [
                                        Icon(Icons.check_circle, size: 12, color: Colors.green.shade500),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Son Kullanım: ${_formatDate(key['last_used_at'])}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.green.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'toggle') {
                                _toggleAPIKey(key);
                              } else if (value == 'regenerate') {
                                _regenerateAPIKey(key);
                              } else if (value == 'delete') {
                                _showDeleteAPIKeyDialog(key);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'toggle',
                                child: Row(
                                  children: [
                                    Icon(Icons.power_settings_new, size: 18),
                                    SizedBox(width: 8),
                                    Text('Aç/Kapat'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'regenerate',
                                child: Row(
                                  children: [
                                    Icon(Icons.refresh, size: 18),
                                    SizedBox(width: 8),
                                    Text('Yenile'),
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
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),

                // Güvenlik Ayarları
                const Text(
                  'Güvenlik Ayarları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Geçerli IP Adresleri',
                          settings['allowed_ips'] ?? 'Sınırlı yok',
                          Colors.blue,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('HTTPS Zorunlu'),
                          subtitle: const Text('API istekleri sadece HTTPS üzerinden kabul et'),
                          value: settings['require_https'] ?? true,
                          onChanged: (value) {
                            _updateAPISetting('require_https', value);
                          },
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('CORS Etkin'),
                          subtitle: const Text('Cross-Origin isteklerine izin ver'),
                          value: settings['cors_enabled'] ?? true,
                          onChanged: (value) {
                            _updateAPISetting('cors_enabled', value);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Rate Limiting
                const Text(
                  'Rate Limiting',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Dakikalık İstek Limiti',
                          '${settings['requests_per_minute'] ?? 60}',
                          Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Saatlik İstek Limiti',
                          '${settings['requests_per_hour'] ?? 10000}',
                          Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Aylık İstek Limiti',
                          '${settings['requests_per_month'] ?? 500000}',
                          Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Webhooks
                const Text(
                  'Webhooks',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.webhook, color: Colors.orange.shade600),
                    ),
                    title: const Text('Webhook Yönetimi'),
                    subtitle: const Text('API olayları için webhook endpoints ayarla'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showWebhooksDialog(),
                  ),
                ),
                const SizedBox(height: 24),

                // Online Ödeme Ayarları (iyzico)
                const Text(
                  'Online Ödeme Ayarları (iyzico)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildIyzicoPaymentSettingsCard(data),

                const SizedBox(height: 24),

                // S3 Depolama Ayarları (idrive e2)
                const Text(
                  'S3 Depolama Ayarları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildS3StorageSettingsCard(data),

                const SizedBox(height: 24),

                // API İstatistikleri
                const Text(
                  'API İstatistikleri (Son 30 Gün)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.api,
                        title: 'Toplam İstek',
                        value: '${settings['total_requests'] ?? 0}',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.check_circle,
                        title: 'Başarılı',
                        value: '${settings['successful_requests'] ?? 0}',
                        color: Colors.green,
                        gradient: [Colors.green.shade400, Colors.green.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.error,
                        title: 'Hata',
                        value: '${settings['failed_requests'] ?? 0}',
                        color: Colors.red,
                        gradient: [Colors.red.shade400, Colors.red.shade600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIyzicoPaymentSettingsCard(Map<String, dynamic> data) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client
          .from('app_about_settings')
          .select('online_payment_enabled, iyzico_api_key, iyzico_secret_key, iyzico_api_url')
          .single()
          .catchError((_) => <String, dynamic>{
                'online_payment_enabled': true,
                'iyzico_api_key': null,
                'iyzico_secret_key': null,
                'iyzico_api_url': 'https://sandbox-api.iyzipay.com',
              }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            elevation: 1,
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final paySettings = snapshot.data ?? {};
        final isEnabled = paySettings['online_payment_enabled'] ?? true;
        final apiKey = (paySettings['iyzico_api_key'] ?? '') as String;
        final secretKey = (paySettings['iyzico_secret_key'] ?? '') as String;
        final apiUrl = (paySettings['iyzico_api_url'] ?? 'https://sandbox-api.iyzipay.com') as String;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text(
                    'Online Ödeme Aktif',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Kullanıcıların online ödeme yapabilmesi için iyzico entegrasyonunu açın',
                  ),
                  value: isEnabled,
                  onChanged: (value) async {
                    try {
                      await Supabase.instance.client
                          .from('app_about_settings')
                          .update({'online_payment_enabled': value})
                          .eq('id', 1);
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Online ödeme ${value ? "aktif" : "pasif"} edildi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  activeColor: Colors.purple,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.payment, color: Colors.purple.shade600, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'iyzico API Bilgileri',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'API Key',
                  apiKey.isEmpty ? 'Ayarlanmadı' : '${apiKey.substring(0, apiKey.length > 8 ? 8 : apiKey.length)}...',
                  apiKey.isEmpty ? Colors.red : Colors.green,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  'Secret Key',
                  secretKey.isEmpty ? 'Ayarlanmadı' : '********',
                  secretKey.isEmpty ? Colors.red : Colors.green,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  'API URL',
                  apiUrl.contains('sandbox') ? 'Sandbox (Test)' : 'Production (Canlı)',
                  apiUrl.contains('sandbox') ? Colors.orange : Colors.blue,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showEditIyzicoDialog(apiKey, secretKey, apiUrl),
                    icon: const Icon(Icons.edit),
                    label: const Text('iyzico API Anahtarlarını Düzenle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
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
                          'Sandbox: https://sandbox-api.iyzipay.com\nProduction: https://api.iyzipay.com',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditIyzicoDialog(String currentApiKey, String currentSecretKey, String currentApiUrl) {
    final apiKeyController = TextEditingController(text: currentApiKey);
    final secretKeyController = TextEditingController(text: currentSecretKey);
    final apiUrlController = TextEditingController(text: currentApiUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('iyzico API Ayarları'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: secretKeyController,
                decoration: const InputDecoration(
                  labelText: 'Secret Key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiUrlController,
                decoration: const InputDecoration(
                  labelText: 'API URL',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
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
              try {
                final updateData = <String, dynamic>{};
                if (apiKeyController.text.trim().isNotEmpty) {
                  updateData['iyzico_api_key'] = apiKeyController.text.trim();
                }
                if (secretKeyController.text.trim().isNotEmpty) {
                  updateData['iyzico_secret_key'] = secretKeyController.text.trim();
                }
                if (apiUrlController.text.trim().isNotEmpty) {
                  updateData['iyzico_api_url'] = apiUrlController.text.trim();
                }
                if (updateData.isNotEmpty) {
                  await Supabase.instance.client
                      .from('app_about_settings')
                      .update(updateData)
                      .eq('id', 1);
                }
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('iyzico ayarları güncellendi'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _loadAPISettings() async {
    try {
      // API Keys yükle
      final apiKeysResponse = await Supabase.instance.client
          .from('api_keys')
          .select()
          .order('created_at', ascending: false);

      final apiKeys = List<Map<String, dynamic>>.from(apiKeysResponse);

      // API Settings yükle
      final settingsResponse = await Supabase.instance.client
          .from('api_settings')
          .select()
          .single()
          .catchError((_) => {
                'require_https': true,
                'cors_enabled': true,
                'requests_per_minute': 60,
                'requests_per_hour': 10000,
                'requests_per_month': 500000,
                'total_requests': 0,
                'successful_requests': 0,
                'failed_requests': 0,
                'allowed_ips': 'Sınırlı yok',
              });

      return {
        'apiKeys': apiKeys,
        'settings': settingsResponse,
      };
    } catch (e) {
      debugPrint('API ayarları yüklenirken hata: $e');
      // Mock veriler döndür
      final now = DateTime.now();
      return {
        'apiKeys': [
          {
            'id': '1',
            'name': 'Production API',
            'key': 'live_${now.millisecondsSinceEpoch}_prod',
            'description': 'Ana üretim ortamı API anahtarı',
            'is_active': true,
            'created_at': now.subtract(const Duration(days: 30)).toIso8601String(),
            'last_used_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
          },
          {
            'id': '2',
            'name': 'Mobile App',
            'key': 'mobile_${now.millisecondsSinceEpoch}_app',
            'description': 'Mobil uygulama API anahtarı',
            'is_active': true,
            'created_at': now.subtract(const Duration(days: 15)).toIso8601String(),
            'last_used_at': now.subtract(const Duration(minutes: 30)).toIso8601String(),
          },
          {
            'id': '3',
            'name': 'Test Environment',
            'key': 'test_${now.millisecondsSinceEpoch}_env',
            'description': 'Test ortamı için API anahtarı',
            'is_active': false,
            'created_at': now.subtract(const Duration(days: 60)).toIso8601String(),
            'last_used_at': now.subtract(const Duration(days: 10)).toIso8601String(),
          },
          {
            'id': '4',
            'name': 'Web Dashboard',
            'key': 'web_${now.millisecondsSinceEpoch}_dash',
            'description': 'Web dashboard için API anahtarı',
            'is_active': true,
            'created_at': now.subtract(const Duration(days: 45)).toIso8601String(),
            'last_used_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
          },
        ],
        'settings': {
          'require_https': true,
          'cors_enabled': true,
          'requests_per_minute': 60,
          'requests_per_hour': 10000,
          'requests_per_month': 500000,
          'total_requests': 145678,
          'successful_requests': 142341,
          'failed_requests': 3337,
          'allowed_ips': 'Sınırsız',
        },
      };
    }
  }

  void _showCreateAPIKeyDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni API Anahtarı Oluştur'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Anahtar Adı',
                  hintText: 'örn: Mobile App',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Bu anahtarın kullanım amacı',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
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
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Anahtar adı gerekli')),
                );
                return;
              }

              try {
                final newKey = 'pk_${DateTime.now().millisecondsSinceEpoch}';

                await Supabase.instance.client.from('api_keys').insert({
                  'name': nameController.text.trim(),
                  'key': newKey,
                  'description': descriptionController.text.trim(),
                  'is_active': true,
                  'created_at': DateTime.now().toIso8601String(),
                });

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('API anahtarı oluşturuldu: $newKey'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
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

  void _showDeleteAPIKeyDialog(Map<String, dynamic> key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API Anahtarını Sil'),
        content: Text(
          '${key['name']} API anahtarını silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz.',
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
                await Supabase.instance.client
                    .from('api_keys')
                    .delete()
                    .eq('id', key['id']);

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API anahtarı silindi')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
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

  void _toggleAPIKey(Map<String, dynamic> key) async {
    try {
      await Supabase.instance.client
          .from('api_keys')
          .update({'is_active': !(key['is_active'] ?? true)})
          .eq('id', key['id']);

      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (key['is_active'] ?? true) ? 'Anahtar deaktive edildi' : 'Anahtar aktive edildi',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  void _regenerateAPIKey(Map<String, dynamic> key) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API Anahtarını Yenile'),
        content: const Text(
          'API anahtarını yenilemek istediğinizden emin misiniz?\n\nEski anahtar artık çalışmayacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final newKey = 'pk_${DateTime.now().millisecondsSinceEpoch}';

                await Supabase.instance.client
                    .from('api_keys')
                    .update({'key': newKey})
                    .eq('id', key['id']);

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('API anahtarı yenilendi: $newKey'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
                  );
                }
              }
            },
            child: const Text('Yenile'),
          ),
        ],
      ),
    );
  }

  void _updateAPISetting(String key, dynamic value) async {
    try {
      await Supabase.instance.client
          .from('api_settings')
          .update({key: value})
          .limit(1);

      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ayar güncellendi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  void _showWebhooksDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Webhook Yönetimi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Webhook Endpoint\'leri:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildWebhookItem('order.created', 'Sipariş oluşturuldu'),
                    _buildWebhookItem('order.completed', 'Sipariş tamamlandı'),
                    _buildWebhookItem('order.cancelled', 'Sipariş iptal edildi'),
                    _buildWebhookItem('payment.completed', 'Ödeme tamamlandı'),
                    _buildWebhookItem('payment.failed', 'Ödeme başarısız'),
                    _buildWebhookItem('user.created', 'Yeni kullanıcı'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yapılandır'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebhookItem(String event, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.webhook, size: 16, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Şikayet Detay Dialog
  void _showReportDetailDialog(Map<String, dynamic> report) {
    final reporter = report['reporter'] as Map<String, dynamic>?;
    final reported = report['reported'] as Map<String, dynamic>?;
    String selectedStatus = report['status'] ?? 'pending';
    final adminResponseController = TextEditingController(text: report['admin_response'] ?? '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade400, Colors.red.shade600],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flag, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Şikayet Detayı',
                      style: TextStyle(fontSize: 16),
                    ),
                    Text(
                      _formatDate(report['created_at']),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Durum
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getReportStatusColor(selectedStatus).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getReportStatusIcon(selectedStatus),
                            size: 14,
                            color: _getReportStatusColor(selectedStatus),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getReportStatusText(selectedStatus),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getReportStatusColor(selectedStatus),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Şikayet Eden Bilgisi
                  const Text(
                    'Şikayet Eden',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.blue.shade200,
                            backgroundImage: reporter?['avatar_url'] != null
                                ? NetworkImage(reporter!['avatar_url'])
                                : null,
                            child: reporter?['avatar_url'] == null
                                ? Text(
                                    (reporter?['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reporter?['full_name'] ?? reporter?['username'] ?? 'Bilinmeyen',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  reporter?['email'] ?? '-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Şikayet Edilen Bilgisi
                  const Text(
                    'Şikayet Edilen',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.red.shade200,
                            backgroundImage: reported?['avatar_url'] != null
                                ? NetworkImage(reported!['avatar_url'])
                                : null,
                            child: reported?['avatar_url'] == null
                                ? Text(
                                    (reported?['username'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade800,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reported?['full_name'] ?? reported?['username'] ?? 'Bilinmeyen',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  reported?['email'] ?? '-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Şikayet Sebebi
                  const Text(
                    'Şikayet Sebebi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.flag, color: Colors.red.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            report['reason'] ?? '-',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Açıklama
                  if (report['description'] != null && (report['description'] as String).isNotEmpty) ...[
                    const Text(
                      'Açıklama',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        report['description'] ?? '-',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Durum Değiştir
                  const Text(
                    'Durum',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      _buildReportStatusOption(
                        status: 'pending',
                        label: 'Bekliyor',
                        icon: Icons.pending,
                        color: Colors.orange,
                        selectedStatus: selectedStatus,
                        onTap: () => setDialogState(() => selectedStatus = 'pending'),
                      ),
                      const SizedBox(height: 8),
                      _buildReportStatusOption(
                        status: 'reviewing',
                        label: 'İnceleniyor',
                        icon: Icons.visibility,
                        color: Colors.blue,
                        selectedStatus: selectedStatus,
                        onTap: () => setDialogState(() => selectedStatus = 'reviewing'),
                      ),
                      const SizedBox(height: 8),
                      _buildReportStatusOption(
                        status: 'resolved',
                        label: 'Çözüldü',
                        icon: Icons.check_circle,
                        color: Colors.green,
                        selectedStatus: selectedStatus,
                        onTap: () => setDialogState(() => selectedStatus = 'resolved'),
                      ),
                      const SizedBox(height: 8),
                      _buildReportStatusOption(
                        status: 'rejected',
                        label: 'Reddedildi',
                        icon: Icons.cancel,
                        color: Colors.red,
                        selectedStatus: selectedStatus,
                        onTap: () => setDialogState(() => selectedStatus = 'rejected'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Admin Cevabı
                  const Text(
                    'Admin Notu',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: adminResponseController,
                    decoration: InputDecoration(
                      hintText: 'Notunuzu yazın...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    maxLines: 3,
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
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Kaydet'),
              onPressed: () async {
                try {
                  debugPrint('📝 Şikayet güncelleniyor: ${report['id']} -> $selectedStatus');
                  
                  final oldResponse = report['admin_response'] as String? ?? '';
                  final newResponse = adminResponseController.text.trim();
                  final oldStatus = report['status'] as String? ?? '';
                  
                  // Durum değiştiyse VEYA admin yanıtı eklendi/degistiyse bildirim gönder
                  final shouldNotify = selectedStatus != oldStatus ||
                                        (newResponse.isNotEmpty && newResponse != oldResponse);

                  if (shouldNotify) {
                    try {
                      final notificationMessage = newResponse.isNotEmpty
                          ? 'Şikayet talebinize yanıt geldi: ${newResponse.substring(0, newResponse.length > 50 ? 50 : newResponse.length)}...'
                          : 'Şikayet durumunuz güncellendi: ${_getReportStatusText(selectedStatus)}';
                      
                      await Supabase.instance.client
                          .from('notifications')
                          .insert({
                            'user_id': report['reporter_id'],
                            'type': 'report_response',
                            'title': 'Şikayet Güncellemesi',
                            'message': notificationMessage,
                            'data': {
                              'report_id': report['id'],
                              'status': selectedStatus,
                              'admin_response': newResponse,
                            },
                            'read': false,
                            'created_at': DateTime.now().toIso8601String(),
                          });
                      debugPrint('✅ Bildirim gönderildi: $notificationMessage');
                    } catch (notifError) {
                      debugPrint('⚠️ Bildirim gönderilemedi: $notifError');
                    }
                  }

                  await Supabase.instance.client
                      .from('user_reports')
                      .update({
                        'status': selectedStatus,
                        'admin_response': newResponse.isNotEmpty ? newResponse : oldResponse,
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', report['id']);

                  debugPrint('✅ Şikayet başarıyla güncellendi');

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Şikayet güncellendi: ${_getReportStatusText(selectedStatus)}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e, stackTrace) {
                  debugPrint('❌ Şikayet güncellenirken hata: $e');
                  debugPrint('📍 Stack trace: $stackTrace');

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Şikayet güncellenirken hata: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportStatusOption({
    required String status,
    required String label,
    required IconData icon,
    required Color color,
    required String selectedStatus,
    required VoidCallback onTap,
  }) {
    final isSelected = status == selectedStatus;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.grey.shade700,
                ),
              ),
            ),
            if (isSelected) Icon(Icons.check, color: color),
          ],
        ),
      ),
    );
  }

  // Şikayet Silme Dialog
  void _showDeleteReportDialog(Map<String, dynamic> report) {
    final reporter = report['reporter'] as Map<String, dynamic>?;
    final reported = report['reported'] as Map<String, dynamic>?;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete, color: Colors.red),
            SizedBox(width: 8),
            Text('Şikayeti Sil'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bu şikayeti silmek istediğinizden emin misiniz?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        'Şikayet Eden: ${reporter?['full_name'] ?? reporter?['username'] ?? '-'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_off, size: 14, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(
                        'Şikayet Edilen: ${reported?['full_name'] ?? reported?['username'] ?? '-'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.flag, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Sebep: ${report['reason'] ?? '-'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu işlem geri alınamaz. Şikayet kalıcı olarak silinecektir.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade900,
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
                debugPrint('🗑️ Şikayet siliniyor: ${report['id']}');

                await Supabase.instance.client
                    .from('user_reports')
                    .delete()
                    .eq('id', report['id']);

                debugPrint('✅ Şikayet başarıyla silindi');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Şikayet başarıyla silindi'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Şikayet silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Şikayet silinirken hata: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
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

  // Adres ID'sinden telefon numarasını çek (Admin için)
  Future<String?> _getAddressPhoneForAdmin(String addressId) async {
    try {
      final response = await Supabase.instance.client
          .from('addresses')
          .select('phone')
          .eq('id', addressId)
          .maybeSingle();

      if (response != null) {
        return response['phone'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Admin: Telefon numarası alınırken hata: $e');
      return null;
    }
  }

  // Müşteriyi ara (Admin için)
  Future<void> _callCustomerFromAdmin(String phoneNumber) async {
    try {
      final uri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Telefon uygulaması açılamadı')),
          );
        }
      }
    } catch (e) {
      debugPrint('Telefon arama hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arama yapılırken hata: $e')),
        );
      }
    }
  }

  // Adresi haritada aç
  Future<void> _openAddressInMap(String address) async {
    try {
      // Google Maps ile adresi aç
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

  // S3 Storage Settings Card
  Widget _buildS3StorageSettingsCard(Map<String, dynamic> data) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client
          .from('api_settings')
          .select('s3_enabled, s3_access_key, s3_secret_key, s3_bucket, s3_endpoint, s3_region, s3_public_url')
          .single()
          .catchError((_) => <String, dynamic>{
                's3_enabled': false,
                's3_access_key': '',
                's3_secret_key': '',
                's3_bucket': '',
                's3_endpoint': '',
                's3_region': 'us-east-1',
                's3_public_url': '',
              }),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            elevation: 1,
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final s3Settings = snapshot.data ?? {};
        final isEnabled = s3Settings['s3_enabled'] ?? false;
        final accessKey = (s3Settings['s3_access_key'] ?? '') as String;
        final bucket = (s3Settings['s3_bucket'] ?? '') as String;
        final endpoint = (s3Settings['s3_endpoint'] ?? '') as String;
        final region = (s3Settings['s3_region'] ?? 'us-east-1') as String;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text(
                    'S3 Storage Aktif',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Yeni dosyalar S3 uyumlu storage\'da (idrive e2 gibi) depolanır. Kapalıyken Supabase Storage kullanılır.',
                  ),
                  value: isEnabled,
                  onChanged: (value) async {
                    try {
                      await Supabase.instance.client
                          .from('api_settings')
                          .update({'s3_enabled': value})
                          .eq('id', (await Supabase.instance.client.from('api_settings').select('id').single())['id']);
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('S3 Storage ${value ? "aktif" : "pasif"} edildi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  activeColor: Colors.purple,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.cloud_upload, color: Colors.purple.shade600, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'S3 API Bilgileri',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Access Key', style: TextStyle(fontSize: 14)),
                      Text(
                        accessKey.isEmpty ? 'Ayarlanmadı' : '${accessKey.substring(0, accessKey.length > 10 ? 10 : accessKey.length)}...',
                        style: const TextStyle(fontSize: 14, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Bucket', style: TextStyle(fontSize: 14)),
                      Text(
                        bucket.isEmpty ? 'Ayarlanmadı' : bucket,
                        style: const TextStyle(fontSize: 14, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Endpoint', style: TextStyle(fontSize: 14)),
                      Text(
                        endpoint.isEmpty ? 'Ayarlanmadı' : endpoint,
                        style: const TextStyle(fontSize: 14, color: Colors.green),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Region', style: TextStyle(fontSize: 14)),
                      Text(
                        region,
                        style: const TextStyle(fontSize: 14, color: Colors.teal),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showS3SettingsDialog(s3Settings),
                    icon: const Icon(Icons.edit),
                    label: const Text('S3 Ayarlarını Düzenle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showS3SettingsDialog(Map<String, dynamic> currentSettings) {
    final accessKeyController = TextEditingController(text: currentSettings['s3_access_key'] ?? '');
    final secretKeyController = TextEditingController(text: currentSettings['s3_secret_key'] ?? '');
    final bucketController = TextEditingController(text: currentSettings['s3_bucket'] ?? '');
    final endpointController = TextEditingController(text: currentSettings['s3_endpoint'] ?? '');
    final regionController = TextEditingController(text: currentSettings['s3_region'] ?? 'us-east-1');
    final publicUrlController = TextEditingController(text: currentSettings['s3_public_url'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('S3 Storage Ayarları'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accessKeyController,
                decoration: const InputDecoration(
                  labelText: 'Access Key ID',
                  hintText: 'Örn: AKIAIOSFODNN7EXAMPLE',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: secretKeyController,
                decoration: const InputDecoration(
                  labelText: 'Secret Access Key',
                  hintText: 'Gizli anahtar',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bucketController,
                decoration: const InputDecoration(
                  labelText: 'Bucket Name',
                  hintText: 'Örn: cizreapp-storage',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endpointController,
                decoration: const InputDecoration(
                  labelText: 'Endpoint URL',
                  hintText: 'Örn: s3.us-east-1.idrivee2.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: regionController,
                decoration: const InputDecoration(
                  labelText: 'Region',
                  hintText: 'Örn: us-east-1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: publicUrlController,
                decoration: const InputDecoration(
                  labelText: 'Public URL (Opsiyonel)',
                  hintText: 'CDN URL varsa',
                  border: OutlineInputBorder(),
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
              try {
                final settingsId = (await Supabase.instance.client
                    .from('api_settings')
                    .select('id')
                    .single())['id'];

                await Supabase.instance.client.from('api_settings').update({
                  's3_access_key': accessKeyController.text.trim(),
                  's3_secret_key': secretKeyController.text.trim(),
                  's3_bucket': bucketController.text.trim(),
                  's3_endpoint': endpointController.text.trim(),
                  's3_region': regionController.text.trim(),
                  's3_public_url': publicUrlController.text.trim(),
                }).eq('id', settingsId);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('S3 ayarları kaydedildi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {});
                }
              } catch (e) {
                if (context.mounted) {
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
    );
  }
}

// Admin Destek Talebi Detay Dialog Widget
class _AdminTicketDetailDialog extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onUpdate;

  const _AdminTicketDetailDialog({
    required this.ticket,
    required this.onUpdate,
  });

  @override
  State<_AdminTicketDetailDialog> createState() => _AdminTicketDetailDialogState();
}

class _AdminTicketDetailDialogState extends State<_AdminTicketDetailDialog> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String _selectedStatus = 'open';
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.ticket['status'] ?? 'open';
    _loadMessages();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    final ticketId = widget.ticket['id'].toString();
    _messagesChannel = Supabase.instance.client
        .channel('admin_ticket_messages_$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_ticket_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: ticketId,
          ),
          callback: (payload) {
            final newMessage = payload.newRecord;
            setState(() {
              _messages.add(newMessage);
            });
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final ticketId = widget.ticket['id'].toString();
      final response = await Supabase.instance.client
          .from('support_ticket_messages')
          .select()
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: true);
      
      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Mesajlar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'open':
        return 'Açık';
      case 'in_progress':
        return 'İşleniyor';
      case 'resolved':
        return 'Çözüldü';
      case 'closed':
        return 'Kapalı';
      default:
        return 'Bilinmiyor';
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '-';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inMinutes < 1) {
        return 'Az önce';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} dakika önce';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} saat önce';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} gün önce';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return '-';
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    
    final message = _messageController.text.trim();
    _messageController.clear();
    
    try {
      final ticketId = widget.ticket['id'].toString();
      final adminId = Supabase.instance.client.auth.currentUser?.id;
      
      await Supabase.instance.client
          .from('support_ticket_messages')
          .insert({
            'ticket_id': ticketId,
            'sender_id': adminId,
            'sender_type': 'admin',
            'message': message,
          });
      
      // Kullanıcıya bildirim gönder
      if (widget.ticket['user_id'] != null) {
        final shortMessage = message.length > 50
            ? '${message.substring(0, 50)}...'
            : message;
        
        await Supabase.instance.client.from('notifications').insert({
          'user_id': widget.ticket['user_id'],
          'type': 'support_response',
          'title': 'Destek Talebinize Yanıt Geldi',
          'content': 'Destek talebinize admin yanıt verdi: $shortMessage',
          'entity_id': widget.ticket['id'].toString(),
          'is_read': false,
        });
      }
    } catch (e) {
      debugPrint('Mesaj gönderilirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await Supabase.instance.client
          .from('support_tickets')
          .update({'status': newStatus, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', widget.ticket['id']);
      
      setState(() {
        _selectedStatus = newStatus;
      });
      
      // Kullanıcıya bildirim gönder
      if (widget.ticket['user_id'] != null) {
        await Supabase.instance.client.from('notifications').insert({
          'user_id': widget.ticket['user_id'],
          'type': 'support_status',
          'title': 'Destek Talebi Durumu Güncellendi',
          'content': 'Destek talebinizin durumu "${_getStatusText(newStatus)}" olarak güncellendi.',
          'entity_id': widget.ticket['id'].toString(),
          'is_read': false,
        });
      }
      
      widget.onUpdate();
    } catch (e) {
      debugPrint('Durum güncellenirken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.support_agent, size: 28, color: Colors.purple),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ticket['subject'] ?? 'Destek Talebi',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '#${widget.ticket['id']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(_selectedStatus).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getStatusColor(_selectedStatus),
                      width: 1,
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedStatus,
                    style: TextStyle(
                      color: _getStatusColor(_selectedStatus),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    underline: const SizedBox.shrink(),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: _getStatusColor(_selectedStatus),
                      size: 20,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('Açık')),
                      DropdownMenuItem(value: 'in_progress', child: Text('İşleniyor')),
                      DropdownMenuItem(value: 'resolved', child: Text('Çözüldü')),
                      DropdownMenuItem(value: 'closed', child: Text('Kapalı')),
                    ],
                    onChanged: (value) {
                      if (value != null && value != _selectedStatus) {
                        _updateStatus(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            
            const Divider(height: 24),
            
            // User Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.ticket['user_email'] ?? 'Bilinmeyen Kullanıcı',
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(widget.ticket['created_at']),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Messages List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                   size: 48,
                                   color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'Henüz mesaj yok',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'İlk mesajı gönderin',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isAdmin = message['sender_type'] == 'admin';
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: isAdmin
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isAdmin) ...[
                                        const Icon(Icons.person,
                                                  size: 14,
                                                  color: Colors.grey),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        isAdmin ? 'Admin' : 'Kullanıcı',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isAdmin
                                              ? Colors.purple
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                      if (isAdmin) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.support_agent,
                                                  size: 14,
                                                  color: Colors.purple),
                                      ],
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatDate(message['created_at']),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 300,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isAdmin
                                          ? Colors.purple.shade100
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      message['message'] ?? '',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            
            const Divider(),
            
            // Message Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Colors.purple, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
