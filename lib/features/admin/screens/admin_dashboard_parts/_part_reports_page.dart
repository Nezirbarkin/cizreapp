part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Raporlar sayfasi + grafik olusturucular
  // ==========================================================================

  // --- _buildReportsPageContent ---
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
                        gradient: [
                          Colors.green.shade400,
                          Colors.green.shade600,
                        ],
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
                        gradient: [
                          Colors.purple.shade400,
                          Colors.purple.shade600,
                        ],
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
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
                        _buildRevenueChart(
                          data['revenueData'] as List<Map<String, dynamic>>? ??
                              [],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sipariş Grafiği
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sipariş Grafiği',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildOrdersChart(
                          data['ordersData'] as List<Map<String, dynamic>>? ??
                              [],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Kategori Dağılımı
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kategori Dağılımı',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCategoryDistribution(
                          data['categoryData'] as List<Map<String, dynamic>>? ??
                              [],
                        ),
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

  // --- _buildPeriodCard ---
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
              Icon(icon, color: isSelected ? Colors.white : color, size: 32),
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

  // --- _buildRevenueChart ---
  Widget _buildRevenueChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.show_chart, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('Veri yok', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final maxValue = data.fold<double>(
      0,
      (max, item) => max > (item['value'] as num)
          ? max
          : (item['value'] as num).toDouble(),
    );

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
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- _buildOrdersChart ---
  Widget _buildOrdersChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('Veri yok', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final maxValue = data.fold<int>(
      0,
      (max, item) =>
          max > (item['value'] as int) ? max : (item['value'] as int),
    );

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
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- _buildCategoryDistribution ---
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

    final total = data.fold<int>(
      0,
      (sum, item) => sum + (item['value'] as int),
    );

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
}
