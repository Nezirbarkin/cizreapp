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
  // Gonderi sikayetleri + detay/silme
  // ==========================================================================

  // NOT: Bu dosyada bir donem `_buildPostReportsContent()` (tam sayfa
  // "Gönderi Şikayetleri Yönetimi" ekrani) ve yalniz onun kullandigi
  // `_buildPostReportStatCard()` bulunuyordu. Hicbir yerden ERISILEMIYORDU:
  // _selectedMenu hicbir zaman 'Gönderi Şikayetleri' degerini almiyor,
  // drawer'da da boyle bir menu yok. Ayni icerik zaten Sikayetler
  // sayfasina gomulu (_part_reports.dart). 2026-08-16'da kaldirildi.
  //
  // Asagidaki iki dialog CANLIDIR: _part_reports.dart icindeki gonderi
  // sikayeti kartlari bunlari cagirir.

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
              try {
                await Supabase.instance.client
                    .from('post_reports')
                    .delete()
                    .eq('id', report['id']);
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
                  );
                }
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
