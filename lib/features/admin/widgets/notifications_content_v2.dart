// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// ⚡ GELİŞTİRİLMİŞ Modern Admin Bildirimler Yönetim Ekranı
/// - Kişiye özel bildirim gönderme
/// - Modern UI/UX tasarımı
/// - Gelişmiş istatistikler
/// - Direct push notification desteği
class NotificationsContentV2 extends StatefulWidget {
  const NotificationsContentV2({super.key});

  @override
  State<NotificationsContentV2> createState() => _NotificationsContentV2State();
}

class _NotificationsContentV2State extends State<NotificationsContentV2> {
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
  
  // Kişiye özel bildirim için değişkenler
  bool isLoadingUsers = false;
  List<Map<String, dynamic>> usersList = [];
  String userSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Admin tarafından son gönderilen bildirimleri yükle
      // Aynı başlık ve içeriğe sahip bildirimleri grupla
      final notificationsResponse = await _client
          .from('notifications')
          .select('id, user_id, type, title, content, is_read, created_at, entity_id')
          .order('created_at', ascending: false)
          .limit(1000);
      
      final notifications = List<Map<String, dynamic>>.from(notificationsResponse);
      
      // Grupla: Aynı title+content'a sahip bildirimleri birleştir
      final Map<String, Map<String, dynamic>> groupedNotifications = {};
      
      for (var notif in notifications) {
        final key = '${notif['title']}|${notif['content']}|${notif['created_at'].toString().substring(0, 16)}'; // dakika hassasiyeti
        
        if (groupedNotifications.containsKey(key)) {
          groupedNotifications[key]!['recipients'] = (groupedNotifications[key]!['recipients'] as List) + [notif['user_id']];
          final recipientCount = (groupedNotifications[key]!['recipients'] as List).length;
          groupedNotifications[key]!['sent_count'] = recipientCount;
          groupedNotifications[key]!['delivered_count'] = recipientCount;
          groupedNotifications[key]!['total_recipients'] = recipientCount;
          if (notif['is_read'] == true) {
            groupedNotifications[key]!['read_count'] = (groupedNotifications[key]!['read_count'] as int) + 1;
          } else {
            groupedNotifications[key]!['pending_count'] = (groupedNotifications[key]!['pending_count'] as int) + 1;
          }
        } else {
          groupedNotifications[key] = {
            'id': notif['id'],
            'title': notif['title'],
            'body': notif['content'],
            'created_at': notif['created_at'],
            'type': notif['type'],
            'entity_id': notif['entity_id'],
            'sent_count': 1,
            'delivered_count': 1,
            'read_count': notif['is_read'] == true ? 1 : 0,
            'failed_count': 0,
            'pending_count': notif['is_read'] == false ? 1 : 0,
            'total_recipients': 1,
            'status': 'sent',
            'recipients': [notif['user_id']],
          };
        }
      }
      
      // İstatistikleri hesapla
      int totalSent = 0;
      int totalRead = 0;
      int totalPending = 0;
      
      for (var group in groupedNotifications.values) {
        totalSent += group['total_recipients'] as int;
        totalRead += group['read_count'] as int;
        totalPending += group['pending_count'] as int;
      }
      
