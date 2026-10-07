import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../../core/models/live_shopping_model.dart';
import '../../../core/models/product_model.dart';
import '../../../core/services/screen_awake_service.dart';
import '../services/agora_service.dart';
import '../services/live_shopping_service.dart';
import '../widgets/live_stream_widgets.dart';
import '../widgets/shop_card.dart' show formatShopMoney;

enum _HostPhase { preparing, setup, connecting, live, ended, failed }

/// Yayıncı ekranı (Görev 3.4): satıcının mağaza yayını ya da [shopId]
/// verilmezse kullanıcının kendi (mağazasız) yayını. Kullanıcı yayınında ürün
/// sabitleme yoktur; bildirim yayıncının takipçilerine gider.
///
/// Akış: yayın kaydı hazırlanır (ya da açık yayın sürdürülür) → Agora anahtarı
/// alınır → kamera önizlemesi → "Yayına Başla" → kanala katılınca yayın canlı
/// olur. Canlıyken 20 sn'de bir sinyal (izleyici sayısıyla) gider; sunucu
/// yayını kapatırsa (zaman aşımı/yönetici) özet ekranına geçilir.
class LiveHostScreen extends StatefulWidget {
  const LiveHostScreen({
    super.key,
    this.shopId,
    required this.shopName,
    this.service,
    this.engineFactory,
    this.now,
    this.heartbeatInterval = const Duration(seconds: 20),
  });

  /// Boş = kullanıcı yayını.
  final String? shopId;

  /// Mağaza adı; kullanıcı yayınında yayıncının adı (varsayılan başlık için).
  final String shopName;
  final LiveShoppingService? service;
  final LiveVideoEngineFactory? engineFactory;
  final DateTime Function()? now;
  final Duration heartbeatInterval;

  @override
  State<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends State<LiveHostScreen> with WidgetsBindingObserver {
  late final LiveShoppingService _service = widget.service ?? LiveShoppingService();
  late final LiveVideoEngine _engine = (widget.engineFactory ?? AgoraService.new)();
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  _HostPhase _phase = _HostPhase.preparing;
  LiveException? _failure;
  LiveSession? _session;
  LiveCredentials? _credentials;
  LiveEndSummary? _summary;
  String? _endedReason;
  String? _titleError;

  List<Product>? _products;
  final List<LiveMessage> _messages = [];
  int _viewers = 0;
  bool _micMuted = false;
  bool _cameraOff = false;
  bool _sending = false;
  bool _ending = false;
  LiveConnectionState _connection = LiveConnectionState.connecting;
  DateTime? _lastTokenRenew;

  Timer? _heartbeat;
  Timer? _clock;
  Timer? _joinTimeout;
  StreamSubscription<Map<String, dynamic>>? _rowSub;
  StreamSubscription<LiveChatEvent>? _chatSub;
  StreamSubscription<int>? _audienceSub;

  DateTime _now() => (widget.now ?? DateTime.now)().toUtc();

  bool get _isUserStream => widget.shopId == null || widget.shopId!.isEmpty;

  Future<({LiveSession session, bool resumed})> _create(String title) => _isUserStream
      ? _service.createUserSession(title: title)
      : _service.createSession(shopId: widget.shopId!, title: title);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final name = widget.shopName.trim();
    final title = name.isEmpty
        ? (_isUserStream ? 'Canlı yayındayım' : 'Mağaza canlı yayında')
        : '$name canlı yayında';
    _titleCtrl.text = title.length > 80 ? title.substring(0, 80) : title;
    if (!_engine.isSupported) {
      _phase = _HostPhase.failed;
      _failure = const LiveException(LiveFailure.unsupported);
      return;
    }
    _prepare();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveLoops();
    final session = _session;
    // Ekran kapanırken hâlâ açık yayın varsa kapat (hazırlıktaki kayıt silinir).
    if (session != null && _phase != _HostPhase.ended) {
      unawaited(_service.endLive(session.id).then((_) {}, onError: (_) {}));
    }
    unawaited(_engine.dispose());
    unawaited(ScreenAwakeService.setKeepOn(false));
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Arka plandan dönünce hemen sinyal: bu arada kapatıldıysa özet gösterilir.
    if (state == AppLifecycleState.resumed && _phase == _HostPhase.live) _beat();
  }

