import 'package:flutter/material.dart';

import '../../../core/models/post_model.dart';
import '../services/post_insights_service.dart';
import 'social_post_card.dart' show formatSocialCount;

/// Gönderi sahibine özel istatistik sayfasını açar (alt sayfa).
Future<void> showPostInsightsSheet(
  BuildContext context,
  Post post, {
  PostInsightsService? service,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PostInsightsSheet(post: post, service: service),
  );
}

class PostInsightsSheet extends StatefulWidget {
  const PostInsightsSheet({super.key, required this.post, this.service});

  final Post post;
  final PostInsightsService? service;

  @override
  State<PostInsightsSheet> createState() => _PostInsightsSheetState();
}

class _PostInsightsSheetState extends State<PostInsightsSheet> {
  late Future<PostInsights> _future;

  @override
  void initState() {
    super.initState();
    _future = (widget.service ?? PostInsightsService()).fetch(widget.post.id);
  }

  void _retry() {
    setState(() {
      _future = (widget.service ?? PostInsightsService()).fetch(widget.post.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F6F8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.insights_rounded, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Gönderi istatistikleri',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF11181C),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if ((widget.post.content ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.post.content!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              ),
            Flexible(
              child: FutureBuilder<PostInsights>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError || !snap.hasData) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          const Text('İstatistikler yüklenemedi'),
                          const SizedBox(height: 10),
                          OutlinedButton(onPressed: _retry, child: const Text('Tekrar dene')),
                        ],
                      ),
                    );
                  }
                  return _InsightsBody(data: snap.data!);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({required this.data});

  final PostInsights data;

  String _pct(double? v) {
    if (v == null) return '—';
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '%${s.replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <_TileData>[
      _TileData(Icons.visibility_outlined, 'Görüntülenme', formatSocialCount(data.views), const Color(0xFF7C3AED)),
      _TileData(Icons.people_alt_outlined, 'Benzersiz kişi', formatSocialCount(data.uniqueViewers), const Color(0xFF0EA5E9)),
      _TileData(Icons.favorite_border, 'Beğeni', formatSocialCount(data.likes), const Color(0xFFE0245E)),
      _TileData(Icons.mode_comment_outlined, 'Yorum', formatSocialCount(data.comments), const Color(0xFF1D9BF0)),
      _TileData(Icons.ios_share_outlined, 'Paylaşım', formatSocialCount(data.shares), const Color(0xFF8B5CF6)),
      _TileData(Icons.bookmark_border, 'Kaydetme', formatSocialCount(data.saves), const Color(0xFFF59E0B)),
      _TileData(Icons.touch_app_outlined, 'Detay açılışı', formatSocialCount(data.detailOpens), const Color(0xFF10B981)),
      _TileData(Icons.bolt_rounded, 'Etkileşim oranı', _pct(data.engagementRate), const Color(0xFFEF4444)),
    ];

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = 10.0;
            final w = (c.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in tiles) SizedBox(width: w, child: _StatTile(data: t)),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _Card(
          title: 'Son 7 gün',
          child: _WeekBars(daily: data.daily),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Erişim',
          child: _ReachBar(
            followers: data.followerViewers,
            total: data.uniqueViewers,
            nonFollowerLabel: _pct(data.nonFollowerRate),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Görüntülenme, gönderinin akışta ekrana gelmesidir; her kişi günde '
                'bir kez sayılır. Senin görüntülemelerin sayılmaz. Kaydetme sayısını '
                'yalnız sen görürsün.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.35),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TileData {
  const _TileData(this.icon, this.label, this.value, this.color);

  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.data});

  final _TileData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9EDF1)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(data.icon, size: 19, color: data.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF11181C),
                    ),
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9EDF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF11181C),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.daily});

  final List<DailyViews> daily;

  static const _days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return Text('Henüz veri yok', style: TextStyle(color: Colors.grey.shade600));
    }
    final max = daily.fold<int>(0, (m, d) => d.views > m ? d.views : m);
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < daily.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      formatSocialCount(daily[i].views),
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: max == 0 ? 0.02 : (daily[i].views / max).clamp(0.02, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: i == daily.length - 1
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFF7C3AED).withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      i == daily.length - 1 ? 'Bugün' : _days[daily[i].day.weekday - 1],
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: i == daily.length - 1 ? FontWeight.w700 : FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReachBar extends StatelessWidget {
  const _ReachBar({
    required this.followers,
    required this.total,
    required this.nonFollowerLabel,
  });

  final int followers;
  final int total;
  final String nonFollowerLabel;

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return Text('Henüz kimse görmedi', style: TextStyle(color: Colors.grey.shade600));
    }
    final share = (followers / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                if (share > 0)
                  Expanded(
                    flex: (share * 1000).round(),
                    child: Container(color: const Color(0xFF0EA5E9)),
                  ),
                if (share < 1)
                  Expanded(
                    flex: ((1 - share) * 1000).round(),
                    child: Container(color: const Color(0xFFF59E0B)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Legend(color: const Color(0xFF0EA5E9), text: 'Takipçiler: $followers'),
            _Legend(
              color: const Color(0xFFF59E0B),
              text: 'Takip etmeyenler: ${total - followers} ($nonFollowerLabel)',
            ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }
}
