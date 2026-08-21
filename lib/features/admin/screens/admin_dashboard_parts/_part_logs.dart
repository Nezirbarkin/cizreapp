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
  // Loglar
  // ==========================================================================

  // --- _refreshLogsData ---
  // Future'i state alaninda (`_logsDataFuture`) tutuyoruz — build() icinde
  // dogrudan _loadLogsData() cagirmak, arama kutusundaki her tus vurusunda
  // (setState(_logsSearchQuery) -> rebuild) YENI bir future olusturup
  // FutureBuilder'i "waiting" durumuna dusuruyordu: liste + arama kutusunun
  // kendisi her karakterde yukleniyor spinner'ina donusuyor, odak kayboluyor
  // ve arka planda gereksiz sorgular tekrar tekrar atiliyordu.
  void _refreshLogsData() {
    if (!mounted) return;
    setState(() => _logsDataFuture = _loadLogsData());
  }

  // --- _buildLogsContent ---
  Widget _buildLogsContent() {
    _logsDataFuture ??= _loadLogsData();
    return FutureBuilder<Map<String, dynamic>>(
      future: _logsDataFuture,
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
        final windowDays = (data['windowDays'] as int?) ?? _logsWindowDays;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Kullanıcı Aktivitesi',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<int>(
                        value: _logsWindowDays,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Son 1 gün')),
                          DropdownMenuItem(value: 7, child: Text('Son 7 gün')),
                          DropdownMenuItem(value: 30, child: Text('Son 30 gün')),
                          DropdownMenuItem(value: 90, child: Text('Son 90 gün')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _logsWindowDays = value);
                          _refreshLogsData();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Yenile',
                        onPressed: _refreshLogsData,
                      ),
                    ],
                  ),
                ],
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
                        title: 'Toplam Etkinlik (tüm zaman)',
                        value: '${data['totalEvents'] ?? 0}',
                        color: Colors.teal,
                        gradient: [Colors.teal.shade400, Colors.teal.shade600],
                      ),
                      _buildStatCard(
                        icon: Icons.visibility_rounded,
                        title: 'Gönderi Görüntüleme ($windowDays g)',
                        value: '${data['postViewCount'] ?? 0}',
                        color: Colors.deepPurple,
                        gradient: [
                          Colors.deepPurple.shade400,
                          Colors.deepPurple.shade600,
                        ],
                      ),
                      _buildStatCard(
                        icon: Icons.timer_rounded,
                        title: 'Ort. Görüntüleme (ms, $windowDays g)',
                        value: '${data['avgViewDuration'] ?? 0}',
                        color: Colors.cyan,
                        gradient: [Colors.cyan.shade400, Colors.cyan.shade600],
                      ),
                      _buildStatCard(
                        icon: Icons.error_outline_rounded,
                        title: 'Hata ($windowDays g)',
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
                'Platform Dağılımı',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final platformCounts =
                      (data['platformCounts'] as Map<String, Map<String, int>>?) ??
                      const {};
                  if (platformCounts.isEmpty) {
                    return const Text('Veri yok.');
                  }
                  const labels = {
                    'ios': 'iOS',
                    'android': 'Android',
                    'web': 'Web',
                    'unknown': 'Bilinmeyen',
                  };
                  const icons = {
                    'ios': Icons.phone_iphone_rounded,
                    'android': Icons.android_rounded,
                    'web': Icons.language_rounded,
                    'unknown': Icons.device_unknown_rounded,
                  };
                  final order = ['ios', 'android', 'web', 'unknown'];
                  final keys = [
                    ...order.where(platformCounts.containsKey),
                    ...platformCounts.keys.where((k) => !order.contains(k)),
                  ];
                  return Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: keys.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final key = keys[index];
                        final counts = platformCounts[key] ?? const {};
                        return ListTile(
                          dense: true,
                          leading: Icon(icons[key] ?? Icons.devices_rounded),
                          title: Text(labels[key] ?? key),
                          subtitle: Text('Toplam: ${counts['total'] ?? 0}'),
                          trailing: Text(
                            'Şu an aktif: ${counts['online'] ?? 0}',
                          ),
                        );
                      },
                    ),
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
                        const platformIcons = {
                          'ios': Icons.phone_iphone_rounded,
                          'android': Icons.android_rounded,
                          'web': Icons.language_rounded,
                        };
                        final platformIcon =
                            platformIcons[u['platform']] ??
                            Icons.device_unknown_rounded;
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
                          trailing: Icon(
                            platformIcon,
                            size: 18,
                            color: Colors.grey.shade600,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Son Hatalar (son $windowDays gün)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (errors.isEmpty)
                Text('Son $windowDays günde kayıtlı hata yok.')
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
              Text(
                'Hata Tipi Dağılımı (son $windowDays gün)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
              // Hangi olcumun gercekten toplandigini gosterir. Bos bir kart ile
              // hic yazilmayan bir event tipi arasindaki farki ancak bu ayirt
              // ettiriyor.
              Text(
                'Etkinlik Tipi Dağılımı (son $windowDays gün)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final counts =
                      (data['eventTypeCounts'] as Map<String, int>?) ?? {};
                  if (counts.isEmpty) {
                    return Text('Son $windowDays günde etkinlik kaydı yok.');
                  }
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
              Text(
                'Saatlik Aktivite Dağılımı (son $windowDays gün)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
              Text(
                'En Çok Görüntülenen İçerikler (son $windowDays gün)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final mostViewed =
                      (data['mostViewedPosts'] as List<Map<String, dynamic>>?) ??
                      const [];
                  if (mostViewed.isEmpty) return const Text('Veri yok.');
                  return Card(
                    child: Column(
                      children: mostViewed
                          .map(
                            (post) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.visibility_rounded),
                              title: Text(
                                post['label'] as String? ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${post['post_id']}',
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                '${post['view_count']} görüntülenme',
                              ),
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
