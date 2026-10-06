import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/live_shopping_model.dart';
import '../../../core/services/screen_awake_service.dart';
import '../services/agora_service.dart';
import '../services/live_shopping_service.dart';
import '../widgets/live_stream_widgets.dart';
import '../../profile/screens/user_profile_screen.dart';
import 'product_detail_screen.dart';
import 'shop_detail_screen.dart';

enum _ViewerPhase { connecting, watching, ended, failed }

/// İzleyici ekranı (Görev 3.4): tam ekran dikey yayın, üstte mağaza ve canlı
/// sayaç, altta sabit ürün kartı + sohbet. Misafir izleyebilir; yazmak için
/// giriş gerekir. Yayın bitince (satıcı/zaman aşımı/yönetici) Realtime ile
/// anında "Yayın sona erdi" gösterilir; bitti ekranında süre, en çok izleyici,
/// mesaj sayısı ve yayında öne çıkan ürünler (geçmişten açılınca da).
/// "Haberdar ol" ile mağazanın sonraki yayınlarında bildirim gelir. Kullanıcı
/// (mağazasız) yayınında üst bilgi yayıncının profilini açar; bildirim
/// takipçilere gittiği için abonelik düğmesi yoktur.
class LiveViewerScreen extends StatefulWidget {
  const LiveViewerScreen({
    super.key,
    required this.session,
    this.service,
    this.engineFactory,
    this.openProduct,
    this.openShop,
    this.openProfile,
    this.share,
  });

  final LiveSession session;
  final LiveShoppingService? service;
  final LiveVideoEngineFactory? engineFactory;

  /// Testler için; varsayılan ürün detayını açar.
  final void Function(BuildContext context, String productId)? openProduct;
  final void Function(BuildContext context, String shopId)? openShop;
  final void Function(BuildContext context, String userId)? openProfile;

  /// Testler için; varsayılan sistem paylaşım penceresini açar.
  final Future<void> Function(String text)? share;

