part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Loglar
  // ==========================================================================

  // --- _buildLogsContent ---
  Widget _buildLogsContent() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadLogsData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final data = snapshot.data ?? {};
        final recentUsers =
            (data['recentUsers'] as List<Map<String, dynamic>>?) ?? [];
        final errors = (data['errors'] as List<AnalyticsEvent>?) ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kullanıcı Aktivitesi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      _buildStatCard(
                        icon: Icons.circle,
                        title: 'Şu An Aktif',
                        value: '${data['online'] ?? 0}',
                        color: Colors.green,
                        gradient: [
                          Colors.green.shade400,
                          Colors.green.shade600,
                        ],
                      ),
                      _buildStatCard(
                        icon: Icons.today_rounded,
                        title: 'Günlük Aktif Kullanıcı',
                        value: '${data['dau'] ?? 0}',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                      _buildStatCard(
                        icon: Icons.date_range_rounded,
                        title: 'Haftalık Aktif Kullanıcı',
                        value: '${data['wau'] ?? 0}',
                        color: Colors.purple,
                        gradient: [
                          Colors.purple.shade400,
                          Colors.purple.shade600,
                        ],
                      ),
                      _buildStatCard(
                        icon: Icons.calendar_month_rounded,
                        title: 'Aylık Aktif Kullanıcı',
                        value: '${data['mau'] ?? 0}',
                        color: Colors.indigo,
                        gradient: [
                          Colors.indigo.shade400,
                          Colors.indigo.shade600,
                        ],
                      ),
                      _buildStatCard(
                        icon: Icons.group_rounded,
                        title: 'Toplam Kullanıcı',
                        value: '${data['totalUsers'] ?? 0}',
                        color: Colors.brown,
                        gradient: [
                          Colors.brown.shade400,
                          Colors.brown.shade600,
                        ],
                      ),
                      _buildStatCard(
                        icon: Icons.person_add_rounded,
                        title: 'Bugün Yeni Kayıt',
                        value: '${data['newToday'] ?? 0}',
                        color: Colors.pink,
                        gradient: [Colors.pink.shade400, Colors.pink.shade600],
                      ),
                      _buildStatCard(
                        icon: Icons.analytics_rounded,
                        title: 'Toplam Etkinlik',
                        value: '${data['totalEvents'] ?? 0}',
                        color: Colors.teal,
                        gradient: [Colors.teal.shade400, Colors.teal.shade600],
                      ),
                      _buildStatCard(
                        icon: Icons.timer_rounded,
                        title: 'Ort. Görüntüleme (ms)',
                        value: '${data['avgViewDuration'] ?? 0}',
                        color: Colors.cyan,
                        gradient: [Colors.cyan.shade400, Colors.cyan.shade600],
                      ),
                      _buildStatCard(
                        icon: Icons.error_outline_rounded,
                        title: 'Toplam Hata',
                        value: '${data['errorCount'] ?? 0}',
                        color: Colors.red,
                        gradient: [Colors.red.shade400, Colors.red.shade600],
                      ),
                      _buildStatCard(
                        icon: Icons.person_off_rounded,
                        title: 'Pasif Kullanıcı (30g+)',
                        value: '${data['inactive'] ?? 0}',
                        color: Colors.grey,
                        gradient: [Colors.grey.shade500, Colors.grey.shade700],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Son Aktif Kullanıcılar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Kullanıcı ara...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _logsSearchQuery = v.toLowerCase()),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final filteredUsers = _logsSearchQuery.isEmpty
                      ? recentUsers
                      : recentUsers.where((u) {
                          final name =
                              '${u['full_name'] ?? ''} ${u['username'] ?? ''}'
                                  .toLowerCase();
                          return name.contains(_logsSearchQuery);
                        }).toList();
                  if (filteredUsers.isEmpty) {
                    return const Text('Sonuç bulunamadı.');
                  }
                  return Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredUsers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final u = filteredUsers[index];
                        final isOnline = u['is_online'] == true;
                        final lastSeen = u['last_seen'] != null
                            ? DateTime.parse(u['last_seen']).toLocal()
                            : null;
                        return ListTile(
                          leading: Icon(
                            Icons.circle,
                            size: 12,
                            color: isOnline ? Colors.green : Colors.grey,
                          ),
                          title: Text(
                            u['full_name'] ?? u['username'] ?? 'Bilinmiyor',
                          ),
                          subtitle: lastSeen != null
                              ? Text('Son görülme: $lastSeen')
                              : null,
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Son Hatalar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (errors.isEmpty)
                const Text('Kayıtlı hata yok.')
              else
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: errors.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = errors[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                        ),
                        title: Text(e.metadata?['type']?.toString() ?? 'Hata'),
                        subtitle: Text(
                          '${e.metadata?['details'] ?? ''}\n${e.timestamp.toLocal()}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 24),
              const Text(
                'Hata Tipi Dağılımı',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final counts =
                      (data['errorTypeCounts'] as Map<String, int>?) ?? {};
                  if (counts.isEmpty) return const Text('Veri yok.');
                  final sorted = counts.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));
                  return Card(
                    child: Column(
                      children: sorted
                          .map(
                            (e) => ListTile(
                              dense: true,
                              title: Text(e.key),
                              trailing: Text('${e.value}'),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Saatlik Aktivite Dağılımı',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final hourly =
                      (data['hourlyDistribution'] as Map<int, int>?) ?? {};
                  if (hourly.isEmpty) return const Text('Veri yok.');
                  final maxVal = hourly.values.fold<int>(
                    0,
                    (m, v) => v > m ? v : m,
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: List.generate(24, (h) {
                          final v = hourly[h] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                SizedBox(width: 36, child: Text('$h:00')),
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: maxVal == 0 ? 0 : v / maxVal,
                                    minHeight: 8,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('$v'),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'En Çok Görüntülenen İçerikler',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final mostViewed =
                      (data['mostViewedPosts'] as Map<String, int>?) ?? {};
                  if (mostViewed.isEmpty) return const Text('Veri yok.');
                  return Card(
                    child: Column(
                      children: mostViewed.entries
                          .map(
                            (e) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.visibility_rounded),
                              title: Text(e.key),
                              trailing: Text('${e.value} görüntülenme'),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
