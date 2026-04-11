// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// Modern Admin Bildirimler Yönetim Ekranı
/// Push bildirimlerini gönderir, istatistikleri gösterir
class NotificationsContent extends StatefulWidget {
  const NotificationsContent({super.key});

  @override
  State<NotificationsContent> createState() => _NotificationsContentState();
}

class _NotificationsContentState extends State<NotificationsContent> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _isLoading = true;
  
  // İstatistikler
  int _totalSent = 0;
  int _totalDelivered = 0;
  int _totalRead = 0;
  int _totalFailed = 0;
  int _totalPending = 0;
  
  // Push bildirimleri listesi
  List<Map<String, dynamic>> _pushNotifications = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Push bildirimlerini yükle
      final pushResponse = await _client
          .from('push_notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(20);
      
      // İstatistikleri hesapla
      int totalSent = 0;
      int totalDelivered = 0;
      int totalRead = 0;
      int totalFailed = 0;
      int totalPending = 0;
      
      for (var notif in pushResponse) {
        totalSent += (notif['sent_count'] as int?) ?? 0;
        totalDelivered += (notif['delivered_count'] as int?) ?? 0;
        totalRead += (notif['read_count'] as int?) ?? 0;
        totalFailed += (notif['failed_count'] as int?) ?? 0;
        totalPending += (notif['pending_count'] as int?) ?? 0;
      }
      
      setState(() {
        _pushNotifications = List<Map<String, dynamic>>.from(pushResponse);
        _totalSent = totalSent;
        _totalDelivered = totalDelivered;
        _totalRead = totalRead;
        _totalFailed = totalFailed;
        _totalPending = totalPending;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Bildirimler yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: 24),
            
            // İstatistik Kartları Grid
            _buildStatsGrid(),
            const SizedBox(height: 24),
            
            // Detaylı İstatistikler Kartı
            _buildDetailedStatsCard(),
            const SizedBox(height: 24),
            
            // Son Gönderilen Bildirimler
            _buildNotificationsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Push Bildirimleri',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _showSendNotificationDialog(),
          icon: const Icon(Icons.send_rounded),
          label: const Text('Bildirim Gönder'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildModernStatCard(
          icon: Icons.send_rounded,
          title: 'Gönderilen',
          value: _totalSent.toString(),
          color: Colors.blue,
          gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.blue.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        _buildModernStatCard(
          icon: Icons.check_circle_rounded,
          title: 'Teslim Edilen',
          value: _totalDelivered.toString(),
          subtitle: 'İnternet sonrası',
          color: Colors.green,
          gradient: LinearGradient(
            colors: [Colors.green.shade400, Colors.green.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        _buildModernStatCard(
          icon: Icons.visibility_rounded,
          title: 'Okunan',
          value: _totalRead.toString(),
          color: Colors.purple,
          gradient: LinearGradient(
            colors: [Colors.purple.shade400, Colors.purple.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        _buildModernStatCard(
          icon: Icons.cancel_rounded,
          title: 'Başarısız',
          value: _totalFailed.toString(),
          color: Colors.red,
          gradient: LinearGradient(
            colors: [Colors.red.shade400, Colors.red.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        _buildModernStatCard(
          icon: Icons.pending_rounded,
          title: 'Bekleyen',
          value: _totalPending.toString(),
          color: Colors.orange,
          gradient: LinearGradient(
            colors: [Colors.orange.shade400, Colors.orange.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        _buildModernStatCard(
          icon: Icons.people_rounded,
          title: 'Toplam Alıcı',
          value: _pushNotifications.isEmpty
              ? '0'
              : _pushNotifications
                  .fold<int>(0, (sum, n) => sum + ((n['total_recipients'] as int?) ?? 0))
                  .toString(),
          color: Colors.teal,
          gradient: LinearGradient(
            colors: [Colors.teal.shade400, Colors.teal.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ],
    );
  }

  Widget _buildModernStatCard({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    required Color color,
    required Gradient gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedStatsCard() {
    final readRate = _totalSent > 0
        ? (_totalRead / _totalSent * 100).toStringAsFixed(1)
        : '0.0';
    final deliveryRate = _totalSent > 0
        ? (_totalDelivered / _totalSent * 100).toStringAsFixed(1)
        : '0.0';
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detaylı İstatistikler',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
            // Progress Bar - Okuma Oranı
            _buildProgressRow(
              label: 'Okuma Oranı',
              percentage: double.tryParse(readRate) ?? 0,
              value: '$readRate%',
              color: Colors.purple,
            ),
            const SizedBox(height: 16),
            
            // Progress Bar - Teslimat Oranı
            _buildProgressRow(
              label: 'Teslimat Oranı',
              percentage: double.tryParse(deliveryRate) ?? 0,
              value: '$deliveryRate%',
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            
            // Info Row - Toplam Bildirim
            _buildInfoRow(
              Icons.notifications_active_rounded,
              'Toplam Bildirim Kampanyası',
              '${_pushNotifications.length}',
              Colors.blue,
            ),
            const SizedBox(height: 12),
            
            // Info Row - Son Gönderim
            if (_pushNotifications.isNotEmpty)
              _buildInfoRow(
                Icons.access_time_rounded,
                'Son Gönderim',
                _formatDate(_pushNotifications.first['created_at']),
                Colors.grey,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow({
    required String label,
    required double percentage,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: color,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsList() {
    if (_pushNotifications.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz bildirim gönderilmemiş',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Son Gönderilen Bildirimler',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(_pushNotifications.length, (index) {
          final notif = _pushNotifications[index];
          return _buildNotificationCard(notif);
        }),
      ],
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notif) {
    final status = notif['status'] as String? ?? 'pending';
    final statusColor = _getStatusColor(status);
    final statusLabel = _getStatusLabel(status);
    
    final sentCount = notif['sent_count'] ?? 0;
    final deliveredCount = notif['delivered_count'] ?? 0;
    final readCount = notif['read_count'] ?? 0;
    final failedCount = notif['failed_count'] ?? 0;
    final totalRecipients = notif['total_recipients'] ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showNotificationDetails(notif),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getStatusIcon(status),
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notif['title'] ?? '-',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(notif['created_at']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Body
              Text(
                notif['body'] ?? '-',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              
              // Stats Row
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildMiniStat(
                    Icons.send_rounded,
                    sentCount.toString(),
                    'Gönderilen',
                    Colors.blue,
                  ),
                  _buildMiniStat(
                    Icons.check_circle_rounded,
                    deliveredCount.toString(),
                    'Teslim',
                    Colors.green,
                  ),
                  _buildMiniStat(
                    Icons.visibility_rounded,
                    readCount.toString(),
                    'Okunan',
                    Colors.purple,
                  ),
                  if (failedCount > 0)
                    _buildMiniStat(
                      Icons.cancel_rounded,
                      failedCount.toString(),
                      'Başarısız',
                      Colors.red,
                    ),
                ],
              ),
              
              // Progress Bar
              if (totalRecipients > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: sentCount / totalRecipients,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$sentCount / $totalRecipients kişiye gönderildi',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  void _showNotificationDetails(Map<String, dynamic> notif) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(notif['title'] ?? '-'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(notif['body'] ?? '-'),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _buildDetailRow('Durum', _getStatusLabel(notif['status'])),
              _buildDetailRow('Toplam Alıcı', '${notif['total_recipients'] ?? 0}'),
              _buildDetailRow('Gönderilen', '${notif['sent_count'] ?? 0}'),
              _buildDetailRow('Teslim Edilen', '${notif['delivered_count'] ?? 0}'),
              _buildDetailRow('Okunan', '${notif['read_count'] ?? 0}'),
              _buildDetailRow('Başarısız', '${notif['failed_count'] ?? 0}'),
              _buildDetailRow('Bekleyen', '${notif['pending_count'] ?? 0}'),
              _buildDetailRow('Oluşturma', _formatDate(notif['created_at'])),
              if (notif['sent_at'] != null)
                _buildDetailRow('Gönderim', _formatDate(notif['sent_at'])),
              if (notif['scheduled_for'] != null)
                _buildDetailRow('Planlanan', _formatDate(notif['scheduled_for'])),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showSendNotificationDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String targetAudience = 'all';
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Push Bildirim Gönder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Başlık',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: bodyController,
                  decoration: InputDecoration(
                    labelText: 'Mesaj',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: targetAudience,
                  decoration: InputDecoration(
                    labelText: 'Hedef Kitle',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('Tüm Kullanıcılar'),
                    ),
                    DropdownMenuItem(
                      value: 'customers',
                      child: Text('Müşteriler'),
                    ),
                    DropdownMenuItem(
                      value: 'sellers',
                      child: Text('Satıcılar'),
                    ),
                    DropdownMenuItem(
                      value: 'admins',
                      child: Text('Adminler'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => targetAudience = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      if (titleController.text.isEmpty ||
                          bodyController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tüm alanları doldurun'),
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSending = true);

                      try {
                        // Push bildirimi gönder
                        final notificationData = {
                          'title': titleController.text.trim(),
                          'body': bodyController.text.trim(),
                          'target_audience': targetAudience,
                          'status': 'pending',
                        };

                        await _client
                            .from('push_notifications')
                            .insert(notificationData);

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Bildirim kuyruğa eklendi'),
                            backgroundColor: Colors.green,
                          ),
                        );

                        _loadData();
                      } catch (e) {
                        setDialogState(() => isSending = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Gönder'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'sent':
        return Colors.green;
      case 'sending':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'sent':
        return 'Gönderildi';
      case 'sending':
        return 'Gönderiliyor';
      case 'failed':
        return 'Başarısız';
      case 'pending':
      default:
        return 'Bekliyor';
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'sent':
        return Icons.check_circle_rounded;
      case 'sending':
        return Icons.send_rounded;
      case 'failed':
        return Icons.cancel_rounded;
      case 'pending':
      default:
        return Icons.pending_rounded;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    
    DateTime dateTime;
    if (date is String) {
      dateTime = DateTime.parse(date);
    } else if (date is DateTime) {
      dateTime = date;
    } else {
      return '-';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Az önce';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} dakika önce';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} saat önce';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else {
      return DateFormat('dd MMM yyyy, HH:mm', 'tr').format(dateTime);
    }
  }
}
