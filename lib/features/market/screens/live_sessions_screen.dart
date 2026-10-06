import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, PostgresChangePayload;

import '../../../core/models/live_shopping_model.dart';
import '../services/live_shopping_service.dart';
import '../widgets/live_stream_widgets.dart';
import 'live_host_screen.dart';
import 'live_viewer_screen.dart';
import 'my_live_streams_screen.dart';

/// Canlı yayınları keşfet (Görev 3.4) — iki sekme:
///
/// - **Şimdi canlı:** izleyiciye göre sıralı canlı yayınlar (`live_sessions_feed`);
///   Realtime ile yeni yayın/bitiş anında, izleyici sayısı yerinde güncellenir.
/// - **Geçmiş:** biten yayınlar (`live_history`, yönetici ayarındaki gün kadar),
///   sayfalı; dokununca yayının özeti (süre, izleyici, öne çıkan ürünler).
///
/// Yönetim izin veriyorsa (`my_access` = ok) "Yayın aç" düğmesiyle kullanıcı
/// kendi (mağazasız) yayınını başlatır. Oturum açmış kişi üst çubuktaki
/// "Yayınlarım" ile kendi biten yayınlarını süre sınırı olmadan görür.
class LiveSessionsScreen extends StatefulWidget {
  const LiveSessionsScreen({
    super.key,
    this.service,
    this.openSession,
    this.startStream,
    this.openMyStreams,
    this.now,
    this.initialTab = 0,
  });

  final LiveShoppingService? service;

  /// Testler için; varsayılan izleyici ekranını açar.
  final void Function(BuildContext context, LiveSession session)? openSession;

  /// Testler için; varsayılan kullanıcı yayıncı ekranını açar.
  final Future<void> Function(BuildContext context)? startStream;

  /// Testler için; varsayılan Yayınlarım ekranını açar.
  final void Function(BuildContext context)? openMyStreams;
  final DateTime Function()? now;

  /// 0 = Şimdi canlı, 1 = Geçmiş (ana sayfa kartı biten yayında Geçmiş'i açar).
  final int initialTab;

  @override
  State<LiveSessionsScreen> createState() => _LiveSessionsScreenState();
}

class _LiveSessionsScreenState extends State<LiveSessionsScreen> with SingleTickerProviderStateMixin {
  static const _historyPageSize = 20;

