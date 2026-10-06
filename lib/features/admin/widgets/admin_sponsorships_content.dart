import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/sponsorship_model.dart';
import '../../market/widgets/shop_card.dart' show formatShopMoney;
import '../services/admin_sponsorship_service.dart';
import 'admin_ui.dart';

/// Admin > Öne Çıkarma (Görev 4.2).
///
/// Satıcıların bakiyeden satın aldığı öne çıkarmaların (sponsorlu vitrin)
/// yönetimi:
/// - **Başvurular:** yönetici onayı açıkken bekleyenler; onay ya da ret (ret
///   ücreti satıcının bakiyesine iade eder).
/// - **Yayında:** süren ve sıradaki öne çıkarmalar; iadeli/iadesiz iptal.
/// - **Geçmiş:** reddedilen, iptal edilen, süresi biten.
/// - **Paketler:** vitrin başına süre/fiyat paketleri.
/// - **Ayarlar:** satışın açık olması ve yönetici onayı zorunluluğu.
///
/// Kararlar sunucuda tek işlemde yürür (zincir, vitrin sütunu, iade, satıcı
/// bildirimi); bu ekran yalnız sonucu gösterir.
class AdminSponsorshipsContent extends StatefulWidget {
  const AdminSponsorshipsContent({super.key, this.service});

  /// Testlerde sahte servis vermek için.
  final AdminSponsorshipService? service;

  @override
  State<AdminSponsorshipsContent> createState() => _AdminSponsorshipsContentState();
}

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

DateTime? _local(DateTime? value) => value?.toLocal();

/// "2 gün 5 sa", "3 sa 20 dk", "12 dk".
String _remaining(DateTime end) {
  final diff = end.difference(DateTime.now());
  if (diff.isNegative) return '0 dk';
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  if (days > 0) return hours == 0 ? '$days gün' : '$days gün $hours sa';
  if (diff.inHours > 0) return minutes == 0 ? '${diff.inHours} sa' : '${diff.inHours} sa $minutes dk';
  return '${diff.inMinutes < 1 ? 1 : diff.inMinutes} dk';
}

/// İptalde sunucunun yapacağı iadenin tahmini (başlamadıysa tamamı, sürüyorsa
/// kalan süre oranı). Gösterim içindir; gerçek tutarı sunucu döndürür.
double estimateSponsorshipRefund(AdminSponsorshipRow row, {DateTime? now}) {
  final at = (now ?? DateTime.now()).toUtc();
  final start = row.startsAt;
  final end = row.endsAt;
  if (start == null || end == null || !end.isAfter(at)) return 0;
  if (start.isAfter(at)) return row.pricePaid;
  final total = end.difference(start).inSeconds;
  if (total <= 0) return 0;
  final left = end.difference(at).inSeconds;
  return (row.pricePaid * left / total * 100).roundToDouble() / 100;
}

class _AdminSponsorshipsContentState extends State<AdminSponsorshipsContent> {
  late final AdminSponsorshipService _service = widget.service ?? AdminSponsorshipService();

  /// Son okunan özet (her liste yüklemesi tazeler).
  AdminSponsorshipPage? _overview;
  bool? _enabled;
  bool? _requiresApproval;

  /// Karar/iptal/ayar değişince artar; liste sekmeleri yeniden okur.
  int _revision = 0;
  bool _savingFlag = false;

  void _onPage(AdminSponsorshipPage page) {
    if (!mounted) return;
    setState(() {
      _overview = page;
      if (!_savingFlag) {
        _enabled = page.enabled;
        _requiresApproval = page.requiresApproval;
      }
    });
  }

  void _changed() {
    if (mounted) setState(() => _revision++);
  }

