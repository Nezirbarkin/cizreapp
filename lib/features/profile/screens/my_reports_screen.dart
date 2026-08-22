import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/profile_service.dart';
import '../../social/services/post_report_service.dart';
import '../../../core/providers/theme_provider.dart';
import 'user_profile_screen.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> with SingleTickerProviderStateMixin {
  final _profileService = ProfileService();
  final _postReportService = PostReportService();
  late TabController _tabController;
  List<Map<String, dynamic>> _userReports = [];
  List<Map<String, dynamic>> _postReports = [];
  bool _isLoading = true;
  // Realtime kanal referansları — dispose'ta removeChannel için tutulur.
  RealtimeChannel? _userReportsChannel;
  RealtimeChannel? _postReportsChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReports();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    // Hayalet kanal + postgres değişiklik dinleyici sızıntısını önle:
    // ekran her açılış/kapanışında referansları kapat.
    final client = Supabase.instance.client;
    if (_userReportsChannel != null) client.removeChannel(_userReportsChannel!);
    if (_postReportsChannel != null) client.removeChannel(_postReportsChannel!);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    try {
      final userReportsFuture = _profileService.getMyReports();
      final postReportsFuture = _postReportService.getMyPostReports();
      
      final results = await Future.wait([userReportsFuture, postReportsFuture]);
      
      setState(() {
        _userReports = results[0];
        _postReports = results[1];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Şikayetler yüklenemedi: $e');
      setState(() => _isLoading = false);
    }
  }

  void _setupRealtimeSubscription() {
    final client = Supabase.instance.client;
    // Yalnızca kullanıcının KENDİ şikayetleri filtrelenir (reporter_id = userId).
    // Filtresiz olsaydı tüm şikayet değişiklikleri buraya düşerdi.
    final userId = client.auth.currentUser?.id;

    final userReportsFilter = userId == null
        ? null
        : PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'reporter_id',
            value: userId,
          );

    final postReportsFilter = userId == null
        ? null
        : PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'reporter_id',
            value: userId,
          );

    // Kullanıcı şikayetleri için realtime
    _userReportsChannel = client
        .channel('user_reports_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_reports',
          filter: userReportsFilter,
          callback: (payload) {
            debugPrint('Kullanıcı şikayeti güncellendi: $payload');
            if (mounted) {
              _loadReports();
              _showNotificationSnackBar('Şikayetinize yanıt geldi!');
            }
          },
        )
        .subscribe();

    // Gönderi şikayetleri için realtime
    _postReportsChannel = client
        .channel('post_reports_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'post_reports',
          filter: postReportsFilter,
          callback: (payload) {
            debugPrint('Gönderi şikayeti güncellendi: $payload');
            if (mounted) {
              _loadReports();
              _showNotificationSnackBar('Gönderi şikayetinize yanıt geldi!');
            }
          },
        )
        .subscribe();
  }

  void _showNotificationSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _getReasonText(String reason) {
    switch (reason) {
      case 'spam':
        return 'Spam/Reklam';
      case 'harassment':
        return 'Taciz/Rahatsızlık';
      case 'fake':
        return 'Sahte Hesap';
      case 'inappropriate':
        return 'Uygunsuz İçerik';
      case 'other':
        return 'Diğer';
      case 'inappropriate_content':
        return 'Uygunsuz İçerik';
      default:
        return reason;
    }
  }

  Color _getStatusColor(String status) {
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

  String _getStatusText(String status) {
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: themeProvider.primaryColor,
        elevation: 0,
        title: const Text(
          'Şikayetlerim',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person, size: 18),
                  const SizedBox(width: 8),
                  Text('Kullanıcı (${_userReports.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.article, size: 18),
                  const SizedBox(width: 8),
                  Text('Gönderi (${_postReports.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Kullanıcı Şikayetleri
                _buildUserReportsList(),
                // Gönderi Şikayetleri
                _buildPostReportsList(),
              ],
            ),
    );
  }

  Widget _buildUserReportsList() {
    if (_userReports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Henüz kullanıcı şikayetiniz yok',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _userReports.length,
        itemBuilder: (context, index) {
          final report = _userReports[index];
          final user = report['reported_user'];
          if (user == null) return const SizedBox.shrink();

          final username = user['username'] ?? 'Kullanıcı';
          final fullName = user['full_name'] ?? username;
          final avatarUrl = user['avatar_url'];
          final reason = report['reason'] ?? '';
          final description = report['description'];
          final status = report['status'] ?? 'pending';
          final adminResponse = report['admin_response'] as String?;
          final reportDate = DateTime.parse(report['created_at']);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                backgroundColor: Colors.grey.shade300,
                child: avatarUrl == null
                    ? Text(
                        username.isNotEmpty
                            ? username.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              title: Text(
                fullName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@$username'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusText(status),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(reportDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 20, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            'Şikayet Nedeni: ${_getReasonText(reason)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      if (description != null && description.toString().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Açıklama:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description.toString(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                      ],
                      // Admin Yanıtı
                      if (adminResponse != null && adminResponse.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Admin Yanıtı',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                adminResponse,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade900,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserProfileScreen(userId: user['id']),
                              ),
                            );
                          },
                          icon: const Icon(Icons.person, size: 18),
                          label: const Text('Profili Görüntüle'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostReportsList() {
    if (_postReports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Henüz gönderi şikayetiniz yok',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _postReports.length,
        itemBuilder: (context, index) {
          final report = _postReports[index];
          final rawPost = report['reported_post'];
          // Join sorgusunda foreign key bir liste dönebilir
          final post = rawPost is List ? (rawPost.isNotEmpty ? rawPost.first : null) : rawPost;
          final content = (post?['content'] as String?) ?? 'Görsel içerik';
          final reason = report['reason'] ?? '';
          final description = report['description'];
          final status = report['status'] ?? 'pending';
          final adminResponse = report['admin_response'] as String?;
          final reportDate = DateTime.parse(report['created_at']);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.orange.shade100,
                child: Icon(Icons.article, color: Colors.orange.shade700),
              ),
              title: Text(
                content.length > 30 ? '${content.substring(0, 30)}...' : content,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusText(status),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(reportDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gönderi içeriği
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.article, size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                content,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 20, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            'Şikayet Nedeni: ${_getReasonText(reason)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      if (description != null && description.toString().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Açıklama:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description.toString(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                      ],
                      // Admin Yanıtı
                      if (adminResponse != null && adminResponse.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Admin Yanıtı',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                adminResponse,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade900,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Bugün ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Dün';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} gün önce';
    } else {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
  }
}
