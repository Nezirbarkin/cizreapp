import 'package:flutter/material.dart';

import '../../../core/models/live_shopping_model.dart';
import '../services/live_shopping_service.dart';
import '../widgets/live_stream_widgets.dart';
import 'live_viewer_screen.dart';

/// `/live/<id>` rotası ("yayın başladı" bildirimine dokunma): yayını yükler ve
/// izleyici ekranını açar. Yayın bu arada bittiyse izleyici ekranı "Yayın sona
/// erdi" özetini gösterir; kayıt yoksa açıklama.
class LiveSessionRouteScreen extends StatefulWidget {
  const LiveSessionRouteScreen({super.key, required this.sessionId, this.service, this.viewerBuilder});

  final String sessionId;
  final LiveShoppingService? service;

  /// Testler için (Agora'sız izleyici).
  final Widget Function(LiveSession session)? viewerBuilder;

  @override
  State<LiveSessionRouteScreen> createState() => _LiveSessionRouteScreenState();
}

class _LiveSessionRouteScreenState extends State<LiveSessionRouteScreen> {
  late final LiveShoppingService _service = widget.service ?? LiveShoppingService();
  LiveSession? _session;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _service.fetchSession(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
        _error = session == null ? LiveFailure.notFound.message : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = LiveShoppingService.toLiveException(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return widget.viewerBuilder?.call(session) ?? LiveViewerScreen(session: session, service: _service);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const LiveStageMessage(icon: Icons.podcasts, text: 'Yayın açılıyor…', busy: true)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.live_tv_outlined, color: Colors.white70, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      _error ?? LiveFailure.notFound.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _load,
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
      ),
    );
  }
}