  Future<void> _setFlag(String key, bool value) async {
    setState(() => _savingFlag = true);
    try {
      await _service.setFlag(key, value);
      if (!mounted) return;
      setState(() {
        if (key == 'sponsorship_enabled') {
          _enabled = value;
        } else {
          _requiresApproval = value;
        }
      });
      _snack(
        context,
        key == 'sponsorship_enabled'
            ? (value ? 'Öne çıkarma satışı açıldı' : 'Öne çıkarma satışı kapatıldı')
            : (value ? 'Yeni satın alımlar onayınızı bekleyecek' : 'Yeni satın alımlar hemen yayına girecek'),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminSponsorshipService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _savingFlag = false);
    }
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final pending = overview?.pending ?? 0;
    return DefaultTabController(
      length: 5,
      child: ColoredBox(
        color: AdminUi.page,
        child: Column(
          children: [
            Builder(
              builder: (context) => _SummaryRow(
                overview: overview,
                onOpenTab: (index) => DefaultTabController.of(context).animateTo(index),
              ),
            ),
            Material(
              color: Colors.white,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AdminUi.brand,
                unselectedLabelColor: AdminUi.muted,
                indicatorColor: AdminUi.brand,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                tabs: [
                  Tab(text: pending > 0 ? 'Başvurular ($pending)' : 'Başvurular'),
                  const Tab(text: 'Yayında'),
                  const Tab(text: 'Geçmiş'),
                  const Tab(text: 'Paketler'),
                  const Tab(text: 'Ayarlar'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SponsorshipListTab(
                    key: const PageStorageKey('sponsorships-pending'),
                    service: _service,
                    status: 'pending',
                    revision: _revision,
                    onPage: _onPage,
                    onChanged: _changed,
                  ),
                  _SponsorshipListTab(
                    key: const PageStorageKey('sponsorships-active'),
                    service: _service,
                    status: 'active',
                    revision: _revision,
                    onPage: _onPage,
                    onChanged: _changed,
                  ),
                  _SponsorshipListTab(
                    key: const PageStorageKey('sponsorships-history'),
                    service: _service,
                    status: 'history',
                    revision: _revision,
                    onPage: _onPage,
                    onChanged: _changed,
                  ),
                  _PackagesTab(service: _service),
                  _SettingsTab(
                    enabled: _enabled,
                    requiresApproval: _requiresApproval,
                    pending: pending,
                    saving: _savingFlag,
                    onChanged: _setFlag,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Özet
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.overview, required this.onOpenTab});

  final AdminSponsorshipPage? overview;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    String count(int? v) => o == null ? '–' : adminCompact(v ?? 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: AdminMiniStat(
              icon: Icons.hourglass_top_rounded,
              label: 'Bekleyen',
              value: count(o?.pending),
              color: Colors.orange.shade700,
              onTap: () => onOpenTab(0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AdminMiniStat(
              icon: Icons.play_circle_outline,
              label: 'Yayında',
              value: count(o?.running),
              color: Colors.green.shade700,
              onTap: () => onOpenTab(1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AdminMiniStat(
              icon: Icons.schedule,
              label: 'Sırada',
              value: count(o?.queued),
              color: Colors.blue.shade700,
              onTap: () => onOpenTab(1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AdminMiniStat(
              icon: Icons.payments_outlined,
              label: 'Gelir (30g)',
              value: o == null ? '–' : formatShopMoney(o.revenue30d),
              color: AdminUi.brand,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Başvurular / Yayında / Geçmiş
// ---------------------------------------------------------------------------

class _SponsorshipListTab extends StatefulWidget {
  const _SponsorshipListTab({
    super.key,
    required this.service,
    required this.status,
    required this.revision,
    required this.onPage,
    required this.onChanged,
  });

  final AdminSponsorshipService service;

  /// 'pending' | 'active' | 'history'
  final String status;
  final int revision;
  final ValueChanged<AdminSponsorshipPage> onPage;
  final VoidCallback onChanged;

  @override
  State<_SponsorshipListTab> createState() => _SponsorshipListTabState();
}

class _SponsorshipListTabState extends State<_SponsorshipListTab> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  List<AdminSponsorshipRow> _rows = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<String> _busy = {};

  /// Yavaş eski yanıt yenisini ezmesin.
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SponsorshipListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load(silent: true);
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
      final page = await widget.service.fetch(widget.status, limit: _pageSize);
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = page.rows;
        _total = page.total;
        _loading = false;
        _error = null;
      });
      widget.onPage(page);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        if (!silent || _rows.isEmpty) _error = AdminSponsorshipService.errorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.fetch(widget.status, limit: _pageSize, offset: _rows.length);
      if (!mounted || seq != _seq) return;
      final known = {for (final row in _rows) row.id};
      setState(() {
        _rows = [..._rows, ...page.rows.where((row) => !known.contains(row.id))];
        _total = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminSponsorshipService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _run(
    AdminSponsorshipRow row,
    Future<double> Function() action,
    String Function(double refunded) doneText,
  ) async {
    setState(() {
      _busy.add(row.id);
    });
    try {
      final refunded = await action();
      if (!mounted) return;
      _snack(context, doneText(refunded));
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminSponsorshipService.errorMessage(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(row.id);
        });
      }
    }
    // Başarıda da hatada da tüm sekmeler yeniden okunur: kayıt başka bir
    // yönetici tarafından sonuçlandırılmış olabilir.
    widget.onChanged();
  }

  Future<void> _approve(AdminSponsorshipRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Öne çıkarma onaylansın mı?'),
        content: Text(
          '${row.shopName} · ${row.placement.label} · ${row.durationDays} gün\n\n'
          'Aynı vitrinde süren bir öne çıkarması varsa onun bitişinden, yoksa '
          'hemen başlar. Satıcıya bildirim gider.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Onayla')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      row,
      () => widget.service.review(row.id, approve: true),
      (_) => 'Onaylandı — ${row.shopName} öne çıkarıldı',
    );
  }

  Future<void> _reject(AdminSponsorshipRow row) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(
        title: 'Başvuru reddedilsin mi?',
        message:
            '${row.shopName} · ${row.placement.label}\n'
            '${formatShopMoney(row.pricePaid)} satıcının bakiyesine iade edilir ve '
            'satıcıya bildirim gider.',
        confirmLabel: 'Reddet',
      ),
    );
    if (note == null || !mounted) return;
    await _run(
      row,
      () => widget.service.review(row.id, approve: false, note: note),
      (refunded) => 'Reddedildi — ${formatShopMoney(refunded)} bakiyeye iade edildi',
    );
  }

  Future<void> _cancel(AdminSponsorshipRow row) async {
    final choice = await showDialog<({bool refund, String note})>(
      context: context,
      builder: (_) => _CancelDialog(row: row),
    );
    if (choice == null || !mounted) return;
    await _run(
      row,
      () => widget.service.cancel(row.id, refund: choice.refund, note: choice.note),
      (refunded) => refunded > 0
          ? 'İptal edildi — ${formatShopMoney(refunded)} bakiyeye iade edildi'
          : 'İptal edildi (iade yok)',
    );
  }

  Widget _empty() {
    final (icon, title, subtitle) = switch (widget.status) {
      'pending' => (
        Icons.inbox_outlined,
        'Bekleyen başvuru yok',
        'Yönetici onayı açıkken satın alınan öne çıkarmalar burada onayınızı bekler '
            '(Ayarlar sekmesi).',
      ),
      'active' => (
        Icons.campaign_outlined,
        'Yayında öne çıkarma yok',
        'Süren ve sıradaki öne çıkarmalar burada görünür.',
      ),
      _ => (
        Icons.history,
        'Geçmiş kayıt yok',
        'Reddedilen, iptal edilen ve süresi biten öne çıkarmalar burada listelenir.',
      ),
    };
    return AdminEmpty(icon: icon, title: title, subtitle: subtitle);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Liste alınamadı',
        subtitle: _error,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar dene'),
        ),
      );
    }
    final remaining = _total - _rows.length;
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [_empty()],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: _rows.length + (remaining > 0 ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == _rows.length) {
                  return Center(
                    child: _loadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(),
                          )
                        : OutlinedButton(
                            onPressed: _loadMore,
                            child: Text(
                              'Daha fazla yükle ($remaining kaldı)',
                              textAlign: TextAlign.center,
                            ),
                          ),
                  );
                }
                final row = _rows[index];
                return _SponsorshipCard(
                  row: row,
                  busy: _busy.contains(row.id),
                  onApprove: () => _approve(row),
                  onReject: () => _reject(row),
                  onCancel: () => _cancel(row),
                );
              },
            ),
    );
  }
}

({Color color, IconData icon}) _statusStyle(AdminSponsorshipRow row) => switch (row.status) {
  SponsorshipStatus.pending => (color: Colors.orange.shade800, icon: Icons.hourglass_top_rounded),
  SponsorshipStatus.rejected => (color: Colors.red.shade700, icon: Icons.close_rounded),
  SponsorshipStatus.cancelled => (color: Colors.grey.shade700, icon: Icons.block),
  SponsorshipStatus.active =>
    row.isRunning
        ? (color: Colors.green.shade700, icon: Icons.play_circle_outline)
        : row.isQueued
        ? (color: Colors.blue.shade700, icon: Icons.schedule)
        : (color: Colors.blueGrey, icon: Icons.history),
};

List<String> _timeLines(AdminSponsorshipRow row) {
  final created = _local(row.createdAt);
  final starts = _local(row.startsAt);
  final ends = _local(row.endsAt);
  final reviewed = _local(row.reviewedAt);
  switch (row.status) {
    case SponsorshipStatus.pending:
      return ['Başvuru: ${adminDateTime(created)} (${adminTimeAgo(created)})'];
    case SponsorshipStatus.rejected:
      return ['Başvuru: ${adminDateTime(created)}', 'Reddedildi: ${adminDateTime(reviewed)}'];
    case SponsorshipStatus.cancelled:
      return [
        if (starts != null) 'Yayın: ${adminDateTime(starts)} – ${adminDateTime(ends)}',
        'İptal: ${adminDateTime(reviewed)}',
      ];
    case SponsorshipStatus.active:
      if (row.isRunning && row.endsAt != null) {
        return [
          'Başladı: ${adminDateTime(starts)}',
          'Bitiş: ${adminDateTime(ends)} · ${_remaining(row.endsAt!)} kaldı',
        ];
      }
      if (row.isQueued) {
        return ['Başlayacak: ${adminDateTime(starts)}', 'Bitiş: ${adminDateTime(ends)}'];
      }
      return ['Yayın: ${adminDateTime(starts)} – ${adminDateTime(ends)}'];
  }
}

class _SponsorshipCard extends StatelessWidget {
  const _SponsorshipCard({
    required this.row,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onCancel,
  });

  final AdminSponsorshipRow row;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(row);
    final canCancel = row.status == SponsorshipStatus.active && (row.isRunning || row.isQueued);
    final note = row.reviewNote?.trim() ?? '';
    return AdminCard(
      key: ValueKey('sponsorship-${row.id}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                row.placement.isProduct ? Icons.inventory_2_outlined : Icons.storefront_outlined,
                size: 20,
                color: AdminUi.brand,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.shopName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AdminUi.ink),
                ),
              ),
            ],
          ),
          if (row.productName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Ürün: ${row.productName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AdminUi.ink),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AdminPill(label: row.statusLabel, color: style.color, icon: style.icon),
              AdminPill(label: row.placement.label, color: Colors.indigo),
              AdminPill(
                label: row.packageName.isEmpty
                    ? '${row.durationDays} gün'
                    : '${row.packageName} · ${row.durationDays} gün',
                color: Colors.teal.shade700,
              ),
              AdminPill(label: formatShopMoney(row.pricePaid), color: Colors.green.shade800),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in _timeLines(row))
            Text(line, style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
          if (row.createdByName != null)
            Text(
              'Satın alan: ${row.createdByName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
            ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminUi.page,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminUi.line),
              ),
              child: Text('Not: $note', style: const TextStyle(fontSize: 12.5, color: AdminUi.ink)),
            ),
          ],
          if (busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ] else if (row.status == SponsorshipStatus.pending) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reddet'),
                  ),
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Onayla'),
                  ),
                ],
              ),
            ),
          ] else if (canCancel) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                icon: const Icon(Icons.block, size: 18),
                label: const Text('İptal et'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ret: isteğe bağlı not (satıcıya bildirimde gösterilir). Vazgeçilirse null,
/// onaylanırsa not (boş olabilir) döner.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.message, required this.confirmLabel});

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('sponsorship-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Satıcıya not (isteğe bağlı)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _note.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// İptal: iade seçimi + not.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.row});

  final AdminSponsorshipRow row;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _note = TextEditingController();
  bool _refund = true;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final estimate = estimateSponsorshipRefund(row);
    return AlertDialog(
      title: const Text('Öne çıkarma iptal edilsin mi?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row.shopName} · ${row.placement.label}\n'
              '${row.isQueued ? 'Henüz başlamadı' : 'Şu an yayında'}; iptal edilince '
              'vitrinden hemen kalkar, sıradaki öne çıkarması varsa öne alınır. '
              'Satıcıya bildirim gider.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('sponsorship-refund'),
              contentPadding: EdgeInsets.zero,
              value: _refund,
              onChanged: (value) => setState(() => _refund = value),
              title: const Text('Bakiyeye iade et'),
              subtitle: Text(
                _refund
                    ? (row.isQueued
                          ? 'Tamamı: ${formatShopMoney(estimate)}'
                          : 'Kalan süre kadarı: yaklaşık ${formatShopMoney(estimate)}')
                    : 'Ücret iade edilmez',
              ),
            ),
            TextField(
              key: const ValueKey('sponsorship-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'İptal nedeni (isteğe bağlı)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (refund: _refund, note: _note.text.trim())),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: const Text('İptal et'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Paketler
// ---------------------------------------------------------------------------

class _PackagesTab extends StatefulWidget {
  const _PackagesTab({required this.service});

  final AdminSponsorshipService service;

  @override
  State<_PackagesTab> createState() => _PackagesTabState();
}

class _PackagesTabState extends State<_PackagesTab> with AutomaticKeepAliveClientMixin {
  List<AdminSponsorPackage> _packages = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

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
      final packages = await widget.service.fetchPackages();
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _packages.isEmpty) _error = AdminSponsorshipService.errorMessage(e);
      });
    }
  }

  Future<void> _edit({AdminSponsorPackage? package, required SponsorPlacement placement}) async {
    final draft = await showDialog<SponsorPackageDraft>(
      context: context,
      builder: (_) => SponsorPackageEditorDialog(package: package, placement: placement),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.service.savePackage(
        id: package?.id,
        placement: draft.placement,
        name: draft.name,
        durationDays: draft.durationDays,
        price: draft.price,
        isActive: draft.isActive,
        sortOrder: draft.sortOrder,
      );
      if (!mounted) return;
      _snack(context, package == null ? 'Paket eklendi' : 'Paket güncellendi');
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminSponsorshipService.errorMessage(e), error: true);
    }
    await _load(silent: true);
  }

  Future<void> _setActive(AdminSponsorPackage package, bool active) async {
    setState(() {
      _busy.add(package.id);
    });
    try {
      await widget.service.setPackageActive(package.id, active);
      if (!mounted) return;
      _snack(context, active ? '${package.name} satıcılara açıldı' : '${package.name} pasifleştirildi');
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminSponsorshipService.errorMessage(e), error: true);
    }
    await _load(silent: true);
    if (mounted) {
      setState(() {
        _busy.remove(package.id);
      });
    }
  }

  Future<void> _delete(AdminSponsorPackage package) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paket silinsin mi?'),
        content: Text(
          '${package.placement.label} · ${package.name} '
          '(${package.durationDays} gün, ${formatShopMoney(package.price)})\n\n'
          'Satın alınmış öne çıkarmalar etkilenmez. Satıcıların görmesini yalnız '
          'durdurmak için paketi pasifleştirmeniz yeterli.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy.add(package.id);
    });
    try {
      await widget.service.deletePackage(package.id);
      if (!mounted) return;
      _snack(context, 'Paket silindi');
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminSponsorshipService.errorMessage(e), error: true);
    }
    await _load(silent: true);
    if (mounted) {
      setState(() {
        _busy.remove(package.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _packages.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Paketler alınamadı',
        subtitle: _error,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar dene'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          const Text(
            'Fiyat ve süre değişiklikleri yalnız yeni satın alımları etkiler. '
            'Pasif paketi satıcılar görmez.',
            style: TextStyle(fontSize: 12.5, color: AdminUi.muted),
          ),
          const SizedBox(height: 12),
          for (final placement in SponsorPlacement.values) ...[
            _PlacementHeader(
              placement: placement,
              onAdd: () => _edit(placement: placement),
            ),
            const SizedBox(height: 8),
            ..._tilesFor(placement),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  List<Widget> _tilesFor(SponsorPlacement placement) {
    final packages = _packages.where((p) => p.placement == placement).toList();
    if (packages.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Bu vitrinde paket yok — satıcılar satın alamaz.',
            style: TextStyle(fontSize: 12.5, color: AdminUi.muted),
          ),
        ),
      ];
    }
    return [
      for (final package in packages)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _PackageTile(
            package: package,
            busy: _busy.contains(package.id),
            onActive: (value) => _setActive(package, value),
            onEdit: () => _edit(package: package, placement: package.placement),
            onDelete: () => _delete(package),
          ),
        ),
    ];
  }
}

