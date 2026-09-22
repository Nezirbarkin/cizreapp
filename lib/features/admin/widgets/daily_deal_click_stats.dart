import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_ui.dart';

/// Günün Fırsatları: kart tıklama istatistikleri (admin_daily_deal_click_stats).
///
/// [stats] RPC sonucudur: totalClicks, uniqueUsers, guestClicks, clicksToday,
/// windowDays. Kart başına sayılar için bkz. [DealClickChip].
class DealClickSummary extends StatelessWidget {
  final Map<String, dynamic> stats;
  final VoidCallback? onClear;

  const DealClickSummary({super.key, required this.stats, this.onClear});

  @override
  Widget build(BuildContext context) {
    final days = (stats['windowDays'] as num?)?.toInt() ?? 30;
    String n(String key) => adminCompact((stats[key] as num?) ?? 0);

    return AdminCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ads_click_rounded, size: 18, color: AdminUi.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kart tıklamaları · son $days gün',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AdminUi.ink),
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Tüm tıklama kayıtlarını sil',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              children: [
                Expanded(child: _tile(Icons.touch_app_rounded, 'Toplam tık', n('totalClicks'), Colors.deepOrange)),
                const SizedBox(width: 8),
                Expanded(child: _tile(Icons.person_rounded, 'Üye', n('uniqueUsers'), Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _tile(Icons.person_outline_rounded, 'Misafir tık', n('guestClicks'), Colors.blueGrey)),
                const SizedBox(width: 8),
                Expanded(child: _tile(Icons.today_rounded, 'Bugün', n('clicksToday'), Colors.green)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AdminUi.ink),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AdminUi.muted),
          ),
        ],
      ),
    );
  }
}

/// Bir fırsat kartının altındaki "42 tık · 17 kişi" çipi; dokununca tıklayanlar açılır.
class DealClickChip extends StatelessWidget {
  final Map<String, dynamic>? deal;
  final VoidCallback onTap;

  const DealClickChip({super.key, required this.deal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final total = (deal?['total_clicks'] as num?)?.toInt() ?? 0;
    final users = (deal?['unique_users'] as num?)?.toInt() ?? 0;
    final guests = (deal?['unique_guests'] as num?)?.toInt() ?? 0;
    final last = adminParseDate(deal?['last_click_at']);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: total > 0 ? Colors.deepOrange.withValues(alpha: 0.10) : Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ads_click_rounded,
              size: 14,
              color: total > 0 ? Colors.deepOrange.shade700 : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                total == 0
                    ? 'Henüz tıklanmadı'
                    : '$total tık · $users üye${guests > 0 ? ' + $guests misafir' : ''}'
                        '${last == null ? '' : ' · son ${adminTimeAgo(last)}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: total > 0 ? Colors.deepOrange.shade800 : Colors.grey.shade700,
                ),
              ),
            ),
            if (total > 0) ...[
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 16, color: Colors.deepOrange.shade700),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bir kartı kimlerin tıkladığını listeler (kişi başına tık sayısı ve zamanı).
Future<void> showDealClickersSheet(
  BuildContext context, {
  required String dealId,
  required String title,
  int days = 30,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DealClickersSheet(dealId: dealId, title: title, days: days),
  );
}

class _DealClickersSheet extends StatefulWidget {
  final String dealId;
  final String title;
  final int days;

  const _DealClickersSheet({required this.dealId, required this.title, required this.days});

  @override
  State<_DealClickersSheet> createState() => _DealClickersSheetState();
}

class _DealClickersSheetState extends State<_DealClickersSheet> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_daily_deal_clickers',
        params: {'p_deal_id': widget.dealId, 'p_days': widget.days, 'p_limit': 200},
      );
      if (!mounted) return;
      setState(() => _data = Map<String, dynamic>.from(res as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ((_data?['users'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final guestClicks = (_data?['guestClicks'] as num?)?.toInt() ?? 0;
    final guestPeople = (_data?['guestPeople'] as num?)?.toInt() ?? 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AdminUi.page,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AdminUi.ink),
            ),
            const SizedBox(height: 2),
            Text(
              'Son ${widget.days} günde tıklayanlar',
              style: const TextStyle(color: AdminUi.muted),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Text('Yüklenemedi: $_error', style: const TextStyle(color: Colors.red))
            else if (_data == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else ...[
              if (guestClicks > 0) ...[
                AdminCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.blueGrey.shade50,
                        child: Icon(Icons.person_outline, color: Colors.blueGrey.shade600),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Misafirler (giriş yapmamış)',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '$guestPeople kişi · $guestClicks tık',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AdminUi.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (users.isEmpty)
                const AdminCard(
                  child: Text('Giriş yapmış kullanıcı tıklaması yok.', style: TextStyle(color: AdminUi.muted)),
                )
              else
                AdminCard(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < users.length; i++) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            children: [
                              AdminAvatar(url: users[i]['avatar_url'] as String?, name: adminDisplayName(users[i]), radius: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      adminDisplayName(users[i]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      'İlk: ${adminDateTime(adminParseDate(users[i]['first_click_at']))}  ·  '
                                      'Son: ${adminDateTime(adminParseDate(users[i]['last_click_at']))}',
                                      style: const TextStyle(fontSize: 11, color: AdminUi.muted),
                                    ),
                                  ],
                                ),
                              ),
                              AdminBadge(label: '${users[i]['clicks']} tık', color: Colors.deepOrange),
                            ],
                          ),
                        ),
                        if (i != users.length - 1) const Divider(height: 1, color: AdminUi.line),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
