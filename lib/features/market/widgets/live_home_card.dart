import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/live_shopping_model.dart';
import '../screens/live_sessions_screen.dart';
import '../screens/live_viewer_screen.dart';
import '../services/live_shopping_service.dart';
import 'live_stream_widgets.dart';

LiveHomeCard? _cache;
DateTime? _cachedAt;
Future<LiveHomeCard>? _inflight;
const _cacheTtl = Duration(seconds: 60);

/// Ana sayfa hikâye satırında, Şehiriçi kartının yanındaki canlı yayın kartı.
///
/// Canlı yayın varsa kırmızı halka + CANLI (en çok izlenen yayın); yoksa son
/// biten yayın gri halkayla "Son yayın" olarak hikâye gibi 24 saat kalır
/// (sunucu süzer; sahibi "Yayınlarım"da hep görür). Yönetici kartı ya da
/// canlı yayını kapattıysa veya gösterilecek yayın yoksa yer kaplamaz (genişlik 0).
///
/// Veri tek RPC (`live_home_card`); 60 sn önbellek (satır yeniden kurulunca
/// tekrar istek atılmaz), uygulama öne gelince ve izleyiciden dönünce tazelenir.
class LiveHomeStoryCard extends StatefulWidget {
  const LiveHomeStoryCard({super.key, this.compact = true, this.width, this.service, this.onOpen});

  /// true: yuvarlak hikâye (70 px); false: Şehiriçi tam kartıyla aynı boyda kart.
  final bool compact;

  /// Tam görünümde kart genişliği.
  final double? width;

  final LiveShoppingService? service;

  /// Testler için; varsayılan: tek canlı yayın → izleyici, birden çok →
  /// Canlı Yayınlar, canlı yok → Geçmiş sekmesi.
  final void Function(BuildContext context, LiveHomeCard card)? onOpen;

  /// Paylaşılan önbelleği temizler (testler).
  @visibleForTesting
  static void resetCache() {
    _cache = null;
    _cachedAt = null;
    _inflight = null;
  }

  @override
  State<LiveHomeStoryCard> createState() => _LiveHomeStoryCardState();
}

class _LiveHomeStoryCardState extends State<LiveHomeStoryCard> with WidgetsBindingObserver {
  late final LiveShoppingService _service = widget.service ?? LiveShoppingService();
  LiveHomeCard? _card = _cache;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh({bool force = false}) async {
    final at = _cachedAt;
    if (!force && _cache != null && at != null && DateTime.now().difference(at) < _cacheTtl) {
      if (!identical(_card, _cache)) setState(() => _card = _cache);
      return;
    }
    try {
      final request = _inflight ??= _service.fetchHomeCard().whenComplete(() => _inflight = null);
      final card = await request;
      _cache = card;
      _cachedAt = DateTime.now();
      if (mounted) setState(() => _card = card);
    } catch (e) {
      debugPrint('live home card: $e');
    }
  }

  void _open(LiveHomeCard card) {
    final onOpen = widget.onOpen;
    if (onOpen != null) {
      onOpen(context, card);
      return;
    }
    final live = card.live;
    final Widget screen = live != null && card.liveCount <= 1
        ? LiveViewerScreen(session: live)
        : LiveSessionsScreen(initialTab: live != null ? 0 : 1);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) {
      if (mounted) _refresh(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final session = card?.session;
    if (card == null || !card.isVisible || session == null) return const SizedBox.shrink();
    return widget.compact ? _compact(card, session) : _full(card, session);
  }

  String _label(LiveHomeCard card, LiveSession session) {
    if (card.isLive && card.liveCount > 1) return '${card.liveCount} canlı yayın';
    return session.isUserStream ? session.displayName : (session.shopName ?? 'Canlı yayın');
  }

  Widget _compact(LiveHomeCard card, LiveSession session) {
    final live = card.isLive;
    final shopName = session.displayName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        label: live ? 'Canlı yayın: $shopName' : 'Son canlı yayın: $shopName',
        child: GestureDetector(
          key: const ValueKey('live-home-card'),
          onTap: () => _open(card),
          child: SizedBox(
            width: 70,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: live
                              ? const [Color(0xFFFF1744), Color(0xFFFF6D00), kLiveRed]
                              : [Colors.grey.shade400, Colors.grey.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          color: const Color(0xFF1E1E1E),
                        ),
                        alignment: Alignment.center,
                        child: LiveShopAvatar(logoUrl: session.displayAvatarUrl, name: shopName, size: 60),
                      ),
                    ),
                    Positioned(
                      bottom: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: live ? kLiveRed : Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          live ? 'CANLI' : 'SON YAYIN',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 14,
                  child: Text(
                    _label(card, session),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _full(LiveHomeCard card, LiveSession session) {
    final live = card.isLive;
    final shopName = session.displayName;
    final image = session.coverImageUrl ??
        session.pinnedProduct?.imageUrl ??
        session.featuredProducts.where((p) => p.imageUrl != null).map((p) => p.imageUrl).firstOrNull;
    const shadow = [Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1))];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: widget.width ?? 120,
        child: Semantics(
          button: true,
          label: live ? 'Canlı yayın: $shopName' : 'Son canlı yayın: $shopName',
          child: GestureDetector(
            key: const ValueKey('live-home-card'),
            onTap: () => _open(card),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 180,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (image != null)
                      CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        memCacheWidth: 450,
                        color: live ? null : Colors.black.withValues(alpha: 0.25),
                        colorBlendMode: live ? null : BlendMode.darken,
                        errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF1E1E1E)),
                      )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: live
                                ? const [Color(0xFF4A0D0D), Color(0xFF1E1E1E)]
                                : const [Color(0xFF2A2A2A), Color(0xFF111111)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(child: LiveShopAvatar(logoUrl: session.displayAvatarUrl, name: shopName, size: 56)),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
                          stops: [0, 0.3, 0.5, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Row(
                        children: [
                          if (live)
                            Flexible(child: LiveBadge(viewers: session.viewerCount))
                          else
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  ['Son yayın', liveAgoText(session.endedAt, DateTime.now().toUtc())]
                                      .where((s) => s.isNotEmpty)
                                      .join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              LiveShopAvatar(logoUrl: session.displayAvatarUrl, name: shopName, size: 22),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _label(card, session),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    shadows: shadow,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            session.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 11, shadows: shadow),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
