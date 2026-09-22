// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_ui.dart';

/// Admin > Müzik Çalar.
///
/// Uygulamadaki arka plan müzik çalarını kimin, hangi şarkıyı, ne kadar
/// dinlediği. Şu an dinleyenler canlı (20 sn'de bir tazelenir). İstemci,
/// çalarken ~30 sn'de bir `music_report` çağırır (bkz.
/// OkeySoundService); sunucu kullanıcı × şarkı × gün özeti tutar.
///
/// Şarkıları YÖNETMEK (yükleme/silme) için "101 Okey" sayfasındaki
/// "Arka Plan Şarkıları" bölümü kullanılır.
class MusicStatsContent extends StatefulWidget {
  const MusicStatsContent({super.key});

  @override
  State<MusicStatsContent> createState() => _MusicStatsContentState();
}

class _MusicStatsContentState extends State<MusicStatsContent> {
  int _days = 30;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  Timer? _liveTimer;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
    // "Şu an dinleyenler" canlı kalsın.
    _liveTimer = Timer.periodic(const Duration(seconds: 20), (_) => _load(spinner: false));
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool spinner = true}) async {
    if (spinner) setState(() => _loading = true);
    try {
      final res = await _db.rpc('admin_music_stats', params: {'p_days': _days});
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(res as Map);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_data == null) _error = '$e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_data?[key] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Dinleme istatistiğini sil'),
        content: const Text(
          'Tüm kullanıcıların müzik dinleme geçmişi ve "şu an dinleyenler" '
          'kaydı silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await _db.rpc('admin_clear_music_stats');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$n kayıt silindi'), behavior: SnackBarBehavior.floating),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e'), backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _showTrackListeners(Map<String, dynamic> track) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TrackListenersSheet(
        trackKey: track['track_key'] as String,
        trackName: (track['track_name'] as String?) ?? 'Şarkı',
        days: _days,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Müzik istatistiği yüklenemedi',
        subtitle: _error,
        action: FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Tekrar dene')),
      );
    }

    final now = _list('listeningNow');
    final tracks = _list('tracks');
    final listeners = _list('listeners');
    final daily = _list('daily');
    final totalSeconds = (_data?['totalSeconds'] as num?) ?? 0;
    final totalPlays = (_data?['totalPlays'] as num?) ?? 0;
    final unique = (_data?['uniqueListeners'] as num?) ?? 0;
    final today = (_data?['listenersToday'] as num?) ?? 0;

    return Container(
      color: AdminUi.page,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Müzik çalar',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AdminUi.ink),
                  ),
                ),
                IconButton(
                  tooltip: 'İstatistiği sil',
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  tooltip: 'Yenile',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AdminChipBar<int>(
              selected: _days,
              color: Colors.deepPurple,
              onSelected: (v) {
                setState(() => _days = v);
                _load();
              },
              items: const [
                (value: 7, label: 'Son 7 gün', icon: null, count: null),
                (value: 30, label: 'Son 30 gün', icon: null, count: null),
                (value: 90, label: 'Son 90 gün', icon: null, count: null),
              ],
            ),
            const SizedBox(height: 12),
            _buildLiveCard(now),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AdminStatTile(
                    icon: Icons.timer_outlined,
                    label: 'Toplam dinleme',
                    value: adminDuration(totalSeconds),
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AdminStatTile(
                    icon: Icons.play_circle_outline,
                    label: 'Çalma sayısı',
                    value: adminCompact(totalPlays),
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AdminStatTile(
                    icon: Icons.headphones_rounded,
                    label: 'Dinleyen kişi',
                    value: adminCompact(unique),
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AdminStatTile(
                    icon: Icons.today_rounded,
                    label: 'Bugün dinleyen',
                    value: adminCompact(today),
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            if (daily.length > 1) ...[
              const SizedBox(height: 12),
              _buildDaily(daily),
            ],
            const SizedBox(height: 18),
            _sectionTitle('En çok dinlenen şarkılar', Icons.library_music_outlined),
            const SizedBox(height: 8),
            if (tracks.isEmpty)
              const AdminCard(child: Text('Bu aralıkta dinleme kaydı yok.', style: TextStyle(color: AdminUi.muted)))
            else
              AdminCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < tracks.length; i++) ...[
                      _trackRow(i + 1, tracks[i]),
                      if (i != tracks.length - 1) const Divider(height: 1, color: AdminUi.line),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 18),
            _sectionTitle('En çok dinleyenler', Icons.emoji_events_outlined),
            const SizedBox(height: 8),
            if (listeners.isEmpty)
              const AdminCard(child: Text('Bu aralıkta dinleyen yok.', style: TextStyle(color: AdminUi.muted)))
            else
              AdminCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < listeners.length; i++) ...[
                      _listenerRow(i + 1, listeners[i]),
                      if (i != listeners.length - 1) const Divider(height: 1, color: AdminUi.line),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AdminUi.brand),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AdminUi.ink),
        ),
      ],
    );
  }

  Widget _buildLiveCard(List<Map<String, dynamic>> now) {
    return AdminCard(
      borderColor: now.isEmpty ? null : Colors.green.shade200,
      color: now.isEmpty ? null : Colors.green.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: now.isEmpty ? Colors.grey : Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                now.isEmpty ? 'Şu an dinleyen yok' : 'Şu an ${now.length} kişi dinliyor',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AdminUi.ink),
              ),
            ],
          ),
          if (now.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final n in now.take(20))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    AdminAvatar(url: n['avatar_url'] as String?, name: adminDisplayName(n), radius: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            adminDisplayName(n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.music_note_rounded, size: 13, color: AdminUi.muted),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  '${n['track_name'] ?? 'Şarkı'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: AdminUi.muted),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (now.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${now.length - 20} kişi daha', style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDaily(List<Map<String, dynamic>> daily) {
    final maxSeconds = daily.fold<int>(1, (m, d) {
      final s = (d['seconds'] as num).toInt();
      return s > m ? s : m;
    });
    return AdminCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Günlük dinleme süresi', style: TextStyle(fontSize: 11.5, color: AdminUi.muted)),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in daily)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${d['day']}: ${adminDuration((d['seconds'] as num))} · ${d['listeners']} kişi',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        height: 4 + 50 * ((d['seconds'] as num).toInt() / maxSeconds),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackRow(int rank, Map<String, dynamic> t) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showTrackListeners(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: rank <= 3 ? Colors.amber.shade800 : AdminUi.muted,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (t['track_name'] as String?) ?? 'Şarkı',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AdminUi.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t['listeners']} kişi · ${t['plays']} çalma · son: ${adminTimeAgo(adminParseDate(t['last_played_at']))}',
                    style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                  ),
                ],
              ),
            ),
            Text(
              adminDuration((t['seconds'] as num)),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminUi.ink),
            ),
            const Icon(Icons.chevron_right_rounded, color: AdminUi.muted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _listenerRow(int rank, Map<String, dynamic> l) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: rank <= 3 ? Colors.amber.shade800 : AdminUi.muted,
              ),
            ),
          ),
          AdminAvatar(url: l['avatar_url'] as String?, name: adminDisplayName(l), radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adminDisplayName(l),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AdminUi.ink),
                ),
                Text(
                  '${l['plays']} çalma · en çok: ${l['top_track'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                ),
              ],
            ),
          ),
          Text(
            adminDuration((l['seconds'] as num)),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminUi.ink),
          ),
        ],
      ),
    );
  }
}