class _PlacementHeader extends StatelessWidget {
  const _PlacementHeader({required this.placement, required this.onAdd});

  final SponsorPlacement placement;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                placement.label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminUi.ink),
              ),
              const SizedBox(height: 2),
              Text(placement.description, style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
            ],
          ),
        ),
        TextButton.icon(
          key: ValueKey('add-package-${placement.dbValue}'),
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Ekle'),
        ),
      ],
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.busy,
    required this.onActive,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminSponsorPackage package;
  final bool busy;
  final ValueChanged<bool> onActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final perDay = package.durationDays > 1
        ? ' · günlük ${formatShopMoney((package.price / package.durationDays * 100).roundToDouble() / 100)}'
        : '';
    return AdminCard(
      key: ValueKey('package-${package.id}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
      color: package.isActive ? null : const Color(0xFFF9FAFB),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: package.isActive ? AdminUi.ink : AdminUi.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${package.durationDays} gün · ${formatShopMoney(package.price)}$perDay',
                  style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                ),
                if (!package.isActive)
                  Text(
                    'Pasif — satıcılar görmez',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Switch(value: package.isActive, onChanged: onActive),
          PopupMenuButton<String>(
            tooltip: 'Paket işlemleri',
            onSelected: (value) {
              if (value == 'edit') {
                onEdit();
              } else {
                onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Düzenle')),
              PopupMenuItem(value: 'delete', child: Text('Sil')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Paket formunun sonucu.
class SponsorPackageDraft {
  const SponsorPackageDraft({
    required this.placement,
    required this.name,
    required this.durationDays,
    required this.price,
    required this.isActive,
    required this.sortOrder,
  });

  final SponsorPlacement placement;
  final String name;
  final int durationDays;
  final double price;
  final bool isActive;
  final int sortOrder;
}

/// "12,50" / "12.5" / "30" → 12.5 / 30; geçersiz, negatif ya da 2'den fazla
/// ondalık → null. Veritabanı sütunu numeric(10,2).
double? parseSponsorPrice(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(text)) return null;
  return double.tryParse(text);
}

/// Paket ekleme/düzenleme penceresi. Sınırlar tablo CHECK'leriyle aynı:
/// ad 1–40, süre 1–90 gün, fiyat ≥ 0 (en çok 2 ondalık).
class SponsorPackageEditorDialog extends StatefulWidget {
  const SponsorPackageEditorDialog({super.key, this.package, required this.placement});

  final AdminSponsorPackage? package;
  final SponsorPlacement placement;

  @override
  State<SponsorPackageEditorDialog> createState() => _SponsorPackageEditorDialogState();
}

class _SponsorPackageEditorDialogState extends State<SponsorPackageEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late SponsorPlacement _placement = widget.package?.placement ?? widget.placement;
  late final TextEditingController _name = TextEditingController(text: widget.package?.name ?? '');
  late final TextEditingController _days = TextEditingController(
    text: widget.package == null ? '' : '${widget.package!.durationDays}',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.package == null ? '' : _priceText(widget.package!.price),
  );
  late final TextEditingController _sort = TextEditingController(text: '${widget.package?.sortOrder ?? 0}');
  late bool _active = widget.package?.isActive ?? true;

  static String _priceText(double price) => price == price.roundToDouble()
      ? price.toInt().toString()
      : price.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    _price.dispose();
    _sort.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      SponsorPackageDraft(
        placement: _placement,
        name: _name.text.trim(),
        durationDays: int.parse(_days.text.trim()),
        price: parseSponsorPrice(_price.text)!,
        isActive: _active,
        sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.package == null ? 'Yeni paket' : 'Paketi düzenle'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<SponsorPlacement>(
                initialValue: _placement,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vitrin'),
                items: [
                  for (final placement in SponsorPlacement.values)
                    DropdownMenuItem(
                      value: placement,
                      child: Text(placement.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _placement = value);
                },
              ),
              const SizedBox(height: 4),
              Text(_placement.description, style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('package-name'),
                controller: _name,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Paket adı', hintText: 'Örn. Haftalık'),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Paket adı gerekli' : null,
              ),
              TextFormField(
                key: const ValueKey('package-days'),
                controller: _days,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                decoration: const InputDecoration(labelText: 'Süre (gün)', helperText: '1–90 gün'),
                validator: (value) {
                  final days = int.tryParse((value ?? '').trim());
                  if (days == null || days < 1 || days > 90) return 'Süre 1–90 gün olmalı';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('package-price'),
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: 'Fiyat (₺)', helperText: 'Örn. 150 ya da 12,50'),
                validator: (value) => parseSponsorPrice(value ?? '') == null
                    ? 'Geçerli bir fiyat girin (en çok 2 ondalık)'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('package-sort'),
                controller: _sort,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: const InputDecoration(labelText: 'Sıra', helperText: 'Küçük sayı önce gösterilir'),
              ),
              SwitchListTile(
                key: const ValueKey('package-active'),
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Satıcılara açık'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ayarlar
// ---------------------------------------------------------------------------

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.enabled,
    required this.requiresApproval,
    required this.pending,
    required this.saving,
    required this.onChanged,
  });

  final bool? enabled;
  final bool? requiresApproval;
  final int pending;
  final bool saving;
  final void Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = this.enabled;
    final requiresApproval = this.requiresApproval;
    if (enabled == null || requiresApproval == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                key: const ValueKey('flag-sponsorship-enabled'),
                value: enabled,
                onChanged: saving ? null : (value) => onChanged('sponsorship_enabled', value),
                secondary: Icon(Icons.campaign_outlined, color: enabled ? AdminUi.brand : AdminUi.muted),
                title: const Text('Öne çıkarma satışı açık', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  enabled
                      ? 'Satıcılar paket satın alabilir.'
                      : 'Satıcılar yeni öne çıkarma satın alamaz; süren öne çıkarmalar '
                            'süresi bitene kadar görünür.',
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey('flag-sponsorship-approval'),
                value: requiresApproval,
                onChanged: saving ? null : (value) => onChanged('sponsorship_requires_approval', value),
                secondary: Icon(
                  Icons.fact_check_outlined,
                  color: requiresApproval ? AdminUi.brand : AdminUi.muted,
                ),
                title: const Text('Yönetici onayı gereksin', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  requiresApproval
                      ? 'Ücret alınır, öne çıkarma onayınızı bekler; reddedilirse ücret '
                            'bakiyeye iade edilir.'
                      : 'Satın alınan öne çıkarma hemen yayına girer.',
                ),
              ),
            ],
          ),
        ),
        if (!requiresApproval && pending > 0) ...[
          const SizedBox(height: 12),
          AdminCard(
            color: Colors.orange.shade50,
            borderColor: Colors.orange.shade200,
            child: Text(
              '$pending başvuru hâlâ onay bekliyor; Başvurular sekmesinden sonuçlandırın.',
              style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nasıl çalışır?', style: TextStyle(fontWeight: FontWeight.w800, color: AdminUi.ink)),
              SizedBox(height: 6),
              Text(
                '• Fiyat ve süreler Paketler sekmesinden yönetilir; değişiklik yalnız yeni '
                'satın alımları etkiler.\n'
                '• İptalde iade seçilirse başlamamış öne çıkarmanın tamamı, süren öne '
                'çıkarmanın kalan süresi kadarı bakiyeye döner.\n'
                '• Onay, ret ve iptalde satıcıya bildirim gider.',
                style: TextStyle(fontSize: 13, color: AdminUi.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
