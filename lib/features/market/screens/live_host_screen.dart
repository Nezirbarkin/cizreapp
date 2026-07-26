// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/live_shopping_model.dart';
import '../../../core/models/product_model.dart';
import '../services/agora_service.dart';
import '../services/live_shopping_service.dart';
import '../services/product_service.dart';

/// Satıcı canlı yayın host ekranı.
/// Ön kamera + ürün pinleme paneli + canlı sohbet.
class LiveHostScreen extends StatefulWidget {
  final String shopId;
  final String shopName;

  const LiveHostScreen({
    super.key,
    required this.shopId,
    required this.shopName,
  });

  @override
  State<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends State<LiveHostScreen> {
  final _liveService = LiveShoppingService();
  final _agora = AgoraService();
  final _productService = ProductService();
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  LiveSession? _session;
  List<Product> _shopProducts = [];
  List<LiveMessage> _messages = [];
  StreamSubscription<LiveMessage>? _msgSub;
  StreamSubscription<void>? _pinSub;
  bool _preparing = true;
  bool _live = false;
  String? _error;
  bool _cameraOn = true;
  bool _micOn = true;

  @override
  void initState() {
    super.initState();
    _prepareSession();
  }

  Future<void> _prepareSession() async {
    setState(() => _preparing = true);
    try {
      _session = await _liveService.createSession(
        shopId: widget.shopId,
        title: '${widget.shopName} Canlı Yayını',
        description: 'Canlı alışveriş başladı!',
      );
      await _agora.startPreview();
      await _loadShopProducts();
      _subscribeMessages();
      _subscribePin();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _loadShopProducts() async {
    try {
      _shopProducts = await _productService.getShopProducts(widget.shopId);
    } catch (_) {}
  }

  void _subscribeMessages() {
    if (_session == null) return;
    _msgSub = _liveService.watchMessages(_session!.id).listen((m) {
      setState(() => _messages.add(m));
      _scrollToBottom();
    });
    // Son mesajları da yükle
    _liveService.getRecentMessages(_session!.id, limit: 30).then((list) {
      if (mounted) setState(() => _messages = list);
    });
  }

  void _subscribePin() {
    if (_session == null) return;
    _pinSub = _liveService.watchPinChanges(_session!.id).listen((_) async {
      final updated = await _liveService.getSessionById(_session!.id);
      if (updated != null && mounted) setState(() => _session = updated);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _goLive() async {
    if (_session == null) return;
    setState(() => _preparing = true);
    try {
      final uid = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      await _agora.joinAsHost(
        channelName: _session!.channelName,
        uid: uid,
        onJoinSuccess: (conn, u) {
          if (mounted) {
            setState(() {
              _live = true;
              _preparing = false;
            });
            _liveService.startLive(_session!.id);
          }
        },
        onError: (err, msg) {
          if (mounted) {
            setState(() {
              _error = 'Bağlantı hatası: $err';
              _preparing = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _preparing = false;
        });
      }
    }
  }

  Future<void> _endLive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Yayını Bitir'),
        content: const Text('Canlı yayını sonlandırmak istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Bitir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (_session != null) {
      await _liveService.endLive(_session!.id);
    }
    await _agora.leaveChannel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleCamera() async {
    setState(() => _cameraOn = !_cameraOn);
    await _agora.engine?.enableLocalVideo(_cameraOn);
  }

  Future<void> _toggleMic() async {
    setState(() => _micOn = !_micOn);
    await _agora.engine?.muteLocalAudioStream(!_micOn);
  }

  Future<void> _pinProduct(Product product) async {
    if (_session == null) return;
    try {
      await _liveService.pinProduct(
        sessionId: _session!.id,
        productId: product.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📌 ${product.name} pinlendi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pinlenemedi: $e')),
        );
      }
    }
  }

  Future<void> _unpin() async {
    if (_session == null) return;
    try {
      await _liveService.unpinProduct(_session!.id);
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _session == null) return;
    _messageCtrl.clear();
    // Host mesajını tabloya yaz + realtime yayın
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.from('live_messages').insert({
      'session_id': _session!.id,
      'user_id': userId,
      'message': text,
      'is_host': true,
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _pinSub?.cancel();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    if (_live) {
      _agora.leaveChannel();
    }
    _agora.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _preparing && _session == null
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: _videoArea()),
                        Expanded(flex: 2, child: _rightPanel()),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.black87,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _live ? _endLive : () => Navigator.of(context).pop(),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _live ? Colors.red : Colors.grey,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _live ? 'CANLI' : 'HAZIRLIK',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _session?.title ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!_live)
            ElevatedButton(
              onPressed: _goLive,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: const Text('Yayına Başla'),
            )
          else
            ElevatedButton(
              onPressed: _endLive,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: const Text('Bitir'),
            ),
        ],
      ),
    );
  }

  Widget _videoArea() {
    return Stack(
      children: [
        Container(color: Colors.black),
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (!_live)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off, color: Colors.white54, size: 48),
                SizedBox(height: 8),
                Text(
                  'Kamera önizlemesi hazır\n"Yayına Başla" ile başlatın',
                  style: TextStyle(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          const Center(
            child: Icon(Icons.videocam, color: Colors.white54, size: 40),
          ),
        // Kontrol bar (altta)
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _controlBtn(
                  icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                  onTap: _toggleCamera,
                ),
                const SizedBox(width: 12),
                _controlBtn(
                  icon: _micOn ? Icons.mic : Icons.mic_off,
                  onTap: _toggleMic,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: Colors.white24,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _rightPanel() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          // Pinli ürün / ürün seçici
          _pinSection(),
          const Divider(color: Colors.white24, height: 1),
          // Sohbet
          Expanded(child: _chatList()),
          // Mesaj input
          _messageInput(),
        ],
      ),
    );
  }

  Widget _pinSection() {
    final pinned = _session?.pinnedProductId;
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ürün Pinle',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          if (pinned != null)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE53935)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '📌 ${_session?.pinnedProductName ?? ""}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _unpin,
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 80,
              child: _shopProducts.isEmpty
                  ? const Center(
                      child: Text(
                        'Mağazada ürün yok',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _shopProducts.length,
                      itemBuilder: (context, i) {
                        final p = _shopProducts[i];
                        return GestureDetector(
                          onTap: () => _pinProduct(p),
                          child: Container(
                            width: 70,
                            margin: const EdgeInsets.only(right: 6),
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: p.imageUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: p.imageUrl!,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) =>
                                                Container(
                                              color: Colors.grey.shade800,
                                              child: const Icon(Icons.image,
                                                  color: Colors.white54),
                                            ),
                                          )
                                        : Container(
                                            color: Colors.grey.shade800,
                                            child: const Icon(Icons.image,
                                                color: Colors.white54),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${p.price.toStringAsFixed(2)} ₺',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _chatList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white, fontSize: 12),
              children: [
                TextSpan(
                  text: m.isHost ? '🛍️ ' : '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: '${m.userName ?? 'Kullanıcı'}: ',
                  style: TextStyle(
                    color: m.isHost
                        ? const Color(0xFFFFD600)
                        : Colors.lightBlueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: m.message),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _messageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      color: Colors.black87,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'İzleyicilere yaz...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}