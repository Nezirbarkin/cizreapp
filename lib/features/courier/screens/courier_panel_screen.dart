// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unnecessary_brace_in_string_interps, curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/courier_assignment_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/courier_notification_service.dart';
import '../../../core/services/courier_location_service.dart';
import '../../../core/services/location_disclosure_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/privacy_service.dart';
import '../../../core/services/email_service.dart';
import '../../market/screens/cart_screen.dart';
import '../../social/screens/social_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../market/providers/cart_provider.dart';
import '../../main/screens/main_screen.dart';
import '../../seller/screens/seller_dashboard_screen.dart';

/// Bir id'yi güvenli şekilde kısa gösterime dönüştürür. id null/boş/kısa ise
/// RangeError fırlatmaz; "null"/"?" yerine güvenli bir değer döner.
String _shortId(dynamic id) {
  final s = id?.toString();
  if (s == null || s.isEmpty) return '?';
  return s.length > 8 ? s.substring(0, 8) : s;
}

/// Bir metnin ilk harfini güvenli şekilde alır (boş/kullanıcı adı yoksa 'K').
String _initialOf(String? text) {
  final t = (text ?? '').trim();
  return t.isNotEmpty ? t[0].toUpperCase() : 'K';
}

/// Bir sipariş/harita satırından dükkan adını güvenli şekilde alır. 'shops'
/// ilişkisi tek Map dönerse adını, List/null/başka tip gelirse 'Dükkan' döner.
String _shopNameOf(Map<String, dynamic> order) {
  final shops = order['shops'];
  if (shops is Map) {
    final name = shops['name'];
    if (name is String && name.isNotEmpty) return name;
  }
  return 'Dükkan';
}

class CourierPanelScreen extends StatefulWidget {
  const CourierPanelScreen({super.key});

  @override
  State<CourierPanelScreen> createState() => _CourierPanelScreenState();
}

