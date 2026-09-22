import 'dart:ui' show lerpDouble;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/leaderboard_models.dart';
import '../services/leaderboard_service.dart';

typedef LeaderboardSnapshotLoader = Future<LeaderboardSnapshot> Function();
typedef LeaderboardEntryOpener =
    void Function(BuildContext context, LeaderboardEntry entry);

/// Ana sayfadaki "Liderler Tablosu" — İlanlar bölümünün altında.
///
/// Kartlar PARMAKLA sağa-sola kaydırılır ([PageView]); üstteki sekmeler kaydırmayla
/// senkron gider, sekmeye dokunmak da kartı kaydırır. Tek çağrıyla (`get_leaderboards`)
/// tüm kartların verisi gelir, bu yüzden kaydırırken bekleme olmaz.
///
/// Admin ana anahtarı kapattıysa ya da hiçbir kart açık değilse HİÇBİR ŞEY
/// çizmez (boş kart bırakmaz). Kartların sırası admin'in belirlediği sıradır.
///
/// ## Neden sabit satır yüksekliği
///
/// [PageView] sınırlı bir yükseklik ister. Kart yüksekliği içeriğe bağlı
/// (limit 3-10 satır, sayaç kartı, boş durum), bu yüzden her kartın yüksekliği
/// satır sayısından HESAPLANIR (satır yüksekliği sabit) ve kaydırma sırasında iki
/// komşu kartın yüksekliği arasında geçiş yapılır — kısa listelerin altında
/// boşluk kalmaz, uzun liste kesilmez.
///
/// Yükleyici test için dışarıdan verilebilir.
class HomeLeaderboardSection extends StatefulWidget {
  const HomeLeaderboardSection({
    super.key,
    required this.onOpenEntry,
    this.snapshotLoader,
  });

  /// Satıra dokununca ne açılacağı. Ana sayfa `openLeaderboardEntry`
  /// (leaderboard_navigator.dart) verir; bölüm ağır ekranları kendisi içe aktarmaz.
  final LeaderboardEntryOpener onOpenEntry;
  final LeaderboardSnapshotLoader? snapshotLoader;

  @override
  State<HomeLeaderboardSection> createState() => _HomeLeaderboardSectionState();
}

class _HomeLeaderboardSectionState extends State<HomeLeaderboardSection> {
  static const _gold = Color(0xFFF5B301);
  static const _silver = Color(0xFF9AA5B1);
  static const _bronze = Color(0xFFC77D3A);

  // Yerleşim sabitleri — kart yüksekliği bunlardan hesaplanır.
  static const double _rowHeight = 64; // 60 satır + 4 boşluk
  static const double _cardChrome = 26; // dolgu (14+10) + kenarlık (2)
  static const double _cardHeader = 44; // başlık (34) + boşluk (10)
  static const double _meBlock = 92; // 6 boşluk + 22 etiket + 64 satır
  static const double _bodyMessage = 120; // boş durum gövdesi
  static const double _statTileHeight = 84;
  static const double _statGap = 10;

  late Future<LeaderboardSnapshot> _future;
  final PageController _pages = PageController(viewportFraction: .92);
  final Map<LeaderboardBoard, GlobalKey> _chipKeys = {};
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<LeaderboardSnapshot> _load({bool force = false}) =>
      (widget.snapshotLoader ??
      () => LeaderboardService.fetchSnapshot(forceRefresh: force))();

  // "Yenile" önbelleği atlar.
  void _retry() => setState(() {
    _page = 0;
    _future = _load(force: true);
  });

  // ---------------------------------------------------------------------------
  // Yükseklik hesabı
  // ---------------------------------------------------------------------------

  double _cardHeightFor(LeaderboardBoard board, LeaderboardSnapshot snapshot) {
    var body = _bodyMessage;
    if (board.isStats) {
      final rows = (snapshot.statsFor(board).length / 2).ceil();
      body = rows * _statTileHeight + (rows - 1).clamp(0, 99) * _statGap;
    } else {
      final top = snapshot.topEntries(board).length;
      if (top > 0) {
        body = top * _rowHeight;
        if (snapshot.myEntryBeyondTop(board) != null) body += _meBlock;
      }
    }
    return _cardChrome + _cardHeader + body;
  }