class _TrackListenersSheet extends StatefulWidget {
  final String trackKey;
  final String trackName;
  final int days;

  const _TrackListenersSheet({
    required this.trackKey,
    required this.trackName,
    required this.days,
  });

  @override
  State<_TrackListenersSheet> createState() => _TrackListenersSheetState();
}

class _TrackListenersSheetState extends State<_TrackListenersSheet> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_music_track_listeners',
        params: {'p_track_key': widget.trackKey, 'p_days': widget.days},
      );
      if (!mounted) return;
      setState(() {
        _rows = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AdminUi.page,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(
              widget.trackName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AdminUi.ink),
            ),
            const SizedBox(height: 2),
            Text(
              'Son ${widget.days} günde dinleyenler',
              style: const TextStyle(color: AdminUi.muted),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Text('Yüklenemedi: $_error', style: const TextStyle(color: Colors.red))
            else if (_rows == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_rows!.isEmpty)
              const AdminCard(child: Text('Dinleyen bulunamadı.', style: TextStyle(color: AdminUi.muted)))
            else
              AdminCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < _rows!.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            AdminAvatar(url: _rows![i]['avatar_url'] as String?, name: adminDisplayName(_rows![i]), radius: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    adminDisplayName(_rows![i]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    '${_rows![i]['plays']} çalma · son: ${adminTimeAgo(adminParseDate(_rows![i]['last_played_at']))}',
                                    style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              adminDuration((_rows![i]['seconds'] as num)),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      if (i != _rows!.length - 1) const Divider(height: 1, color: AdminUi.line),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