  // ------------------------------------------------------------ hazırlık

  Future<void> _prepare() async {
    setState(() {
      _phase = _HostPhase.preparing;
      _failure = null;
    });
    try {
      final created = await _create(_titleCtrl.text.trim());
      _session = created.session;
      if (created.resumed) _titleCtrl.text = created.session.title;
      _credentials = await _service.fetchCredentials(created.session.id, asHost: true);
      await _engine.startPreview(_credentials!);
      if (!_isUserStream) unawaited(_loadProducts());
      if (!mounted) return;
      if (created.resumed) {
        await _join();
      } else {
        setState(() => _phase = _HostPhase.setup);
      }
    } catch (e) {
      final failure = LiveShoppingService.toLiveException(e);
      final session = _session;
      if (session != null && session.isScheduled) {
        // Başlamadan vazgeçildi: boş hazırlık kaydını bırakma.
        unawaited(_service.endLive(session.id).then((_) {}, onError: (_) {}));
        _session = null;
      }
      if (mounted) {
        setState(() {
          _phase = _HostPhase.failed;
          _failure = failure;
        });
      }
    }
  }

  Future<void> _loadProducts() async {
    final shopId = widget.shopId;
    if (shopId == null || shopId.isEmpty) return;
    try {
      final list = await _service.fetchShopProducts(shopId);
      if (mounted) setState(() => _products = list.where((p) => p.isAvailable).toList());
    } catch (_) {
      if (mounted) setState(() => _products = const []);
    }
  }

  Future<void> _startPressed() async {
    final title = _titleCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (title.length < 3 || title.length > 80) {
      setState(() => _titleError = 'Başlık 3–80 karakter olmalı');
      return;
    }
    setState(() => _titleError = null);
    final session = _session;
    if (session == null) return;
    if (title != session.title) {
      try {
        final updated = await _create(title);
        _session = updated.session;
      } catch (e) {
        _snack(LiveShoppingService.toLiveException(e).message);
        return;
      }
    }
    await _join();
  }

  Future<void> _join() async {
    final credentials = _credentials;
    if (credentials == null || !mounted) return;
    setState(() => _phase = _HostPhase.connecting);
    _joinTimeout?.cancel();
    _joinTimeout = Timer(const Duration(seconds: 25), () {
      if (mounted && _phase == _HostPhase.connecting) {
        _fail(const LiveException(LiveFailure.connection, 'join timeout'));
      }
    });
    try {
      await _engine.joinAsHost(
        credentials,
        LiveEngineEvents(
          onJoined: _onJoined,
          onConnection: (state) {
            if (!mounted) return;
            setState(() => _connection = state);
            if (state == LiveConnectionState.failed && _phase == _HostPhase.live) {
              _fail(const LiveException(LiveFailure.connection, 'connection failed'));
            }
          },
          onTokenExpiring: _renewToken,
          onError: (code) {
            if (code.contains('Token') || code.contains('token')) _renewToken();
          },
        ),
      );
    } catch (e) {
      _fail(LiveShoppingService.toLiveException(e));
    }
  }

  Future<void> _onJoined() async {
    _joinTimeout?.cancel();
    final session = _session;
    if (session == null || !mounted || _phase == _HostPhase.live) return;
    try {
      final live = await _service.startLive(session.id);
      if (!mounted) return;
      setState(() {
        _session = live;
        _phase = _HostPhase.live;
        _connection = LiveConnectionState.connected;
      });
      unawaited(ScreenAwakeService.setKeepOn(true));
      _startLiveLoops(live.id);
      // Takipçilere/abonelere "yayın başladı" bildirimi gittiyse söyle.
      final notified = live.notified ?? 0;
      if (notified > 0) _snack('🔔 $notified kişiye yayın bildirimi gönderildi');
    } catch (e) {
      _fail(LiveShoppingService.toLiveException(e));
    }
  }

