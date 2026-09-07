// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unused_element, unnecessary_underscores, unused_local_variable, prefer_conditional_assignment, unnecessary_brace_in_string_interps, curly_braces_in_flow_control_structures

// ignore_for_file: deprecated_member_use

library;

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/performance_monitoring_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../profile/screens/profile_screen.dart';
import '../../market/services/category_service.dart';
import '../widgets/reports_content.dart';
import 'shop_detail_admin_screen.dart';
import '../widgets/support_tickets_content.dart';
import '../widgets/daily_deals_content.dart';
import '../widgets/notifications_content_v2.dart';
import '../widgets/groups_management_content.dart';
import '../widgets/admin_ticket_detail_dialog.dart';
import 'about_settings_screen.dart';
import 'ad_settings_screen.dart';
import 'admin_smm_providers_screen.dart';
import '../widgets/task_management_content.dart';
import '../widgets/suspicious_users_content.dart';
import '../widgets/fraud_signals_content.dart';
import '../../shop/services/cancellation_request_service.dart';
import 'courier_quick_settings_screen.dart';
import '../widgets/courier_notices_management_content.dart';
import '../../../sehirici/admin/sehirici_admin_management_content.dart';
import '../../news/widgets/news_management_content.dart';
import '../widgets/admin_package_requests_tab.dart';
import '../widgets/wallet_management_content.dart';
import '../widgets/courier_payout_requests_section.dart';
import '../widgets/reward_points_overview_section.dart';
import '../widgets/users_with_balance_tab_widget.dart';
import 'commission_dashboard_screen.dart';
import '../../wallet/screens/admin_withdrawal_screen.dart';
import '../utils/admin_user_helpers.dart';
import '../../../kullaniciozellikler/admin/user_features_admin_content.dart';
import '../../../ilanlar/admin/ilan_admin_content.dart';
import '../../../core/models/invoice_model.dart';
import '../../../okey/admin/okey_admin_content.dart';

part 'admin_dashboard_parts/_part_helpers.dart';
part 'admin_dashboard_parts/_part_data_loaders.dart';
part 'admin_dashboard_parts/_part_drawer.dart';
part 'admin_dashboard_parts/_part_dashboard.dart';
part 'admin_dashboard_parts/_part_users.dart';
part 'admin_dashboard_parts/_part_posts.dart';
part 'admin_dashboard_parts/_part_products.dart';
part 'admin_dashboard_parts/_part_categories.dart';
part 'admin_dashboard_parts/_part_shops.dart';
part 'admin_dashboard_parts/_part_orders.dart';
part 'admin_dashboard_parts/_part_reports.dart';
part 'admin_dashboard_parts/_part_post_reports.dart';
part 'admin_dashboard_parts/_part_support_tickets.dart';
part 'admin_dashboard_parts/_part_payments.dart';
part 'admin_dashboard_parts/_part_reports_page.dart';
part 'admin_dashboard_parts/_part_analytics.dart';
part 'admin_dashboard_parts/_part_logs.dart';
part 'admin_dashboard_parts/_part_settings.dart';
part 'admin_dashboard_parts/_part_api_settings.dart';
part 'admin_dashboard_parts/_part_courier.dart';
part 'admin_dashboard_parts/_part_misc_remaining.dart';

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
  double _totalRevenue = 0; // İptal edilmemiş siparişlerin toplam tutarı
  double _totalAdminCommission = 0; // Toplam admin komisyonu
  int _totalDigitalOrders = 0; // Toplam dijital (SMM) sipariş sayısı
  double _totalDigitalRevenue =
      0; // İptal/iade edilmemiş dijital sipariş geliri
  int _totalCouriers = 0; // Toplam kurye sayısı
  int _onlineCouriers = 0; // Şu an çevrimiçi kurye sayısı
  int _unansweredComplaintCount = 0; // Yanıtlanmamış şikayet sayısı
  int _unansweredTicketCount = 0; // Yanıtlanmamış destek talebi sayısı
  int _newPostsCount = 0; // Menü görülmeden gelen yeni gönderi sayısı
  int _newProductsCount = 0; // Menü görülmeden gelen yeni ürün sayısı
  int _newOrdersCount = 0; // Menü görülmeden gelen yeni sipariş sayısı
  int _newDigitalOrdersCount =
      0; // Menü görülmeden gelen yeni dijital (SMM) sipariş sayısı
  int _newGroupsCount = 0; // Menü görülmeden gelen yeni grup sayısı
  int _newUsersCount = 0; // Menü görülmeden gelen yeni kullanıcı sayısı
  bool _isLoading = true;

  // Realtime subscriptions
  RealtimeChannel? _reportsChannel;
  RealtimeChannel? _ticketsChannel;
  RealtimeChannel? _newItemsChannel;
  // Admin tek-adım sipariş iptal+iade servisi (admin_cancel_with_refund RPC)
  final CancellationRequestService _cancellationService =
      CancellationRequestService();
  String _selectedMenu = 'Dashboard';
  String _logsSearchQuery = '';
  String _selectedPeriod = 'weekly'; // Raporlar için seçili dönem
  String _userSearchQuery = ''; // Kullanıcı arama sorgusu
  String? _roleFilter; // Kullanıcı listesi rol filtresi (kart tıklayınca)
  final TextEditingController _userSearchController = TextEditingController();
  Future<List<Map<String, dynamic>>>? _usersFuture;
  // Kullanicilar sekmesindeki ozet kartlarin (Toplam/Admin/Kurye/...) veri
  // kaynagi. _usersFuture SINIRLI (limit=100, en yeni once) bir sayfa
  // dondurdugu icin ondan sayim yapmak toplam profil sayisi limiti astiginda
  // erken acilmis admin/kurye/haberci hesaplarini "0" gosteriyordu. Bu future
  // limitten bagimsiz, tum tablo uzerinde GROUP BY role hesabi yapan
  // admin_user_role_counts RPC'sini cagirir.
  Future<Map<String, int>?>? _userRoleCountsFuture;
  Future<Map<String, dynamic>>? _logsDataFuture;
  Future<Map<String, dynamic>>? _analyticsDataFuture;
  // Dagilim/hata metriklerinin zaman penceresi. Tum zamanlar uzerinden
  // hesaplanan "saatlik dagilim" hem anlamsizdi hem de tablo buyudukce
  // her acilista tam tablo taramasi yapiyordu.
  int _logsWindowDays = 30;
  String? _selectedShopFilter; // Sipariş yönetiminde dükkan filtresi
  String _paymentsStatusFilter = 'all'; // Ödemeler sekmesinde durum filtresi

  // Dükkan listesi - state değişkeni olarak saklanıyor
  List<Map<String, dynamic>> _shopsDetailed = [];
  bool _isLoadingShops = true;

  @override
  void initState() {
    super.initState();
    _usersFuture = _loadUsers();
    _userRoleCountsFuture = _loadUserRoleCounts();
    _loadRealData();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _reportsChannel?.unsubscribe();
    _ticketsChannel?.unsubscribe();
    _newItemsChannel?.unsubscribe();
    _userSearchController.dispose();
    super.dispose();
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
              colors: [Colors.purple.shade600, Colors.purple.shade800],
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
}
