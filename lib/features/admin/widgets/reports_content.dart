import 'package:flutter/material.dart';

class ReportsContent extends StatelessWidget {
  final String selectedPeriod;
  final Function(String) onPeriodChanged;
  final Future<Map<String, dynamic>> Function() loadData;
  final VoidCallback onRefresh;
  final Widget Function(List<Map<String, dynamic>>) buildRevenueChart;
  final Widget Function(List<Map<String, dynamic>>) buildOrdersChart;
  final Widget Function(List<Map<String, dynamic>>) buildCategoryDistribution;

  const ReportsContent({
    super.key,
    required this.selectedPeriod,
    required this.onPeriodChanged,
    required this.loadData,
    required this.onRefresh,
    required this.buildRevenueChart,
    required this.buildOrdersChart,
    required this.buildCategoryDistribution,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: loadData(),
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
            onRefresh();
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
                      child: _PeriodCard(
                        title: 'Günlük',
                        icon: Icons.today,
                        color: Colors.blue,
                        isSelected: selectedPeriod == 'daily',
                        onTap: () => onPeriodChanged('daily'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PeriodCard(
                        title: 'Haftalık',
                        icon: Icons.view_week,
                        color: Colors.green,
                        isSelected: selectedPeriod == 'weekly',
                        onTap: () => onPeriodChanged('weekly'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PeriodCard(
                        title: 'Aylık',
                        icon: Icons.calendar_month,
                        color: Colors.orange,
                        isSelected: selectedPeriod == 'monthly',
                        onTap: () => onPeriodChanged('monthly'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Özet İstatistikler
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.attach_money,
                        title: 'Toplam Kazanç',
                        value: '₺${data['totalRevenue'] ?? 0}',
                        color: Colors.green,
                        gradient: const [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.shopping_cart,
                        title: 'Toplam Sipariş',
                        value: '${data['totalOrders'] ?? 0}',
                        color: Colors.blue,
                        gradient: const [Color(0xFF2196F3), Color(0xFF1565C0)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.trending_up,
                        title: 'Ort. Sipariş',
                        value: '₺${data['avgOrder'] ?? 0}',
                        color: Colors.purple,
                        gradient: const [Color(0xFF9C27B0), Color(0xFF6A1B9A)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.people,
                        title: 'Aktif Müşteri',
                        value: '${data['activeCustomers'] ?? 0}',
                        color: Colors.teal,
                        gradient: const [Color(0xFF009688), Color(0xFF00695C)],
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
                        buildRevenueChart(data['revenueData'] as List<Map<String, dynamic>>? ?? []),
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
                        buildOrdersChart(data['ordersData'] as List<Map<String, dynamic>>? ?? []),
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
                        buildCategoryDistribution(data['categoryData'] as List<Map<String, dynamic>>? ?? []),
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
}

class _PeriodCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        // ignore: deprecated_member_use
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
                  // ignore: deprecated_member_use
                  color: isSelected ? Colors.white : color.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final List<Color> gradient;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 26,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