  void _startLiveLoops(String sessionId) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(widget.heartbeatInterval, (_) => _beat());
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _audienceSub = _service.watchAudience(sessionId, countMe: false).listen((count) {
      if (mounted) setState(() => _viewers = count);
    });
    _chatSub = _service.watchChat(sessionId).listen(_onChat);
    _rowSub = _service.watchSessionRow(sessionId).listen((row) {
      final current = _session;
      if (current == null || !mounted) return;
      final updated = current.applyRow(row);
      if (updated.isEnded && _phase == _HostPhase.live) {
        _endedRemotely(updated);
      }
    });
    unawaited(_service.fetchRecentMessages(sessionId).then((list) {
      if (!mounted) return;
      setState(() {
        final known = _messages.map((m) => m.id).toSet();
        _messages.insertAll(0, list.where((m) => !known.contains(m.id)));
      });
    }, onError: (_) {}));
  }

  void _stopLiveLoops() {
    _heartbeat?.cancel();
    _clock?.cancel();
    _joinTimeout?.cancel();
    _heartbeat = null;
    _clock = null;
    unawaited(_rowSub?.cancel());
    unawaited(_chatSub?.cancel());
    unawaited(_audienceSub?.cancel());
    _rowSub = null;
    _chatSub = null;
    _audienceSub = null;
  }

  Future<void> _beat() async {
    final session = _session;
    if (session == null || _phase != _HostPhase.live) return;
    try {
      final beat = await _service.heartbeat(session.id, _viewers);
      if (beat.isEnded && mounted && _phase == _HostPhase.live) {
        _endedRemotely(_session!.applyRow({'status': 'ended', 'ended_reason': beat.endedReason}));
      }
    } catch (_) {
      // Geçici ağ hatası: bir sonraki sinyal dener; 2 dk sürerse sunucu kapatır.
    }
  }

  Future<void> _renewToken() async {
    final session = _session;
    final last = _lastTokenRenew;
    if (session == null || (last != null && _now().difference(last) < const Duration(seconds: 20))) return;
    _lastTokenRenew = _now();
    try {
      final credentials = await _service.fetchCredentials(session.id, asHost: true);
      _credentials = credentials;
      await _engine.renewToken(credentials.token);
    } catch (e) {
      debugPrint('live host token renew: $e');
    }
  }

  void _fail(LiveException failure) {
    if (!mounted) return;
    _stopLiveLoops();
    unawaited(_engine.leave());
    unawaited(ScreenAwakeService.setKeepOn(false));
    setState(() {
      _phase = _HostPhase.failed;
      _failure = failure;
    });
  }

  // ------------------------------------------------------------ canlı

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
    final text = _messageCtrl.text.trim();
    final session = _session;
    if (text.isEmpty || session == null || _sending) return;
    setState(() => _sending = true);
    try {
      final message = await _service.sendMessage(session.id, text);
      _messageCtrl.clear();
      _onChat(LiveChatEvent.message(message));
    } catch (e) {
      _snack(LiveShoppingService.toLiveException(e).message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _moderate(LiveMessage message) async {
    if (message.isHost) return;
    final delete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '${message.authorName}: ${message.message}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Mesajı sil', style: TextStyle(color: Colors.red)),
              subtitle: const Text('Yayındaki herkes için kaldırılır'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (delete != true) return;
    try {
      await _service.deleteMessage(message.id);
      _onChat(LiveChatEvent.deleted(message.id));
    } catch (e) {
      _snack(LiveShoppingService.toLiveException(e).message);
    }
  }

  Future<void> _openProducts() async {
    if (_products == null) await _loadProducts();
    if (!mounted) return;
    final products = _products ?? const <Product>[];
    final pinnedId = _session?.pinnedProduct?.id;
    final picked = await showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Yayında göstereceğin ürünü seç',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'İzleyiciler ürünü görüntünün altında görür, dokununca ürün sayfası açılır.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? const Center(child: Text('Satışta ürünün yok.'))
                  : ListView.separated(
                      controller: scroll,
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = products[i];
                        final pinned = p.id == pinnedId;
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: p.imageUrl == null
                                  ? const ColoredBox(color: Color(0xFFF1F1F1), child: Icon(Icons.image_outlined))
                                  : CachedNetworkImage(
                                      imageUrl: p.imageUrl!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 144,
                                      errorWidget: (_, _, _) =>
                                          const ColoredBox(color: Color(0xFFF1F1F1), child: Icon(Icons.image_outlined)),
                                    ),
                            ),
                          ),
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatShopMoney(p.effectivePrice)),
                          trailing: pinned
                              ? const Chip(label: Text('Gösteriliyor'), visualDensity: VisualDensity.compact)
                              : const Icon(Icons.push_pin_outlined),
                          onTap: pinned ? null : () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || _session == null) return;
    try {
      final updated = await _service.pinProduct(_session!.id, picked.id);
      if (mounted) setState(() => _session = updated);
    } catch (e) {
      _snack(LiveShoppingService.toLiveException(e).message);
    }
  }

  Future<void> _unpin() async {
    final session = _session;
    if (session == null) return;
    try {
      final updated = await _service.unpinProduct(session.id);
      if (mounted) setState(() => _session = updated);
    } catch (e) {
      _snack(LiveShoppingService.toLiveException(e).message);
    }
  }

  Future<void> _toggleMic() async {
    setState(() => _micMuted = !_micMuted);
    await _engine.setMicMuted(_micMuted);
  }

  Future<void> _toggleCamera() async {
    setState(() => _cameraOff = !_cameraOff);
    await _engine.setCameraEnabled(!_cameraOff);
  }

  // ------------------------------------------------------------ bitiş

  Future<void> _confirmEnd() async {
    if (_ending) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yayını bitir'),
        content: const Text('Canlı yayın herkes için sona erecek. Emin misin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: kLiveRed),
            child: const Text('Bitir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final session = _session;
    if (session == null) return;
    setState(() => _ending = true);
    try {
      final summary = await _service.endLive(session.id);
      _stopLiveLoops();
      await _engine.leave();
      unawaited(ScreenAwakeService.setKeepOn(false));
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _endedReason = summary.endedReason ?? 'host';
        _phase = _HostPhase.ended;
      });
    } catch (e) {
      _snack(LiveShoppingService.toLiveException(e).message);
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  /// Sunucu yayını kapattı (zaman aşımı / yönetici): özet yerelden kurulur.
  void _endedRemotely(LiveSession ended) {
    _stopLiveLoops();
    unawaited(_engine.leave());
    unawaited(ScreenAwakeService.setKeepOn(false));
    final start = ended.startedAt;
    setState(() {
      _session = ended;
      _endedReason = ended.endedReason ?? 'timeout';
      _summary = LiveEndSummary(
        status: 'ended',
        endedReason: _endedReason,
        duration: start == null ? Duration.zero : (ended.endedAt ?? _now()).difference(start),
        peakViewerCount: ended.peakViewerCount,
        messageCount: _messages.length,
      );
      _phase = _HostPhase.ended;
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ------------------------------------------------------------ arayüz

  bool get _blocksPop => _phase == _HostPhase.live || _phase == _HostPhase.connecting;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_blocksPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _HostPhase.live) _confirmEnd();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: switch (_phase) {
          _HostPhase.preparing => const LiveStageMessage(icon: Icons.videocam, text: 'Yayın hazırlanıyor…', busy: true),
          _HostPhase.failed => _failureView(),
          _HostPhase.ended => _summaryView(),
          _ => _stage(),
        },
      ),
    );
  }

  Widget _stage() {
    final live = _phase == _HostPhase.live;
    final session = _session;
    final pinned = session?.pinnedProduct;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_cameraOff)
          const LiveStageMessage(icon: Icons.videocam_off, text: 'Kameran kapalı; izleyiciler yalnız sesini duyuyor.')
        else
          _engine.buildLocalView(),
        const _Scrim(),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                child: Row(
                  children: [
                    if (live)
                      LiveBadge(elapsed: session?.durationAt(_now()) ?? Duration.zero, viewers: _viewers)
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                        child: const Text(
                          'ÖNİZLEME',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                    const Spacer(),
                    if (live)
                      FilledButton(
                        onPressed: _ending ? null : _confirmEnd,
                        style: FilledButton.styleFrom(backgroundColor: kLiveRed),
                        child: Text(_ending ? 'Bitiriliyor…' : 'Bitir'),
                      )
                    else
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: _phase == _HostPhase.connecting ? null : () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                  ],
                ),
              ),
              if (live && _connection == LiveConnectionState.reconnecting)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bağlantı yeniden kuruluyor…',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    // Kurulum panelinde klavye açılınca (ya da sohbet listesi
                    // büyüyünce) bu alan düğmelerden kısa kalıyor; sabit Column
                    // alttan taşıyordu (admin Loglar: "RenderFlex overflowed by
                    // 41 pixels on the bottom"). Sığmazsa kayar.
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LiveRoundButton(
                            icon: Icons.cameraswitch_outlined,
                            tooltip: 'Kamerayı çevir',
                            onPressed: _cameraOff ? null : () => _engine.switchCamera(),
                          ),
                          LiveRoundButton(
                            icon: _micMuted ? Icons.mic_off : Icons.mic,
                            tooltip: _micMuted ? 'Mikrofonu aç' : 'Mikrofonu kapat',
                            active: _micMuted,
                            onPressed: _toggleMic,
                          ),
                          LiveRoundButton(
                            icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                            tooltip: _cameraOff ? 'Kamerayı aç' : 'Kamerayı kapat',
                            active: _cameraOff,
                            onPressed: _toggleCamera,
                          ),
                          if (live && !_isUserStream)
                            LiveRoundButton(
                              icon: Icons.shopping_bag_outlined,
                              tooltip: 'Ürün göster',
                              onPressed: _openProducts,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_phase == _HostPhase.setup) _setupPanel(),
              if (_phase == _HostPhase.connecting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: LiveStageMessage(icon: Icons.podcasts, text: 'Yayına bağlanılıyor…', busy: true),
                ),
              if (live) ...[
                LiveChatList(
                  messages: _messages,
                  onMessageLongPress: _moderate,
                  hostIcon: _isUserStream ? Icons.videocam : Icons.storefront,
                ),
                if (pinned != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: LivePinnedProductCard(product: pinned, onRemove: _unpin),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: LiveChatInput(
                    controller: _messageCtrl,
                    onSend: _sendMessage,
                    sending: _sending,
                    hint: 'İzleyicilere yaz…',
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _setupPanel() {
    final products = _products;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Canlı yayına hazır mısın?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 10),
          TextField(
            controller: _titleCtrl,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Yayın başlığı',
              errorText: _titleError,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          Text(
            _isUserStream
                ? "Yayının Canlı Yayınlar'da görünür, takipçilerine bildirim gider. "
                      'Hesabın gizliyse yalnız takipçilerin izleyebilir. Topluluk kurallarına uymayan yayınları yönetim kapatır.'
                : products == null
                ? 'Ürünlerin yükleniyor…'
                : products.isEmpty
                ? 'Satışta ürünün yok; yayında ürün gösteremezsin.'
                : 'Yayındayken ${products.length} ürününden birini ekranda gösterebilirsin.',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _startPressed,
            style: FilledButton.styleFrom(
              backgroundColor: kLiveRed,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.podcasts),
            label: const Text('Yayına Başla', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
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
            const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 24),
            if (failure.failure == LiveFailure.permissionDenied)
              FilledButton(
                onPressed: () => openAppSettings(),
                style: FilledButton.styleFrom(backgroundColor: kLiveRed),
                child: const Text('İzinleri aç'),
              ),
            if (canRetry)
              FilledButton(
                onPressed: _prepare,
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

  Widget _summaryView() {
    final summary = _summary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 56),
            const SizedBox(height: 12),
            const Text(
              'Yayın sona erdi',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              liveEndedReasonText(_endedReason, forHost: true),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _stat('Süre', formatLiveDuration(summary?.duration ?? Duration.zero)),
                _stat('En çok izleyici', '${summary?.peakViewerCount ?? 0}'),
                _stat('Mesaj', '${summary?.messageCount ?? 0}'),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(backgroundColor: kLiveRed, minimumSize: const Size.fromHeight(48)),
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    ),
  );
}

/// Üst ve alt kenarda okunabilirlik için karartma.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
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
    );
  }
}
