// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/admin_notification_model.dart';
import '../../../core/services/admin_notification_service.dart';
import '../screens/admin_notification_composer_screen.dart';
import 'admin_notification_detail_sheet.dart';
import 'admin_notification_widgets.dart';
import 'admin_ui.dart';

/// Admin > Bildirimler (Bildirim Merkezi).
///
/// Kullanıcılara toplu (herkes / müşteri / satıcı / kurye) ya da kişiye özel
/// bildirim gönderir; gönderilenleri listeler, okunma oranını gösterir,
/// düzenletir, tekrar gönderir, siler; zamanlanmışları yönetir.
class NotificationsContentV2 extends StatefulWidget {
  const NotificationsContentV2({super.key, this.service});

  /// Testlerde sahte servis vermek için.
  final AdminNotificationService? service;

  @override
  State<NotificationsContentV2> createState() => _NotificationsContentV2State();
}

enum _Filter { all, broadcast, personal, scheduled }

class _NotificationsContentV2State extends State<NotificationsContentV2> {
  late final AdminNotificationService _service =
      widget.service ?? AdminNotificationService();

  List<AdminNotification> _all = const [];
  bool _loading = true;
  String? _error;

  _Filter _filter = _Filter.all;
  String _query = '';
  final TextEditingController _searchC = TextEditingController();

  // Çoklu seçim (karta uzun basınca).
  final Set<String> _selected = {};

