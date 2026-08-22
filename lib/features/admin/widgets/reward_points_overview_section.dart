import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/admin_reward_overview_model.dart';
import '../../../core/services/ad_settings_service.dart';

/// Ödül puan (rewarded-ad) kazanç özeti: bugünkü verilen puan, son
/// doğrulanmış olaylar ve en çok kazananlar.
///
/// Hem "Reklam Ayarları" ekranında (AdMob/SSV yapılandırmasıyla birlikte)
/// hem de "Ödemeler" hub'ının "Ödül/Reklam Kazançları" sekmesinde aynı
/// `admin_reward_points_overview` RPC'sinden beslenerek kullanılır.
class RewardPointsOverviewSection extends StatefulWidget {
  const RewardPointsOverviewSection({super.key});

  @override
  State<RewardPointsOverviewSection> createState() =>
      _RewardPointsOverviewSectionState();
}

class _RewardPointsOverviewSectionState
    extends State<RewardPointsOverviewSection> {
  final _service = AdSettingsService();
  AdminRewardOverview? _overview;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final overview = await _service.getAdminOverview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (error) {
      debugPrint(
        '[RewardPointsOverviewSection] overview_load_failed '
        'errorType=${error.runtimeType} error=$error',
      );
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Widget _todayCard() {
    final today = _overview?.today;
    if (today == null) {
      return _section('Bugünkü Kazanımlar', const [Text('Rapor yüklenemedi.')]);
    }
    final budgetPct = (today.budgetUsedFraction * 100).toStringAsFixed(1);
    return _section('Bugünkü Kazanımlar', [
      Row(
        children: [
          Expanded(
            child: _metricTile(
              'Verilen puan',
              '${today.grantedPoints}',
              Icons.stars_rounded,
              Colors.amber,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metricTile(
              'İzleme',
              '${today.grantCount}',
              Icons.play_circle_rounded,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metricTile(
              'Kullanıcı',
              '${today.distinctUsers}',
              Icons.people_rounded,
              Colors.green,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _infoRow(
        'Günlük bütçe kullanımı',
        '${today.grantedPoints} / ${today.maxDailyRewardPoints} puan (%$budgetPct)',
      ),
      _infoRow('Kalan günlük bütçe', '${today.remainingPoints} puan'),
    ]);
  }

  Widget _recentEventsCard() {
    if (_loading) {
      return _section('Son Doğrulanmış Puan Olayları', const [
        Center(child: CircularProgressIndicator()),
      ]);
    }
    final events = _overview?.recent ?? const <AdminRewardRecentSession>[];
    return _section('Son Doğrulanmış Puan Olayları', [
      if (events.isEmpty)
        const Text('Henüz doğrulanmış puan olayı yok.')
      else
        ...events.map(
          (event) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified, color: Colors.green),
            title: Text(
              event.creditedPoints == null
                  ? event.fullName ?? 'Kullanıcı'
                  : '+${event.creditedPoints} puan — ${event.fullName ?? 'Kullanıcı'}',
            ),
            subtitle: Text(
              '${event.email ?? '-'} · '
              '${event.creditedAt == null ? '-' : DateFormat('dd.MM.yyyy HH:mm').format(event.creditedAt!)}',
            ),
            trailing: Text(event.status),
          ),
        ),
    ]);
  }

  Widget _topEarnersCard() {
    if (_loading) {
      return _section('En Çok Puan Kazananlar', const [
        Center(child: CircularProgressIndicator()),
      ]);
    }
    final earners = _overview?.topEarners ?? const <AdminRewardTopEarner>[];
    return _section('En Çok Puan Kazananlar', [
      if (earners.isEmpty)
        const Text('Henüz puan kazanan yok.')
      else
        ...earners.asMap().entries.map((entry) {
          final index = entry.key;
          final earner = entry.value;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Colors.amber.shade100,
              child: Text('${index + 1}'),
            ),
            title: Text(earner.fullName ?? 'Kullanıcı'),
            subtitle: Text(
              '${earner.email ?? '-'} · ${earner.sessionCount} izleme',
            ),
            trailing: Text(
              '${earner.totalPoints} puan',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }),
    ]);
  }

  Widget _metricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _todayCard(),
        const SizedBox(height: 16),
        _recentEventsCard(),
        const SizedBox(height: 16),
        _topEarnersCard(),
      ],
    );
  }
}
