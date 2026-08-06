part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // --- _setupRealtimeSubscription ---
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

    // Yeni gönderi/ürün/sipariş/grup badge rozetleri için realtime dinleme
    _newItemsChannel = Supabase.instance.client
        .channel('admin_new_items_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            if (_selectedMenu != 'Gönderiler') {
              setState(() => _newPostsCount++);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            if (_selectedMenu != 'Ürünler') {
              setState(() => _newProductsCount++);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            if (_selectedMenu != 'Siparişler') {
              setState(() => _newOrdersCount++);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'groups',
          callback: (payload) {
            if (_selectedMenu != 'Gruplar') {
              setState(() => _newGroupsCount++);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            if (_selectedMenu != 'Kullanıcılar') {
              setState(() => _newUsersCount++);
            }
          },
        )
        .subscribe();
  }

  // --- _loadRealData ---
  //
  // 20260803000006_secure_profiles_privileges_and_pii.sql sonrasında
  // profiles üzerindeki authenticated SELECT policy'si kaldırıldı;
  // support_tickets policy gövdesi de inline
  // `SELECT role FROM profiles` içeriyordu. Tüm sorguları tek tek
  // yapıp tek bir setState'te birleştirmek, RLS patlamasında tüm
  // sayaçların 0 kalmasına yol açıyordu. Çözüm: SECURITY DEFINER
  // admin_dashboard_counts() RPC üzerinden tek atomik çağrı.
  Future<void> _loadRealData() async {
    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;
      debugPrint('📊 Admin Dashboard veri yüklemesi başladı...');
      debugPrint('📊 Mevcut kullanıcı: ${client.auth.currentUser?.id}');
      debugPrint(
        '📊 Mevcut kullanıcı email: ${client.auth.currentUser?.email}',
      );

      final rows = await client.rpc<List<dynamic>>(
        'admin_dashboard_counts',
      );

      if (rows.isEmpty) {
        throw Exception('admin_dashboard_counts boş döndü');
      }
      final r = (rows.first as Map).cast<String, dynamic>();

      if (!mounted) return;
      setState(() {
        _totalUsers = (r['total_users'] as num).toInt();
        _totalPosts = (r['total_posts'] as num).toInt();
        _totalProducts = (r['total_products'] as num).toInt();
        _totalOrders = (r['total_orders'] as num).toInt();
        _totalReports = (r['total_reports'] as num).toInt();
        _unansweredComplaintCount =
            (r['unanswered_complaints'] as num).toInt();
        _unansweredTicketCount = (r['unanswered_tickets'] as num).toInt();
        _isLoading = false;
      });

      debugPrint('✅ Admin Dashboard veri yükleme tamamlandı');
      debugPrint(
        '📊 Sonuçlar - Users: $_totalUsers, Posts: $_totalPosts, Products: $_totalProducts, Orders: $_totalOrders',
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Veriler yüklenirken hata: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Sessiz catch→0 deseni bu bug'ı görünmez yapıyordu; hatayı
      // artık kullanıcıya da gösteriyoruz.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dashboard verileri yüklenemedi: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // --- _buildBody ---
  Widget _buildBody() {
    switch (_selectedMenu) {
      case 'Dashboard':
        return _buildDashboardContent();
      case 'Kullanıcılar':
        return _buildUsersContent();
      case 'Gönderiler':
        return _buildPostsContent();
      case 'Haberler':
        return const NewsManagementContent();
      case 'Ürünler':
        return _buildProductsContent();
      case 'SMM Sağlayıcıları':
        return const AdminSmmProvidersScreen();
      case 'Kategoriler':
        return _buildCategoriesContent();
      case 'Dükkanlar':
        return _buildShopsContent();
      case 'Siparişler':
        return _buildOrdersContent();
      case 'Kurye Yönetimi':
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(
                labelColor: Colors.teal,
                tabs: [
                  Tab(text: 'Kuryeler', icon: Icon(Icons.delivery_dining)),
                  Tab(text: 'Paketler', icon: Icon(Icons.inventory_2)),
                  Tab(text: 'Ayarlar', icon: Icon(Icons.settings)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildCourierManagementContent(),
                    const AdminPackageRequestsTab(),
                    const CourierQuickSettingsScreen(embedded: true),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'Gruplar':
        return const GroupsManagementContent();
      case 'Bildirimler':
        return const NotificationsContentV2();
      case 'Şikayetler':
        return _buildReportsContent();
      case 'Gönderi Şikayetleri':
        return _buildPostReportsContent();
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
      case 'Loglar':
        return _buildLogsContent();
      case 'API Ayarları':
        return _buildAPISettingsContent();
      case 'Ayarlar':
        return _buildSettingsContent();
      case 'Hakkında Ayarları':
        return const AdminAboutSettingsScreen();
      case 'Reklam Ayarları':
        return const AdminAdSettingsScreen();
      case 'Cüzdan Yönetimi':
        return const WalletManagementContent();
      case 'Görev Yönetimi':
        return const TaskManagementContent();
      case 'Kurye Uyarıları':
        return const CourierNoticesManagementContent();
      case 'Şehiriçi Yönetimi':
        return const SehiriciAdminManagementContent();
      case 'Şüpheli Kullanıcılar':
        return const SuspiciousUsersContent();
      case 'Dolandırıcılık Sinyalleri':
        return const FraudSignalsContent();
      default:
        return _buildComingSoon();
    }
  }

  // --- _getReportStatusColor ---
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

  // --- _getReportStatusIcon ---
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

  // --- _getCategoryColor ---
  Color _getCategoryColor(String? colorHex) {
    return _parseColor(colorHex);
  }

  // --- _parseColor ---
  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return Colors.purple;
    try {
      final colorValue = int.parse(colorHex.replaceFirst('#', '0xFF'));
      return Color(colorValue);
    } catch (e) {
      return Colors.purple;
    }
  }

  // --- _getOrderStatusColor ---
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

  // --- _buildComingSoon ---
  Widget _buildComingSoon() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction, size: 80, color: Colors.grey.shade400),
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
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // --- _buildInfoRow ---
  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
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

  // --- _getNotificationStatusColor ---
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

  // --- _getSupportTicketStatusColor ---
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

  // --- _getPaymentStatusColor ---
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

  // --- _getPaymentIcon ---
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
}
