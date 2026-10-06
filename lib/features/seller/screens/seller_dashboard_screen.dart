// ignore_for_file: use_build_context_synchronously

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/address_model.dart';
import '../../../core/models/seller_announcement_model.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/widgets/lazy_tab_stack.dart';
import '../../market/screens/address_picker_screen.dart';
import '../services/payout_service.dart';
import '../services/shop_analytics_service.dart';
import '../utils/shop_contact_requirements.dart';
import '../widgets/common/seller_bottom_nav.dart';
import '../widgets/dashboard/seller_menu.dart';
import '../widgets/dashboard/seller_more_tab.dart';
import '../widgets/dashboard/seller_overview_tab.dart';
import '../widgets/dashboard/seller_payments_tab.dart';
import 'coupons_screen.dart';
import 'products_screen.dart';
import 'seller_orders_screen.dart';
import 'seller_reports_screen.dart';
import 'seller_reviews_screen.dart';
import 'shop_settings_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

/// Alt navigasyon öğeleri: 0=Genel Bakış, 1=Ürünler, 2=Siparişler, 3=Ödemeler,
/// 4=Diğer. Alt bar HER ZAMAN sabit kalsın diye beşi de [LazyTabStack] içinde
/// gömülü tutulur; kendi Scaffold/AppBar'ı olan Ürünler/Siparişler/Diğer ise
/// kendi tam-ekran alt akışlarını (ürün düzenle, kupon oluştur vb.) sürdürsün
/// diye ayrıca kendi iç [Navigator]'ına sarılır — bottom nav bu iç sayfalarda
/// da görünür kalır, sadece o sekmenin içeriği değişir.

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  late final PayoutService _payoutService;
  final ShopAnalyticsService _analyticsService = ShopAnalyticsService();

  bool _isLoading = true;
  bool _isAcceptingOrders = true;
  int _navIndex = 0;

  // Ürünler/Siparişler/Diğer'in kendi iç gezinme yığınları — alt bar sabit
  // kalırken bu sekmeler içinde push/pop yapabilmek için (bkz. yukarıdaki not).
  final _productsNavKey = GlobalKey<NavigatorState>();
  final _ordersNavKey = GlobalKey<NavigatorState>();
  final _moreNavKey = GlobalKey<NavigatorState>();

  // Yan menüyü (endDrawer) açıp kapatmak ve geri tuşunda kapatmak için.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Dashboard verileri
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _topProducts = [];
  int _totalViews = 0;
  int _totalFavorites = 0;

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
    _payoutService = PayoutService(_supabase);
    _loadDashboardData();
  }

  /// Aynı anda iki yükleme olursa (ör. "Diğer"den dönüş + aşağı çekme)
  /// ekrana yalnız en sonuncusu yazar.
  int _loadSeq = 0;

  /// Panel verileri. Tam ekran spinner YALNIZ ilk yüklemede gösterilir;
  /// sonraki yenilemeler (aşağı çekme, "Diğer"deki bir sayfadan dönüş,
  /// IBAN/ödeme işlemleri) ekranı yerinde günceller. Eskiden her yenileme
  /// gövdeyi spinner'a çevirip sekmeleri ve iç sayfa yığınlarını sıfırlıyor,
  /// alt bar da ~15 ARDIŞIK istek boyunca kayboluyordu (Görev 1.5). Mağaza
  /// bulunduktan sonraki istekler birbirinden bağımsız olduğundan PARALEL.
  Future<void> _loadDashboardData() async {
    final seq = ++_loadSeq;
    final hasData = _shopInfo != null || _stats.isNotEmpty;
    if (!hasData && !_isLoading) setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('🔴 [_loadDashboardData] HATA: userId null - giriş yapılmamış olabilir');
        return;
      }

      // Satıcının mağazasını bul
      final shopResponse = await _supabase
          .from('shops')
          .select('id, name, phone, latitude, longitude, iban, bank_name, account_holder_name, pending_payout, total_paid, commission_rate, has_own_courier, delivery_fee, logo_url, is_accepting_orders, admin_credit, commission_debt, cash_payment_revenue, online_payment_revenue')
          .eq('owner_id', userId)
          .maybeSingle();
      if (!mounted || seq != _loadSeq) return;

      if (shopResponse == null) {
        debugPrint('🔴 [_loadDashboardData] HATA: Satıcıya ait mağaza yok! userId=$userId');
        setState(() {
          _stats = {'hasShop': false};
          _isLoading = false;
        });
        return;
      }

      final shopId = shopResponse['id'] as String;
      _shopInfo = Map<String, dynamic>.from(shopResponse);
      _hasOwnCourier = shopResponse['has_own_courier'] as bool? ?? false;
      _isAcceptingOrders = shopResponse['is_accepting_orders'] as bool? ?? true;

      // Ödeme/istatistik parçaları eskisi gibi hata verirse varsayılana düşer;
      // sayılar ve listeler hata verirse yenileme iptal olur, eski veri kalır.
      Future<T> orDefault<T>(
        String label,
        Future<T> Function() load,
        T fallback,
      ) async {
        try {
          return await load();
        } catch (e) {
          debugPrint('🔴 [_loadDashboardData] $label HATASI: $e');
          return fallback;
        }
      }

      final results = await Future.wait<Object?>([
        // 0-1: sayılar — satırları indirmeden, yalnız sayı (HEAD + count)
        _supabase.from('orders').count(CountOption.exact).eq('shop_id', shopId),
        _supabase.from('products').count(CountOption.exact).eq('shop_id', shopId),
        // 2: son siparişler
        _supabase
            .from('orders')
            .select('*, profiles!orders_user_id_fkey(full_name)')
            .eq('shop_id', shopId)
            .order('created_at', ascending: false)
            .limit(5),
        // 3: son eklenen ürünler
        _supabase
            .from('products')
            .select('*')
            .eq('shop_id', shopId)
            .order('created_at', ascending: false)
            .limit(5),
        // 4: gelir özeti (tek sorgu ile tüm gelir verileri)
        orDefault(
          'Gelir özeti',
          () => _payoutService.getRevenueSummary(shopId),
          <String, dynamic>{},
        ),
        // 5-6: bekleyen / toplam ödenen
        orDefault(
          'Bekleyen ödeme',
          () => _payoutService.getPendingPayoutAmount(shopId),
          0.0,
        ),
        orDefault(
          'Toplam ödenen',
          () => _payoutService.getTotalPaidAmount(shopId),
          0.0,
        ),
        // 7-8: toplam görüntülenme + beğeni
        orDefault(
          'Toplam görüntülenme',
          () => _analyticsService.getShopTotalViews(shopId),
          0,
        ),
        orDefault(
          'Toplam beğeni',
          () => _analyticsService.getShopTotalFavorites(shopId),
          0,
        ),
        // 9-10: ödeme istekleri + bekleyenlerin toplamı
        orDefault(
          'Ödeme istekleri',
          () => _payoutService.getPayoutRequests(userId),
          <Map<String, dynamic>>[],
        ),
        orDefault(
          'Bekleyen istekler',
          () => _payoutService.getPendingPayoutRequestsTotal(userId),
          0.0,
        ),
      ]);
      if (!mounted || seq != _loadSeq) return;

      final revenueSummary = results[4] as Map<String, dynamic>;
      final pendingPayout = results[5] as double;
      final pendingRequestsTotal = results[10] as double;
      // Kullanılabilir ödeme tutarı
      final availablePayout = pendingPayout - pendingRequestsTotal;

      setState(() {
        _stats = {
          'hasShop': true,
          'ordersCount': results[0] as int,
          'productsCount': results[1] as int,
        };
        _recentOrders = List<Map<String, dynamic>>.from(results[2] as List);
        _topProducts = List<Map<String, dynamic>>.from(results[3] as List);
        _revenueSummary = revenueSummary;
        _adminCredit =
            (revenueSummary['admin_credit'] as num?)?.toDouble() ?? 0;
        _commissionDebt =
            (revenueSummary['commission_debt'] as num?)?.toDouble() ?? 0;
        _cashPaymentRevenue =
            (revenueSummary['cash_payment_revenue'] as num?)?.toDouble() ?? 0;
        _onlinePaymentRevenue =
            (revenueSummary['online_payment_revenue'] as num?)?.toDouble() ??
            0;
        _pendingPayout = pendingPayout;
        _totalPaid = results[6] as double;
        _totalViews = results[7] as int;
        _totalFavorites = results[8] as int;
        _payoutRequests = results[9] as List<Map<String, dynamic>>;
        _pendingRequestsTotal = pendingRequestsTotal;
        _availablePayout = availablePayout < 0 ? 0 : availablePayout;
        _isLoading = false;
      });
      debugPrint('🟢 [_loadDashboardData] BAŞARIYLA TAMAMLANDI');
    } catch (e, stack) {
      debugPrint('🔴 [_loadDashboardData] CATCH BLOĞU - HATA: $e');
      debugPrint('🔴 [_loadDashboardData] STACK TRACE: $stack');
      if (mounted && seq == _loadSeq) setState(() => _isLoading = false);
    }
  }

  /// Görünen sekmenin kendi iç [Navigator]'ı (Ürünler/Siparişler/Diğer);
  /// diğer sekmelerde null. Gizli sekmede açık kalan sayfa geriyi yutmaz.
  NavigatorState? get _activeTabNavigator => switch (_navIndex) {
    1 => _productsNavKey.currentState,
    2 => _ordersNavKey.currentState,
    4 => _moreNavKey.currentState,
    _ => null,
  };

  /// Geri (üstteki ok / Android geri tuşu). Önce görünen sekmenin kendi
  /// yığını kullanır: iç sayfayı kapatır ya da o sayfanın kendi PopScope'u
  /// işler (ör. Ürünler'de çoklu seçimden çıkma). Kullanmazsa panel kapanır.
  ///
  /// Paneli kapatmak için `maybePop` ÇAĞRILMAZ: bu PopScope `canPop: false`
  /// olduğundan maybePop yine bu işleyiciyi tetikliyordu; bu sonsuz döngü
  /// uygulamayı tamamen donduruyordu (Görev 1.5).
  Future<void> _handleBack() async {
    // Yan menü açıksa geri onu kapatır. (PopScope canPop:false olduğundan
    // menünün kendi "geri ile kapan" kaydı çalışmaz; kapatmak bize düşer.)
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isEndDrawerOpen) {
      scaffold.closeEndDrawer();
      return;
    }
    final tab = _activeTabNavigator;
    if (tab != null && await tab.maybePop()) return;
    if (!mounted) return;
    // Bu arada üstte başka bir sayfa/diyalog açıldıysa ona dokunma.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    // Girişten sonra panel kök sayfa olarak açılır; kökte pop boş yığın
    // (siyah ekran) bırakırdı, bu yüzden ana sayfaya döner.
    AppNavigator.popOrGo(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    final hasShop = _stats['hasShop'] != false;
    final showNav = !_isLoading && hasShop;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      key: _scaffoldKey,
      // Sağdan açılır: soldaki geri oku yerinde kalsın.
      endDrawer: showNav ? _buildSideMenu() : null,
      appBar: AppBar(
        title: const Text('Satıcı Paneli'),
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
          if (showNav)
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Menü',
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !hasShop
              ? _buildNoShopView()
              : SellerPanelInfo(
                  shopInfo: _shopInfo,
                  isAcceptingOrders: _isAcceptingOrders,
                  child: _buildShell(),
                ),
      bottomNavigationBar: showNav
          ? SellerBottomNav(
              currentIndex: _navIndex,
              onTap: _onNavTap,
              items: const [
                SellerNavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Genel Bakış'),
                SellerNavItem(icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: 'Ürünler'),
                SellerNavItem(icon: Icons.shopping_bag_outlined, activeIcon: Icons.shopping_bag, label: 'Siparişler'),
                SellerNavItem(icon: Icons.payments_outlined, activeIcon: Icons.payments, label: 'Ödemeler'),
                SellerNavItem(icon: Icons.more_horiz, activeIcon: Icons.more_horiz, label: 'Diğer'),
              ],
            )
          : null,
      ),
    );
  }

  /// Ürünler/Siparişler/Diğer sekmeleri kendi iç [Navigator]'ına sarılır:
  /// bu ekranlar iç akışlarında (ürün düzenle, kupon oluştur, iade detayı
  /// vb.) `Navigator.push` kullandığında bu, dış paneli değil bu iç yığını
  /// büyütür — dolayısıyla alt bar her zaman görünür/sabit kalır.
  Widget _buildShell() {
    return LazyTabStack(
      index: _navIndex,
      count: 5,
      retained: const {0, 1, 2, 3, 4},
      tabBuilder: (index) {
        switch (index) {
          case 0:
            return SellerOverviewTab(
              shopInfo: _shopInfo,
              isAcceptingOrders: _isAcceptingOrders,
              onToggleAcceptingOrders: _toggleAcceptingOrders,
              hasOwnCourier: _hasOwnCourier,
              ordersCount: (_stats['ordersCount'] as int?) ?? 0,
              productsCount: (_stats['productsCount'] as int?) ?? 0,
              cashPaymentRevenue: _cashPaymentRevenue,
              onlinePaymentRevenue: _onlinePaymentRevenue,
              adminCredit: _adminCredit,
              commissionDebt: _commissionDebt,
              recentOrders: _recentOrders,
              topProducts: _topProducts,
              totalViews: _totalViews,
              totalFavorites: _totalFavorites,
              onAnnouncementAction: _handleAnnouncementAction,
              onOpenProducts: () => _onNavTap(1),
              onRefresh: _loadDashboardData,
              onCompleteShopInfo: _openShopSettingsForContact,
            );
          case 1:
            return Navigator(
              key: _productsNavKey,
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (context) => const ProductsScreen(),
              ),
            );
          case 2:
            return Navigator(
              key: _ordersNavKey,
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (context) => const SellerOrdersScreen(),
              ),
            );
          case 3:
            return SellerPaymentsTab(
              shopInfo: _shopInfo,
              payoutService: _payoutService,
              pendingPayout: _pendingPayout,
              totalPaid: _totalPaid,
              availablePayout: _availablePayout,
              pendingRequestsTotal: _pendingRequestsTotal,
              adminCredit: _adminCredit,
              hasOwnCourier: _hasOwnCourier,
              payoutRequests: _payoutRequests,
              onEditIban: _showIbanEditDialog,
              onCreatePayoutRequest: _showCreatePayoutDialog,
              onCancelPayoutRequest: _cancelPayoutRequest,
            );
          case 4:
          default:
            return Navigator(
              key: _moreNavKey,
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (context) => SellerMoreTab(
                  shopInfo: _shopInfo,
                  onManageCategories: _showCategoryManagement,
                  onReturnRefresh: _loadDashboardData,
                ),
              ),
            );
        }
      },
    );
  }

  void _onNavTap(int index) => setState(() => _navIndex = index);

  /// Yan menünün üstündeki panel bölümleri — alt bardaki sekmelerle aynı sıra.
  static const _sideMenuSections = [
    SellerMenuSection(icon: Icons.dashboard_outlined, label: 'Genel Bakış'),
    SellerMenuSection(icon: Icons.inventory_2_outlined, label: 'Ürünler'),
    SellerMenuSection(icon: Icons.shopping_bag_outlined, label: 'Siparişler'),
    SellerMenuSection(icon: Icons.payments_outlined, label: 'Ödemeler'),
    SellerMenuSection(icon: Icons.more_horiz, label: 'Diğer'),
  ];

  /// Sağdan açılan yan menü (Görev 2.4): "Diğer" sekmesiyle AYNI menü, üstte
  /// panel bölümleri. Alt bar yerinde kalır; menü her sekmeden erişim sağlar.
  Widget _buildSideMenu() {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.88, 380.0);
    return Drawer(
      width: width,
      backgroundColor: const Color(0xFFF6F5FA),
      child: SafeArea(
        child: SellerMenu(
          shopInfo: _shopInfo,
          isAcceptingOrders: _isAcceptingOrders,
          content: SellerMenuContent.forShop(
            shopInfo: _shopInfo,
            onManageCategories: _showCategoryManagement,
          ),
          sections: _sideMenuSections,
          currentSection: _navIndex,
          onSection: (index) {
            _scaffoldKey.currentState?.closeEndDrawer();
            _onNavTap(index);
          },
          onOpen: (_, entry) => _openFromSideMenu(entry),
        ),
      ),
    );
  }

  /// Yan menüden seçilen araç "Diğer" sekmesinin iç yığınında açılır: alt bar
  /// görünür kalır ve geri önce o sayfayı kapatır — sekmeden açılmışla aynı.
  void _openFromSideMenu(SellerMenuEntry entry) {
    _scaffoldKey.currentState?.closeEndDrawer();
    if (entry.page == null) {
      entry.action?.call(context);
      return;
    }
    setState(() => _navIndex = 4);
    // "Diğer" sekmesi ilk kez açılıyorsa iç Navigator'ı bu karede kurulur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _moreNavKey.currentState;
      if (!mounted || navigator == null) return;
      navigator.popUntil((route) => route.isFirst);
      openSellerMenuEntry(
        context: context,
        navigator: navigator,
        entry: entry,
        onReturnRefresh: _loadDashboardData,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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
          width: MediaQuery.sizeOf(context).width * 0.9,
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

  Widget _buildNoShopView() {
    final primary = Theme.of(context).colorScheme.primary;
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
                backgroundColor: primary,
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

  /// Yönetimden gelen duyuru kartının eylem butonu: ilgili ekrana götürür.
  Future<void> _handleAnnouncementAction(SellerAnnouncement a) async {
    Future<void> open(Widget screen) async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen),
      );
      if (mounted) _loadDashboardData();
    }

    switch (a.actionTarget) {
      case AnnouncementTarget.products:
        setState(() => _navIndex = 1);
        return;
      case AnnouncementTarget.orders:
        setState(() => _navIndex = 2);
        return;
      case AnnouncementTarget.coupons:
        return open(const CouponsScreen());
      case AnnouncementTarget.reviews:
        return open(const SellerReviewsScreen());
      case AnnouncementTarget.shopSettings:
        return open(const ShopSettingsScreen());
      case AnnouncementTarget.payments:
        setState(() => _navIndex = 3);
        return;
      case AnnouncementTarget.url:
        final uri = Uri.tryParse(a.actionUrl ?? '');
        if (uri == null || uri.scheme != 'https') return;
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlantı açılamadı')),
          );
        }
        return;
      case null:
        return;
    }
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
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(context);
                      messenger.showSnackBar(
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
    final primary = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet, color: primary),
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

              if (!_hasOwnCourier) ...[
                // Kuryesi olmayan satıcılar için teslimat ücreti kesintisi bilgisi
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
                      Icon(Icons.local_shipping, color: Colors.orange.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Kuryeniz olmadığı için teslimat ücretleri, admin tarafından '
                          'siparişlerden zaten kesilmiş olarak bu tutara yansımıştır. '
                          'İsteği oluşturduğunuzda kesinti detayını görebilirsiniz.',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

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
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(
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

  /// Mağaza oluştur (Görev 3.7): telefon ve haritadan konum ZORUNLU —
  /// sunucu da bunlarsız mağaza açılmasını reddeder.
  void _showCreateShopDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final phoneController = TextEditingController();
    final primary = Theme.of(context).colorScheme.primary;
    double? latitude;
    double? longitude;
    String? address;
    String? phoneError;
    var saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Mağaza Oluştur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Telefon *',
                    hintText: '0532 123 45 67',
                    prefixIcon: const Icon(Icons.phone),
                    border: const OutlineInputBorder(),
                    errorText: phoneError,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final result = await Navigator.of(dialogContext).push<Address>(
                            MaterialPageRoute(
                              builder: (_) => AddressPickerScreen(
                                initialLatitude: latitude,
                                initialLongitude: longitude,
                                warningBanner:
                                    'Lütfen dükkanınızın gerçek konumunu işaretleyin. Müşteriler ve kurye, siparişleri bu noktaya göre bulur.',
                              ),
                            ),
                          );
                          final lat = result?.latitude;
                          final lng = result?.longitude;
                          if (lat == null || lng == null) return;
                          setDialogState(() {
                            latitude = lat;
                            longitude = lng;
                            address = result!.fullAddress;
                          });
                        },
                  icon: Icon(
                    latitude == null ? Icons.map_outlined : Icons.check_circle,
                    color: latitude == null ? null : Colors.green.shade700,
                  ),
                  label: Text(latitude == null ? 'Haritadan Konum Seç *' : 'Konum seçildi — değiştir'),
                ),
                if (latitude == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Konum zorunlu: kurye ve müşteri mağazanı bu noktaya göre bulur.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
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
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
              ),
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final description = descriptionController.text.trim();
                      final phone = phoneController.text.trim();

                      if (name.isEmpty) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Mağaza adı gerekli')),
                        );
                        return;
                      }
                      final phoneMessage = ShopContactRequirements.phoneError(phone);
                      if (phoneMessage != null) {
                        setDialogState(() => phoneError = phoneMessage);
                        return;
                      }
                      if (latitude == null || longitude == null) {
                        setDialogState(() => phoneError = null);
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Mağaza konumunu haritadan seçin')),
                        );
                        return;
                      }
                      setDialogState(() {
                        phoneError = null;
                        saving = true;
                      });

                      try {
                        final userId = Supabase.instance.client.auth.currentUser?.id;
                        if (userId == null) throw Exception('Kullanıcı bulunamadı');

                        await Supabase.instance.client.from('shops').insert({
                          'owner_id': userId,
                          'name': name,
                          'slug': name.toLowerCase().replaceAll(' ', '-'),
                          'description': description.isEmpty ? null : description,
                          'phone': phone,
                          'latitude': latitude,
                          'longitude': longitude,
                          'address': address,
                          'is_active': true,
                          'is_approved': false, // Admin onayı bekleyecek
                          'is_verified': false,
                          'commission_rate': 10.0,
                          'min_order_amount': 0.0,
                          'delivery_fee': 0.0,
                        });

                        if (!mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Mağaza oluşturuldu! Admin onayı bekleniyor...'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _loadDashboardData();
                      } catch (e) {
                        debugPrint('Mağaza oluşturulurken hata: $e');
                        setDialogState(() => saving = false);
                        final hinted = e is PostgrestException
                            ? ShopContactRequirements.messageForHint(e.hint)
                            : null;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(hinted ?? 'Hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
  }

  /// Eksik telefon/konum şeridinden: mağaza ayarları, dönünce panel tazelenir.
  Future<void> _openShopSettingsForContact() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShopSettingsScreen()),
    );
    if (mounted) await _loadDashboardData();
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
    final primary = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.white,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
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
                    Icon(Icons.category, color: primary),
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
                              color: primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.label, size: 14, color: primary),
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
                      icon: Icon(Icons.add_circle, color: primary),
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
                      backgroundColor: primary,
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