  // ---------------------------------------------------------------------------
  // Derleme
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Çok büyük yazı ölçeğinde sabit satır yüksekliği taşardı.
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: 1.15),
      ),
      child: FutureBuilder<LeaderboardSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          if (snapshot.hasError) return _buildError();
          final data = snapshot.data;
          if (data == null) return const SizedBox.shrink();
          final cards = data.cards;
          if (cards.isEmpty) return const SizedBox.shrink();
          return _buildCarousel(data, cards);
        },
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_outlined, color: Colors.orange),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Liderler tablosu şu anda yüklenemedi.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: _retry, child: const Text('Yenile')),
        ],
      ),
    );
  }

  Widget _buildCarousel(
    LeaderboardSnapshot data,
    List<LeaderboardBoard> cards,
  ) {
    final page = _page.clamp(0, cards.length - 1);
    final heights = [for (final b in cards) _cardHeightFor(b, data)];

    final pageView = PageView.builder(
      controller: _pages,
      itemCount: cards.length,
      onPageChanged: (i) {
        setState(() => _page = i);
        _revealChip(cards[i]);
      },
      itemBuilder: (context, index) {
        final board = cards[index];
        // Sayfa, PageView'ın O ANKİ (geçerli karta göre) yüksekliğiyle sınırlanır.
        // Yandan görünen komşu kart daha uzunsa `Align`+`SizedBox` onu o
        // yüksekliğe sıkıştırıp taşırırdı; `OverflowBox` kartın kendi yüksekliğini
        // verir, taşan kısmı PageView'ın kırpması gizler.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: heights[index],
            maxHeight: heights[index],
            child: SizedBox(
              height: heights[index],
              child: _buildCard(data, board),
            ),
          ),
        );
      },
    );

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 14),
          _buildChips(cards, page),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _pages,
            child: pageView,
            builder: (context, child) {
              // Kaydırma sürerken iki komşu kartın yüksekliği arasında geçiş.
              final position =
                  _pages.hasClients && _pages.position.haveDimensions
                  ? (_pages.page ?? page.toDouble())
                  : page.toDouble();
              final clamped = position.clamp(0.0, cards.length - 1.0);
              final lo = clamped.floor();
              final hi = clamped.ceil();
              final height = lerpDouble(
                heights[lo],
                heights[hi],
                clamped - lo,
              )!;
              return SizedBox(height: height, child: child);
            },
          ),
        ],
      ),
    );
  }

  void _revealChip(LeaderboardBoard board) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _chipKeys[board]?.currentContext;
      if (context == null || !context.mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: .5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _TrophyBadge(),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Liderler Tablosu',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                Text(
                  'Cizre’nin en aktifleri · kaydırarak gez',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChips(List<LeaderboardBoard> cards, int selected) {
    return SizedBox(
      height: 38,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              KeyedSubtree(
                key: _chipKeys.putIfAbsent(cards[i], GlobalKey.new),
                child: _chip(cards[i], i, i == selected),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(LeaderboardBoard board, int index, bool isSelected) {
    return InkWell(
      key: ValueKey('leaderboard-chip-${board.key}'),
      onTap: () => _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
      borderRadius: BorderRadius.circular(19),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: isSelected ? board.color : Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: isSelected
                ? board.color
                : board.color.withValues(alpha: .28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              board.icon,
              size: 17,
              color: isSelected ? Colors.white : board.color,
            ),
            const SizedBox(width: 6),
            Text(
              board.chipLabel,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Kart
  // ---------------------------------------------------------------------------

  Widget _buildCard(LeaderboardSnapshot data, LeaderboardBoard board) {
    return Container(
      key: ValueKey('leaderboard-card-${board.key}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: board.color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeaderRow(board, data.settings.period),
          const SizedBox(height: 10),
          Expanded(
            child: board.isStats
                ? _statsBody(data, board)
                : _rankingBody(data, board),
          ),
        ],
      ),
    );
  }

  Widget _cardHeaderRow(LeaderboardBoard board, LeaderboardPeriod period) {
    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: board.color.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(board.icon, size: 19, color: board.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    board.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    board.caption(period),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.black54,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankingBody(LeaderboardSnapshot data, LeaderboardBoard board) {
    final entries = data.topEntries(board);
    if (entries.isEmpty) {
      return _message(
        icon: board == LeaderboardBoard.topViewedStories
            ? Icons.auto_stories_outlined
            : Icons.hourglass_empty_rounded,
        text: board == LeaderboardBoard.topViewedStories
            ? 'Şu an yayında izlenen hikaye yok.'
            : 'Bu pano için henüz yeterli veri yok.',
      );
    }
    final mine = data.myEntryBeyondTop(board);
    return Column(
      children: [
        for (final entry in entries)
          _LeaderRow(
            entry: entry,
            board: board,
            onTap: () => widget.onOpenEntry(context, entry),
          ),
        if (mine != null) ...[
          const SizedBox(height: 6),
          const SizedBox(
            height: 22,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'Senin sıran',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black45,
                  ),
                ),
              ),
            ),
          ),
          _LeaderRow(
            entry: mine,
            board: board,
            onTap: () => widget.onOpenEntry(context, mine),
          ),
        ],
      ],
    );
  }

  Widget _statsBody(LeaderboardSnapshot data, LeaderboardBoard board) {
    final stats = data.statsFor(board);
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: _statGap));
      rows.add(
        SizedBox(
          height: _statTileHeight,
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  stat: stats[i],
                  value: data.stats[stats[i].key]!,
                ),
              ),
              const SizedBox(width: _statGap),
              Expanded(
                child: i + 1 < stats.length
                    ? _StatTile(
                        stat: stats[i + 1],
                        value: data.stats[stats[i + 1].key]!,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _message({required IconData icon, required String text}) {
    return SizedBox(
      height: _bodyMessage,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black38, size: 28),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrophyBadge extends StatelessWidget {
  const _TrophyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: _HomeLeaderboardSectionState._gold.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.emoji_events_rounded,
        color: _HomeLeaderboardSectionState._gold,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat, required this.value});

  final LeaderboardStat stat;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('leaderboard-stat-${stat.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: stat.color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: stat.color.withValues(alpha: .16),
              shape: BoxShape.circle,
            ),
            child: Icon(stat.icon, size: 19, color: stat.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatCount(value),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
                Text(
                  stat.label,
                  // "Tamamlanan sipariş" dar karolarda iki satıra sığar.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.black54,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.entry,
    required this.board,
    required this.onTap,
  });

  final LeaderboardEntry entry;
  final LeaderboardBoard board;
  final VoidCallback onTap;

  Color? get _medal {
    switch (entry.rank) {
      case 1:
        return _HomeLeaderboardSectionState._gold;
      case 2:
        return _HomeLeaderboardSectionState._silver;
      case 3:
        return _HomeLeaderboardSectionState._bronze;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medal;
    final first = entry.rank == 1;
    final primary = Theme.of(context).colorScheme.primary;
    final metricText = board.metricLabel(entry);
    final sub = board.metricSubLabel(entry);
    final subtitle = entry.handle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        key: ValueKey('leaderboard-row-${board.key}-${entry.rank}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: first
                ? _HomeLeaderboardSectionState._gold.withValues(alpha: .10)
                : (entry.isMe
                      ? primary.withValues(alpha: .07)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
            border: entry.isMe
                ? Border.all(color: primary.withValues(alpha: .35))
                : null,
          ),
          child: Row(
            children: [
              _rankBadge(medal),
              const SizedBox(width: 10),
              _avatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: first
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (entry.isMe) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Sen',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Değer okunamadıysa (ör. katılma zamanı gelmedi) boş bir hap
                  // çizmek yerine hiç çizme.
                  if (metricText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: board.color.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (board == LeaderboardBoard.topRatedShops) ...[
                            Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: board.color,
                            ),
                            const SizedBox(width: 2),
                          ],
                          Text(
                            metricText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: board.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rankBadge(Color? medal) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: medal ?? Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Text(
        '${entry.rank}',
        style: TextStyle(
          fontSize: entry.rank >= 100 ? 10 : 12.5,
          fontWeight: FontWeight.w900,
          color: medal != null ? Colors.white : Colors.black54,
        ),
      ),
    );
  }

  Widget _avatar() {
    final square =
        entry.type != LeaderboardEntityType.user; // dükkan/gönderi/hikaye
    final fallbackIcon = switch (entry.type) {
      LeaderboardEntityType.shop => Icons.storefront_rounded,
      LeaderboardEntityType.post => Icons.article_rounded,
      LeaderboardEntityType.story => Icons.auto_stories_rounded,
      LeaderboardEntityType.user => null,
    };
    final fallback = Container(
      color: board.color.withValues(alpha: .12),
      alignment: Alignment.center,
      child: fallbackIcon != null
          ? Icon(fallbackIcon, color: board.color, size: 22)
          : Text(
              entry.name.isEmpty
                  ? '?'
                  : entry.name.characters.first.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: board.color,
              ),
            ),
    );
    final url = entry.avatarUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(square ? 12 : 22),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null
            ? fallback
            : CachedNetworkImage(
                memCacheWidth: 200,
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}