  // Zamanlanmış bildirim varken liste kendini yeniler; gönderilince "Gönderildi" olsun.
  Timer? _ticker;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _all.any((n) => n.isScheduled)) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _searchC.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Veri
  // ---------------------------------------------------------------------------

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _service.history();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
        _error = null;
        // Silinmiş/artık olmayan satırlar seçimde kalmasın.
        _selected.removeWhere((id) => !list.any((n) => n.id == id));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _all.isEmpty) _error = adminNotifError(e);
      });
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? Colors.red.shade700 : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Eylemler
  // ---------------------------------------------------------------------------

  Future<void> _openComposer({
    AdminNotifComposerMode mode = AdminNotifComposerMode.create,
    AdminNotification? source,
  }) async {
    final message = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminNotificationComposerScreen(
          mode: mode,
          source: source,
          service: widget.service,
        ),
      ),
    );
    if (message != null && mounted) {
      _snack(message);
      _load(silent: true);
    }
  }

  Future<void> _openDetail(AdminNotification n) async {
    final action = await showAdminNotificationDetail(
      context,
      item: n,
      service: widget.service,
    );
    if (action != null && mounted) await _handle(action, n);
  }

  Future<void> _handle(AdminNotifAction action, AdminNotification n) async {
    switch (action) {
      case AdminNotifAction.detail:
        await _openDetail(n);
      case AdminNotifAction.edit:
        await _openComposer(mode: AdminNotifComposerMode.edit, source: n);
      case AdminNotifAction.duplicate:
        await _openComposer(mode: AdminNotifComposerMode.duplicate, source: n);
      case AdminNotifAction.sendNow:
        await _sendNow(n);
      case AdminNotifAction.delete:
        await _delete([n]);
    }
  }

  Future<void> _sendNow(AdminNotification n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Şimdi gönderilsin mi?'),
        content: Text(
          '"${n.title}" bildirimi ${n.audienceLabel} için '
          '${adminDateTime(n.scheduledFor)} tarihine zamanlanmıştı. Hemen gönderilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _service.sendNow(n.id);
      _snack('${adminCompact(r.recipientCount)} kişiye gönderildi');
      _load(silent: true);
    } catch (e) {
      _snack('Gönderilemedi: ${adminNotifError(e)}', error: true);
    }
  }

  Future<void> _delete(List<AdminNotification> items) async {
    if (items.isEmpty) return;
    final single = items.length == 1 ? items.first : null;
    final scheduledOnly = items.every((n) => n.isScheduled);
    final title = single != null
        ? (single.isScheduled ? 'Zamanlama iptal edilsin mi?' : 'Bildirim silinsin mi?')
        : '${items.length} bildirim silinsin mi?';
    final body = scheduledOnly
        ? 'Zamanlanmış gönderim iptal edilir; kimseye gönderilmez.'
        : 'Bildirim alıcıların bildirim kutusundan ve uygulamadaki Duyurular '
            'bölümünden de kalkar; henüz gitmemiş push iptal olur. Cihazlara '
            'çoktan giden push geri alınamaz. Bu işlem geri alınamaz.';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(
          single != null ? '"${single.title}"\n\n$body' : body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(scheduledOnly ? 'İptal et' : 'Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final ids = items.map((n) => n.id).toList();
      final n = await _service.delete(ids);
      if (!mounted) return;
      setState(() {
        _all = _all.where((x) => !ids.contains(x.id)).toList();
        _selected.removeAll(ids);
      });
      _snack(scheduledOnly ? 'Zamanlama iptal edildi' : '$n bildirim silindi');
      _load(silent: true);
    } catch (e) {
      _snack('Silinemedi: ${adminNotifError(e)}', error: true);
    }
  }

  void _toggleSelect(AdminNotification n) {
    setState(() {
      if (!_selected.remove(n.id)) _selected.add(n.id);
    });
  }

  // ---------------------------------------------------------------------------
  // Türetilmiş veri
  // ---------------------------------------------------------------------------

  List<AdminNotification> get _visible {
    final q = _query.trim().toLowerCase();
    return _all.where((n) {
      final okFilter = switch (_filter) {
        _Filter.all => true,
        _Filter.broadcast => !n.isPersonal,
        _Filter.personal => n.isPersonal,
        _Filter.scheduled => n.isScheduled,
      };
      if (!okFilter) return false;
      if (q.isEmpty) return true;
      return n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q) ||
          n.audienceLabel.toLowerCase().contains(q) ||
          n.recipientNames.any((r) => r.toLowerCase().contains(q));
    }).toList();
  }

  String _groupOf(AdminNotification n, DateTime now) {
    if (n.isScheduled) return 'Zamanlanmış';
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(n.when.year, n.when.month, n.when.day);
    final diff = today.difference(d).inDays;
    if (diff <= 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    if (diff < 7) return 'Bu hafta';
    return 'Daha önce';
  }

  // ---------------------------------------------------------------------------
  // Görünüm
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _all.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [_header(), const SizedBox(height: 16), const AdminNotifSkeleton()],
      );
    }
    if (_error != null && _all.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline_rounded,
        title: 'Bildirimler yüklenemedi',
        subtitle: _error,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tekrar dene'),
          style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
        ),
      );
    }

    final visible = _visible;
    final now = DateTime.now();

    // Başlık + kart satırları (tek liste; uzun geçmişte tembel çizilir).
    final rows = <Object>[];
    String? last;
    for (final n in visible) {
      final g = _groupOf(n, now);
      if (g != last) {
        rows.add(g);
        last = g;
      }
      rows.add(n);
    }

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: rows.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 14),
                _stats(),
                const SizedBox(height: 14),
                _searchAndFilters(),
                const SizedBox(height: 6),
              ],
            );
          }
          if (i == rows.length + 1) {
            if (visible.isEmpty) return _emptyState();
            return const SizedBox(height: 4);
          }
          final row = rows[i - 1];
          if (row is String) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
              child: Text(
                row.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  color: AdminUi.muted,
                ),
              ),
            );
          }
          final n = row as AdminNotification;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AdminNotifCard(
              item: n,
              selected: _selected.contains(n.id),
              selectionMode: _selecting,
              onTap: () => _selecting ? _toggleSelect(n) : _openDetail(n),
              onLongPress: () => _toggleSelect(n),
              onAction: (a) => _handle(a, n),
            ),
          );
        },
      ),
    );
  }

  Widget _header() {
    if (_selecting) {
      final picked = _all.where((n) => _selected.contains(n.id)).toList();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AdminUi.brandSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminUi.brand.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Seçimi bırak',
              onPressed: () => setState(_selected.clear),
              icon: const Icon(Icons.close_rounded),
            ),
            Expanded(
              child: Text(
                '${_selected.length} seçildi',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AdminUi.ink,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _selected
                  ..clear()
                  ..addAll(_visible.map((n) => n.id));
              }),
              child: const Text('Tümünü seç'),
            ),
            FilledButton.icon(
              onPressed: () => _delete(picked),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Sil'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            ),
            const SizedBox(width: 6),
          ],
        ),
      );
    }

    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bildirim merkezi',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AdminUi.ink,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Duyuru ve kişisel mesaj gönderin, düzenleyin, geri çekin.',
                style: TextStyle(fontSize: 12.5, color: AdminUi.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _openComposer,
          icon: const Icon(Icons.add_rounded, size: 19),
          label: const Text('Yeni bildirim'),
          style: FilledButton.styleFrom(
            backgroundColor: AdminUi.brand,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _stats() {
    final sent = _all.where((n) => !n.isScheduled).toList();
    final reached = sent.fold<int>(0, (s, n) => s + n.recipientCount);
    final reads = sent.fold<int>(0, (s, n) => s + n.readCount);
    final rate = reached == 0 ? 0 : (reads / reached * 100).round();
    final scheduled = _all.where((n) => n.isScheduled).length;

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final cols = c.maxWidth >= 640 ? 4 : 2;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        Widget tile(Widget t) => SizedBox(width: w, child: t);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            tile(AdminStatTile(
              icon: Icons.send_rounded,
              label: 'Gönderilen',
              value: adminCompact(sent.length),
              color: Colors.blue,
            )),
            tile(AdminStatTile(
              icon: Icons.people_alt_rounded,
              label: 'Ulaşılan kişi',
              value: adminCompact(reached),
              color: Colors.teal,
            )),
            tile(AdminStatTile(
              icon: Icons.mark_email_read_rounded,
              label: 'Okunma oranı',
              value: '%$rate',
              color: Colors.green,
            )),
            tile(AdminStatTile(
              icon: Icons.schedule_rounded,
              label: 'Zamanlanmış',
              value: '$scheduled',
              color: Colors.amber.shade800,
              onTap: scheduled == 0
                  ? null
                  : () => setState(() => _filter = _Filter.scheduled),
            )),
          ],
        );
      },
    );
  }

  Widget _searchAndFilters() {
    int count(_Filter f) => switch (f) {
          _Filter.all => _all.length,
          _Filter.broadcast => _all.where((n) => !n.isPersonal).length,
          _Filter.personal => _all.where((n) => n.isPersonal).length,
          _Filter.scheduled => _all.where((n) => n.isScheduled).length,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchC,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Başlık, mesaj veya alıcı ara',
            hintStyle: const TextStyle(fontSize: 13.5, color: AdminUi.muted),
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Temizle',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () => setState(() {
                      _searchC.clear();
                      _query = '';
                    }),
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AdminUi.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AdminUi.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AdminUi.brand, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AdminChipBar<_Filter>(
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
          items: [
            (value: _Filter.all, label: 'Tümü', icon: null, count: count(_Filter.all)),
            (value: _Filter.broadcast, label: 'Toplu', icon: Icons.campaign_outlined, count: count(_Filter.broadcast)),
            (value: _Filter.personal, label: 'Kişiye özel', icon: Icons.person_pin_outlined, count: count(_Filter.personal)),
            (value: _Filter.scheduled, label: 'Zamanlanmış', icon: Icons.schedule_rounded, count: count(_Filter.scheduled)),
          ],
        ),
      ],
    );
  }

  Widget _emptyState() {
    final none = _all.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: AdminEmpty(
        icon: none ? Icons.notifications_none_rounded : Icons.search_off_rounded,
        title: none ? 'İlk bildiriminizi gönderin' : 'Bu filtreye uyan bildirim yok',
        subtitle: none
            ? 'Kampanya, duyuru ya da tek kişiye özel bir mesaj gönderebilirsiniz.'
            : 'Arama veya filtreyi değiştirmeyi deneyin.',
        action: none
            ? FilledButton.icon(
                onPressed: _openComposer,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Yeni bildirim'),
                style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
              )
            : null,
      ),
    );
  }
}
