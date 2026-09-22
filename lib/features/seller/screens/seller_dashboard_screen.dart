// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/seller_announcement_model.dart';
import '../../../core/widgets/lazy_tab_stack.dart';
import '../services/payout_service.dart';
import '../services/shop_analytics_service.dart';
import '../widgets/common/seller_bottom_nav.dart';
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

  Future<void> _loadDashboardData() async {
    debugPrint('🔵 [_loadDashboardData] Başladı');
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      debugPrint('🔵 [_loadDashboardData] userId: $userId');
      if (userId == null) {
        debugPrint('🔴 [_loadDashboardData] HATA: userId null - giriş yapılmamış olabilir');
        return;
      }

      // Satıcının mağazasını bul
      debugPrint('🔵 [_loadDashboardData] Mağaza sorgulanıyor...');
      final shopResponse = await _supabase
          .from('shops')
          .select('id, name, iban, bank_name, account_holder_name, pending_payout, total_paid, commission_rate, has_own_courier, delivery_fee, logo_url, is_accepting_orders, admin_credit, commission_debt, cash_payment_revenue, online_payment_revenue')
          .eq('owner_id', userId)
          .maybeSingle();
      debugPrint('🔵 [_loadDashboardData] Mağaza sonucu: ${shopResponse != null ? "BULUNDU (id: ${shopResponse['id']})" : "BULUNAMADI"}');

      if (shopResponse == null) {
        debugPrint('🔴 [_loadDashboardData] HATA: Satıcıya ait mağaza yok! userId=$userId');
        if (!mounted) return;
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
      debugPrint('🔵 [_loadDashboardData] Shop ID: $shopId, hasOwnCourier: $_hasOwnCourier');
      debugPrint('🔵 [_loadDashboardData] admin_credit: ${shopResponse['admin_credit']}, commission_debt: ${shopResponse['commission_debt']}');
      debugPrint('🔵 [_loadDashboardData] cash_payment_revenue: ${shopResponse['cash_payment_revenue']}, online_payment_revenue: ${shopResponse['online_payment_revenue']}');

      // İstatistikleri yükle
      debugPrint('🔵 [_loadDashboardData] Siparişler sorgulanıyor...');
      final ordersResult = await _supabase
          .from('orders')
          .select('id')
          .eq('shop_id', shopId);
      debugPrint('🔵 [_loadDashboardData] Sipariş sayısı: ${(ordersResult as List).length}');

      debugPrint('🔵 [_loadDashboardData] Ürünler sorgulanıyor...');
      final productsResult = await _supabase
          .from('products')
          .select('id')
          .eq('shop_id', shopId);
      debugPrint('🔵 [_loadDashboardData] Ürün sayısı: ${(productsResult as List).length}');

      // Son siparişler
      debugPrint('🔵 [_loadDashboardData] Son siparişler sorgulanıyor...');
      final orders = await _supabase
          .from('orders')
          .select('*, profiles!orders_user_id_fkey(full_name)')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false)
          .limit(5);
      debugPrint('🔵 [_loadDashboardData] Son siparişler: ${(orders as List).length} adet');

      // En çok satılan ürünler
      debugPrint('🔵 [_loadDashboardData] Ürünler sorgulanıyor...');
      final products = await _supabase
          .from('products')
          .select('*')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false)
          .limit(5);
      debugPrint('🔵 [_loadDashboardData] Ürünler: ${(products as List).length} adet');

      // Gelir özeti (YENİ - tek sorgu ile tüm gelir verileri)
      debugPrint('🔵 [_loadDashboardData] Gelir özeti sorgulanıyor...');
      try {
        _revenueSummary = await _payoutService.getRevenueSummary(shopId);
        debugPrint('🔵 [_loadDashboardData] Gelir özeti başarılı: $_revenueSummary');
      } catch (e) {
        debugPrint('🔴 [_loadDashboardData] Gelir özeti HATASI: $e');
        _revenueSummary = {};
      }

      debugPrint('🔵 [_loadDashboardData] Bekleyen ödeme tutarı sorgulanıyor...');
      try {
        _pendingPayout = await _payoutService.getPendingPayoutAmount(shopId);
        debugPrint('🔵 [_loadDashboardData] Bekleyen ödeme: $_pendingPayout');
      } catch (e) {
        debugPrint('🔴 [_loadDashboardData] Bekleyen ödeme HATASI: $e');
        _pendingPayout = 0;
      }

      debugPrint('🔵 [_loadDashboardData] Toplam ödenen sorgulanıyor...');
      try {
        _totalPaid = await _payoutService.getTotalPaidAmount(shopId);
        debugPrint('🔵 [_loadDashboardData] Toplam ödenen: $_totalPaid');
      } catch (e) {
        debugPrint('🔴 [_loadDashboardData] Toplam ödenen HATASI: $e');
        _totalPaid = 0;
      }

      // Toplam görüntülenme + beğeni (satıcı paneli yeni özellik)
      debugPrint('🔵 [_loadDashboardData] Toplam görüntülenme sorgulanıyor...');
      var totalViews = 0;
      try {
        totalViews = await _analyticsService.getShopTotalViews(shopId);
      } catch (e) {
        debugPrint('🔴 [_loadDashboardData] Toplam görüntülenme HATASI: $e');
      }
      debugPrint('🔵 [_loadDashboardData] Toplam beğeni sorgulanıyor...');
      var totalFavorites = 0;
      try {
        totalFavorites = await _analyticsService.getShopTotalFavorites(shopId);
      } catch (e) {
        debugPrint('🔴 [_loadDashboardData] Toplam beğeni HATASI: $e');
      }

      // Değişkenleri ata
      final adminCredit = (_revenueSummary?['admin_credit'] as num?)?.toDouble() ?? 0;
      final commissionDebt = (_revenueSummary?['commission_debt'] as num?)?.toDouble() ?? 0;
      final cashRevenue = (_revenueSummary?['cash_payment_revenue'] as num?)?.toDouble() ?? 0;
      final onlineRevenue = (_revenueSummary?['online_payment_revenue'] as num?)?.toDouble() ?? 0;
      debugPrint('🔵 [_loadDashboardData] Hesaplanan değerler: adminCredit=$adminCredit, commissionDebt=$commissionDebt, cashRevenue=$cashRevenue, onlineRevenue=$onlineRevenue');

      // Ödeme isteklerini yükle
      debugPrint('🔵 [_loadDashboardData] Ödeme istekleri sorgulanıyor...');
      try {
        _payoutRequests = await _payoutService.getPayoutRequests(userId);
        debugPrint('🔵 [_loadDashboardData] Ödeme istekleri: ${_payoutRequests.length} adet');
      } catch (e) {
        debugPrint('🔴 [_loadDashboardData] Ödeme istekleri HATASI: $e');
        _payoutRequests = [];
      }

      // Bekleyen ödeme isteklerinin toplam tutarını hesapla
      debugPrint('🔵 [_loadDashboardData] Bekleyen istekler toplamı sorgulanıyor...');
      try {
        _pendingRequestsTotal = await _payoutService.getPendingPayoutRequestsTotal(userId);
        debugPrint('🔵 [_loadDashboardData] Bekleyen istekler toplamı: $_pendingRequestsTotal');
      } catch (e) {
        debugPrint('🔴 [_loadDashboardData] Bekleyen istekler HATASI: $e');
        _pendingRequestsTotal = 0;
      }

      // Kullanılabilir ödeme tutarı
      _availablePayout = _pendingPayout - _pendingRequestsTotal;
      if (_availablePayout < 0) _availablePayout = 0;
      debugPrint('🔵 [_loadDashboardData] Kullanılabilir ödeme: $_availablePayout');

      if (!mounted) return;
      setState(() {
        _stats = {
          'hasShop': true,
          'ordersCount': (ordersResult as List).length,
          'productsCount': (productsResult as List).length,
        };
        // Gelir değerlerini setState içinde atayarak UI'ın güncellenmesini sağlıyoruz.
        _adminCredit = adminCredit;
        _commissionDebt = commissionDebt;
        _cashPaymentRevenue = cashRevenue;
        _onlinePaymentRevenue = onlineRevenue;
        _revenueSummary = _revenueSummary;
        _pendingPayout = _pendingPayout;
        _totalPaid = _totalPaid;
        _payoutRequests = _payoutRequests;
        _pendingRequestsTotal = _pendingRequestsTotal;
        _availablePayout = _availablePayout;
        _recentOrders = List<Map<String, dynamic>>.from(orders);
        _topProducts = List<Map<String, dynamic>>.from(products);
        _totalViews = totalViews;
        _totalFavorites = totalFavorites;
        _isLoading = false;
      });
      debugPrint('🟢 [_loadDashboardData] BAŞARIYLA TAMAMLANDI');
    } catch (e, stack) {
      debugPrint('🔴 [_loadDashboardData] CATCH BLOĞU - HATA: $e');
      debugPrint('🔴 [_loadDashboardData] STACK TRACE: $stack');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Sekmenin kendi iç [Navigator]'ı varsa (Ürünler/Siparişler/Diğer) ve
  /// içinde geri gidebileceği bir sayfa varsa önce onu kapatır; yoksa `false`
  /// döner ki sistem geri tuşu paneli normal şekilde kapatabilsin.
  Future<bool> _maybePopActiveTab() async {
    final key = switch (_navIndex) {
      1 => _productsNavKey,
      2 => _ordersNavKey,
      4 => _moreNavKey,
      _ => null,
    };
    final navState = key?.currentState;
    if (navState != null && navState.canPop()) {
      navState.pop();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final hasShop = _stats['hasShop'] != false;
    final showNav = !_isLoading && hasShop;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _maybePopActiveTab()) return;
        if (mounted) Navigator.of(context).maybePop();
      },
      child: Scaffold(
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
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !hasShop
              ? _buildNoShopView()
              : _buildShell(),
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

  void _showCreateShopDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final primary = Theme.of(context).colorScheme.primary;

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
              backgroundColor: primary,
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
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(
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
