part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Sikayetler + rapor kartlari + detay/silme
  // ==========================================================================

  // --- _buildReportsContent ---
  Widget _buildReportsContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final reports = snapshot.data ?? [];

        // İstatistikler (her iki tür için)
        final userPendingCount = reports
            .where((r) => r['status'] == 'pending')
            .length;
        final userReviewingCount = reports
            .where((r) => r['status'] == 'reviewing')
            .length;
        final userResolvedCount = reports
            .where((r) => r['status'] == 'resolved')
            .length;
        final userRejectedCount = reports
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
                // ==================== KULLANICI ŞİKAYETLERİ ====================
                const Text(
                  'Kullanıcı Şikayetleri',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // İstatistik Kartları (Kullanıcı)
                Row(
                  children: [
                    Expanded(
                      child: _buildReportStatCard(
                        icon: Icons.pending,
                        title: 'Bekleyen',
                        count: userPendingCount,
                        status: 'pending',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildReportStatCard(
                        icon: Icons.visibility,
                        title: 'İnceleniyor',
                        count: userReviewingCount,
                        status: 'reviewing',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildReportStatCard(
                        icon: Icons.check_circle,
                        title: 'Çözüldü',
                        count: userResolvedCount,
                        status: 'resolved',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildReportStatCard(
                        icon: Icons.cancel,
                        title: 'Reddedildi',
                        count: userRejectedCount,
                        status: 'rejected',
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
                            'Şikayet bulunamadı',
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
                      final reported =
                          report['reported'] as Map<String, dynamic>?;
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
                          onTap: () => _showReportDetailDialog(report),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Başlık - Durum ve İşlemler
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
                                          _showDeleteReportDialog(report),
                                      tooltip: 'Sil',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Şikayet Eden
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
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.person,
                                                size: 12,
                                                color: Colors.blue.shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                reporter?['full_name'] ??
                                                    reporter?['username'] ??
                                                    'Bilinmeyen',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
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
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundImage:
                                          reported?['avatar_url'] != null
                                          ? NetworkImage(
                                              reported!['avatar_url'],
                                            )
                                          : null,
                                      child: reported?['avatar_url'] == null
                                          ? Text(
                                              (reported?['username'] as String?)
                                                      ?.substring(0, 1)
                                                      .toUpperCase() ??
                                                  '?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red.shade700,
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
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.person_off,
                                                size: 12,
                                                color: Colors.red.shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  reported?['full_name'] ??
                                                      reported?['username'] ??
                                                      'Bilinmeyen',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            'Şikayet edilen',
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

                                // Şikayet Sebebi
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
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
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red.shade900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Açıklama (varsa)
                                if (report['description'] != null &&
                                    (report['description'] as String)
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.description_outlined,
                                          color: Colors.grey.shade700,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            report['description'],
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 13,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                // Tarih
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDate(report['created_at']),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 32),
                const Divider(thickness: 2),
                const SizedBox(height: 16),

                // ==================== GÖNDERT ŞİKAYETLERİ ====================
                const Text(
                  'Gönderi Şikayetleri',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Gönderi şikayetlerini yükle
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadPostReports(),
                  builder: (context, postSnapshot) {
                    if (postSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final postReports = postSnapshot.data ?? [];
                    final postPendingCount = postReports
                        .where((r) => r['status'] == 'pending')
                        .length;
                    final postReviewingCount = postReports
                        .where((r) => r['status'] == 'reviewing')
                        .length;
                    final postResolvedCount = postReports
                        .where((r) => r['status'] == 'resolved')
                        .length;
                    final postRejectedCount = postReports
                        .where((r) => r['status'] == 'rejected')
                        .length;

                    return Column(
                      children: [
                        // İstatistik Kartları (Gönderi)
                        Row(
                          children: [
                            Expanded(
                              child: _buildReportStatCard(
                                icon: Icons.pending,
                                title: 'Bekleyen',
                                count: postPendingCount,
                                status: 'pending',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildReportStatCard(
                                icon: Icons.visibility,
                                title: 'İnceleniyor',
                                count: postReviewingCount,
                                status: 'reviewing',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildReportStatCard(
                                icon: Icons.check_circle,
                                title: 'Çözüldü',
                                count: postResolvedCount,
                                status: 'resolved',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildReportStatCard(
                                icon: Icons.cancel,
                                title: 'Reddedildi',
                                count: postRejectedCount,
                                status: 'rejected',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        if (postReports.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.post_add_outlined,
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
                            itemCount: postReports.length,
                            itemBuilder: (context, index) {
                              final report = postReports[index];
                              final reporter =
                                  report['reporter'] as Map<String, dynamic>?;
                              final reportedPost =
                                  report['reported_post']
                                      as Map<String, dynamic>?;
                              final status =
                                  report['status'] as String? ?? 'pending';

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
                                  onTap: () =>
                                      _showPostReportDetailDialog(report),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Başlık - Durum ve İşlemler
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getReportStatusColor(
                                                  status,
                                                ).withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    _getReportStatusIcon(
                                                      status,
                                                    ),
                                                    size: 14,
                                                    color:
                                                        _getReportStatusColor(
                                                          status,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _getReportStatusText(
                                                      status,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          _getReportStatusColor(
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
                                                  _showDeletePostReportDialog(
                                                    report,
                                                  ),
                                              tooltip: 'Sil',
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        // Şikayet Eden -> Gönderi
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundImage:
                                                  reporter?['avatar_url'] !=
                                                      null
                                                  ? NetworkImage(
                                                      reporter!['avatar_url'],
                                                    )
                                                  : null,
                                              child:
                                                  reporter?['avatar_url'] ==
                                                      null
                                                  ? Text(
                                                      (reporter?['username']
                                                                  as String?)
                                                              ?.substring(0, 1)
                                                              .toUpperCase() ??
                                                          '?',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .blue
                                                            .shade700,
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
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.person,
                                                        size: 12,
                                                        color: Colors
                                                            .blue
                                                            .shade700,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        reporter?['full_name'] ??
                                                            reporter?['username'] ??
                                                            'Bilinmeyen',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    'Şikayet eden',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          Colors.grey.shade600,
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
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.article_outlined,
                                                        size: 12,
                                                        color: Colors
                                                            .orange
                                                            .shade700,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          (reportedPost?['title'] ??
                                                                  (reportedPost?['content'] !=
                                                                              null &&
                                                                          (reportedPost?['content']
                                                                                  as String)
                                                                              .isNotEmpty
                                                                      ? ((reportedPost?['content']
                                                                                        as String)
                                                                                    .length >
                                                                                20
                                                                            ? (reportedPost?['content']
                                                                                      as String)
                                                                                  .substring(
                                                                                    0,
                                                                                    20,
                                                                                  )
                                                                            : reportedPost?['content'])
                                                                      : 'Gönderi')) ??
                                                              'Gönderi',
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14,
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    'Gönderi',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        // Şikayet Sebebi
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.flag,
                                                color: Colors.orange.shade700,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  report['reason'] ?? '-',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        Colors.orange.shade900,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Açıklama (varsa)
                                        if (report['description'] != null &&
                                            (report['description'] as String)
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.description_outlined,
                                                  color: Colors.grey.shade700,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    report['description'],
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade700,
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],

                                        const SizedBox(height: 12),

                                        // Tarih
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.access_time,
                                              size: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _formatDate(report['created_at']),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
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

  // --- _buildReportStatCard ---
  Widget _buildReportStatCard({
    required IconData icon,
    required String title,
    required int count,
    required String status,
  }) {
    final color = _getReportStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // --- _togglePin ---
  Future<void> _togglePin(String table, String id, bool pin) async {
    try {
      debugPrint('📌 SABİTLEME BAŞLADI: table=$table, id=$id, pin=$pin');

      // Önce mevcut durumu oku
      try {
        final currentData = await Supabase.instance.client
            .from(table)
            .select('is_pinned, admin_pinned')
            .eq('id', id)
            .maybeSingle();
        debugPrint(
          '📌 MEVCUT DURUM: is_pinned=${currentData?['is_pinned']}, admin_pinned=${currentData?['admin_pinned']}',
        );
      } catch (e) {
        debugPrint('⚠️ Mevcut durum okunamadı: $e');
      }

      // RPC fonksiyonu adını belirle
      String rpcFunction = 'admin_pin_$table';
      if (table == 'posts') {
        rpcFunction = 'admin_pin_post';
      } else if (table == 'stories') {
        rpcFunction = 'admin_pin_story';
      } else if (table == 'products') {
        rpcFunction = 'admin_pin_product';
      } else if (table == 'shops') {
        rpcFunction = 'admin_pin_shop';
      }

      // Önce RPC ile dene
      bool pinned = false;
      try {
        // Doğru parametre adını belirle: stories -> story_id, posts -> post_id
        String paramIdName = '${table.substring(0, table.length - 1)}_id';
        // stories -> story_id (duzeltme), posts -> post_id
        if (table == 'stories') paramIdName = 'story_id';
        debugPrint(
          '📌 RPC çağrılıyor: $rpcFunction, params: $paramIdName=$id, pinned=$pin',
        );
        final rpcResponse = await Supabase.instance.client.rpc(
          rpcFunction,
          params: {paramIdName: id, 'pinned': pin},
        );
        debugPrint('✅ RPC sabitleme yanıtı: $rpcResponse');
        pinned = true;

        // RPC başarılı olsa bile ek olarak admin_pinned sütununu güncelle
        // Stories için de admin_pinned güncellemesi yapmalıyız!
        if (table == 'posts' || table == 'stories') {
          try {
            debugPrint('📌 Ek admin_pinned güncellemesi yapılıyor: $pin');
            final updateResponse = await Supabase.instance.client
                .from(table)
                .update({'admin_pinned': pin})
                .eq('id', id)
                .select();
            debugPrint(
              '✅ Ek admin_pinned güncellemesi yapıldı: $pin, yanıt: $updateResponse',
            );
          } catch (e) {
            debugPrint('⚠️ admin_pinned güncelleme hatası (yoksayıldı): $e');
          }
        }
      } catch (rpcError) {
        debugPrint(
          '⚠️ RPC hatası (fonksiyon yok olabilir), doğrudan güncelleme deneniyor: $rpcError',
        );
        // RPC başarısız olursa doğrudan güncelle
        // Stories ve Posts tablosu hem is_pinned hem admin_pinned kullanır
        final Map<String, dynamic> updates;
        if (table == 'stories' || table == 'posts') {
          // Her iki kolonu da güncelle (sabitleme durumunu senkronize tut)
          updates = {'is_pinned': pin, 'admin_pinned': pin};
        } else {
          updates = {'admin_pinned': pin};
        }

        final response = await Supabase.instance.client
            .from(table)
            .update(updates)
            .eq('id', id)
            .select();

        debugPrint('✅ Doğrudan sabitleme yanıtı: $response');
        if (response.isNotEmpty) {
          pinned = true;
        }
      }

      if (mounted) {
        if (pinned) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(pin ? 'İçerik sabitlendi' : 'Sabitleme kaldırıldı'),
              backgroundColor: pin
                  ? Colors.amber.shade700
                  : Colors.grey.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
          setState(() {});
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sabitleme yapılamadı - RLS izni kontrol edin'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Pin toggle hatası: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sabitleme hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // --- _showReportDetailDialog ---
  void _showReportDetailDialog(Map<String, dynamic> report) {
    final reporter = report['reporter'] as Map<String, dynamic>?;
    final reported = report['reported'] as Map<String, dynamic>?;
    String selectedStatus = report['status'] ?? 'pending';
    final adminResponseController = TextEditingController(
      text: report['admin_response'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade400, Colors.red.shade600],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flag, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Şikayet Detayı',
                      style: TextStyle(fontSize: 16),
                    ),
                    Text(
                      _formatDate(report['created_at']),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Durum
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getReportStatusColor(
                          selectedStatus,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getReportStatusIcon(selectedStatus),
                            size: 14,
                            color: _getReportStatusColor(selectedStatus),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getReportStatusText(selectedStatus),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getReportStatusColor(selectedStatus),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Şikayet Eden Bilgisi
                  const Text(
                    'Şikayet Eden',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.blue.shade200,
                            backgroundImage: reporter?['avatar_url'] != null
                                ? NetworkImage(reporter!['avatar_url'])
                                : null,
                            child: reporter?['avatar_url'] == null
                                ? Text(
                                    (reporter?['username'] as String?)
                                            ?.substring(0, 1)
                                            .toUpperCase() ??
                                        '?',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reporter?['full_name'] ??
                                      reporter?['username'] ??
                                      'Bilinmeyen',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  reporter?['email'] ?? '-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Şikayet Edilen Bilgisi
                  const Text(
                    'Şikayet Edilen',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.red.shade200,
                            backgroundImage: reported?['avatar_url'] != null
                                ? NetworkImage(reported!['avatar_url'])
                                : null,
                            child: reported?['avatar_url'] == null
                                ? Text(
                                    (reported?['username'] as String?)
                                            ?.substring(0, 1)
                                            .toUpperCase() ??
                                        '?',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade800,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reported?['full_name'] ??
                                      reported?['username'] ??
                                      'Bilinmeyen',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  reported?['email'] ?? '-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Şikayet Sebebi
                  const Text(
                    'Şikayet Sebebi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.flag, color: Colors.red.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            report['reason'] ?? '-',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Açıklama
                  if (report['description'] != null &&
                      (report['description'] as String).isNotEmpty) ...[
                    const Text(
                      'Açıklama',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        report['description'] ?? '-',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Durum Değiştir
                  const Text(
                    'Durum',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      _buildReportStatusOption(
                        status: 'pending',
                        label: 'Bekliyor',
                        icon: Icons.pending,
                        color: Colors.orange,
                        selectedStatus: selectedStatus,
                        onTap: () =>
                            setDialogState(() => selectedStatus = 'pending'),
                      ),
                      const SizedBox(height: 8),
                      _buildReportStatusOption(
                        status: 'reviewing',
                        label: 'İnceleniyor',
                        icon: Icons.visibility,
                        color: Colors.blue,
                        selectedStatus: selectedStatus,
                        onTap: () =>
                            setDialogState(() => selectedStatus = 'reviewing'),
                      ),
                      const SizedBox(height: 8),
                      _buildReportStatusOption(
                        status: 'resolved',
                        label: 'Çözüldü',
                        icon: Icons.check_circle,
                        color: Colors.green,
                        selectedStatus: selectedStatus,
                        onTap: () =>
                            setDialogState(() => selectedStatus = 'resolved'),
                      ),
                      const SizedBox(height: 8),
                      _buildReportStatusOption(
                        status: 'rejected',
                        label: 'Reddedildi',
                        icon: Icons.cancel,
                        color: Colors.red,
                        selectedStatus: selectedStatus,
                        onTap: () =>
                            setDialogState(() => selectedStatus = 'rejected'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Admin Cevabı
                  const Text(
                    'Admin Notu',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: adminResponseController,
                    decoration: InputDecoration(
                      hintText: 'Notunuzu yazın...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Kaydet'),
              onPressed: () async {
                try {
                  debugPrint(
                    '📝 Şikayet güncelleniyor: ${report['id']} -> $selectedStatus',
                  );

                  final oldResponse = report['admin_response'] as String? ?? '';
                  final newResponse = adminResponseController.text.trim();
                  final oldStatus = report['status'] as String? ?? '';

                  // Durum değiştiyse VEYA admin yanıtı eklendi/degistiyse bildirim gönder
                  final shouldNotify =
                      selectedStatus != oldStatus ||
                      (newResponse.isNotEmpty && newResponse != oldResponse);

                  if (shouldNotify) {
                    try {
                      final notificationMessage = newResponse.isNotEmpty
                          ? 'Şikayet talebinize yanıt geldi: ${newResponse.substring(0, newResponse.length > 50 ? 50 : newResponse.length)}...'
                          : 'Şikayet durumunuz güncellendi: ${_getReportStatusText(selectedStatus)}';

                      await Supabase.instance.client
                          .from('notifications')
                          .insert({
                            'user_id': report['reporter_id'],
                            'type': 'admin_notification',
                            'title': 'Şikayet Güncellemesi',
                            'content': notificationMessage,
                            'metadata': {
                              'report_id': report['id'],
                              'status': selectedStatus,
                              'admin_response': newResponse,
                              'report_type': 'user_report',
                            },
                            'is_read': false,
                            'created_at': DateTime.now().toIso8601String(),
                          });
                      debugPrint('✅ Bildirim gönderildi: $notificationMessage');
                    } catch (notifError) {
                      debugPrint('⚠️ Bildirim gönderilemedi: $notifError');
                    }
                  }

                  await Supabase.instance.client
                      .from('user_reports')
                      .update({
                        'status': selectedStatus,
                        'admin_response': newResponse.isNotEmpty
                            ? newResponse
                            : oldResponse,
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', report['id']);

                  debugPrint('✅ Şikayet başarıyla güncellendi');

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Şikayet güncellendi: ${_getReportStatusText(selectedStatus)}',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e, stackTrace) {
                  debugPrint('❌ Şikayet güncellenirken hata: $e');
                  debugPrint('📍 Stack trace: $stackTrace');

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Şikayet güncellenirken hata: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- _buildReportStatusOption ---
  Widget _buildReportStatusOption({
    required String status,
    required String label,
    required IconData icon,
    required Color color,
    required String selectedStatus,
    required VoidCallback onTap,
  }) {
    final isSelected = status == selectedStatus;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.grey.shade700,
                ),
              ),
            ),
            if (isSelected) Icon(Icons.check, color: color),
          ],
        ),
      ),
    );
  }

  // --- _showDeleteReportDialog ---
  void _showDeleteReportDialog(Map<String, dynamic> report) {
    final reporter = report['reporter'] as Map<String, dynamic>?;
    final reported = report['reported'] as Map<String, dynamic>?;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete, color: Colors.red),
            SizedBox(width: 8),
            Text('Şikayeti Sil'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bu şikayeti silmek istediğinizden emin misiniz?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        'Şikayet Eden: ${reporter?['full_name'] ?? reporter?['username'] ?? '-'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_off, size: 14, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(
                        'Şikayet Edilen: ${reported?['full_name'] ?? reported?['username'] ?? '-'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.flag, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Sebep: ${report['reason'] ?? '-'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu işlem geri alınamaz. Şikayet kalıcı olarak silinecektir.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                debugPrint('🗑️ Şikayet siliniyor: ${report['id']}');

                await Supabase.instance.client
                    .from('user_reports')
                    .delete()
                    .eq('id', report['id']);

                debugPrint('✅ Şikayet başarıyla silindi');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Şikayet başarıyla silindi'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('❌ Şikayet silinirken hata: $e');
                debugPrint('📍 Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Şikayet silinirken hata: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
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

  // --- _getReportStatusText ---
  String _getReportStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Bekliyor';
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

  // --- _callCustomerFromAdmin ---
  Future<void> _callCustomerFromAdmin(String phoneNumber) async {
    try {
      final uri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Telefon uygulaması açılamadı')),
          );
        }
      }
    } catch (e) {
      debugPrint('Telefon arama hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Arama yapılırken hata: $e')));
      }
    }
  }

  // --- _openAddressInMap ---
  Future<void> _openAddressInMap(String address) async {
    try {
      // Google Maps ile adresi aç
      final encodedAddress = Uri.encodeComponent(address);
      final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encodedAddress',
      );

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Harita uygulaması açılamadı')),
          );
        }
      }
    } catch (e) {
      debugPrint('Harita açma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Harita açılırken hata: $e')));
      }
    }
  }
}