  late final LiveShoppingService _service = widget.service ?? LiveShoppingService();
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));

  LiveFeed _feed = const LiveFeed();
  bool _loading = true;
  String? _error;
  StreamSubscription<PostgresChangePayload>? _changes;
  Timer? _reloadDebounce;

  // Geçmiş sekmesi (ilk açılışta yüklenir)
  List<LiveSession> _history = const [];
  int _historyTotal = 0;
  int _historyDays = 30;
  bool _historyLoaded = false;
  bool _historyLoading = false;
  bool _historyLoadingMore = false;
  String? _historyError;

  /// Yavaş eski geçmiş yanıtı yenisini ezmesin.
  int _historySeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = _service.watchAllSessions().listen(_onChange, onError: (_) {});
    _tabs.addListener(_onTab);
    if (_tabs.index == 1) _loadHistory();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    unawaited(_changes?.cancel());
    _tabs
      ..removeListener(_onTab)
      ..dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tabs.index == 1 && !_historyLoaded && !_historyLoading) _loadHistory();
  }

  Future<void> _load() async {
    if (_feed.isEmpty) setState(() => _loading = true);
    try {
      final feed = await _service.fetchFeed();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = LiveShoppingService.toLiveException(e).message;
      });
    }
  }

  Future<void> _loadHistory({bool silent = false}) async {
    final seq = ++_historySeq;
    if (!silent) {
      setState(() {
        _historyLoading = true;
        _historyError = null;
      });
    }
    try {
      final page = await _service.fetchHistory(limit: _historyPageSize);
      if (!mounted || seq != _historySeq) return;
      setState(() {
        _history = page.rows;
        _historyTotal = page.total;
        _historyDays = page.days;
        _historyLoaded = true;
        _historyLoading = false;
        _historyError = null;
      });
    } catch (e) {
      if (!mounted || seq != _historySeq) return;
      setState(() {
        _historyLoading = false;
        if (!silent || _history.isEmpty) _historyError = LiveShoppingService.toLiveException(e).message;
      });
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_historyLoadingMore) return;
    final seq = _historySeq;
    setState(() => _historyLoadingMore = true);
    try {
      final page = await _service.fetchHistory(limit: _historyPageSize, offset: _history.length);
      if (!mounted || seq != _historySeq) return;
      final known = {for (final s in _history) s.id};
      setState(() {
        _history = [..._history, ...page.rows.where((s) => !known.contains(s.id))];
        _historyTotal = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(LiveShoppingService.toLiveException(e).message)));
    } finally {
      if (mounted) setState(() => _historyLoadingMore = false);
    }
  }

  /// Satıcı sinyali (izleyici sayısı) listeyi yeniden yüklemez; yeni yayın,
  /// başlama ya da bitiş yükler (1 sn içinde toplanır). Biten yayın geçmişe
  /// düştüğü için açılmış geçmiş de tazelenir.
  void _onChange(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = payload.newRecord;
    if (payload.eventType == PostgresChangeEvent.update) {
      final id = row['id']?.toString();
      final index = _feed.live.indexWhere((s) => s.id == id);
      final status = row['status']?.toString();
      if (index >= 0 && status == 'live') {
        setState(() {
          final live = [..._feed.live];
          live[index] = live[index].applyRow(Map<String, dynamic>.from(row));
          _feed = _feed.copyWith(live: live);
        });
        return;
      }
      if (index < 0 && status != 'live') return; // listede olmayan hazırlık/bitmiş kayıt
    }
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(seconds: 1), () {
      _load();
      if (_historyLoaded) _loadHistory(silent: true);
    });
  }

  void _open(LiveSession session) {
    final open = widget.openSession;
    if (open != null) {
      open(context, session);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => LiveViewerScreen(session: session))).then((_) {
      if (mounted) _load();
    });
  }

  Future<void> _startStream() async {
    final start = widget.startStream;
    if (start != null) {
      await start(context);
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LiveHostScreen(shopName: '')),
      );
    }
    if (mounted) _load();
  }

  void _openMyStreams() {
    final open = widget.openMyStreams;
    if (open != null) {
      open(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MyLiveStreamsScreen(service: widget.service)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveCount = _feed.live.length;
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('Canlı Yayınlar'),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        actions: [
          if (_service.currentUserId != null)
            IconButton(
              key: const ValueKey('live-my-streams'),
              tooltip: 'Yayınlarım',
              onPressed: _openMyStreams,
              icon: const Icon(Icons.video_library_outlined),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: kLiveRed,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: liveCount > 0 ? 'Şimdi canlı ($liveCount)' : 'Şimdi canlı'),
            const Tab(text: 'Geçmiş'),
          ],
        ),
      ),
      floatingActionButton: _feed.canStartUserStream
          ? FloatingActionButton.extended(
              key: const ValueKey('live-start-user-stream'),
              onPressed: _startStream,
              backgroundColor: kLiveRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.videocam),
              label: const Text('Yayın aç', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          RefreshIndicator(onRefresh: _load, child: _liveTab()),
          RefreshIndicator(onRefresh: () => _loadHistory(silent: _history.isNotEmpty), child: _historyTab()),
        ],
      ),
    );
  }

  Widget _liveTab() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (_error != null && _feed.live.isEmpty) return _message(Icons.error_outline, _error!, retry: _load);
    if (_feed.live.isEmpty) {
      return _feed.enabled
          ? _message(
              Icons.live_tv_outlined,
              'Şu an canlı yayın yok',
              detail: _feed.canStartUserStream
                  ? 'İlk yayını sen başlat ya da yayınlar başladığında burada gör.'
                  : 'Yayınlar başladığında burada görünecek.',
              action: ('Geçmiş yayınlara göz at', () => _tabs.animateTo(1)),
            )
          : _message(
              Icons.pause_circle_outline,
              'Canlı yayınlar şu anda kapalı',
              detail: 'Yönetim canlı yayınları geçici olarak kapattı.',
              action: ('Geçmiş yayınlara göz at', () => _tabs.animateTo(1)),
            );
    }
    return ListView(
      // "Yayın aç" düğmesi son kartı örtmesin.
      padding: EdgeInsets.only(top: 8, bottom: _feed.canStartUserStream ? 96 : 24),
      children: [
        if (!_feed.enabled)
          Container(
            key: const ValueKey('live-feed-disabled'),
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.pause_circle_outline, color: Colors.white70),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Canlı yayınlar şu anda kapalı; süren yayınlar bitene kadar izlenebilir.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        for (final s in _feed.live) _LiveTile(session: s, onTap: () => _open(s)),
      ],
    );
  }

  Widget _historyTab() {
    if (_historyLoading && _history.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_historyError != null && _history.isEmpty) {
      return _message(Icons.error_outline, _historyError!, retry: _loadHistory);
    }
    if (_history.isEmpty) {
      return _message(
        Icons.history,
        'Geçmiş yayın yok',
        detail: 'Son $_historyDays günde biten yayınlar burada listelenir.',
      );
    }
    final now = (widget.now ?? DateTime.now)().toUtc();
    final remaining = _historyTotal - _history.length;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _history.length + 1,
      itemBuilder: (context, index) {
        if (index == _history.length) {
          if (remaining <= 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Son $_historyDays günün yayınları gösteriliyor.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: _historyLoadingMore
                  ? const CircularProgressIndicator(color: Colors.white)
                  : OutlinedButton(
                      onPressed: _loadMoreHistory,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                      child: Text('Daha fazla yükle ($remaining kaldı)'),
                    ),
            ),
          );
        }
        final session = _history[index];
        return LiveEndedTile(session: session, now: now, onTap: () => _open(session));
      },
    );
  }

  Widget _message(
    IconData icon,
    String text, {
    String? detail,
    Future<void> Function()? retry,
    (String, VoidCallback)? action,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 100),
        Icon(icon, color: Colors.white38, size: 60),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15)),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
        if (retry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: retry,
              style: FilledButton.styleFrom(backgroundColor: kLiveRed),
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
            ),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: action.$2,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              icon: const Icon(Icons.history),
              label: Text(action.$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveTile extends StatelessWidget {
  const _LiveTile({required this.session, required this.onTap});

  final LiveSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shopName = session.displayName;
    final cover = session.coverImageUrl ?? session.pinnedProduct?.imageUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: 108,
                height: 128,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null)
                      CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        memCacheWidth: 324,
                        errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF2A2A2A)),
                      )
                    else
                      ColoredBox(
                        color: const Color(0xFF2A2A2A),
                        child: Center(child: LiveShopAvatar(logoUrl: session.displayAvatarUrl, name: shopName, size: 52)),
                      ),
                    const Positioned(left: 6, top: 6, child: LiveBadge()),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          LiveShopAvatar(logoUrl: session.displayAvatarUrl, name: shopName, size: 22),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        session.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.visibility_outlined, size: 14, color: Colors.white60),
                          const SizedBox(width: 4),
                          Text(
                            '${session.viewerCount} izliyor',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                      if (session.pinnedProduct != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.push_pin, size: 13, color: kLiveRed),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                session.pinnedProduct!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3 sa önce" gibi göreli zaman.
String liveAgoText(DateTime? at, DateTime now) {
  if (at == null) return '';
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'az önce';
  if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
  if (diff.inDays < 1) return '${diff.inHours} sa önce';
  return '${diff.inDays} gün önce';
}

/// Biten yayın satırı (Geçmiş sekmesi ve Yayınlarım): yayıncı, süre, en çok
/// izleyici, ne zaman bittiği ve öne çıkan ürünler.
class LiveEndedTile extends StatelessWidget {
  const LiveEndedTile({super.key, required this.session, required this.now, required this.onTap});

  final LiveSession session;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shopName = session.displayName;
    final seconds = session.durationSeconds;
    final duration = seconds != null ? Duration(seconds: seconds) : session.durationAt(now);
    final featured = session.featuredProducts;
    return InkWell(
      key: ValueKey('live-history-${session.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LiveShopAvatar(logoUrl: session.displayAvatarUrl, name: shopName, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      shopName,
                      if (duration != null) formatLiveDuration(duration),
                      '${session.peakViewerCount} izleyici',
                      liveAgoText(session.endedAt, now),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (featured.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final product in featured.take(4))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: product.imageUrl == null
                                    ? const ColoredBox(
                                        color: Color(0xFF2A2A2A),
                                        child: Icon(Icons.shopping_bag_outlined, color: Colors.white38, size: 18),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: product.imageUrl!,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 108,
                                        errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF2A2A2A)),
                                      ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            featured.length == 1 ? featured.first.name : '${featured.length} ürün öne çıktı',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
              child: const Text(
                'BİTTİ',
                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
