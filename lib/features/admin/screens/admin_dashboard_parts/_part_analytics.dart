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
  //
  // Bu sekme eskiden `AnalyticsService`'in YEREL Hive kutusunu okuyordu:
  // gosterilen sayilar tum kullanicilarin degil, panele bakan adminin kendi
  // cihazinda birikmis eventlerdi. Ayrica beğeni/yorum/paylasim hicbir zaman
  // yazilmadigi icin o satirlar kalici olarak 0 gorunuyordu. Artik hepsi
  // `admin_logs_data` RPC'sinden, merkezi tablodan geliyor.

  void _refreshAnalyticsData() {
    if (!mounted) return;
    setState(() => _analyticsDataFuture = _loadLogsData());
  }

  // --- _buildAnalyticsContent ---
  Widget _buildAnalyticsContent() {
    _analyticsDataFuture ??= _loadLogsData();
    return FutureBuilder<Map<String, dynamic>>(
      future: _analyticsDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final windowDays = (data['windowDays'] as int?) ?? _logsWindowDays;
        final eventTypeCounts =
            (data['eventTypeCounts'] as Map<String, int>?) ?? const {};
        final mostViewed =
            (data['mostViewedPosts'] as List<Map<String, dynamic>>?) ??
            const [];

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
                          const Expanded(
                            child: Text(
                              'Analitik',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Yenile',
                            onPressed: _refreshAnalyticsData,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tüm kullanıcılar · son $windowDays gün',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Toplam Etkinlik (tüm zaman)',
                        '${data['totalEvents'] ?? 0}',
                        Colors.grey.shade700,
                      ),
                      _buildInfoRow(
                        'Etkinlik (son $windowDays g)',
                        '${data['windowEvents'] ?? 0}',
                        Colors.grey.shade700,
                      ),
                      _buildInfoRow(
                        'Gönderi Görüntüleme',
                        '${data['postViewCount'] ?? 0}',
                        Colors.blue,
                      ),
                      _buildInfoRow(
                        'Beğeni',
                        '${eventTypeCounts['like'] ?? 0}',
                        Colors.red,
                      ),
                      _buildInfoRow(
                        'Yorum',
                        '${eventTypeCounts['comment'] ?? 0}',
                        Colors.orange,
                      ),
                      _buildInfoRow(
                        'Paylaşım',
                        '${eventTypeCounts['share'] ?? 0}',
                        Colors.green,
                      ),
                      _buildInfoRow(
                        'Akış Yüklemesi',
                        '${eventTypeCounts['feed_load'] ?? 0}',
                        Colors.teal,
                      ),
                      _buildInfoRow(
                        'Hata',
                        '${data['errorCount'] ?? 0}',
                        Colors.red,
                      ),
                      if (mostViewed.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'En Çok Görüntülenen Gönderiler:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...mostViewed.map(
                          (post) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '  • ${post['label']} (${post['view_count']} görüntülenme)',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                          onPressed: _confirmPurgeAnalytics,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Merkezi Analitiği Temizle'),
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
      },
    );
  }

  // --- _confirmPurgeAnalytics ---
  // Eski dugme yalnizca adminin kendi cihazindaki Hive kutusunu siliyor ama
  // "Analitik verileri temizlendi" diyordu; merkezi tablo el degmeden
  // kaliyordu. Artik gercekten sunucudan siliyor ve geri alinamaz oldugu icin
  // once onay istiyor.
  Future<void> _confirmPurgeAnalytics() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Merkezi analitiği temizle'),
        content: const Text(
          'Tüm kullanıcıların analitik kayıtları sunucudan kalıcı olarak '
          'silinecek. Bu işlem geri alınamaz. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final deleted = await _analyticsService.purgeRemoteEvents();
      await _analyticsService.clearAllEvents(); // bu cihazdaki yerel kopya
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$deleted analitik kaydı silindi')),
      );
      _refreshAnalyticsData();
      _refreshLogsData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
    }
  }
}