      setState(() {
        _pushNotifications = groupedNotifications.values.toList()
          ..sort((a, b) {
            final aDate = a['created_at'] as String;
            final bDate = b['created_at'] as String;
            return bDate.compareTo(aDate);
          });
        _totalSent = totalSent;
        _totalDelivered = totalSent;
        _totalRead = totalRead;
        _totalFailed = 0;
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Push Bildirimleri',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Kullanıcılara anında bildirim gönderin',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => _showSendNotificationDialog(),
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Bildirim Gönder'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
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
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
            Row(
              children: [
                Icon(Icons.analytics_rounded, color: Colors.blue.shade600, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Detaylı İstatistikler',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
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
            
            const Divider(),
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
            const SizedBox(height: 8),
            Text(
              'Yukarıdaki butondan ilk bildirimi gönder',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, color: Colors.grey.shade700, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Son Gönderilen Bildirimler',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
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
    
    // entity_id'den ikon tipini al (format: "admin_icon:discount")
    final entityId = notif['entity_id'] as String? ?? '';
    String? iconType;
    if (entityId.startsWith('admin_icon:')) {
      iconType = entityId.replaceFirst('admin_icon:', '');
    }
    final hasCustomIcon = iconType != null && iconType.isNotEmpty;
    final notifIcon = hasCustomIcon ? getAdminNotificationIcon(iconType) : _getStatusIcon(status);
    final notifIconColor = hasCustomIcon ? getAdminNotificationColor(iconType) : statusColor;
    
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
                      color: notifIconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      notifIcon,
                      color: notifIconColor,
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
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade600),
            const SizedBox(width: 12),
            Expanded(child: Text(notif['title'] ?? '-')),
          ],
        ),
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

  /// ⚡ GELİŞTİRİLMİŞ: Bildirim gönderme dialogu - Kişiye özel bildirim desteği + İkon seçimi
  void _showSendNotificationDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String targetAudience = 'all';
    String? selectedUserId;
    String selectedUserName = '';
    String selectedIconType = 'announcement'; // Varsayılan ikon
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: Colors.blue.shade600, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Push Bildirim Gönder',
                  style: TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Başlık
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Başlık',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.title),
                        contentPadding: EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Mesaj
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: bodyController,
                      decoration: const InputDecoration(
                        labelText: 'Mesaj',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.message),
                        contentPadding: EdgeInsets.all(16),
                      ),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 🎯 İkon Seçimi
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.emoji_emotions_rounded, color: Colors.purple.shade700, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Bildirim İkonu',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.purple.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildIconChip(
                              label: 'Duyuru',
                              icon: Icons.campaign_rounded,
                              color: Colors.blue,
                              isSelected: selectedIconType == 'announcement',
                              onTap: () => setDialogState(() => selectedIconType = 'announcement'),
                            ),
                            _buildIconChip(
                              label: 'İndirim',
                              icon: Icons.discount_rounded,
                              color: Colors.red,
                              isSelected: selectedIconType == 'discount',
                              onTap: () => setDialogState(() => selectedIconType = 'discount'),
                            ),
                            _buildIconChip(
                              label: 'Kampanya',
                              icon: Icons.local_offer_rounded,
                              color: Colors.orange,
                              isSelected: selectedIconType == 'campaign',
                              onTap: () => setDialogState(() => selectedIconType = 'campaign'),
                            ),
                            _buildIconChip(
                              label: 'Haber',
                              icon: Icons.newspaper_rounded,
                              color: Colors.teal,
                              isSelected: selectedIconType == 'news',
                              onTap: () => setDialogState(() => selectedIconType = 'news'),
                            ),
                            _buildIconChip(
                              label: 'Etkinlik',
                              icon: Icons.event_rounded,
                              color: Colors.purple,
                              isSelected: selectedIconType == 'event',
                              onTap: () => setDialogState(() => selectedIconType = 'event'),
                            ),
                            _buildIconChip(
                              label: 'Güncelleme',
                              icon: Icons.system_update_rounded,
                              color: Colors.green,
                              isSelected: selectedIconType == 'update',
                              onTap: () => setDialogState(() => selectedIconType = 'update'),
                            ),
                            _buildIconChip(
                              label: 'Uyarı',
                              icon: Icons.warning_amber_rounded,
                              color: Colors.amber,
                              isSelected: selectedIconType == 'warning',
                              onTap: () => setDialogState(() => selectedIconType = 'warning'),
                            ),
                            _buildIconChip(
                              label: 'Hediye',
                              icon: Icons.card_giftcard_rounded,
                              color: Colors.pink,
                              isSelected: selectedIconType == 'gift',
                              onTap: () => setDialogState(() => selectedIconType = 'gift'),
                            ),
                            _buildIconChip(
                              label: 'Bilgi',
                              icon: Icons.info_rounded,
                              color: Colors.indigo,
                              isSelected: selectedIconType == 'info',
                              onTap: () => setDialogState(() => selectedIconType = 'info'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                   
                  // Hedef kitle seçimi
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.people_rounded, color: Colors.grey.shade700, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Hedef Kitle',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildTargetChip(
                              label: 'Tümü',
                              icon: Icons.public,
                              isSelected: targetAudience == 'all',
                              onTap: () => setDialogState(() {
                                targetAudience = 'all';
                                selectedUserId = null;
                              }),
                            ),
                            _buildTargetChip(
                              label: 'Müşteriler',
                              icon: Icons.person,
                              isSelected: targetAudience == 'customers',
                              onTap: () => setDialogState(() {
                                targetAudience = 'customers';
                                selectedUserId = null;
                              }),
                            ),
                            _buildTargetChip(
                              label: 'Satıcılar',
                              icon: Icons.store,
                              isSelected: targetAudience == 'sellers',
                              onTap: () => setDialogState(() {
                                targetAudience = 'sellers';
                                selectedUserId = null;
                              }),
                            ),
                            _buildTargetChip(
                              label: 'Kişisel',
                              icon: Icons.person_pin_rounded,
                              isSelected: targetAudience == 'personal',
                              onTap: () async {
                                setDialogState(() => targetAudience = 'personal');
                                await _loadUsersForPersonalNotification(setDialogState);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Kişi seçimi
                  if (targetAudience == 'personal') ...[
                    const SizedBox(height: 10),
                    // Arama TextField
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: TextField(
                        onChanged: (value) {
                          setDialogState(() => userSearchQuery = value);
                        },
                        decoration: InputDecoration(
                          hintText: 'Kullanıcı ara...',
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.search, color: Colors.grey.shade600, size: 20),
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (usersList.isNotEmpty)
                      Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: isLoadingUsers
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                itemCount: _filterUsers(userSearchQuery).take(20).length,
                                itemBuilder: (context, index) {
                                  final user = _filterUsers(userSearchQuery)[index];
                                  final isSelected = selectedUserId == user['id'];
                                  return InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        selectedUserId = user['id'];
                                        selectedUserName = user['full_name'] ?? user['username'] ?? '';
                                      });
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.blue.shade100 : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected ? Colors.blue.shade300 : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundImage: user['avatar_url'] != null
                                                ? NetworkImage(user['avatar_url'])
                                                : null,
                                            child: user['avatar_url'] == null
                                                ? Text(
                                                    (user['username'] as String? ?? '?')[0].toUpperCase(),
                                                    style: const TextStyle(fontSize: 12),
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  user['full_name'] ?? user['username'] ?? '-',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '@${user['username'] ?? '-'}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isSelected)
                                            const Icon(Icons.check_circle, color: Colors.blue, size: 18),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    if (usersList.isEmpty && !isLoadingUsers)
                      Container(
                        height: 80,
                        alignment: Alignment.center,
                        child: Text(
                          userSearchQuery.isNotEmpty
                              ? 'Sonuç bulunamadı'
                              : 'Kullanıcı yükleniyor...',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ),
                    if (selectedUserId != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.blue, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Seçili: $selectedUserName',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  
                  const SizedBox(height: 10),
                   
                  // Uyarı mesajı
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Push bildirimleri Firebase FCM üzerinden gönderilir',
                            style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: isSending
                  ? null
                  : () async {
                      if (titleController.text.isEmpty || bodyController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Başlık ve mesaj alanlarını doldurun'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      if (targetAudience == 'personal' && selectedUserId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lütfen bir kullanıcı seçin'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSending = true);

                      try {
                        int sentCount = 0;
                        
                        if (targetAudience == 'personal') {
                          // Kişiye özel - direkt bildirim gönder
                          await _client.from('notifications').insert({
                            'user_id': selectedUserId,
                            'type': 'order',
                            'title': titleController.text.trim(),
                            'content': bodyController.text.trim(),
                            'is_read': false,
                            'entity_id': 'admin_icon:$selectedIconType',
                          });
                          
                          // FCM push gönderimi
                          try {
                            await _client.functions.invoke(
                              'send-push',
                              body: {
                                'user_id': selectedUserId,
                                'title': titleController.text.trim(),
                                'body': bodyController.text.trim(),
                                'data': {'type': 'order', 'icon_type': selectedIconType},
                              },
                            );
                          } catch (e) {
                            debugPrint('Push gönderim hatası: $e');
                          }
                          sentCount = 1;
                        } else {
                          // Bulk notification - hedef kitleye göre kullanıcıları bul
                          List<Map<String, dynamic>> users;
                          
                          if (targetAudience == 'customers') {
                            final response = await _client.from('profiles').select('id').eq('role', 'customer');
                            users = List<Map<String, dynamic>>.from(response);
                          } else if (targetAudience == 'sellers') {
                            final response = await _client.from('profiles').select('id').eq('role', 'seller');
                            users = List<Map<String, dynamic>>.from(response);
                          } else {
                            // 'all' için filtre yok
                            final response = await _client.from('profiles').select('id');
                            users = List<Map<String, dynamic>>.from(response);
                          }
                          
                          if (users.isNotEmpty) {
                            // Her kullanıcı için bildirim oluştur
                            for (final user in users) {
                              try {
                                await _client.from('notifications').insert({
                                  'user_id': user['id'],
                                  'type': 'order',
                                  'title': titleController.text.trim(),
                                  'content': bodyController.text.trim(),
                                  'is_read': false,
                                  'entity_id': 'admin_icon:$selectedIconType',
                                });
                                
                                // FCM push gönderimi
                                try {
                                  await _client.functions.invoke(
                                    'send-push',
                                    body: {
                                      'user_id': user['id'],
                                      'title': titleController.text.trim(),
                                      'body': bodyController.text.trim(),
                                      'data': {'type': 'order', 'icon_type': selectedIconType},
                                    },
                                  );
                                } catch (e) {
                                  debugPrint('Push gönderim hatası: $e');
                                }
                                sentCount++;
                              } catch (e) {
                                debugPrint('Kullanıcıya bildirim gönderilemedi: $e');
                              }
                            }
                          }
                        }

                        // Herkese açık broadcasts tablosuna da ekle (üye olmayanlar da görsün)
                        if (targetAudience != 'personal') {
                          try {
                            await _client.from('admin_broadcasts').insert({
                              'title': titleController.text.trim(),
                              'content': bodyController.text.trim(),
                              'icon_type': selectedIconType,
                              'target_audience': targetAudience,
                              'is_active': true,
                            });
                            debugPrint('✅ Broadcasts tablosuna eklendi');
                          } catch (e) {
                            debugPrint('⚠️ Broadcasts tablosuna eklenemedi (tablo yok olabilir): $e');
                          }
                        }

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ $sentCount kişiye bildirim gönderildi',
                            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(isSending ? 'Gönderiliyor...' : 'Gönder'),
            ),
          ],
        ),
      ),
    );
  }

  /// Kişiye özel bildirim için kullanıcıları yükle
  Future<void> _loadUsersForPersonalNotification(StateSetter setDialogState) async {
    setDialogState(() => isLoadingUsers = true);
    
    try {
      final response = await _client
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .order('created_at', ascending: false)
          .limit(100);
      
      setDialogState(() {
        usersList = List<Map<String, dynamic>>.from(response);
        isLoadingUsers = false;
        userSearchQuery = '';
      });
    } catch (e) {
      setDialogState(() => isLoadingUsers = false);
      debugPrint('Kullanıcılar yüklenirken hata: $e');
    }
  }

  /// Kullanıcı arama filtresi
  List<Map<String, dynamic>> _filterUsers(String query) {
    if (query.isEmpty) return usersList;
    
    final lowerQuery = query.toLowerCase();
    return usersList.where((user) {
      final username = (user['username'] as String? ?? '').toLowerCase();
      final fullName = (user['full_name'] as String? ?? '').toLowerCase();
      return username.contains(lowerQuery) || fullName.contains(lowerQuery);
    }).toList();
  }

  /// Modern hedef seçim chip'i
  Widget _buildTargetChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade600 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.blue.shade600 : Colors.grey.shade300,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// İkon seçim chip'i
  Widget _buildIconChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Admin bildirim ikon tipinden IconData döndür
  static IconData getAdminNotificationIcon(String? iconType) {
    switch (iconType) {
      case 'announcement':
        return Icons.campaign_rounded;
      case 'discount':
        return Icons.discount_rounded;
      case 'campaign':
        return Icons.local_offer_rounded;
      case 'news':
        return Icons.newspaper_rounded;
      case 'event':
        return Icons.event_rounded;
      case 'update':
        return Icons.system_update_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'gift':
        return Icons.card_giftcard_rounded;
      case 'info':
        return Icons.info_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  /// Admin bildirim ikon tipinden renk döndür
  static Color getAdminNotificationColor(String? iconType) {
    switch (iconType) {
      case 'announcement':
        return Colors.blue;
      case 'discount':
        return Colors.red;
      case 'campaign':
        return Colors.orange;
      case 'news':
        return Colors.teal;
      case 'event':
        return Colors.purple;
      case 'update':
        return Colors.green;
      case 'warning':
        return Colors.amber;
      case 'gift':
        return Colors.pink;
      case 'info':
        return Colors.indigo;
      default:
        return Colors.blue;
    }
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
