// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../../core/models/live_shopping_model.dart';
import '../services/agora_service.dart';
import '../services/live_shopping_service.dart';
import 'product_detail_screen.dart';

/// İzleyici ekranı: Agora uzak video + sağda canlı sohbet + altta pinli ürün.
class LiveViewerScreen extends StatefulWidget {
  final LiveSession session;
  const LiveViewerScreen({super.key, required this.session});

  @override
  State<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends State<LiveViewerScreen> {
  final _liveService = LiveShoppingService();
  final _agora = AgoraService();
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // v6: uzak video widget için controller
  VideoViewController? _remoteController;

  List<LiveMessage> _messages = [];
  StreamSubscription<LiveMessage>? _msgSub;
  StreamSubscription<void>? _pinSub;
  LiveSession? _session;
  bool _connected = false;
  String? _error;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _join();
    _loadMessages();
    _subscribeMessages();
    _subscribePin();
  }

  Future<void> _join() async {
    try {
      final uid = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      await _agora.joinAsViewer(
        channelName: widget.session.channelName,
        uid: uid,
        onJoinSuccess: (conn, u) {
          if (!mounted) return;
          // Remote video widget'ı hazırla
          _remoteController = VideoViewController.remote(
            rtcEngine: _agora.engine!,
            canvas: VideoCanvas(uid: 0),
            connection: conn,
          );
          setState(() => _connected = true);
        },
        onError: (err, msg) {
          if (mounted) setState(() => _error = 'Bağlantı hatası: $err');
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadMessages() async {
    final list = await _liveService.getRecentMessages(widget.session.id, limit: 50);
    if (mounted) setState(() => _messages = list);
  }

  void _subscribeMessages() {
    _msgSub = _liveService.watchMessages(widget.session.id).listen((m) {
      setState(() => _messages.add(m));
      _scrollToBottom();
    });
  }

  void _subscribePin() {
    _pinSub = _liveService.watchPinChanges(widget.session.id).listen((_) async {
      final updated = await _liveService.getSessionById(widget.session.id);
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

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    _messageCtrl.clear();
    try {
      await _liveService.sendMessage(
        sessionId: widget.session.id,
        message: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mesaj gönderilemedi: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _pinSub?.cancel();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    _remoteController?.dispose();
    _agora.leaveChannel();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _agora.muteAllRemoteAudio(_muted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 3, child: _videoArea()),
                  Expanded(flex: 2, child: _chatArea()),
                ],
              ),
            ),
            if (_session?.pinnedProductId != null) _pinnedProductBar(),
            _messageInput(),
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
            onPressed: () => Navigator.of(context).pop(),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'CANLI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.session.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white),
            onPressed: _toggleMute,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white70, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '.env dosyasında AGORA_APP_ID olduğundan emin olun',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else if (_connected && _remoteController != null)
          // v6: remote video view
          // ignore: deprecated_member_use
          Stack(
            children: [
              Container(color: Colors.black),
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ],
          )
        else
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.black54,
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text(
                  widget.session.hostUserName ?? 'Satıcı',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chatArea() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sohbet',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _pinnedProductBar() {
    final session = _session!;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(productId: session.pinnedProductId!),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        color: const Color(0xFFE53935),
        child: Row(
          children: [
            const Icon(Icons.push_pin, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '📌 ${session.pinnedProductName} — '
                '${session.pinnedProductPrice?.toStringAsFixed(2) ?? ''} ₺',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.add_shopping_cart, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _messageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                  hintText: 'Mesaj yaz...',
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
            const SizedBox(width: 6),
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