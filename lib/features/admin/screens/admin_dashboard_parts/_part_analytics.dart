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
  // Analitik icerigi
  // ==========================================================================

  // --- _buildAnalyticsContent ---
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                  _buildInfoRow(
                    'Toplam Etkinlik',
                    '${_analyticsService.eventCount}',
                    Colors.grey.shade700,
                  ),
                  _buildInfoRow(
                    'Görüntülenme',
                    '${metrics['views'] ?? 0}',
                    Colors.blue,
                  ),
                  _buildInfoRow(
                    'Beğeni',
                    '${metrics['likes'] ?? 0}',
                    Colors.red,
                  ),
                  _buildInfoRow(
                    'Yorum',
                    '${metrics['comments'] ?? 0}',
                    Colors.orange,
                  ),
                  _buildInfoRow(
                    'Paylaşım',
                    '${metrics['shares'] ?? 0}',
                    Colors.green,
                  ),
                  _buildInfoRow(
                    'Hata',
                    '${metrics['errors'] ?? 0}',
                    Colors.red,
                  ),
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
                    ...mostViewed.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '  • ${e.key.substring(0, 8)}... (${e.value} görüntülenme)',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _analyticsService.clearAllEvents();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Analitik verileri temizlendi'),
                            ),
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
}
