part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Gonderi sikayetleri + detay/silme
  // ==========================================================================

  // --- _buildPostReportsContent ---
  Widget _buildPostReportsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadPostReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final reports = snapshot.data ?? [];

        // İstatistikler
        final pendingCount = reports
            .where((r) => r['status'] == 'pending')
            .length;
        final reviewingCount = reports
            .where((r) => r['status'] == 'reviewing')
            .length;
        final resolvedCount = reports
            .where((r) => r['status'] == 'resolved')
            .length;
        final rejectedCount = reports
            .where((r) => r['status'] == 'rejected')
            .length;

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
                  'Gönderi Şikayetleri Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // İstatistik Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildPostReportStatCard(
                        icon: Icons.pending,
                        title: 'Bekleyen',
                        count: pendingCount,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPostReportStatCard(
                        icon: Icons.visibility,
                        title: 'İnceleniyor',
                        count: reviewingCount,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPostReportStatCard(
                        icon: Icons.check_circle,
                        title: 'Çözüldü',
                        count: resolvedCount,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPostReportStatCard(
                        icon: Icons.cancel,
                        title: 'Reddedildi',
                        count: rejectedCount,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                if (reports.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Gönderi şikayeti bulunamadı',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: reports.length,
                    itemBuilder: (context, index) {
                      final report = reports[index];
                      final reporter =
                          report['reporter'] as Map<String, dynamic>?;
                      final reportedPost =
                          report['reported_post'] as Map<String, dynamic>?;
                      final status = report['status'] as String? ?? 'pending';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: _getReportStatusColor(
                              status,
                            ).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _showPostReportDetailDialog(report),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getReportStatusColor(
                                          status,
                                        ).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _getReportStatusIcon(status),
                                            size: 14,
                                            color: _getReportStatusColor(
                                              status,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _getReportStatusText(status),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _getReportStatusColor(
                                                status,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      onPressed: () =>
                                          _showDeletePostReportDialog(report),
                                      tooltip: 'Sil',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Şikayet eden
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundImage:
                                          reporter?['avatar_url'] != null
                                          ? NetworkImage(
                                              reporter!['avatar_url'],
                                            )
                                          : null,
                                      child: reporter?['avatar_url'] == null
                                          ? Text(
                                              (reporter?['username'] as String?)
                                                      ?.substring(0, 1)
                                                      .toUpperCase() ??
                                                  '?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade700,
                                              ),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            reporter?['full_name'] ??
                                                reporter?['username'] ??
                                                'Bilinmeyen',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            'Şikayet eden',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 16,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            reportedPost?['title'] ?? 'Gönderi',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Gönderi',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Şikayet nedeni
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.flag,
                                        color: Colors.red.shade700,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          report['reason'] ?? '-',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Açıklama varsa
                                if (report['description'] != null &&
                                    (report['description'] as String)
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    report['description'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 8),
                                Text(
                                  _formatDate(report['created_at']),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _buildPostReportStatCard ---
  Widget _buildPostReportStatCard({
    required IconData icon,
    required String title,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.orange, size: 24),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // --- _showPostReportDetailDialog ---
  void _showPostReportDetailDialog(Map<String, dynamic> report) {
    final reporter = report['reporter'] as Map<String, dynamic>?;
    final reportedPost = report['reported_post'] as Map<String, dynamic>?;
    String selectedStatus = report['status'] ?? 'pending';
    final adminResponseController = TextEditingController(
      text: report['admin_response'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.flag, color: Colors.orange),
              SizedBox(width: 10),
              Text('Gönderi Şikayeti Detayı'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildReportDetailRow(
                  'Şikayet eden',
                  reporter?['full_name'] ?? reporter?['username'] ?? '-',
                ),
                const SizedBox(height: 8),
                _buildReportDetailRow(
                  'Gönderi',
                  (reportedPost?['content']?.toString().length ?? 0) > 50
                      ? '${reportedPost!['content'].toString().substring(0, 50)}...'
                      : (reportedPost?['content']?.toString() ?? '-'),
                ),
                if (reportedPost?['content'] != null &&
                    reportedPost!['content'].toString().length > 50) ...[
                  const SizedBox(height: 4),
                  Text(
                    reportedPost['content'].toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 16),
                _buildReportDetailRow(
                  'Şikayet Nedeni',
                  report['reason'] ?? '-',
                ),
                if (report['description'] != null &&
                    (report['description'] as String).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildReportDetailRow('Açıklama', report['description']),
                ],
                const SizedBox(height: 16),
                _buildReportDetailRow(
                  'Durum',
                  _getPostReportStatusText(selectedStatus),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: selectedStatus,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Beklemede'),
                    ),
                    DropdownMenuItem(
                      value: 'reviewing',
                      child: Text('İnceleniyor'),
                    ),
                    DropdownMenuItem(value: 'resolved', child: Text('Çözüldü')),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Reddedildi'),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => selectedStatus = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: adminResponseController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Admin Yanıtı',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final oldResponse = report['admin_response'] as String? ?? '';
                  final newResponse = adminResponseController.text.trim();
                  final oldStatus = report['status'] as String? ?? 'pending';

                  // Durum değiştiyse VEYA admin yanıtı eklendi/değiştiyse bildirim gönder
                  final shouldNotify =
                      selectedStatus != oldStatus ||
                      (newResponse.isNotEmpty && newResponse != oldResponse);

                  if (shouldNotify && reporter != null) {
                    try {
                      final notificationMessage = newResponse.isNotEmpty
                          ? 'Gönderi şikayetinize yanıt geldi: ${newResponse.substring(0, newResponse.length > 50 ? 50 : newResponse.length)}${newResponse.length > 50 ? '...' : ''}'
                          : 'Gönderi şikayetinizin durumu güncellendi: ${_getPostReportStatusText(selectedStatus)}';

                      if (reporter['id'] != null) {
                        await Supabase.instance.client
                            .from('notifications')
                            .insert({
                              'user_id': reporter['id'],
                              'type': 'admin_notification',
                              'title': 'Şikayetinize Yanıt Geldi',
                              'content': notificationMessage,
                              'metadata': {
                                'report_id': report['id'],
                                'status': selectedStatus,
                                'admin_response': newResponse,
                                'report_type': 'post_report',
                              },
                              'is_read': false,
                              'created_at': DateTime.now().toIso8601String(),
                            });
                      }
                      debugPrint(
                        '✅ Gönderi şikayeti bildirimi gönderildi: $notificationMessage',
                      );
                    } catch (notifError) {
                      debugPrint('⚠️ Bildirim gönderilemedi: $notifError');
                    }
                  }

                  await Supabase.instance.client
                      .from('post_reports')
                      .update({
                        'status': selectedStatus,
                        'admin_response': adminResponseController.text.trim(),
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', report['id']);

                  debugPrint('✅ Gönderi şikayeti başarıyla güncellendi');

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Şikayet başarıyla güncellendi'),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Şikayet güncellenirken hata: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hata: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  // --- _buildReportDetailRow ---
  Widget _buildReportDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // --- _showDeletePostReportDialog ---
  void _showDeletePostReportDialog(Map<String, dynamic> report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şikayeti Sil'),
        content: const Text('Bu şikayeti silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await Supabase.instance.client
                  .from('post_reports')
                  .delete()
                  .eq('id', report['id']);
              if (mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // --- _getPostReportStatusText ---
  String _getPostReportStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Beklemede';
      case 'reviewing':
        return 'İnceleniyor';
      case 'resolved':
        return 'Çözüldü';
      case 'rejected':
        return 'Reddedildi';
      default:
        return status;
    }
  }
}