  @override
  State<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends State<LiveViewerScreen> {
  late final LiveShoppingService _service = widget.service ?? LiveShoppingService();
  late final LiveVideoEngine _engine = (widget.engineFactory ?? AgoraService.new)();
  final _messageCtrl = TextEditingController();

  late LiveSession _session = widget.session;
  _ViewerPhase _phase = _ViewerPhase.connecting;
  LiveException? _failure;
  LiveCredentials? _credentials;
  final List<LiveMessage> _messages = [];
  int? _viewers;
  bool _hostOnline = false;
  bool _hostVideo = true;
  bool _muted = false;
  bool _sending = false;
  bool _loadingPin = false;
  LiveConnectionState _connection = LiveConnectionState.connecting;
  DateTime? _lastTokenRenew;

  StreamSubscription<Map<String, dynamic>>? _rowSub;
  StreamSubscription<LiveChatEvent>? _chatSub;
  StreamSubscription<int>? _audienceSub;

  bool get _isGuest => _service.currentUserId == null;

  @override
  void initState() {
    super.initState();
    // Biten yayının özeti görüntü motoru istemez (web'de de açılır).
    if (_session.isEnded) {
      _phase = _ViewerPhase.ended;
      _loadEndedDetail();
      return;
    }
    if (!_engine.isSupported) {
      _phase = _ViewerPhase.failed;
      _failure = const LiveException(LiveFailure.unsupported);
      return;
    }
    _connect();
  }

  /// Bitti ekranı için süre/mesaj sayısı ve öne çıkan ürünler.
  Future<void> _loadEndedDetail() async {
    try {
      final fresh = await _service.fetchSession(_session.id);
      if (fresh != null && mounted) setState(() => _session = fresh);
    } catch (_) {
      // Ayrıntı gelmezse bitti ekranı eldeki bilgiyle kalır.
    }
  }

  @override
  void dispose() {
    _stopStreams();
    unawaited(_engine.dispose());
    unawaited(ScreenAwakeService.setKeepOn(false));
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _phase = _ViewerPhase.connecting;
      _failure = null;
    });
    try {
      final credentials = await _service.fetchCredentials(_session.id, asHost: false);
      _credentials = credentials;
      if (!mounted) return;
      _startStreams();
      await _engine.joinAsViewer(
        credentials,
        LiveEngineEvents(
          onJoined: () {
            if (!mounted) return;
            setState(() => _phase = _ViewerPhase.watching);
            unawaited(ScreenAwakeService.setKeepOn(true));
          },
          onRemoteJoined: (uid) {
            if (uid == credentials.hostUid && mounted) {
              setState(() {
                _hostOnline = true;
                _hostVideo = true;
              });
            }
          },
          onRemoteLeft: (uid) {
            if (uid == credentials.hostUid && mounted) setState(() => _hostOnline = false);
          },
          onRemoteVideo: (uid, playing) {
            if (uid == credentials.hostUid && mounted) setState(() => _hostVideo = playing);
          },
          onConnection: (state) {
            if (mounted) setState(() => _connection = state);
          },
          onTokenExpiring: _renewToken,
        ),
      );
    } catch (e) {
      final failure = LiveShoppingService.toLiveException(e);
      if (!mounted) return;
      if (failure.failure == LiveFailure.notLive || failure.failure == LiveFailure.ended) {
        _showEnded();
      } else {
        _stopStreams();
        setState(() {
          _phase = _ViewerPhase.failed;
          _failure = failure;
        });
      }
    }
  }

  void _startStreams() {
    final id = _session.id;
    _rowSub ??= _service.watchSessionRow(id).listen(_onRow);
    _chatSub ??= _service.watchChat(id).listen(_onChat);
    _audienceSub ??= _service.watchAudience(id, countMe: true).listen((count) {
      if (mounted) setState(() => _viewers = count);
    });
    unawaited(_service.fetchRecentMessages(id).then((list) {
      if (!mounted) return;
      setState(() {
        final known = _messages.map((m) => m.id).toSet();
        _messages.insertAll(0, list.where((m) => !known.contains(m.id)));
      });
    }, onError: (_) {}));
  }

  void _stopStreams() {
    unawaited(_rowSub?.cancel());
    unawaited(_chatSub?.cancel());
    unawaited(_audienceSub?.cancel());
    _rowSub = null;
    _chatSub = null;
    _audienceSub = null;
  }

  void _onRow(Map<String, dynamic> row) {
    if (!mounted) return;
    final updated = _session.applyRow(row);
    if (updated.isEnded) {
      _session = updated;
      _showEnded();
      return;
    }
    setState(() => _session = updated);
    if (updated.needsPinnedDetail) _loadPinned();
  }

  Future<void> _loadPinned() async {
    if (_loadingPin) return;
    _loadingPin = true;
    try {
      final fresh = await _service.fetchSession(_session.id);
      if (fresh != null && mounted && !_session.isEnded) {
        setState(() => _session = fresh);
      }
    } catch (_) {
      // Bir sonraki satır değişikliğinde yeniden denenir.
    } finally {
      _loadingPin = false;
    }
  }

  void _showEnded() {
    _stopStreams();
    unawaited(_engine.leave());
    unawaited(ScreenAwakeService.setKeepOn(false));
    if (!mounted) return;
    final wasEnded = _phase == _ViewerPhase.ended;
    setState(() => _phase = _ViewerPhase.ended);
    if (!wasEnded) _loadEndedDetail();
  }

  Future<void> _shareLive() async {
    final text = liveShareText(_session);
    try {
      final share = widget.share;
      if (share != null) {
        await share(text);
      } else {
        await SharePlus.instance.share(ShareParams(text: text));
      }
    } catch (e) {
      debugPrint('live share: $e');
      _snack('Paylaşım yapılamadı');
    }
  }

  Future<void> _renewToken() async {
    final last = _lastTokenRenew;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 20)) return;
    _lastTokenRenew = DateTime.now();
    try {
      final credentials = await _service.fetchCredentials(_session.id, asHost: false);
      _credentials = credentials;
      await _engine.renewToken(credentials.token);
    } catch (e) {
      final failure = LiveShoppingService.toLiveException(e);
      if (failure.failure == LiveFailure.ended || failure.failure == LiveFailure.notLive) _showEnded();
    }
  }

  void _onChat(LiveChatEvent event) {
    if (!mounted) return;
    setState(() {
      final message = event.message;
      if (message != null) {
        if (_messages.every((m) => m.id != message.id)) _messages.add(message);
        if (_messages.length > 200) _messages.removeRange(0, _messages.length - 200);
      } else {
        _messages.removeWhere((m) => m.id == event.deletedId);
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_isGuest) {
      _askLogin();
      return;
    }
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final message = await _service.sendMessage(_session.id, text);
      _messageCtrl.clear();
      _onChat(LiveChatEvent.message(message));
    } catch (e) {
      _snack(LiveShoppingService.toLiveException(e).message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _askLogin() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Yorum yapmak için giriş yapmalısın'),
          action: SnackBarAction(label: 'Giriş Yap', onPressed: () => Navigator.of(context).pushNamed('/login')),
        ),
      );
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _engine.setRemoteAudioMuted(_muted);
  }

  void _openProduct(String productId) {
    final open = widget.openProduct;
    if (open != null) {
      open(context, productId);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: productId)));
  }

  /// Mağaza yayınında mağaza, kullanıcı yayınında yayıncının profili.
  void _openHost() {
    if (_session.isUserStream) {
      final open = widget.openProfile;
      if (open != null) {
        open(context, _session.hostUserId);
        return;
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: _session.hostUserId)));
      return;
    }
    final open = widget.openShop;
    if (open != null) {
      open(context, _session.shopId);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: _session.shopId)));
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ------------------------------------------------------------ arayüz

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_phase) {
        _ViewerPhase.failed => _failureView(),
        _ViewerPhase.ended => _endedView(),
        _ => _stage(),
      },
    );
  }

  Widget _video() {
    final credentials = _credentials;
    if (_phase == _ViewerPhase.connecting || credentials == null) {
      return const LiveStageMessage(icon: Icons.podcasts, text: 'Yayına bağlanılıyor…', busy: true);
    }
    final who = _session.isUserStream ? 'Yayıncı' : 'Satıcı';
    if (!_hostOnline) {
      return LiveStageMessage(icon: Icons.hourglass_top, text: '${who}nın görüntüsü bekleniyor…', busy: true);
    }
    if (!_hostVideo) {
      return LiveStageMessage(icon: Icons.videocam_off, text: '$who kamerasını kısa süreliğine kapattı.');
    }
    return _engine.buildRemoteView(credentials.hostUid);
  }

  Widget _stage() {
    final pinned = _session.pinnedProduct;
    final shopName = _session.displayName;
    return Stack(
      fit: StackFit.expand,
      children: [
        _video(),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                stops: [0, 0.2, 0.55, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _openHost,
                      child: LiveShopAvatar(logoUrl: _session.displayAvatarUrl, name: shopName),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: _openHost,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              _session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Paylaş',
                      onPressed: _shareLive,
                      icon: const Icon(Icons.share_outlined, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: _muted ? 'Sesi aç' : 'Sesi kapat',
                      onPressed: _toggleMute,
                      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    LiveBadge(viewers: _viewers ?? _session.viewerCount),
                    const SizedBox(width: 8),
                    if (_session.shopId.isNotEmpty)
                      Flexible(
                        child: LiveSubscribeButton(
                          shopId: _session.shopId,
                          shopName: _session.shopName,
                          service: _service,
                        ),
                      ),
                  ],
                ),
              ),
              if (_connection == LiveConnectionState.reconnecting)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Bağlantı yeniden kuruluyor…', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              const Spacer(),
              LiveChatList(
                messages: _messages,
                hostIcon: _session.isUserStream ? Icons.videocam : Icons.storefront,
              ),
              if (pinned != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: LivePinnedProductCard(product: pinned, onTap: () => _openProduct(pinned.id)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: _isGuest
                    ? SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _askLogin,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(Icons.login),
                          label: const Text('Yorum yapmak için giriş yap'),
                        ),
                      )
                    : LiveChatInput(controller: _messageCtrl, onSend: _sendMessage, sending: _sending),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _endedView() {
    final shopName = _session.displayName;
    final seconds = _session.durationSeconds;
    final duration = seconds != null ? Duration(seconds: seconds) : _session.durationAt(DateTime.now().toUtc());
    final messages = _session.messageCount;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: LiveShopAvatar(logoUrl: _session.displayAvatarUrl, name: shopName, size: 72)),
                const SizedBox(height: 16),
                const Text(
                  'Yayın sona erdi',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  liveEndedReasonText(
                    _session.endedReason,
                    forHost: false,
                    userStream: _session.isUserStream,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  _session.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                if (_session.startedAt != null) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (duration != null)
                        LiveStatChip(icon: Icons.timer_outlined, value: formatLiveDuration(duration), label: 'süre'),
                      LiveStatChip(
                        icon: Icons.visibility_outlined,
                        value: '${_session.peakViewerCount}',
                        label: 'en çok izleyici',
                      ),
                      if (messages != null)
                        LiveStatChip(icon: Icons.chat_bubble_outline, value: '$messages', label: 'mesaj'),
                    ],
                  ),
                ],
                if (_session.featuredProducts.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  LiveFeaturedProducts(products: _session.featuredProducts, onTap: _openProduct),
                ],
                const SizedBox(height: 24),
                if (_session.shopId.isNotEmpty) ...[
                  LiveSubscribeButton(
                    shopId: _session.shopId,
                    shopName: shopName,
                    service: _service,
                    expanded: true,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Mağaza yeniden canlı yayına başlayınca bildirim gelir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                  const SizedBox(height: 14),
                ],
                FilledButton.icon(
                  onPressed: _openHost,
                  style: FilledButton.styleFrom(backgroundColor: kLiveRed, minimumSize: const Size.fromHeight(48)),
                  icon: Icon(_session.isUserStream ? Icons.person_outline : Icons.storefront),
                  label: Text(_session.isUserStream ? '$shopName profiline git' : '$shopName mağazasına git'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _failureView() {
    final failure = _failure ?? const LiveException(LiveFailure.unknown);
    final canRetry = failure.failure == LiveFailure.connection || failure.failure == LiveFailure.unknown;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.live_tv_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 24),
            if (canRetry)
              FilledButton(
                onPressed: _connect,
                style: FilledButton.styleFrom(backgroundColor: kLiveRed),
                child: const Text('Tekrar dene'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
  }
}
