import 'package:flutter/material.dart';

import '../../../core/models/live_shopping_model.dart';
import '../services/live_shopping_service.dart';
import '../widgets/live_stream_widgets.dart';
import 'live_sessions_screen.dart' show LiveEndedTile;
import 'live_viewer_screen.dart';

/// Yayınlarım: kişinin kendi biten canlı yayınları (mağaza ya da kullanıcı
/// yayını), en yeni önce, süre sınırı olmadan (`live_my_history`).
///
/// Ana sayfa kartında biten yayın hikâye gibi 24 saat kalır, herkese açık
/// Geçmiş sekmesinde yönetici ayarındaki gün kadar; burada hep durur ve yalnız
/// sahibi görür. Dokununca yayının özeti (süre, izleyici, mesaj, öne çıkan
/// ürünler) açılır.
class MyLiveStreamsScreen extends StatefulWidget {
  const MyLiveStreamsScreen({super.key, this.service, this.openSession, this.now});

  final LiveShoppingService? service;

  /// Testler için; varsayılan izleyici ekranının yayın özetini açar.
  final void Function(BuildContext context, LiveSession session)? openSession;
  final DateTime Function()? now;

  @override
  State<MyLiveStreamsScreen> createState() => _MyLiveStreamsScreenState();
}

class _MyLiveStreamsScreenState extends State<MyLiveStreamsScreen> {
  static const _pageSize = 20;

  late final LiveShoppingService _service = widget.service ?? LiveShoppingService();

  List<LiveSession> _rows = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// Yavaş eski yanıt yenisini ezmesin.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final seq = ++_seq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _service.fetchMyHistory(limit: _pageSize);
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = page.rows;
        _total = page.total;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        if (!silent || _rows.isEmpty) _error = LiveShoppingService.toLiveException(e).message;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchMyHistory(limit: _pageSize, offset: _rows.length);
      if (!mounted || seq != _seq) return;
      final known = {for (final s in _rows) s.id};
      setState(() {
        _rows = [..._rows, ...page.rows.where((s) => !known.contains(s.id))];
        _total = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(LiveShoppingService.toLiveException(e).message)));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _open(LiveSession session) {
    final open = widget.openSession;
    if (open != null) {
      open(context, session);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LiveViewerScreen(session: session, service: widget.service)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('Yayınlarım'),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(onRefresh: () => _load(silent: _rows.isNotEmpty), child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _rows.isEmpty) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (_error != null && _rows.isEmpty) return _message(Icons.error_outline, _error!, retry: _load);
    if (_rows.isEmpty) {
      return _message(
        Icons.videocam_off_outlined,
        'Henüz biten bir yayının yok',
        detail: 'Yayınların bitince burada kalır. Ana sayfada biten yayın yalnız 24 saat görünür.',
      );
    }
    final now = (widget.now ?? DateTime.now)().toUtc();
    final remaining = _total - _rows.length;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _rows.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return const _InfoBanner();
        if (index == _rows.length + 1) {
          if (remaining <= 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Toplam $_total yayın',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator(color: Colors.white)
                  : OutlinedButton(
                      onPressed: _loadMore,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                      child: Text('Daha fazla yükle ($remaining kaldı)'),
                    ),
            ),
          );
        }
        final session = _rows[index - 1];
        return LiveEndedTile(session: session, now: now, onTap: () => _open(session));
      },
    );
  }

  Widget _message(IconData icon, String text, {String? detail, Future<void> Function()? retry}) {
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
      ],
    );
  }
}

/// Listenin başında: kimin gördüğü ve ana sayfadaki 24 saat kuralı.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('my-live-info'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.white70, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bu listeyi yalnız sen görürsün. Biten yayının ana sayfada 24 saat kalır; burada hep durur.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