class _CourierPanelScreenState extends State<CourierPanelScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _didApplyRouteArguments = false;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didApplyRouteArguments) return;
    _didApplyRouteArguments = true;

    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is Map && arguments['tab'] == 1) {
      _selectedIndex = 1;
    }
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
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Text(
                        cartProvider.itemCount > 9
                            ? '9+'
                            : '${cartProvider.itemCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerDocked,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
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

  // Haftalık istatistikler
  int _weeklyDeliveries = 0;
  double _weeklyEarnings = 0;
  int _monthlyDeliveries = 0;
  double _monthlyEarnings = 0;
  // Kurye online/offline tercihi (is_online_enabled). DB'den yüklenir.
  // false ise kurye manuel çevrimdışı: app ön plana gelse bile otomatik online yapılmaz.
  bool _isOnlineEnabled = true;

  // Kurye konum paylaşımı (CourierLocationService). Açıkken kuryenin
  // last_known_lat/lng'si periyodik olarak yazılır ve kullanıcıların
  // "Yakın Kuryeler" haritasında moto ikonuyla görünür.
  bool _isLocationSharing = false;

  List<Map<String, dynamic>> _serviceNotices = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        // Oturum yoksa spinner sonsuza kadar dönmesin.
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Profil bilgilerini al
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      _profile = Map<String, dynamic>.from(profileData);

      // Kurye online GÖRÜNME TERCİHİ DB'den yüklenir (önceden default true
      // gösteriliyordu, bu yüzden gerçek durumu yansıtmıyordu).
      // is_online_enabled sütunu yoksa true kabul edilir (eski davranış).
      _isOnlineEnabled = _profile?['is_online_enabled'] as bool? ?? true;

      // Konum paylaşım servisi singleton olduğu için app oturumundaki gerçek
      // durumu (çalışıyor/çalışmıyor) yansıtır. Açılışta buton buna göre görünür.
      _isLocationSharing = CourierLocationService().isTracking;

      // Kurye ucretini al (en guncel kaydi al)
      try {
        final settings = await Supabase.instance.client
            .from('courier_settings')
            .select('fee_per_delivery')
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (settings != null) {
          _feePerDelivery =
              (settings['fee_per_delivery'] as num?)?.toDouble() ?? 15.0;
          debugPrint('✅ Kurye ucreti yuklendi: ₺$_feePerDelivery');
        } else {
          debugPrint('⚠️ courier_settings tablosunda kayit yok!');
          _feePerDelivery = 15.0;
        }
      } catch (e) {
        debugPrint('❌ Kurye ucreti yukleme hatasi: $e');
        _feePerDelivery = 15.0;
      }

      // Haftalık istatistikleri yükle
      await _loadWeeklyStats();

      // Aylık istatistikleri yükle
      await _loadMonthlyStats();

      // Uyarıları yükle
      await _loadServiceNotices();

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Veriler yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWeeklyStats() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeek = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day,
      );

      final response = await Supabase.instance.client
          .from('courier_assignments')
          .select('fee_amount')
          .eq('courier_id', userId)
          .eq('status', 'delivered')
          .gte('delivered_at', startOfWeek.toIso8601String());

      final deliveries = List<Map<String, dynamic>>.from(response);
      _weeklyDeliveries = deliveries.length;
      _weeklyEarnings = deliveries.fold(
        0.0,
        (sum, d) => sum + ((d['fee_amount'] as num?)?.toDouble() ?? 0),
      );

      final packages = await Supabase.instance.client
          .from('courier_requests')
          .select('courier_fee')
          .eq('courier_id', userId)
          .eq('status', 'delivered')
          .gte('delivered_at', startOfWeek.toIso8601String());
      final packageList = List<Map<String, dynamic>>.from(packages);
      _weeklyDeliveries += packageList.length;
      _weeklyEarnings += packageList.fold(
        0.0,
        (sum, d) => sum + ((d['courier_fee'] as num?)?.toDouble() ?? 0),
      );
    } catch (e) {
      debugPrint('Haftalık istatistikler yüklenirken hata: $e');
    }
  }

  Future<void> _loadMonthlyStats() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      final response = await Supabase.instance.client
          .from('courier_assignments')
          .select('fee_amount')
          .eq('courier_id', userId)
          .eq('status', 'delivered')
          .gte('delivered_at', startOfMonth.toIso8601String());

      final deliveries = List<Map<String, dynamic>>.from(response);
      _monthlyDeliveries = deliveries.length;
      _monthlyEarnings = deliveries.fold(
        0.0,
        (sum, d) => sum + ((d['fee_amount'] as num?)?.toDouble() ?? 0),
      );

      final packages = await Supabase.instance.client
          .from('courier_requests')
          .select('courier_fee')
          .eq('courier_id', userId)
          .eq('status', 'delivered')
          .gte('delivered_at', startOfMonth.toIso8601String());
      final packageList = List<Map<String, dynamic>>.from(packages);
      _monthlyDeliveries += packageList.length;
      _monthlyEarnings += packageList.fold(
        0.0,
        (sum, d) => sum + ((d['courier_fee'] as num?)?.toDouble() ?? 0),
      );
    } catch (e) {
      debugPrint('Aylık istatistikler yüklenirken hata: $e');
    }
  }

  Future<void> _toggleOnlineStatus() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final newValue = !_isOnlineEnabled;
      setState(() => _isOnlineEnabled = newValue);

      // Ortak PrivacyService kullanılarak tercihi (is_online_enabled) günceller.
      // Bu, app lifecycle'ın da saygı duyduğu kalıcı tercihi yazar ve
      // is_online alanını da buna göre setler. Böylece kurye manuel olarak
      // offline yaptığında app ön plana gelse bile tekrar online yapılmaz.
      final privacyService = PrivacyService();
      final success = await privacyService.updateOnlineEnabled(newValue);

      if (!success) {
        // Hata: geri al
        if (mounted) {
          setState(() => _isOnlineEnabled = !newValue);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Durum güncellenemedi'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newValue ? 'Online moduna geçtiniz' : 'Offline moduna geçtiniz',
            ),
            backgroundColor: newValue ? Colors.green : Colors.grey,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Online durumu güncellenirken hata: $e');
      // Hata: geri al
      if (mounted) {
        setState(() => _isOnlineEnabled = !_isOnlineEnabled);
      }
    }
  }

  /// Kurye konum paylaşımını açar/kapatır. Açıkken CourierLocationService
  /// kuryenin konumunu (last_known_lat/lng) periyodik olarak veritabanına
  /// yazar; böylece kullanıcıların "Yakın Kuryeler" haritasında moto ikonuyla
  /// görünür. Konum izni, paylaşım açılmadan önce burada — Prominent
  /// Disclosure ekranı gösterilerek — alınır; izin yoksa başlatma yapılmaz ve
  /// durum butona yansır.
  Future<void> _toggleLocationSharing() async {
    final service = CourierLocationService();
    if (service.isTracking) {
      await service.stopTracking();
      if (mounted) {
        setState(() => _isLocationSharing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konum paylaşımı durduruldu'),
            backgroundColor: Colors.grey,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Önce uygulama içi açıklama + sistem izni. Reddedilirse hiçbir konum
    // API'si çağrılmaz.
    final allowed = await LocationDisclosureService.ensure(
      context,
      LocationPurpose.courierTracking,
    );
    if (!allowed) {
      if (mounted) setState(() => _isLocationSharing = false);
      return;
    }

    // startTracking yalnızca ilk konum veritabanına yazılırsa true döner;
    // aksi halde (eksik sütun, RLS, ağ hatası) false döner ve buton
    // "paylaşılıyor" diye yanıltıcı görünmez.
    final started = await service.startTracking();
    if (mounted) {
      setState(() => _isLocationSharing = started);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            started
                ? 'Konumunuz paylaşılıyor — kullanıcılar sizi haritada görebilir'
                : 'Konum paylaşımı başlatılamadı (konum izni veya veritabanı hatası)',
          ),
          backgroundColor: started ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Normal moda (MainScreen) geç
  void _goToNormalMode() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  /// Satıcı paneline git
  void _goToSellerPanel() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Satıcı olup olmadığını kontrol et
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    if (profile?['role'] == 'seller') {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const SellerDashboardScreen(),
          ),
          (route) => false,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Satıcı rolüne sahip değilsiniz'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Kurye ayarlar dialogu - isim, email, telefon güncelleme
  void _showSettingsDialog() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final nameController = TextEditingController(
      text: _profile?['full_name'] ?? '',
    );
    final emailController = TextEditingController(
      text: _profile?['email'] ?? '',
    );
    final phoneController = TextEditingController(
      text: _profile?['phone'] ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.settings,
                color: Colors.teal.shade700,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Kurye Ayarları'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sipariş atandığında e-posta bildirimi gönderilir',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Ad Soyad',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'E-posta',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Telefon',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newEmail = emailController.text.trim();
              final newPhone = phoneController.text.trim();

              try {
                await Supabase.instance.client
                    .from('profiles')
                    .update({'full_name': newName, 'phone': newPhone})
                    .eq('id', userId);

                // Email güncelleme (auth metadata)
                if (newEmail.isNotEmpty) {
                  try {
                    await Supabase.instance.client.auth.updateUser(
                      UserAttributes(email: newEmail),
                    );
                  } catch (e) {
                    debugPrint('Email güncelleme hatası: $e');
                  }
                }

                if (mounted) {
                  Navigator.pop(ctx);
                  _loadData(); // Verileri yenile
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ayarlar güncellendi!'),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
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
                    expandedHeight: 280,
                    pinned: true,
                    actions: [
                      // Online/Offline Toggle
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: _toggleOnlineStatus,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _isOnlineEnabled
                                  ? Colors.green
                                  : Colors.grey,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isOnlineEnabled
                                      ? Icons.wifi
                                      : Icons.wifi_off,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isOnlineEnabled ? 'Online' : 'Offline',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Menü Butonu
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onSelected: (value) {
                          switch (value) {
                            case 'normal_mode':
                              _goToNormalMode();
                              break;
                            case 'seller_panel':
                              _goToSellerPanel();
                              break;
                            case 'refresh':
                              _loadData();
                              break;
                            case 'settings':
                              _showSettingsDialog();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'settings',
                            child: Row(
                              children: [
                                Icon(Icons.settings, color: Colors.teal),
                                SizedBox(width: 12),
                                Text('Ayarlar'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'normal_mode',
                            child: Row(
                              children: [
                                Icon(Icons.apps, color: Colors.blue),
                                SizedBox(width: 12),
                                Text('Normal Moda Geç'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'seller_panel',
                            child: Row(
                              children: [
                                Icon(Icons.store, color: Colors.orange),
                                SizedBox(width: 12),
                                Text('Satıcı Paneline Git'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'refresh',
                            child: Row(
                              children: [
                                Icon(Icons.refresh, color: Colors.grey),
                                SizedBox(width: 12),
                                Text('Yenile'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
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
                                      backgroundImage:
                                          _profile?['avatar_url'] != null
                                          ? NetworkImage(
                                              _profile!['avatar_url'],
                                            )
                                          : null,
                                      child: _profile?['avatar_url'] == null
                                          ? Text(
                                              _initialOf(
                                                _profile?['username']
                                                    as String?,
                                              ),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Merhaba,',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.8,
                                              ),
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            _profile?['full_name'] ??
                                                _profile?['username'] ??
                                                'Kurye',
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
                                const SizedBox(height: 16),
                                // Ana istatistikler
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildStatItem(
                                        Icons.attach_money,
                                        '₺${_feePerDelivery.toStringAsFixed(0)}',
                                        'Paket',
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: Colors.white.withOpacity(0.3),
                                      ),
                                      _buildStatItem(
                                        Icons.check_circle,
                                        '${_profile?['delivered_count'] ?? 0}',
                                        'Toplam',
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: Colors.white.withOpacity(0.3),
                                      ),
                                      _buildStatItem(
                                        Icons.calendar_today,
                                        '₺${_weeklyEarnings.toStringAsFixed(0)}',
                                        'Bu Hafta',
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Aylık özet
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildMiniStat(
                                        'Bu Ay Teslimat',
                                        '$_monthlyDeliveries',
                                      ),
                                      Container(
                                        width: 1,
                                        height: 30,
                                        color: Colors.white.withOpacity(0.3),
                                      ),
                                      _buildMiniStat(
                                        'Bu Ay Kazanç',
                                        '₺${_monthlyEarnings.toStringAsFixed(0)}',
                                      ),
                                      Container(
                                        width: 1,
                                        height: 30,
                                        color: Colors.white.withOpacity(0.3),
                                      ),
                                      _buildMiniStat(
                                        'Haftalık',
                                        '$_weeklyDeliveries',
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
                        // Admin uyarıları
                        _buildServiceNotices(),

                        const Text(
                          'Hızlı İşlemler',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildQuickActionCard(
                          icon: _isLocationSharing
                              ? Icons.location_on
                              : Icons.location_off,
                          title: _isLocationSharing
                              ? 'Konum Paylaşılıyor'
                              : 'Konumum Paylaş',
                          subtitle: _isLocationSharing
                              ? 'Kullanıcıların haritasında görünürsünüz'
                              : 'Konumunuzu paylaşarak görünür olun',
                          color: _isLocationSharing
                              ? Colors.green
                              : Colors.indigo,
                          onTap: _toggleLocationSharing,
                        ),
                        const SizedBox(height: 12),
                        _buildQuickActionCard(
                          icon: Icons.delivery_dining,
                          title: 'Mevcut Siparişler',
                          subtitle: 'Atanan siparişleri görüntüle',
                          color: Colors.orange,
                          onTap: () {
                            // Kurye siparişler sekmesine geç
                            final courierState = context
                                .findAncestorStateOfType<
                                  _CourierPanelScreenState
                                >();
                            if (courierState != null) {
                              courierState.setState(() {
                                courierState._selectedIndex = 1;
                              });
                            }
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
                        const SizedBox(height: 12),
                        _buildQuickActionCard(
                          icon: Icons.payment,
                          title: 'Ödeme Bilgileri',
                          subtitle: 'IBAN ve banka bilgileri',
                          color: Colors.purple,
                          onTap: () => _showPaymentInfoDialog(),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Nasıl Çalışır?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
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
            _buildStepItem(
              Icons.notifications_active,
              '1',
              'Sipariş Atanır',
              'Kuryesi olmayan satıcıların siparişleri size atanır',
            ),
            const Divider(),
            _buildStepItem(
              Icons.local_shipping,
              '2',
              'Siparişi Al',
              'Dükkanandan siparişi teslim al',
            ),
            const Divider(),
            _buildStepItem(
              Icons.home,
              '3',
              'Teslim Et',
              'Müşteriye siparişi teslim et',
            ),
            const Divider(),
            _buildStepItem(
              Icons.attach_money,
              '4',
              'Teslimat Yap',
              'Teslim et, kazan!',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(
    IconData icon,
    String step,
    String title,
    String description,
  ) {
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
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentInfoDialog() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Mevcut odeme bilgilerini yukle
    Map<String, dynamic>? paymentInfo;
    try {
      final response = await Supabase.instance.client
          .from('courier_payment_info')
          .select()
          .eq('courier_id', userId)
          .maybeSingle();
      paymentInfo = response;
    } catch (e) {
      debugPrint('Odeme bilgisi yukleme hatasi: $e');
    }

    final ibanController = TextEditingController(
      text: paymentInfo?['iban'] ?? '',
    );
    final bankNameController = TextEditingController(
      text: paymentInfo?['bank_name'] ?? '',
    );
    final accountHolderController = TextEditingController(
      text:
          paymentInfo?['account_holder_name'] ??
          paymentInfo?['full_name'] ??
          '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odeme Bilgileri'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Odeme hesabinizi girin. Kazanclariniz bu IBAN\'a odenir.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ibanController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'IBAN',
                  hintText: 'TR00 0000 0000 0000 0000 0000 00',
                  prefixIcon: Icon(Icons.account_balance),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bankNameController,
                decoration: const InputDecoration(
                  labelText: 'Banka Adi',
                  hintText: 'Ziraat Bankasi',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountHolderController,
                decoration: const InputDecoration(
                  labelText: 'Hesap Sahibi Adi',
                  hintText: 'Ad Soyad',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Iptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final iban = ibanController.text.trim();
              final bankName = bankNameController.text.trim();
              final accountHolder = accountHolderController.text.trim();

              if (iban.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('IBAN zorunludur'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                if (paymentInfo != null) {
                  // Guncelle
                  await Supabase.instance.client
                      .from('courier_payment_info')
                      .update({
                        'iban': iban,
                        'bank_name': bankName,
                        'account_holder_name': accountHolder,
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('courier_id', userId);
                } else {
                  // Olustur
                  await Supabase.instance.client
                      .from('courier_payment_info')
                      .insert({
                        'courier_id': userId,
                        'iban': iban,
                        'bank_name': bankName,
                        'account_holder_name': accountHolder,
                      });
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Odeme bilgileri kaydedildi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Odeme bilgisi kaydetme hatasi: $e');
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
      MaterialPageRoute(builder: (context) => const CourierEarningsScreen()),
    );
  }

  Future<void> _loadServiceNotices() async {
    try {
      final notices = await Supabase.instance.client
          .from('courier_service_notices')
          .select()
          .eq('show_on_courier_panel', true)
          .order('priority', ascending: false)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(
          () => _serviceNotices = List<Map<String, dynamic>>.from(notices),
        );
      }
    } catch (e) {
      debugPrint('Uyarılar yükleme hatası: $e');
    }
  }

  Widget _buildServiceNotices() {
    if (_serviceNotices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        ..._serviceNotices.map((notice) {
          final noticeType = notice['notice_type'] as String? ?? 'info';
          final title = notice['title'] as String? ?? '';
          final message = notice['message'] as String? ?? '';
          final priority = notice['priority'] as int? ?? 0;

          Color bgColor;
          Color borderColor;
          Color textColor;
          IconData icon;

          switch (noticeType) {
            case 'warning':
              bgColor = Colors.orange.shade50;
              borderColor = Colors.orange.shade200;
              textColor = Colors.orange.shade900;
              icon = Icons.warning_amber_rounded;
              break;
            case 'alert':
              bgColor = Colors.red.shade50;
              borderColor = Colors.red.shade200;
              textColor = Colors.red.shade900;
              icon = Icons.error_rounded;
              break;
            case 'success':
              bgColor = Colors.green.shade50;
              borderColor = Colors.green.shade200;
              textColor = Colors.green.shade900;
              icon = Icons.check_circle_rounded;
              break;
            default: // info
              bgColor = Colors.blue.shade50;
              borderColor = Colors.blue.shade200;
              textColor = Colors.blue.shade900;
              icon = Icons.info_rounded;
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: textColor, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (priority > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: priority > 1
                                    ? Colors.red.shade300
                                    : Colors.orange.shade300,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                priority > 1 ? 'ACİL' : 'ÖNEMLİ',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ==================== KURYE SİPARİŞLER TAB ====================

class CourierOrdersTab extends StatefulWidget {
  const CourierOrdersTab({super.key});

  @override
  State<CourierOrdersTab> createState() => _CourierOrdersTabState();
}

class _CourierOrdersTabState extends State<CourierOrdersTab>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  RealtimeChannel? _ordersChannel;
  List<Map<String, dynamic>> _availableOrders = [];
  List<Map<String, dynamic>> _myOrders = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _refreshQueued = false;
  bool _focusRequestedTabAfterRefresh = false;
  bool _didReadRouteArguments = false;
  String? _packageError; // Paket RPC hata özeti (UI'da gösterilir)
  double _commissionPercent = 20;

  /// Kurye ücretini al
  Future<double> _getCourierFee() async {
    try {
      final settings = await Supabase.instance.client
          .from('courier_settings')
          .select('fee_per_delivery')
          .limit(1)
          .maybeSingle();
      return (settings?['fee_per_delivery'] as num?)?.toDouble() ?? 15.0;
    } catch (e) {
      debugPrint('Kurye ucreti yukleme hatasi: $e');
      return 15.0;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Uygulama ön plana geri döndüğünde (resume) sipariş listesini yenile.
    // Eskiden didChangeAppLifecycleState yalnızca parent'ta setState ederdi
    // ve kurye yeni atamaları görmezdi; pull-to-refresh gerekirdi.
    WidgetsBinding.instance.addObserver(this);
    _subscribeToCourierWorkChanges();
    _loadOrders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _ordersChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didReadRouteArguments) return;
    _didReadRouteArguments = true;

    // Atama/yönlendirme push'ından gelindiğinde dış panel "Siparişler"i açar;
    // yeni işler açık kabul beklediği için içte "Atanabilir" sekmesi gösterilir.
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is Map && arguments['tab'] == 1) {
      _focusRequestedTabAfterRefresh = true;
    }
  }

  /// Kurye paneli açıkken yapılan atama/devir ve Paket+ değişikliklerini anlık
  /// yeniler. Özellikle `reject_order_assignment` mevcut assignment satırının
  /// `courier_id` değerini değiştirdiği için yeni kurye, uygulamayı yeniden
  /// açmadan siparişi görmelidir.
  void _subscribeToCourierWorkChanges() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final previous = _ordersChannel;
    if (previous != null) {
      Supabase.instance.client.removeChannel(previous);
    }

    _ordersChannel = Supabase.instance.client
        .channel('courier_work_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'courier_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'courier_id',
            value: userId,
          ),
          callback: (_) {
            if (mounted) {
              _focusRequestedTabAfterRefresh = true;
              _loadOrders();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'courier_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'courier_id',
            value: userId,
          ),
          callback: (_) {
            if (mounted) _loadOrders();
          },
        )
        // Paket teklifinde courier_requests.courier_id kabul öncesi null kalır;
        // sipariş teklifinde de hedef değişikliği sırasında Realtime UPDATE
        // filtresi her istemcide güvenilir olmayabilir. Hedef kullanıcıya yazılan
        // yönlendirme notification'ı iki akış için ortak ve RLS ile kullanıcıya
        // özeldir; bu olay Atanabilir listesini anında yeniler.
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (mounted) {
              _focusRequestedTabAfterRefresh = true;
              _loadOrders();
            }
          },
        )
        .subscribe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadOrders();
    }
  }

  Future<void> _loadOrders() async {
    if (_isRefreshing) {
      // Atama ilk yükleme devam ederken gelirse Realtime olayını kaybetme.
      _refreshQueued = true;
      return;
    }
    _isRefreshing = true;
    setState(() {
      _isLoading = true;
      _packageError = null;
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      try {
        final settings = await Supabase.instance.client
            .from('courier_service_settings')
            .select('commission_percent')
            .limit(1)
            .maybeSingle();
        _commissionPercent =
            (settings?['commission_percent'] as num?)?.toDouble() ?? 20;
      } catch (e) {
        debugPrint('Komisyon oranı yüklenemedi: $e');
      }

      debugPrint('========== KURYE SİPARİŞ YÜKLEME ==========');
      debugPrint('Kullanıcı ID: $userId');

      // Atanabilir siparişleri PII içermeyen RPC'den yükle.
      // Eski yol orders'ı doğrudan select edip customer_phone /
      // delivery_address_text (PII) henüz kabul etmemiş tüm kuryelere
      // sızdırıyordu; ayrıca RLS körlüğü yüzünden başka kuryeye atanmış
      // siparişleri de listeliyordu. get_available_orders_for_courier her iki
      // sorunu da sunucu tarafında çözer — yalnız id/total/shop_name/item_count
      // döner; adres/telefon yalnız kabul edene (get_courier_active_orders) açılır.
      List<Map<String, dynamic>> availableFiltered = [];
      try {
        final rows = await Supabase.instance.client.rpc(
          'get_available_orders_for_courier',
        );
        availableFiltered = (rows as List)
            .map<Map<String, dynamic>>(
              (r) => {
                'id': r['id'],
                'total': r['total'],
                'shop_id': r['shop_id'],
                'shop_name': r['shop_name'],
                'shops': {'name': r['shop_name']},
                'created_at': r['created_at'],
                // RPC order status döndürmez; havuz yalnızca
                // confirmed/preparing/ready siparişleri içerir.
                'status': 'ready',
                'item_count': r['item_count'],
                'order_items': List.generate(
                  (r['item_count'] as num? ?? 0).toInt(),
                  (_) => <String, dynamic>{},
                ),
                '_type': 'order',
              },
            )
            .toList();
        debugPrint('Toplam atanabilir sipariş: ${availableFiltered.length}');
      } catch (e) {
        debugPrint('❌ Atanabilir siparişler hatası: $e');
      }

      // Ret/devret sonrası yalnız hedef kuryeye yönlendirilmiş sipariş teklifleri.
      // Bu RPC kabul öncesi tam teslimat detayını yalnız offer sahibine açar.
      try {
        final routedRows = await Supabase.instance.client.rpc(
          'get_courier_routed_order_offers',
        );
        final routedOrders = (routedRows as List).map<Map<String, dynamic>>((
          r,
        ) {
          final items = r['order_items_json'];
          return {
            'id': r['order_id'],
            'total': r['order_total'],
            'shop_id': r['shop_id'],
            'shop_name': r['shop_name'],
            'shops': {'name': r['shop_name']},
            'created_at': r['created_at'],
            'status': r['order_status'] ?? 'ready',
            'delivery_address_text': r['delivery_address_text'],
            'customer_phone': r['customer_phone'],
            'order_items': items is List
                ? List<Map<String, dynamic>>.from(items)
                : <Map<String, dynamic>>[],
            'assignment_id': r['assignment_id'],
            'offer_id': r['offer_id'],
            'fee_amount': r['fee_amount'],
            'is_routed_offer': true,
            '_type': 'order',
          };
        }).toList();
        availableFiltered = [...routedOrders, ...availableFiltered];
        debugPrint('Yönlendirilmiş sipariş teklifi: ${routedOrders.length}');
      } catch (e) {
        debugPrint('❌ Yönlendirilmiş sipariş teklifleri hatası: $e');
      }

      // Aktif siparişleri getir (bu kuryeye atanmış olanlar)
      List<Map<String, dynamic>> myOrdersList = [];
      try {
        // SECURITY DEFINER RPC, assignment devrinden sonra yeni kuryenin tam
        // sipariş detayını tek sorguda ve RLS/embed kırılganlığı olmadan döner.
        // Önceki doğrudan courier_assignments -> orders embed sorgusunda alt
        // orders kaydı RLS nedeniyle null dönebildiği için assignment mevcut
        // olsa bile kart listeye hiç eklenmiyordu.
        final assignments = await Supabase.instance.client.rpc(
          'get_courier_active_orders',
        );

        debugPrint('Aktif sipariş sayısı: ${assignments.length}');

        for (final a in (assignments as List)) {
          final items = a['order_items_json'];
          final normalizedItems = items is List
              ? List<Map<String, dynamic>>.from(items)
              : <Map<String, dynamic>>[];
          final order = <String, dynamic>{
            'id': a['order_id'],
            'total': a['order_total'],
            'status': a['order_status'],
            'delivery_address_text': a['delivery_address_text'],
            'customer_phone': a['customer_phone'],
            'created_at': a['created_at'],
            'shops': {'name': a['shop_name']},
            'order_items': normalizedItems,
            'assignment_id': a['assignment_id'],
            'assignment_status': a['assignment_status'],
            'fee_amount': a['fee_amount'],
          };
          myOrdersList.add(order);
          debugPrint(
            'Aktif sipariş: ${order['id']} | durum: ${a['assignment_status']} | items: ${normalizedItems.length}',
          );
        }

        debugPrint('Toplam aktif sipariş: ${myOrdersList.length}');
      } catch (e) {
        debugPrint('❌ Aktif siparişler hatası: $e');
      }

      debugPrint('===========================================');

      // Paket gönderim talepleri güvenli RPC üzerinden yüklenir. Hedeflenmiş
      // tekliflerde tam alım/teslim bilgisi yalnız hedef kuryeye; genel havuzda
      // ise PII yerine açıklayıcı adres özeti döner.
      List<Map<String, dynamic>> availablePackages = [];
      List<Map<String, dynamic>> myPackages = [];
      String? packageError; // UI'da gösterilecek hata özeti
      try {
        final pending = await Supabase.instance.client.rpc(
          'list_available_package_requests',
        );
        availablePackages = List<Map<String, dynamic>>.from(pending as List)
            .map(
              (r) => {
                'id': r['id'],
                'distance_km': r['distance_km'],
                'total_fee': r['total_fee'],
                'courier_fee': r['courier_fee'],
                'delivery_card_label': r['delivery_card_label'],
                'created_at': r['created_at'],
                'offer_id': r['offer_id'],
                'sender_name': r['sender_name'],
                'sender_phone': r['sender_phone'],
                'recipient_name': r['recipient_name'],
                'recipient_phone': r['recipient_phone'],
                'pickup_address': r['pickup_address'],
                'pickup_lat': r['pickup_lat'],
                'pickup_lng': r['pickup_lng'],
                'delivery_address': r['delivery_address'],
                'delivery_address_detail': r['delivery_address_detail'],
                'delivery_lat': r['delivery_lat'],
                'delivery_lng': r['delivery_lng'],
                'is_routed_offer': r['is_routed'] == true,
                '_type': 'package',
              },
            )
            .toList();

        // Atanmış paketler: kendi satırlarımızı RLS üzerinden çekebiliriz.
        // Sadece PII olmayan kolonları istiyoruz; detaylar get_assigned_package_details
        // ile kart açılınca yüklenir.
        final myAccepted = await Supabase.instance.client
            .from('courier_requests')
            .select(
              'id, status, courier_fee, total_fee, admin_commission, created_at, '
              'accepted_at, delivered_at, distance_km, '
              'sender_name, sender_phone, recipient_name, recipient_phone, '
              'pickup_address, pickup_lat, pickup_lng, '
              'delivery_address, delivery_address_detail, delivery_lat, delivery_lng',
            )
            .eq('courier_id', userId)
            .inFilter('status', [
              'accepted',
              'delivered',
              'delivery_pending_confirmation',
            ])
            .order('created_at', ascending: false);
        myPackages = List<Map<String, dynamic>>.from(
          myAccepted as List,
        ).map((r) => {...r, '_type': 'package'}).toList();
      } catch (e) {
        debugPrint('❌ Paket talepleri hatası: $e');
        // Kullanıcı dostu özet. Özellikle 42P01 (tablo yok) ve
        // PGRST202 (PostgREST cache eski) durumları için yönlendirme.
        final msg = e.toString();
        if (msg.contains('42P01') || msg.contains('does not exist')) {
          packageError =
              'Sistemde bir güncelleme gerekiyor (paket tablosu eksik). '
              'Lütfen yöneticiyle iletişime geçin.';
        } else if (msg.contains('PGRST202')) {
          packageError =
              'Şema önbelleği güncelleniyor. Birkaç saniye sonra tekrar '
              'denemek için aşağıya dokunun.';
        } else {
          packageError = 'Paket talepleri yüklenemedi. Tekrar deneyin.';
        }
      }

      setState(() {
        _availableOrders = [...availablePackages, ...availableFiltered];
        _myOrders = [...myPackages, ...myOrdersList];
        _packageError = packageError;
        _isLoading = false;
      });

      if (_focusRequestedTabAfterRefresh && _availableOrders.isNotEmpty) {
        _focusRequestedTabAfterRefresh = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tabController.index != 0) {
            _tabController.animateTo(0);
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Genel hata: $e');
      debugPrint('Stack: $stackTrace');
      if (mounted) setState(() => _isLoading = false);
    } finally {
      _isRefreshing = false;
      if (_refreshQueued && mounted) {
        _refreshQueued = false;
        Future.microtask(_loadOrders);
      }
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
              children: [_buildAvailableOrdersList(), _buildMyOrdersList()],
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
              'Kuryesi olmayan satıcıların siparişleri burada görünür',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _packageError != null
            ? _availableOrders.length + 1
            : _availableOrders.length,
        itemBuilder: (context, index) {
          // İlk item, RPC hata özeti ise bilgi kartı göster
          if (_packageError != null && index == 0) {
            return _buildPackageErrorBanner(_packageError!);
          }
          final orderIndex = _packageError != null ? index - 1 : index;
          final order = _availableOrders[orderIndex];
          if (order['_type'] == 'package')
            return _buildPackageCard(order, isMine: false);
          return _buildAvailableOrderCard(order);
        },
      ),
    );
  }

  Widget _buildAvailableOrderCard(Map<String, dynamic> order) {
    final items = order['order_items'] as List? ?? [];
    final shopName = _shopNameOf(order);
    final orderStatus = order['status'] as String? ?? 'ready';

    // Duruma göre renk ve etiket belirle
    final statusInfo = _getStatusInfo(orderStatus);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showOrderDetails(order),
        borderRadius: BorderRadius.circular(12),
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
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '#${_shortId(order['id'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Durum badge'i
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusInfo['color'] as Color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          statusInfo['label'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '₺${(order['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (order['delivery_address_text'] != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order['delivery_address_text'],
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
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
      ),
    );
  }

  /// Sipariş durumuna göre renk ve etiket döndürür
  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'confirmed':
        return {'color': Colors.blue.shade600, 'label': 'Onaylandı'};
      case 'preparing':
        return {'color': Colors.orange.shade600, 'label': 'Hazırlanıyor'};
      case 'ready':
        return {'color': Colors.green.shade600, 'label': 'Hazır'};
      default:
        return {'color': Colors.grey.shade600, 'label': status};
    }
  }

  /// Atama durumu badge'i oluştur
  Widget _buildAssignmentStatusBadge(Map<String, dynamic> order) {
    final assignmentStatus =
        order['assignment_status'] as String? ?? 'assigned';
    String label;
    Color bgColor;
    Color textColor;

    switch (assignmentStatus) {
      case 'assigned':
        label = 'Teslim Edilecek';
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade800;
        break;
      case 'picked_up':
        label = 'Yolda';
        bgColor = Colors.indigo.shade100;
        textColor = Colors.indigo.shade800;
        break;
      case 'delivered':
        label = 'Teslim Edildi';
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      default:
        label = assignmentStatus;
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  /// Sipariş detaylarını göster
  void _showOrderDetails(Map<String, dynamic> order) {
    final items = order['order_items'] as List? ?? [];
    final shopName = _shopNameOf(order);
    final orderStatus = order['status'] as String? ?? 'ready';
    final statusInfo = _getStatusInfo(orderStatus);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Durum badge'i
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusInfo['color'] as Color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusInfo['label'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '#${_shortId(order['id'])}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '₺${(order['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Teslimat Adresi
              if (order['delivery_address_text'] != null) ...[
                const Text(
                  'Teslimat Adresi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.red.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order['delivery_address_text'],
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Müşteri Bilgileri
              if (order['customer_phone'] != null) ...[
                const Text(
                  'Müşteri Bilgileri',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.phone, color: Colors.grey.shade600, size: 18),
                      const SizedBox(width: 8),
                      Text(order['customer_phone'] ?? ''),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Ürünler
              const Text(
                'Sipariş İçeriği',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...items.map(
                (item) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.teal.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${item['quantity'] ?? 1}x',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item['product_name'] ?? 'Ürün',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Sipariş Al Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _acceptOrder(order);
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Siparişi Al'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
              ),
            ],
          ),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _myOrders.length,
        itemBuilder: (context, index) {
          final order = _myOrders[index];
          if (order['_type'] == 'package')
            return _buildPackageCard(order, isMine: true);
          return _buildMyOrderCard(order);
        },
      ),
    );
  }

  Widget _buildMyOrderCard(Map<String, dynamic> order) {
    final items = order['order_items'] as List? ?? [];
    final shopName = _shopNameOf(order);

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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '#${_shortId(order['id'])}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildAssignmentStatusBadge(order),
              ],
            ),
            const SizedBox(height: 12),
            if (order['delivery_address_text'] != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order['delivery_address_text'],
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
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
              '${items.length} ürün • ₺${(order['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            // Teslim edilmiş siparişlerde buton gösterme
            if (order['assignment_status'] != 'delivered') ...[
              if (order['assignment_status'] == 'assigned') ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectOrderAssignment(order),
                    icon: const Icon(Icons.close),
                    label: const Text('Siparişi Reddet'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Sol tarafta duruma göre adım butonu, sağ tarafta her durumda
              // doğrudan erişilebilen "Teslim Ettim" butonu gösterilir. Böylece
              // kurye ara adımları (aldım/yola çıktım) tamamlamak zorunda kalmadan
              // teslimatı tek dokunuşla bitirebilir.
              Row(
                children: [
                  if (order['assignment_status'] == 'assigned')
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _acceptDelivery(order),
                        icon: const Icon(Icons.delivery_dining, size: 18),
                        label: const Text('Siparişi Aldım'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                    )
                  else if (order['assignment_status'] == 'picked_up')
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _startDelivery(order),
                        icon: const Icon(Icons.two_wheeler, size: 18),
                        label: const Text('Yola Çıktım'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _navigateToAddress(order),
                        icon: const Icon(Icons.navigation, size: 18),
                        label: const Text('Yol Tarifi'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _markAsDelivered(order),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Teslim Ettim'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Teslim edilmiş sipariş bilgisi
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Teslim Edildi',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    final orderId = order['id'];
    try {
      // Sunucu-otoriteli atama (self-accept): p_courier_id gönderilmediğinde
      // RPC auth.uid()'yi atar. courier_assignments INSERT policy'si olmadığı
      // için istemci doğrudan insert edemezdi (42501). RPC ayrıca fee, anti-race
      // (FOR UPDATE + aktif-atama kontrolü), orders.status=on_the_way ve
      // müşteriye tek "yolda" bildirimini atomik yapar.
      final isRoutedOffer = order['is_routed_offer'] == true;
      final result = await Supabase.instance.client.rpc(
        isRoutedOffer ? 'accept_routed_order_offer' : 'assign_order_to_courier',
        params: isRoutedOffer
            ? {'p_offer_id': order['offer_id']}
            : {'p_order_id': orderId},
      );
      final fee = (result is List && result.isNotEmpty)
          ? (((result.first as Map)['r_fee_amount'] as num?)?.toDouble() ?? 0)
          : 0;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sipariş alındı! Teslim ettiğinizde ₺${fee.toStringAsFixed(2)} kazanacaksınız.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        await _loadOrders();
        if (mounted && _tabController.index != 1) {
          _tabController.animateTo(1);
        }
      }
    } catch (e) {
      debugPrint('❌ Sipariş alınırken hata: $e');
      final msg = e.toString();
      final userMsg = msg.contains('already_assigned')
          ? 'Bu sipariş başka bir kurye tarafından alınmış.'
          : 'Sipariş alınamadı: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMsg), backgroundColor: Colors.orange),
        );
        _loadOrders();
      }
    }
  }

  /// Siparişi aldığında çağrılır - picked_up durumuna geçer.
  ///
  /// Müşteriye "Siparişiniz Yolda" bildirimi artık assign_order_to_courier
  /// RPC'sinde TEK SEFER gönderiliyor (atama anında). Eskiden hem _acceptOrder
  /// hem burada g��nderiliyordu (çift bildirim); artık burada gönderilmez.
  Future<void> _acceptDelivery(Map<String, dynamic> order) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final orderId = order['id'] as String?;
      final assignmentId = order['assignment_id'] as String?;
      if (orderId == null) return;

      // Assignment durumunu picked_up yap (RLS UPDATE policy izin verir).
      if (assignmentId != null) {
        await Supabase.instance.client
            .from('courier_assignments')
            .update({'status': 'picked_up'})
            .eq('id', assignmentId);
      } else {
        await Supabase.instance.client
            .from('courier_assignments')
            .update({'status': 'picked_up'})
            .eq('order_id', orderId)
            .eq('courier_id', userId);
      }

      // Sipariş durumunu 'on_the_way' yap (assign RPC zaten yapmış olsa da
      // savunma amaçlı tutulur; satıcı paneli uyumu).
      try {
        await Supabase.instance.client
            .from('orders')
            .update({
              'status': 'on_the_way',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', orderId);
      } catch (e) {
        debugPrint('⚠️ Sipariş status güncellenemedi (kritik değil): $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sipariş alındı. Teslimata çıkabilirsiniz.'),
            backgroundColor: Colors.blue,
          ),
        );
        _loadOrders();
      }
    } catch (e) {
      debugPrint('❌ Sipariş alınırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Yola çıkıldığında çağrılır - on_the_way durumuna geçer
  Future<void> _startDelivery(Map<String, dynamic> order) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final orderId = order['id'] as String?;
      final assignmentId = order['assignment_id'] as String?;
      if (orderId == null) return;

      // Assignment durumunu on_the_way yap
      if (assignmentId != null) {
        await Supabase.instance.client
            .from('courier_assignments')
            .update({'status': 'on_the_way'})
            .eq('id', assignmentId);
      } else {
        await Supabase.instance.client
            .from('courier_assignments')
            .update({'status': 'on_the_way'})
            .eq('order_id', orderId)
            .eq('courier_id', userId);
      }

      // NOT: Müşteriye "Yolda" bildirimi artık yalnızca _acceptDelivery
      // (kurye "Siparişi Aldım" bastığında) içinde gönderiliyor. Burada
      // tekrar gönderilmiyor, böylece çift "Yolda" bildirimi engelleniyor.

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yola çıktınız!'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadOrders();
      }
    } catch (e) {
      debugPrint('❌ Yola çıkılırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _markAsDelivered(Map<String, dynamic> order) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Assignment ID'yi order'dan al (yeni yapı)
      final assignmentId = order['assignment_id'] as String?;

      if (assignmentId == null) {
        // Eski yöntem: assignment'ı bul
        final assignment = await Supabase.instance.client
            .from('courier_assignments')
            .select('id')
            .eq('order_id', order['id'])
            .eq('courier_id', userId)
            .inFilter('status', ['assigned', 'picked_up', 'on_the_way'])
            .maybeSingle();

        if (assignment == null) {
          throw Exception('Atama bulunamadı');
        }

        await _completeDelivery(assignment['id'], order['id'], userId);
      } else {
        await _completeDelivery(assignmentId, order['id'], userId);
      }

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

  /// Teslimatı tamamla (yardımcı metod).
  ///
  /// Sunucu-otoriteli: complete_order_delivery RPC tek atomik işlemde
  ///   * courier_assignments.status='delivered' + delivered_at
  ///   * orders.status='delivered', payment_status='paid', delivered_courier_*
  ///   * profiles.delivered_count + 1 (guard trigger sadece RPC/postgres'i geçer)
  ///   * idempotent courier_earnings (assignment_id unique)
  ///   * müşteri + satıcı teslim bildirimi (add_notification)
  /// yapar. Eski istemci akışı kırıktı: courier_earnings INSERT REVOKE'lu,
  /// delivered_count guard'ı istemci UPDATE'ini engelliyor, satıcı/müşteri
  /// bildirimleri RLS (user_id=auth.uid()) altında bloklanıyordu.
  Future<void> _completeDelivery(
    String assignmentId,
    String orderId,
    String userId,
  ) async {
    await Supabase.instance.client.rpc(
      'complete_order_delivery',
      params: {'p_assignment_id': assignmentId},
    );
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
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$encodedAddress',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendPackagePickupEmail(String requestId) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'send-courier-package-email',
        body: {'request_id': requestId},
      );
      debugPrint(
        '📧 Kurye paket kabul maili: status=${response.status} data=${response.data}',
      );
    } catch (e) {
      // Paket kabulü tamamlandı; e-posta ikincil bir kanal olduğundan ana işlemi
      // başarısız göstermiyoruz. Edge Function başarısız kaydıyla tekrar denenebilir.
      debugPrint('⚠️ Kurye paket kabul e-postası gönderilemedi: $e');
    }
  }

  Future<void> _acceptPackage(Map<String, dynamic> request) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      // Sunucu-otoriteli kabul: courier_id/status/fee sunucuda hesaplanır.
      // İstemci hiçbir finansal veya kimlik alanı göndermez.
      final accepted = await Supabase.instance.client.rpc(
        'accept_package_request',
        params: {'p_request_id': request['id']},
      );
      if ((accepted as List).isEmpty) {
        throw Exception(
          'Talep kabul edilemedi (yetki sorunu veya başka kurye almış olabilir)',
        );
      }

      // Gönderici bildirimi RPC içinde atomiktir. Kuryenin e-postası istemciye
      // açılmadan, JWT doğrulayan Edge Function tarafından gönderilir.
      await _sendPackagePickupEmail(request['id'] as String);
      _loadOrders();
    } catch (e) {
      debugPrint('Paket kabul hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectPackage(Map<String, dynamic> request) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      // Sunucu-otoriteli ret: rejected_by sütununu istemci göndermez; sunucu
      // atomik olarak normalized tabloya ve sütuna ekleme yapar.
      final response = await Supabase.instance.client.rpc(
        'reject_package_request',
        params: {'p_request_id': request['id']},
      );
      final rows = List<Map<String, dynamic>>.from(response as List);
      final nextCourierId = rows.isEmpty
          ? null
          : rows.first['r_next_courier_id'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nextCourierId == null
                  ? 'Paket reddedildi ve kurye havuzuna geri bırakıldı.'
                  : 'Paket başka bir kuryeye yönlendirildi.',
            ),
          ),
        );
      }
      _loadOrders();
    } catch (e) {
      debugPrint('Paket reddetme hatası: $e');
    }
  }

  Future<void> _rejectOrderAssignment(Map<String, dynamic> order) async {
    final assignmentId = order['assignment_id'] as String?;
    if (assignmentId == null) return;

    try {
      final response = await Supabase.instance.client.rpc(
        'reject_order_assignment',
        params: {'p_assignment_id': assignmentId},
      );
      final rows = List<Map<String, dynamic>>.from(response as List);
      final wasReassigned =
          rows.isNotEmpty && rows.first['r_next_courier_id'] != null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasReassigned
                  ? 'Sipariş başka bir kuryeye atandı.'
                  : 'Sipariş reddedildi ve kurye havuzuna geri bırakıldı.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await _loadOrders();
    } catch (e) {
      debugPrint('❌ Sipariş reddetme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sipariş reddedilemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Kurye teslimi doğrudan tamamlar (gönderici onayı yok). Sunucu-otoriteli
  /// complete_package_delivery RPC atomik olarak status='delivered' +
  /// idempotent earnings + delivered_count artışı + göndericiye teslim
  /// bildirimi yapar.
  Future<void> _completePackageDelivery(Map<String, dynamic> request) async {
    try {
      await Supabase.instance.client.rpc(
        'complete_package_delivery',
        params: {'p_request_id': request['id']},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paket teslim edildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadOrders();
    } catch (e) {
      debugPrint('Paket teslim tamamlama hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openPackageLocation(num? lat, num? lng) async {
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu adres için konum bilgisi yok')),
      );
      return;
    }
    final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _buildPackageAddressLine(
    String label,
    dynamic address,
    dynamic lat,
    dynamic lng,
  ) {
    final hasLocation = lat != null && lng != null;
    final addressText = address?.toString().trim();
    final visibleAddress = addressText == null || addressText.isEmpty
        ? 'Adres bilgisi kabul sonrası açılır'
        : addressText;
    return InkWell(
      onTap: () => _openPackageLocation(lat as num?, lng as num?),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '$label: $visibleAddress',
              style: TextStyle(
                fontSize: 13,
                color: hasLocation ? Colors.blue.shade700 : null,
                decoration: hasLocation ? TextDecoration.underline : null,
              ),
            ),
          ),
          if (hasLocation)
            Icon(Icons.map_outlined, size: 16, color: Colors.blue.shade700),
        ],
      ),
    );
  }

  /// Paket kartında telefon satırı (alım = gönderici, teslim = alıcı). Veri
  /// yoksa (henüz kabul edilmemiş paketler) hiçbir şey gösterilmez.
  Widget _buildPackagePhoneLine(String label, dynamic phone) {
    final p = (phone as String?)?.trim();
    if (p == null || p.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(Icons.phone, size: 14, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Text(
            '$label: $p',
            style: TextStyle(fontSize: 12, color: Colors.green.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange.shade800,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange.shade900,
                height: 1.4,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadOrders,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Colors.orange.shade900,
            ),
            child: const Text(
              'Tekrar dene',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(
    Map<String, dynamic> request, {
    required bool isMine,
  }) {
    final totalFee = (request['total_fee'] as num?)?.toDouble() ?? 0;
    final storedCourierFee = (request['courier_fee'] as num?)?.toDouble();
    final storedCommission = (request['admin_commission'] as num?)?.toDouble();
    final courierFee =
        storedCourierFee ?? (totalFee * (1 - _commissionPercent / 100));
    final adminCommission = storedCommission ?? (totalFee - courierFee);
    final pickupLat = request['pickup_lat'] as num?;
    final pickupLng = request['pickup_lng'] as num?;
    final deliveryLat = request['delivery_lat'] as num?;
    final deliveryLng = request['delivery_lng'] as num?;

    // Kayıtlı distance_km yoksa/eksikse koordinatlardan anlık gerçek mesafeyi hesapla
    double? distanceKm = (request['distance_km'] as num?)?.toDouble();
    if ((distanceKm == null || distanceKm == 0) &&
        pickupLat != null &&
        pickupLng != null &&
        deliveryLat != null &&
        deliveryLng != null) {
      final meters = Geolocator.distanceBetween(
        pickupLat.toDouble(),
        pickupLng.toDouble(),
        deliveryLat.toDouble(),
        deliveryLng.toDouble(),
      );
      distanceKm = meters / 1000;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.inventory_2,
                  size: 18,
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 6),
                Text(
                  'Paket - Gönderen: ${request['sender_name'] ?? 'Bilgi kabul sonrası açılır'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildPackageAddressLine(
              'Alım',
              request['pickup_address'],
              pickupLat,
              pickupLng,
            ),
            _buildPackagePhoneLine('Alım Tel', request['sender_phone']),
            _buildPackageAddressLine(
              'Teslim',
              request['delivery_address'],
              deliveryLat,
              deliveryLng,
            ),
            _buildPackagePhoneLine('Teslim Tel', request['recipient_phone']),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  distanceKm != null
                      ? '${distanceKm.toStringAsFixed(1)} km'
                      : '-',
                ),
                Text(
                  'Toplam: ${totalFee.toStringAsFixed(2)} ₺',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Komisyon: -${adminCommission.toStringAsFixed(2)} ₺',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  'Net: ${courierFee.toStringAsFixed(2)} ₺',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            if (request['status'] == 'delivered') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Teslim Edildi',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!isMine)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _rejectPackage(request),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Reddet'),
                      ),
                    ),
                  if (!isMine) const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      // 2026-08-10: Gönderici onayı kaldırıldı. Kabul eden
                      // kurye doğrudan "Teslim Ettim" ile teslimi tamamlar;
                      // sunucu atomik olarak earnings + delivered_count artışı
                      // yapar ve göndericiye bildirim gönderir.
                      onPressed: () => isMine
                          ? _completePackageDelivery(request)
                          : _acceptPackage(request),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(isMine ? 'Teslim Ettim' : 'Kabul Et'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== TESLİMAT GEÇMİŞİ ====================

class CourierDeliveryHistoryScreen extends StatefulWidget {
  const CourierDeliveryHistoryScreen({super.key});

  @override
  State<CourierDeliveryHistoryScreen> createState() =>
      _CourierDeliveryHistoryScreenState();
}

class _CourierDeliveryHistoryScreenState
    extends State<CourierDeliveryHistoryScreen> {
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
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

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

      final assignmentDeliveries = List<Map<String, dynamic>>.from(response);

      List<Map<String, dynamic>> packageDeliveries = [];
      try {
        final packages = await Supabase.instance.client
            .from('courier_requests')
            .select()
            .eq('courier_id', userId)
            .eq('status', 'delivered')
            .order('delivered_at', ascending: false)
            .limit(50);
        packageDeliveries = List<Map<String, dynamic>>.from(
          packages,
        ).map((p) => {...p, '_type': 'package'}).toList();
      } catch (e) {
        debugPrint('Teslim edilen paketler yüklenirken hata: $e');
      }

      final combined = [...assignmentDeliveries, ...packageDeliveries];
      combined.sort((a, b) {
        final aDate = a['delivered_at'] as String? ?? '';
        final bDate = b['delivered_at'] as String? ?? '';
        return bDate.compareTo(aDate);
      });

      setState(() {
        _deliveries = combined;
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
                final isPackage = delivery['_type'] == 'package';

                final title = isPackage
                    ? 'Paket - ${delivery['sender_name'] ?? 'Gönderen'}'
                    : (delivery['orders']?['shops']?['name'] ?? 'Dükkan');
                final fee = isPackage
                    ? (delivery['courier_fee'] as num?)?.toDouble() ?? 0
                    : (delivery['fee_amount'] as num?)?.toDouble() ?? 0;
                final totalFee = isPackage
                    ? (delivery['total_fee'] as num?)?.toDouble() ?? 0
                    : null;
                final commission = isPackage
                    ? (delivery['admin_commission'] as num?)?.toDouble() ?? 0
                    : null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPackage ? Icons.inventory_2 : Icons.check,
                        color: Colors.green.shade700,
                      ),
                    ),
                    title: Text(title),
                    subtitle: Text(
                      isPackage && totalFee != null
                          ? '${delivery['delivered_at'] != null ? _formatDate(delivery['delivered_at']) : '-'}\nToplam ₺${totalFee.toStringAsFixed(2)} • Komisyon -₺${commission!.toStringAsFixed(2)}'
                          : (delivery['delivered_at'] != null
                                ? _formatDate(delivery['delivered_at'])
                                : '-'),
                    ),
                    isThreeLine: isPackage,
                    trailing: Text(
                      '₺${fee.toStringAsFixed(2)}',
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
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Gerçek teslimatlar: sipariş atamaları (sabit ücret) + paket talepleri (komisyonlu)
      List<Map<String, dynamic>> assignmentDeliveries = [];
      try {
        final assignments = await Supabase.instance.client
            .from('courier_assignments')
            .select('id, fee_amount, delivered_at, orders(shops(name))')
            .eq('courier_id', userId)
            .eq('status', 'delivered')
            .order('delivered_at', ascending: false)
            .limit(100);
        assignmentDeliveries = List<Map<String, dynamic>>.from(assignments)
            .map(
              (a) => {
                '_type': 'order',
                'title': a['orders']?['shops']?['name'] ?? 'Sipariş',
                'amount': (a['fee_amount'] as num?)?.toDouble() ?? 0,
                'total_fee': null,
                'commission': null,
                'created_at': a['delivered_at'],
              },
            )
            .toList();
      } catch (e) {
        debugPrint('Sipariş teslimatları yüklenemedi: $e');
      }

      List<Map<String, dynamic>> packageDeliveries = [];
      try {
        final packages = await Supabase.instance.client
            .from('courier_requests')
            .select(
              'id, courier_fee, total_fee, admin_commission, delivered_at, sender_name',
            )
            .eq('courier_id', userId)
            .eq('status', 'delivered')
            .order('delivered_at', ascending: false)
            .limit(100);
        packageDeliveries = List<Map<String, dynamic>>.from(packages)
            .map(
              (p) => {
                '_type': 'package',
                'title': 'Paket - ${p['sender_name'] ?? 'Gönderen'}',
                'amount': (p['courier_fee'] as num?)?.toDouble() ?? 0,
                'total_fee': (p['total_fee'] as num?)?.toDouble(),
                'commission': (p['admin_commission'] as num?)?.toDouble(),
                'created_at': p['delivered_at'],
              },
            )
            .toList();
      } catch (e) {
        debugPrint('Paket teslimatları yüklenemedi: $e');
      }

      final combined = [...assignmentDeliveries, ...packageDeliveries];
      combined.sort(
        (a, b) => (b['created_at'] as String? ?? '').compareTo(
          a['created_at'] as String? ?? '',
        ),
      );

      // Bekleyen ve ödenen tutarlar courier_earnings tablosundaki gerçek
      // durumdan (status) hesaplanır. Eski yöntem "tüm zamanların canlı
      // teslimat tutarı - tüm zamanların ödenen tutarı" şeklindeydi; bu,
      // ödenen tutar geçmişte teslimat tutarını aştığında (örn. sadece
      // paket teslim eden bir kuryenin geçmiş sipariş ödemeleri varsa)
      // her zaman 0'a sabitleniyordu.
      double pending = 0;
      double paid = 0;
      try {
        final earningsRows = await Supabase.instance.client
            .from('courier_earnings')
            .select('amount, status')
            .eq('courier_id', userId);
        for (final row in List<Map<String, dynamic>>.from(earningsRows)) {
          final amount = (row['amount'] as num?)?.toDouble() ?? 0;
          if (row['status'] == 'pending') {
            pending += amount;
          } else if (row['status'] == 'paid') {
            paid += amount;
          }
        }
      } catch (e) {
        debugPrint('Kazanç durumu yüklenemedi: $e');
      }

      setState(() {
        _earnings = combined;
        _totalPending = pending;
        _totalPaid = paid;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Kazançlar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestPayout() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ödeme İsteği'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tahsil edilecek tutar: ₺${_totalPending.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 12),
              const Text(
                'Ödeme isteğiniz admin onayına gönderilecektir.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('İsteği Gönder'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Sunucu-otoriteli payout: amount, status ve requested_at sunucu
      // tarafından belirlenir. İstemci hiçbir finansal değer göndermez.
      // Atomik: pending earnings'ler kilitlenir, payout header + items +
      // earnings status güncellemesi tek transaction'da yapılır.
      final payoutResult = await Supabase.instance.client.rpc(
        'request_courier_payout',
        params: {
          // request_courier_payout(p_idempotency_key uuid) — geçerli v4 UUID
          // zorunlu. Eski kod 'ts-userId' biçiminde string gönderiyordu ve
          // PostgREST bunu uuid'e cast edemeyip 22P02 ile patlıyordu.
          'p_idempotency_key': const Uuid().v4(),
        },
      );

      // Admin bildirimi/email (RPC zaten notifications tablosuna yazdı;
      // bu yalnızca e-posta için ek bir bildirim)
      try {
        final courierProfile = await Supabase.instance.client
            .from('profiles')
            .select('full_name, username')
            .eq('id', userId)
            .maybeSingle();
        final courierName =
            courierProfile?['full_name'] ??
            courierProfile?['username'] ??
            'Kurye';
        final payoutAmount = (payoutResult as List).isNotEmpty
            ? ((payoutResult.first as Map)['amount'] as num?)?.toDouble() ??
                  _totalPending
            : _totalPending;

        await EmailService().sendCourierPayoutRequestEmailToAdmin(
          courierName: courierName,
          amount: payoutAmount,
        );
      } catch (e) {
        debugPrint('⚠️ Admin email gönderilemedi: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ödeme isteğiniz gönderildi!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadEarnings();
      }
    } catch (e) {
      debugPrint('Ödeme isteği hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
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
                            _buildEarningStat(
                              'Teslimat',
                              '${_earnings.length}',
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white24,
                            ),
                            _buildEarningStat(
                              'Ödenen',
                              '₺${_totalPaid.toStringAsFixed(2)}',
                            ),
                          ],
                        ),
                        if (_totalPending > 0) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _requestPayout(),
                              icon: const Icon(Icons.payments),
                              label: Text(
                                'Ödeme İste (₺${_totalPending.toStringAsFixed(2)})',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Detaylar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
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
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final earning = _earnings[index];
                      final isPackage = earning['_type'] == 'package';
                      final totalFee = earning['total_fee'] as double?;
                      final commission = earning['commission'] as double?;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          isThreeLine: isPackage && totalFee != null,
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPackage ? Icons.inventory_2 : Icons.check,
                              color: Colors.green.shade700,
                            ),
                          ),
                          title: Text(
                            earning['title'] as String? ??
                                (isPackage ? 'Paket' : 'Sipariş'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            isPackage && totalFee != null && commission != null
                                ? '${earning['created_at'] != null ? _formatDate(earning['created_at']) : '-'}\nToplam ₺${totalFee.toStringAsFixed(2)} • Komisyon -₺${commission.toStringAsFixed(2)}'
                                : (earning['created_at'] != null
                                      ? _formatDate(earning['created_at'])
                                      : '-'),
                          ),
                          trailing: Text(
                            '₺${(earning['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      );
                    }, childCount: _earnings.length),
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
