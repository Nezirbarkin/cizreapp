// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../../../core/models/seller_announcement_model.dart';
import '../../../core/services/seller_announcement_service.dart';
import '../screens/seller_announcement_editor_screen.dart';
import 'admin_ui.dart';

/// Admin > Satıcı Duyuruları.
///
/// Satıcıların panelindeki "Genel Bakış" sekmesinin en üstünde görünen
/// duyuru kartlarının yönetimi: listele, yayına al / taslağa çek, düzenle,
/// sil. Her satırda kaç satıcıya ulaştığı, kaçının gördüğü ve kapattığı yazar.
class SellerAnnouncementsContent extends StatefulWidget {
  const SellerAnnouncementsContent({super.key, this.service});

  /// Testlerde sahte servis vermek için.
  final SellerAnnouncementService? service;

  @override
  State<SellerAnnouncementsContent> createState() =>
      _SellerAnnouncementsContentState();
}

enum _Filter { all, live, scheduled, draft, ended }

class _SellerAnnouncementsContentState
    extends State<SellerAnnouncementsContent> {
  late final SellerAnnouncementService _service =
      widget.service ?? SellerAnnouncementService();

  List<SellerAnnouncement> _all = const [];
  bool _loading = true;
  String? _error;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _service.fetchAllForAdmin();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _all.isEmpty) _error = _clean(e);
      });
    }
  }

  String _clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  _Filter _filterOf(SellerAnnouncement a, DateTime now) {
    switch (a.statusAt(now)) {
      case AnnouncementStatus.draft:
        return _Filter.draft;
      case AnnouncementStatus.scheduled:
        return _Filter.scheduled;
      case AnnouncementStatus.live:
        return _Filter.live;
      case AnnouncementStatus.ended:
        return _Filter.ended;
    }
  }

  Future<void> _openEditor([SellerAnnouncement? item]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SellerAnnouncementEditorScreen(
          initial: item,
          service: widget.service,
        ),
      ),
    );
    if (saved == true) {
      _snack('Duyuru kaydedildi');
      _load(silent: true);
    }
  }

  Future<void> _togglePublished(SellerAnnouncement a, bool value) async {
    try {
      await _service.setPublished(a.id!, value);
      _snack(value ? 'Duyuru yayında' : 'Duyuru taslağa alındı');
      _load(silent: true);
    } catch (e) {
      _snack('Değiştirilemedi: ${_clean(e)}', error: true);
    }
  }

  Future<void> _delete(SellerAnnouncement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Duyuruyu sil'),
        content: Text(
          '"${a.title}" duyurusu ve satıcıların görüntüleme/kapatma kayıtları '
          'silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
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
      await _service.delete(a.id!);
      _snack('Duyuru silindi');
      _load(silent: true);
    } catch (e) {
      _snack('Silinemedi: ${_clean(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _all.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Duyurular yüklenemedi',
        subtitle: _error,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar dene'),
        ),
      );
    }

    final now = DateTime.now();
    int count(_Filter f) => f == _Filter.all
        ? _all.length
        : _all.where((a) => _filterOf(a, now) == f).length;
    final visible = _filter == _Filter.all
        ? _all
        : _all.where((a) => _filterOf(a, now) == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Satıcı duyuruları',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Satıcıların Genel Bakış ekranının en üstünde görünür.',
                      style: TextStyle(fontSize: 12.5, color: AdminUi.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Yeni'),
                style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminChipBar<_Filter>(
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
            items: [
              (value: _Filter.all, label: 'Tümü', icon: null, count: count(_Filter.all)),
              (value: _Filter.live, label: 'Yayında', icon: null, count: count(_Filter.live)),
              (value: _Filter.scheduled, label: 'Zamanlanmış', icon: null, count: count(_Filter.scheduled)),
              (value: _Filter.draft, label: 'Taslak', icon: null, count: count(_Filter.draft)),
              (value: _Filter.ended, label: 'Bitti', icon: null, count: count(_Filter.ended)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 40),
                      AdminEmpty(
                        icon: Icons.campaign_outlined,
                        title: _all.isEmpty
                            ? 'İlk duyurunuzu oluşturun'
                            : 'Bu filtreye uyan duyuru yok',
                        subtitle: _all.isEmpty
                            ? 'Satıcılara kampanya, uyarı ya da yeni özellik duyurusu gösterin.'
                            : null,
                        action: _all.isEmpty
                            ? FilledButton.icon(
                                onPressed: () => _openEditor(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Yeni duyuru'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AdminUi.brand,
                                ),
                              )
                            : null,
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final a = visible[i];
                      return _AnnouncementTile(
                        item: a,
                        now: now,
                        onEdit: () => _openEditor(a),
                        onDelete: () => _delete(a),
                        onTogglePublished: (v) => _togglePublished(a, v),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({
    required this.item,
    required this.now,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePublished,
  });

  final SellerAnnouncement item;
  final DateTime now;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onTogglePublished;

  ({String label, Color color}) get _status {
    switch (item.statusAt(now)) {
      case AnnouncementStatus.live:
        return (label: 'Yayında', color: Colors.green.shade700);
      case AnnouncementStatus.scheduled:
        return (label: 'Zamanlanmış', color: Colors.blue.shade700);
      case AnnouncementStatus.ended:
        return (label: 'Bitti', color: Colors.blueGrey);
      case AnnouncementStatus.draft:
        return (label: 'Taslak', color: Colors.orange.shade800);
    }
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AdminUi.muted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
        ],
      );

  String get _window {
    final s = item.startsAt;
    final e = item.endsAt;
    if (e == null) return s == null ? 'Süresiz' : '${adminDate(s)} – süresiz';
    return '${adminDate(s)} – ${adminDate(e)}';
  }

  /// "Tüm satıcılar · 140 mağaza" / "3 seçili mağaza".
  String get _audienceLabel {
    if (item.audience == AnnouncementAudience.shops) {
      return '${item.shopIds.length} seçili mağaza';
    }
    return '${item.audience.label} · ${item.targetCount} mağaza';
  }

  @override
  Widget build(BuildContext context) {
    final style = item.type.style;
    final status = _status;
    final published = item.isPublished;

    return AdminCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: style.iconBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(style.icon, size: 21, color: style.iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AdminUi.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AdminUi.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AdminBadge(label: status.label, color: status.color),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _meta(Icons.groups_outlined, _audienceLabel),
                _meta(Icons.visibility_outlined, '${item.seenCount} görüntüledi'),
                if (item.isDismissible)
                  _meta(Icons.close_rounded, '${item.dismissedCount} kapattı')
                else
                  _meta(Icons.lock_outline_rounded, 'Kapatılamaz'),
                _meta(Icons.event_outlined, _window),
                if (item.isPinned) _meta(Icons.push_pin_outlined, 'Sabit'),
              ],
            ),
          ),
          const Divider(height: 14),
          Row(
            children: [
              Switch(value: published, onChanged: onTogglePublished),
              Text(
                published ? 'Yayında' : 'Taslak',
                style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
              ),
              const Spacer(),
              IconButton(
                onPressed: onEdit,
                tooltip: 'Düzenle',
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Sil',
                icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
