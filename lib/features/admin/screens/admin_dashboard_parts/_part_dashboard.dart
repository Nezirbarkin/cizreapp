// Bu dosya `part of admin_dashboard_screen.dart` oldugu icin ana dosyadaki
// ignore_for_file direktifleri buraya UYGULANMAZ; her part kendi listesini
// tasimak zorundadir.
//
// invalid_use_of_protected_member: bu part'lar `extension on
// _AdminDashboardScreenState` deseniyle yazildi; setState/mounted analiz
// acisindan sinif disindan cagrilmis gorunur ama calisma zamaninda
// State'in kendi uyesidir. Tek gercek false positive budur ve yalniz o
// susturulur - dosyalarin analizden komple cikarilmasi (analysis_options
// exclude) dead_code/tip hatalarini da gizliyordu.
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: use_build_context_synchronously, deprecated_member_use
part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Dashboard ana sayfa + istatistik kartlari
  // ==========================================================================

  // --- _buildDashboardContent ---
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
            const SizedBox(height: 16),

            // Gelir & Kurye Özeti
            _buildRevenueCourierCard(),
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

  // --- _buildWelcomeBanner ---
  Widget _buildWelcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade600, Colors.purple.shade800],
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

  // --- _buildStatsGrid ---
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
            // Eskiden yerel Hive sayacini yaziyordu; o deger adminin KENDI
            // cihazindaki kutunun boyutuydu, tum kullanicilarin etkinligi
            // degil. Artik merkezi tablodan geliyor.
            FutureBuilder<Map<String, dynamic>>(
              future: _analyticsDataFuture ??= _loadLogsData(),
              builder: (context, snapshot) => _buildStatCard(
                icon: Icons.analytics_rounded,
                title: 'Etkinlikler',
                value: snapshot.hasData
                    ? '${snapshot.data!['totalEvents'] ?? 0}'
                    : (snapshot.hasError ? '–' : '...'),
                color: Colors.teal,
                gradient: [Colors.teal.shade400, Colors.teal.shade600],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- _buildStatCard ---
  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required List<Color> gradient,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
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
                      child: Icon(icon, color: Colors.white, size: 22),
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
        ),
      ),
    );
  }

  // --- _buildStatCardOld ---
  Widget _buildStatCardOld({
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
                  child: Icon(icon, color: Colors.white, size: 22),
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

  // --- _buildRevenueCourierCard ---
  Widget _buildRevenueCourierCard() {
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
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.payments_rounded,
                    color: Colors.green.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Gelir & Kurye Özeti',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMiniStat(
                    label: 'Toplam Gelir',
                    value: '₺${_totalRevenue.toStringAsFixed(2)}',
                    color: Colors.green,
                    onTap: () =>
                        setState(() => _selectedMenu = 'Siparişler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMiniStat(
                    label: 'Admin Komisyonu',
                    value: '₺${_totalAdminCommission.toStringAsFixed(2)}',
                    color: Colors.teal,
                    onTap: () =>
                        setState(() => _selectedMenu = 'Siparişler'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMiniStat(
                    label: 'Dijital Sipariş Geliri',
                    value:
                        '₺${_totalDigitalRevenue.toStringAsFixed(2)} · $_totalDigitalOrders adet',
                    color: Colors.indigo,
                    onTap: () => setState(
                      () => _selectedMenu = 'SMM Sağlayıcıları',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMiniStat(
                    label: 'Kuryeler',
                    value: '$_onlineCouriers / $_totalCouriers çevrimiçi',
                    color: Colors.orange,
                    onTap: () =>
                        setState(() => _selectedMenu = 'Kurye Yönetimi'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- _buildMiniStat ---
  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- _buildNetworkStatusCard ---
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  // --- _buildCacheStatisticsCard ---
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              'Cached Posts',
              '${_cacheService.cacheSize}',
              Colors.grey.shade700,
            ),
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

  // --- _buildPerformanceCard ---
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              'Toplam API Çağrısı',
              '${summary['total_calls']}',
              Colors.grey.shade700,
            ),
            _buildInfoRow(
              'Ort. Yanıt Süresi',
              '${summary['average_response_time_ms']}ms',
              Colors.grey.shade700,
            ),
            _buildInfoRow(
              'Başarı Oranı',
              '${summary['success_rate'].toStringAsFixed(1)}%',
              Colors.green,
            ),
            _buildInfoRow(
              'P95 Latency',
              '${summary['p95_latency_ms']}ms',
              Colors.grey.shade700,
            ),
            _buildInfoRow(
              'P99 Latency',
              '${summary['p99_latency_ms']}ms',
              Colors.grey.shade700,
            ),
            if (slowest.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'En Yavaş Endpointler:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...slowest.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '  • ${e.key}: ${e.value}ms',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
              ),
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
}
