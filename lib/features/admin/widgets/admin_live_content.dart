import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/live_shopping_model.dart';
import '../../market/screens/live_viewer_screen.dart';
import '../services/admin_live_service.dart';
import 'admin_ui.dart';

typedef AdminLiveViewerOpener = void Function(BuildContext context, LiveSession session);

/// Admin > Canlı Yayınlar (Görev 4.3).
///
/// - **Yayında:** şu an canlı yayınlar; izle ya da notla kapat (isteğe bağlı
///   mağazanın iznini de kaldır).
/// - **Geçmiş:** biten yayınlar ve bitiş nedeni (yönetici kapattıysa not).
/// - **Mağaza İzinleri:** mağaza başına izin ver / kaldır / varsayılana dön.
/// - **Kullanıcı İzinleri:** mağazası olmayan kullanıcıların yayın izni
///   (arama, izin ver / kaldır / varsayılan).
/// - **Ayarlar:** modül açık mı, kimler yayın açabilir (mağazalar: herkes /
///   yalnız izinliler; kullanıcılar: herkes / yalnız izinliler / kapalı);
///   yayın bildirimleri (kitle, bekleme süresi, alıcı sınırı), ana sayfa
///   kartı ve geçmiş süresi + son 30 günün sayaçları.
///
/// Kurallar sunucuda (`admin_live_*`, `private.live_shop_access`); satıcı ve
/// izleyici ekranları kapatma nedenini zaten gösterir.
class AdminLiveContent extends StatefulWidget {
  const AdminLiveContent({super.key, this.service, this.openViewer, this.moderatorMode = false});

  /// Testlerde sahte servis vermek için.
  final AdminLiveService? service;

  /// Görev 4.6: Moderasyon Paneli'nde yalnız Yayında/Geçmiş sekmeleri; mağaza
  /// izni ve genel ayarlar yöneticiye kalır.
  final bool moderatorMode;

  /// Testlerde izleyici ekranı (Agora) yerine.
  final AdminLiveViewerOpener? openViewer;

  @override
  State<AdminLiveContent> createState() => _AdminLiveContentState();
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

Color _accessColor(LiveShopAccess access) => switch (access) {
  LiveShopAccess.ok => Colors.green.shade700,
  LiveShopAccess.revoked => Colors.red.shade700,
  LiveShopAccess.notPermitted => Colors.orange.shade800,
  LiveShopAccess.disabled => Colors.grey.shade700,
  LiveShopAccess.usersOff => Colors.grey.shade700,
  LiveShopAccess.accountInactive => Colors.grey.shade700,
};

class _AdminLiveContentState extends State<AdminLiveContent> {
  late final AdminLiveService _service = widget.service ?? AdminLiveService();

  /// Son okunan özet (Yayında/Geçmiş yüklemeleri tazeler).
  AdminLiveSessionsPage? _overview;
  AdminLiveSettings? _settings;

  /// Kapatma/izin/ayar değişince artar; sekmeler yeniden okur.
  int _revision = 0;
  bool _savingSettings = false;

  void _onSessionsPage(AdminLiveSessionsPage page) {
    if (!mounted) return;
    setState(() {
      _overview = page;
      if (!_savingSettings) _settings = page.settings;
    });
  }

  void _onSettings(AdminLiveSettings settings) {
    if (!mounted || _savingSettings) return;
    setState(() => _settings = settings);
  }

  void _changed() {
    if (mounted) setState(() => _revision++);
  }

  void _openViewer(LiveSession session) {
    final opener = widget.openViewer;
    if (opener != null) {
      opener(context, session);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LiveViewerScreen(session: session)));
  }

  Future<void> _applySettings({bool? enabled, String? access, bool closeRunning = false}) async {
    setState(() => _savingSettings = true);
    try {
      final change = await _service.setSettings(enabled: enabled, access: access, closeRunning: closeRunning);
      if (!mounted) return;
      setState(() => _settings = change.settings);
      _snack(
        context,
        [
          if (enabled != null) enabled ? 'Canlı yayın açıldı' : 'Canlı yayın kapatıldı',
          if (access != null)
            access == 'invite'
                ? 'Artık yalnız izin verilen mağazalar yayın açabilir'
                : 'Tüm aktif mağazalar yayın açabilir',
          if (change.closed > 0) '${change.closed} yayın kapatıldı',
        ].join(' · '),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
    _changed();
  }

  Future<void> _applyUserMode(String mode, {bool closeRunning = false}) async {
    setState(() => _savingSettings = true);
    try {
      final change = await _service.setUserMode(mode, closeRunning: closeRunning);
      if (!mounted) return;
      final current = _settings ?? const AdminLiveSettings();
      setState(() => _settings = AdminLiveSettings(enabled: current.enabled, access: current.access, userMode: mode));
      _snack(
        context,
        [
          switch (mode) {
            'off' => 'Kullanıcı yayınları kapatıldı',
            'invite' => 'Artık yalnız izin verilen kullanıcılar yayın açabilir',
            _ => 'Tüm aktif kullanıcılar yayın açabilir',
          },
          if (change.closed > 0) '${change.closed} yayın kapatıldı',
        ].join(' · '),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final liveNow = _overview?.liveNow ?? 0;
    final moderator = widget.moderatorMode;
    return DefaultTabController(
      length: moderator ? 2 : 5,
      child: ColoredBox(
        color: AdminUi.page,
        child: Column(
          children: [
            Builder(
              builder: (context) => _LiveSummaryRow(
                overview: _overview,
                showPermissions: !moderator,
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
                  Tab(text: liveNow > 0 ? 'Yayında ($liveNow)' : 'Yayında'),
                  const Tab(text: 'Geçmiş'),
                  if (!moderator) const Tab(text: 'Mağaza İzinleri'),
                  if (!moderator) const Tab(text: 'Kullanıcı İzinleri'),
                  if (!moderator) const Tab(text: 'Ayarlar'),
                ],
              ),
            ),
            if (_settings?.enabled == false)
              Material(
                key: const ValueKey('live-disabled-banner'),
                color: const Color(0xFFFEF2F2),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.pause_circle_outline, color: Colors.red.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Canlı yayın genel olarak kapalı — yeni yayın açılamıyor.',
                          style: TextStyle(fontSize: 12.5, color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _LiveSessionsTab(
                    key: const PageStorageKey('admin-live-live'),
                    service: _service,
                    status: 'live',
                    revision: _revision,
                    onPage: _onSessionsPage,
                    onChanged: _changed,
                    onWatch: _openViewer,
                    allowRevoke: !moderator,
                  ),
                  _LiveSessionsTab(
                    key: const PageStorageKey('admin-live-ended'),
                    service: _service,
                    status: 'ended',
                    revision: _revision,
                    onPage: _onSessionsPage,
                    onChanged: _changed,
                    onWatch: _openViewer,
                    allowRevoke: !moderator,
                  ),
                  if (!moderator)
                    _LiveShopsTab(
                      service: _service,
                      revision: _revision,
                      onSettings: _onSettings,
                      onChanged: _changed,
                    ),
                  if (!moderator)
                    _LiveUsersTab(
                      service: _service,
                      revision: _revision,
                      onSettings: _onSettings,
                      onChanged: _changed,
                      settings: _settings,
                      saving: _savingSettings,
                      onUserMode: _applyUserMode,
                    ),
                  if (!moderator)
                    _LiveSettingsTab(
                      settings: _settings,
                      saving: _savingSettings,
                      onApply: _applySettings,
                      onUserMode: _applyUserMode,
                      service: _service,
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

class _LiveSummaryRow extends StatelessWidget {
  const _LiveSummaryRow({required this.overview, required this.onOpenTab, this.showPermissions = true});

  final AdminLiveSessionsPage? overview;
  final ValueChanged<int> onOpenTab;
  final bool showPermissions;

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
              icon: Icons.sensors,
              label: 'Yayında',
              value: count(o?.liveNow),
              color: Colors.red.shade700,
              onTap: () => onOpenTab(0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AdminMiniStat(
              icon: Icons.today_outlined,
              label: 'Bugün',
              value: count(o?.today),
              color: Colors.blue.shade700,
              onTap: () => onOpenTab(1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AdminMiniStat(
              icon: Icons.timer_outlined,
              label: '7 gün (dk)',
              value: count(o?.minutes7d),
              color: AdminUi.brand,
              onTap: () => onOpenTab(1),
            ),
          ),
          if (showPermissions) ...[
            const SizedBox(width: 8),
            Expanded(
              child: AdminMiniStat(
                icon: Icons.block,
                label: 'İzni yok',
                value: count(o?.revokedShops),
                color: Colors.orange.shade800,
                onTap: () => onOpenTab(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Yayında / Geçmiş
// ---------------------------------------------------------------------------

class _LiveSessionsTab extends StatefulWidget {
  const _LiveSessionsTab({
    super.key,
    required this.service,
    required this.status,
    required this.revision,
    required this.onPage,
    required this.onChanged,
    required this.onWatch,
    this.allowRevoke = true,
  });

  final AdminLiveService service;

  /// Kapatırken "mağazanın iznini de kaldır" seçeneği (yalnız yönetici).
  final bool allowRevoke;

  /// 'live' | 'ended'
  final String status;
  final int revision;
  final ValueChanged<AdminLiveSessionsPage> onPage;
  final VoidCallback onChanged;
  final ValueChanged<LiveSession> onWatch;

  @override
  State<_LiveSessionsTab> createState() => _LiveSessionsTabState();
}

class _LiveSessionsTabState extends State<_LiveSessionsTab> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  List<AdminLiveSessionRow> _rows = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<String> _busy = {};

  /// Yavaş eski yanıt yenisini ezmesin.
  int _seq = 0;

  /// Canlı sekmesi izleyici sayısı/süre güncel kalsın diye 30 sn'de bir okunur.
  Timer? _ticker;

  bool get _isLive => widget.status == 'live';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    if (_isLive) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    }
  }

  @override
  void didUpdateWidget(covariant _LiveSessionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load(silent: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
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
      final page = await widget.service.fetchSessions(widget.status, limit: _pageSize);
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
        if (!silent || _rows.isEmpty) _error = AdminLiveService.errorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.fetchSessions(widget.status, limit: _pageSize, offset: _rows.length);
      if (!mounted || seq != _seq) return;
      final known = {for (final row in _rows) row.session.id};
      setState(() {
        _rows = [..._rows, ...page.rows.where((row) => !known.contains(row.session.id))];
        _total = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _close(AdminLiveSessionRow row) async {
    final choice = await showDialog<({String note, bool revoke})>(
      context: context,
      builder: (_) => _CloseLiveDialog(row: row, allowRevoke: widget.allowRevoke),
    );
    if (choice == null || !mounted) return;
    final session = row.session;
    setState(() {
      _busy.add(session.id);
    });
    try {
      if (choice.revoke) {
        final user = session.isUserStream;
        final change = user
            ? await widget.service.setUserPermission(session.hostUserId, 'revoked', note: choice.note)
            : await widget.service.setShopPermission(session.shopId, 'revoked', note: choice.note);
        if (!mounted) return;
        _snack(
          context,
          user
              ? (change.closed > 0 ? 'Yayın kapatıldı ve kullanıcının izni kaldırıldı' : 'Kullanıcının izni kaldırıldı')
              : (change.closed > 0 ? 'Yayın kapatıldı ve mağazanın izni kaldırıldı' : 'Mağazanın izni kaldırıldı'),
        );
      } else {
        final status = await widget.service.endSession(session.id, note: choice.note);
        if (!mounted) return;
        _snack(context, status == 'discarded' ? 'Hazırlıktaki yayın silindi' : 'Yayın kapatıldı');
      }
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(session.id);
        });
      }
    }
    // Başarıda da hatada da yeniden okunur: yayın bu arada bitmiş olabilir.
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Yayınlar alınamadı',
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
              children: [
                _isLive
                    ? const AdminEmpty(
                        icon: Icons.sensors_off,
                        title: 'Şu an canlı yayın yok',
                        subtitle: 'Satıcılar ve kullanıcılar yayın açınca burada görünür; liste 30 sn\'de bir yenilenir.',
                      )
                    : const AdminEmpty(
                        icon: Icons.history,
                        title: 'Geçmiş yayın yok',
                        subtitle: 'Biten yayınlar bitiş nedeniyle burada listelenir.',
                      ),
              ],
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
                return _LiveSessionCard(
                  row: row,
                  busy: _busy.contains(row.session.id),
                  onWatch: () => widget.onWatch(row.session),
                  onClose: () => _close(row),
                );
              },
            ),
    );
  }
}

class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({
    required this.row,
    required this.busy,
    required this.onWatch,
    required this.onClose,
  });

  final AdminLiveSessionRow row;
  final bool busy;
  final VoidCallback onWatch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final session = row.session;
    final live = session.status == 'live';
    final reasonColor = switch (session.endedReason) {
      'admin' => Colors.red.shade700,
      'timeout' => Colors.orange.shade800,
      _ => Colors.blueGrey,
    };
    final pinned = session.pinnedProduct;
    return AdminCard(
      key: ValueKey('live-session-${session.id}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                live ? Icons.sensors : Icons.history,
                size: 20,
                color: live ? Colors.red.shade700 : AdminUi.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AdminUi.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            session.isUserStream
                ? 'Kullanıcı yayını · ${row.hostUsername != null ? '@${row.hostUsername}' : (row.hostName ?? 'Kullanıcı')}'
                : '${session.shopName ?? 'Mağaza'} · ${row.hostName ?? 'Satıcı'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AdminUi.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (session.isUserStream)
                AdminPill(label: 'KULLANICI', color: Colors.purple.shade700, icon: Icons.person_outline),
              if (live)
                AdminPill(label: 'CANLI', color: Colors.red.shade700, icon: Icons.circle)
              else
                AdminPill(label: row.endedReasonLabel, color: reasonColor),
              AdminPill(
                label: live ? '${session.viewerCount} izleyici' : 'En çok ${session.peakViewerCount} izleyici',
                color: Colors.indigo,
                icon: Icons.visibility_outlined,
              ),
              if (live) AdminPill(label: 'En çok ${session.peakViewerCount}', color: Colors.indigo.shade300),
              AdminPill(label: adminDuration(row.durationSeconds), color: Colors.teal.shade700, icon: Icons.timer_outlined),
              AdminPill(label: '${row.messageCount} mesaj', color: Colors.blueGrey, icon: Icons.chat_bubble_outline),
              if (row.shopAccess != LiveShopAccess.ok)
                AdminPill(label: row.shopAccess.label, color: _accessColor(row.shopAccess), icon: Icons.block),
            ],
          ),
          if (live && pinned != null) ...[
            const SizedBox(height: 6),
            Text(
              'Sabit ürün: ${pinned.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AdminUi.ink),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            live
                ? 'Başladı: ${adminDateTime(_local(session.startedAt))}'
                : 'Yayın: ${adminDateTime(_local(session.startedAt))} – ${adminDateTime(_local(session.endedAt))}',
            style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
          ),
          if (!live && session.endedReason == 'admin' && row.endedByName != null)
            Text(
              'Kapatan: ${row.endedByName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
            ),
          if (!live && row.endedNote != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminUi.page,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminUi.line),
              ),
              child: Text('Not: ${row.endedNote}', style: const TextStyle(fontSize: 12.5, color: AdminUi.ink)),
            ),
          ],
          if (live) ...[
            const SizedBox(height: 10),
            if (busy)
              const LinearProgressIndicator(minHeight: 3)
            else
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onWatch,
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('İzle'),
                    ),
                    FilledButton.icon(
                      onPressed: onClose,
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Yayını kapat'),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Kapatma: not (satıcıya bildirimde) + isteğe bağlı mağaza iznini kaldırma.
class _CloseLiveDialog extends StatefulWidget {
  const _CloseLiveDialog({required this.row, this.allowRevoke = true});

  final AdminLiveSessionRow row;
  final bool allowRevoke;

  @override
  State<_CloseLiveDialog> createState() => _CloseLiveDialogState();
}

class _CloseLiveDialogState extends State<_CloseLiveDialog> {
  final _note = TextEditingController();
  bool _revoke = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.row.session;
    final user = session.isUserStream;
    final who = user ? 'yayıncı' : 'satıcı';
    return AlertDialog(
      title: const Text('Yayın kapatılsın mı?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${session.title}" · ${session.displayName}\n'
              'Yayın hemen biter; $who ve izleyiciler "Yayın yönetici tarafından '
              'kapatıldı" görür, ${who}ya bildirim gider.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('live-close-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: user ? 'Yayıncıya not (isteğe bağlı)' : 'Satıcıya not (isteğe bağlı)',
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.allowRevoke)
              CheckboxListTile(
                key: const ValueKey('live-close-revoke'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _revoke,
                onChanged: (value) => setState(() => _revoke = value ?? false),
                title: Text(user ? 'Kullanıcının yayın iznini de kaldır' : 'Mağazanın yayın iznini de kaldır'),
                subtitle: Text(
                  user
                      ? 'Yeni yayın açamaz; Kullanıcı İzinleri sekmesinden geri verilir.'
                      : 'Yeni yayın açamaz; Mağaza İzinleri sekmesinden geri verilir.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (note: _note.text.trim(), revoke: _revoke)),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mağaza İzinleri
// ---------------------------------------------------------------------------

class _LiveShopsTab extends StatefulWidget {
  const _LiveShopsTab({
    required this.service,
    required this.revision,
    required this.onSettings,
    required this.onChanged,
  });

  final AdminLiveService service;
  final int revision;
  final ValueChanged<AdminLiveSettings> onSettings;
  final VoidCallback onChanged;

  @override
  State<_LiveShopsTab> createState() => _LiveShopsTabState();
}

class _LiveShopsTabState extends State<_LiveShopsTab> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  final _search = TextEditingController();
  Timer? _debounce;
  String _filter = 'all';
  List<AdminLiveShop> _rows = const [];
  int _total = 0;
  int _granted = 0;
  int _revoked = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<String> _busy = {};
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LiveShopsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load(silent: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
    setState(() {});
  }

  void _setFilter(String value) {
    if (value == _filter) return;
    setState(() => _filter = value);
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
      final page = await widget.service.fetchShops(search: _search.text, filter: _filter, limit: _pageSize);
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = page.rows;
        _total = page.total;
        _granted = page.granted;
        _revoked = page.revoked;
        _loading = false;
        _error = null;
      });
      widget.onSettings(page.settings);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        if (!silent || _rows.isEmpty) _error = AdminLiveService.errorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.fetchShops(
        search: _search.text,
        filter: _filter,
        limit: _pageSize,
        offset: _rows.length,
      );
      if (!mounted || seq != _seq) return;
      final known = {for (final row in _rows) row.shopId};
      setState(() {
        _rows = [..._rows, ...page.rows.where((row) => !known.contains(row.shopId))];
        _total = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _change(AdminLiveShop shop, String permission) async {
    String? note;
    if (permission == 'revoked') {
      note = await showDialog<String>(
        context: context,
        builder: (_) => _RevokeDialog(name: shop.shopName, isLive: shop.isLiveNow),
      );
      if (note == null || !mounted) return;
    }
    setState(() {
      _busy.add(shop.shopId);
    });
    try {
      final change = await widget.service.setShopPermission(shop.shopId, permission, note: note);
      if (!mounted) return;
      final text = switch (permission) {
        'granted' => '${shop.shopName}: yayın izni verildi',
        'revoked' => '${shop.shopName}: yayın izni kaldırıldı',
        _ => '${shop.shopName}: varsayılana döndü (${(change.effective ?? LiveShopAccess.ok).label})',
      };
      _snack(context, change.closed > 0 ? '$text · ${change.closed} yayın kapatıldı' : text);
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(shop.shopId);
        });
      }
    }
    widget.onChanged();
  }

  Widget _filterChips() {
    final items = <({String value, String label, int? count})>[
      (value: 'all', label: 'Tümü', count: null),
      (value: 'granted', label: 'İzinli', count: _granted),
      (value: 'revoked', label: 'İzni kaldırılan', count: _revoked),
      (value: 'streamed', label: 'Yayın açmış', count: null),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('live-shops-filter-${item.value}'),
                selected: _filter == item.value,
                showCheckmark: false,
                selectedColor: AdminUi.brand,
                backgroundColor: Colors.white,
                side: BorderSide(color: _filter == item.value ? AdminUi.brand : AdminUi.line),
                onSelected: (_) => _setFilter(item.value),
                label: Text(
                  item.count == null ? item.label : '${item.label} · ${item.count}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _filter == item.value ? Colors.white : AdminUi.ink,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Mağazalar alınamadı',
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
              children: const [AdminEmpty(icon: Icons.storefront_outlined, title: 'Mağaza bulunamadı')],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
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
                final shop = _rows[index];
                return _LiveShopCard(
                  shop: shop,
                  busy: _busy.contains(shop.shopId),
                  onChange: (permission) => _change(shop, permission),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            key: const ValueKey('live-shops-search'),
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Mağaza ya da satıcı ara',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Temizle',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _onSearchChanged('');
                      },
                    ),
            ),
          ),
        ),
        _filterChips(),
        const SizedBox(height: 8),
        Expanded(child: _list()),
      ],
    );
  }
}

class _LiveShopCard extends StatelessWidget {
  const _LiveShopCard({required this.shop, required this.busy, required this.onChange});

  final AdminLiveShop shop;
  final bool busy;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final owner = shop.ownerName ?? (shop.ownerUsername == null ? null : '@${shop.ownerUsername}');
    final permissionLabel = switch (shop.permission) {
      'granted' => 'İzin verildi',
      'revoked' => 'İzin kaldırıldı',
      _ => 'Varsayılan',
    };
    return AdminCard(
      key: ValueKey('live-shop-${shop.shopId}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.shopName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AdminUi.ink),
                ),
                if (owner != null)
                  Text(
                    owner,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AdminPill(label: shop.effective.label, color: _accessColor(shop.effective)),
                    AdminPill(label: permissionLabel, color: Colors.blueGrey),
                    if (shop.isLiveNow) AdminPill(label: 'CANLI', color: Colors.red.shade700, icon: Icons.circle),
                    if (!shop.isActive || !shop.isApproved) AdminPill(label: 'Mağaza pasif', color: Colors.grey.shade700),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  shop.sessionCount == 0
                      ? 'Henüz yayın açmadı'
                      : '${shop.sessionCount} yayın · son: ${adminDateTime(_local(shop.lastLiveAt))}',
                  style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                ),
                if (shop.note != null)
                  Text('Not: ${shop.note}', style: const TextStyle(fontSize: 12.5, color: AdminUi.ink)),
                if (shop.updatedByName != null)
                  Text(
                    'Güncelleyen: ${shop.updatedByName} · ${adminDateTime(_local(shop.permissionUpdatedAt))}',
                    style: const TextStyle(fontSize: 12, color: AdminUi.muted),
                  ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            PopupMenuButton<String>(
              key: ValueKey('live-shop-menu-${shop.shopId}'),
              tooltip: 'Yayın izni',
              onSelected: onChange,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'granted', enabled: shop.permission != 'granted', child: const Text('İzin ver')),
                PopupMenuItem(value: 'revoked', enabled: shop.permission != 'revoked', child: const Text('İzni kaldır')),
                PopupMenuItem(
                  value: 'default',
                  enabled: shop.permission != null,
                  child: const Text('Varsayılana döndür'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// İzni kaldırma: not (satıcıya/kullanıcıya bildirimde ve yayın açmaya
/// çalışınca gösterilir).
class _RevokeDialog extends StatefulWidget {
  const _RevokeDialog({required this.name, required this.isLive, this.user = false});

  final String name;
  final bool isLive;

  /// Kullanıcı yayıncısı (mağaza değil).
  final bool user;

  @override
  State<_RevokeDialog> createState() => _RevokeDialogState();
}

class _RevokeDialogState extends State<_RevokeDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.user ? 'Kullanıcıya' : 'Satıcıya';
    return AlertDialog(
      title: const Text('Yayın izni kaldırılsın mı?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.name} yeni yayın açamaz'
              '${widget.isLive ? '; şu anki yayını da hemen kapatılır' : ''}. $who bildirim gider.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('live-revoke-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: widget.user
                    ? 'Neden (kullanıcıya gösterilir, isteğe bağlı)'
                    : 'Neden (satıcıya gösterilir, isteğe bağlı)',
                border: const OutlineInputBorder(),
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
          child: const Text('İzni kaldır'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Kullanıcı İzinleri
// ---------------------------------------------------------------------------

class _LiveUsersTab extends StatefulWidget {
  const _LiveUsersTab({
    required this.service,
    required this.revision,
    required this.onSettings,
    required this.onChanged,
    required this.settings,
    required this.saving,
    required this.onUserMode,
  });

  final AdminLiveService service;
  final int revision;
  final ValueChanged<AdminLiveSettings> onSettings;
  final VoidCallback onChanged;

  /// Üstteki "Tüm kullanıcılar yayın açabilir" anahtarı için.
  final AdminLiveSettings? settings;
  final bool saving;
  final Future<void> Function(String mode, {bool closeRunning}) onUserMode;

  @override
  State<_LiveUsersTab> createState() => _LiveUsersTabState();
}

class _LiveUsersTabState extends State<_LiveUsersTab> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  final _search = TextEditingController();
  Timer? _debounce;
  String _filter = 'all';
  List<AdminLiveUser> _rows = const [];
  int _total = 0;
  int _granted = 0;
  int _revoked = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<String> _busy = {};
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LiveUsersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load(silent: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
    setState(() {});
  }

  void _setFilter(String value) {
    if (value == _filter) return;
    setState(() => _filter = value);
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
      final page = await widget.service.fetchUsers(search: _search.text, filter: _filter, limit: _pageSize);
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = page.rows;
        _total = page.total;
        _granted = page.granted;
        _revoked = page.revoked;
        _loading = false;
        _error = null;
      });
      widget.onSettings(page.settings);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        if (!silent || _rows.isEmpty) _error = AdminLiveService.errorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.fetchUsers(
        search: _search.text,
        filter: _filter,
        limit: _pageSize,
        offset: _rows.length,
      );
      if (!mounted || seq != _seq) return;
      final known = {for (final row in _rows) row.userId};
      setState(() {
        _rows = [..._rows, ...page.rows.where((row) => !known.contains(row.userId))];
        _total = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _change(AdminLiveUser user, String permission) async {
    String? note;
    if (permission == 'revoked') {
      note = await showDialog<String>(
        context: context,
        builder: (_) => _RevokeDialog(name: user.displayName, isLive: user.isLiveNow, user: true),
      );
      if (note == null || !mounted) return;
    }
    setState(() => _busy.add(user.userId));
    try {
      final change = await widget.service.setUserPermission(user.userId, permission, note: note);
      if (!mounted) return;
      final text = switch (permission) {
        'granted' => '${user.displayName}: yayın izni verildi',
        'revoked' => '${user.displayName}: yayın izni kaldırıldı',
        _ => '${user.displayName}: varsayılana döndü (${(change.effective ?? LiveShopAccess.ok).label})',
      };
      _snack(context, change.closed > 0 ? '$text · ${change.closed} yayın kapatıldı' : text);
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(user.userId));
    }
    widget.onChanged();
  }

  Widget _filterChips() {
    final items = <({String value, String label, int? count})>[
      (value: 'all', label: 'Tümü', count: null),
      (value: 'granted', label: 'İzinli', count: _granted),
      (value: 'revoked', label: 'İzni kaldırılan', count: _revoked),
      (value: 'streamed', label: 'Yayın açmış', count: null),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('live-users-filter-${item.value}'),
                selected: _filter == item.value,
                showCheckmark: false,
                selectedColor: AdminUi.brand,
                backgroundColor: Colors.white,
                side: BorderSide(color: _filter == item.value ? AdminUi.brand : AdminUi.line),
                onSelected: (_) => _setFilter(item.value),
                label: Text(
                  item.count == null ? item.label : '${item.label} · ${item.count}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _filter == item.value ? Colors.white : AdminUi.ink,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Kullanıcılar alınamadı',
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
              children: [
                AdminEmpty(
                  icon: Icons.person_search_outlined,
                  title: _search.text.trim().isEmpty ? 'Henüz kayıt yok' : 'Kullanıcı bulunamadı',
                  subtitle: _search.text.trim().isEmpty
                      ? 'Yayın açmış ya da izni değiştirilmiş kullanıcılar burada listelenir. '
                            'Başka birine izin vermek için adını arayın.'
                      : null,
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
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
                final user = _rows[index];
                return _LiveUserCard(
                  user: user,
                  busy: _busy.contains(user.userId),
                  onChange: (permission) => _change(user, permission),
                );
              },
            ),
    );
  }

  /// Açık = 'open' (tüm aktif kullanıcılar); kapatınca yalnız izinliler.
  Future<void> _toggleAll(bool value) async {
    if (value) {
      await widget.onUserMode('open');
      return;
    }
    final closeRunning = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmWithCheckbox(
        title: 'Yalnız izinli kullanıcılar moduna geçilsin mi?',
        message: 'Aşağıdan "İzin ver" dediğiniz kullanıcılar dışında kimse kullanıcı yayını açamaz.',
        checkboxLabel: 'İzinsiz kalan süren kullanıcı yayınlarını kapat',
        initialChecked: false,
        confirmLabel: 'Geç',
      ),
    );
    if (closeRunning == null) return;
    await widget.onUserMode('invite', closeRunning: closeRunning);
  }

  Widget _allUsersSwitch() {
    final settings = widget.settings;
    final mode = settings?.userMode ?? 'open';
    final subtitle = switch (mode) {
      'open' => 'Her aktif kullanıcı Canlı Yayınlar ve Hikaye Oluştur ekranından yayın açabilir; '
          'izni kaldırılanlar hariç.',
      'off' => 'Kullanıcı yayınları Ayarlar\'dan kapatılmış. Açınca tüm kullanıcılar yayın açabilir.',
      _ => 'Şu an yalnız aşağıda izin verdiğiniz kullanıcılar yayın açabilir.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: AdminCard(
        padding: EdgeInsets.zero,
        child: SwitchListTile(
          key: const ValueKey('live-users-all'),
          value: mode == 'open',
          onChanged: settings == null || widget.saving ? null : _toggleAll,
          secondary: Icon(Icons.groups_outlined, color: mode == 'open' ? AdminUi.brand : AdminUi.muted),
          title: const Text(
            'Tüm kullanıcılar canlı yayın açabilir',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _allUsersSwitch(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            key: const ValueKey('live-users-search'),
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Kullanıcı adı ya da ad ara',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Temizle',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _onSearchChanged('');
                      },
                    ),
            ),
          ),
        ),
        _filterChips(),
        const SizedBox(height: 8),
        Expanded(child: _list()),
      ],
    );
  }
}

class _LiveUserCard extends StatelessWidget {
  const _LiveUserCard({required this.user, required this.busy, required this.onChange});

  final AdminLiveUser user;
  final bool busy;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final permissionLabel = switch (user.permission) {
      'granted' => 'İzin verildi',
      'revoked' => 'İzin kaldırıldı',
      _ => 'Varsayılan',
    };
    return AdminCard(
      key: ValueKey('live-user-${user.userId}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AdminUi.ink),
                ),
                if (user.username != null && user.fullName != null)
                  Text(
                    user.fullName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AdminPill(label: user.effective.label, color: _accessColor(user.effective)),
                    AdminPill(label: permissionLabel, color: Colors.blueGrey),
                    if (user.isLiveNow) AdminPill(label: 'CANLI', color: Colors.red.shade700, icon: Icons.circle),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  user.sessionCount == 0
                      ? 'Henüz yayın açmadı'
                      : '${user.sessionCount} yayın · son: ${adminDateTime(_local(user.lastLiveAt))}',
                  style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                ),
                if (user.note != null)
                  Text('Not: ${user.note}', style: const TextStyle(fontSize: 12.5, color: AdminUi.ink)),
                if (user.updatedByName != null)
                  Text(
                    'Güncelleyen: ${user.updatedByName} · ${adminDateTime(_local(user.permissionUpdatedAt))}',
                    style: const TextStyle(fontSize: 12, color: AdminUi.muted),
                  ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            PopupMenuButton<String>(
              key: ValueKey('live-user-menu-${user.userId}'),
              tooltip: 'Yayın izni',
              onSelected: onChange,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'granted', enabled: user.permission != 'granted', child: const Text('İzin ver')),
                PopupMenuItem(value: 'revoked', enabled: user.permission != 'revoked', child: const Text('İzni kaldır')),
                PopupMenuItem(
                  value: 'default',
                  enabled: user.permission != null,
                  child: const Text('Varsayılana döndür'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ayarlar
// ---------------------------------------------------------------------------

class _LiveSettingsTab extends StatelessWidget {
  const _LiveSettingsTab({
    required this.settings,
    required this.saving,
    required this.onApply,
    required this.onUserMode,
    required this.service,
  });

  final AdminLiveSettings? settings;
  final bool saving;
  final Future<void> Function({bool? enabled, String? access, bool closeRunning}) onApply;
  final Future<void> Function(String mode, {bool closeRunning}) onUserMode;

  /// Bildirim / ana sayfa kartı / geçmiş ayarları için.
  final AdminLiveService service;

  Future<void> _toggleEnabled(BuildContext context, bool value) async {
    if (value) {
      await onApply(enabled: true);
      return;
    }
    final closeRunning = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmWithCheckbox(
        title: 'Canlı yayın kapatılsın mı?',
        message: 'Satıcılar yeni yayın açamaz; izleyiciler canlı yayın listesinde "şu anda kapalı" görür.',
        checkboxLabel: 'Süren yayınları da hemen kapat',
        initialChecked: true,
        confirmLabel: 'Kapat',
      ),
    );
    if (closeRunning == null) return;
    await onApply(enabled: false, closeRunning: closeRunning);
  }

  Future<void> _setAccess(BuildContext context, String access) async {
    if (saving || settings?.access == access) return;
    if (access == 'open') {
      await onApply(access: 'open');
      return;
    }
    final closeRunning = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmWithCheckbox(
        title: 'Yalnız izinliler moduna geçilsin mi?',
        message: 'Mağaza İzinleri sekmesinde "İzin ver" dediğiniz mağazalar dışında kimse yeni yayın açamaz.',
        checkboxLabel: 'İzni olmayan mağazaların süren yayınlarını kapat',
        initialChecked: false,
        confirmLabel: 'Geç',
      ),
    );
    if (closeRunning == null) return;
    await onApply(access: 'invite', closeRunning: closeRunning);
  }

  Future<void> _setUserMode(BuildContext context, String mode) async {
    if (saving || settings?.userMode == mode) return;
    if (mode == 'open') {
      await onUserMode('open');
      return;
    }
    final closeRunning = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmWithCheckbox(
        title: mode == 'off' ? 'Kullanıcı yayınları kapatılsın mı?' : 'Yalnız izinli kullanıcılar moduna geçilsin mi?',
        message: mode == 'off'
            ? 'Mağazası olmayan kullanıcılar yayın açamaz; mağaza yayınları etkilenmez.'
            : 'Kullanıcı İzinleri sekmesinde "İzin ver" dediğiniz kullanıcılar dışında kimse kullanıcı yayını açamaz.',
        checkboxLabel: 'İzinsiz kalan süren kullanıcı yayınlarını kapat',
        initialChecked: mode == 'off',
        confirmLabel: mode == 'off' ? 'Kapat' : 'Geç',
      ),
    );
    if (closeRunning == null) return;
    await onUserMode(mode, closeRunning: closeRunning);
  }

  @override
  Widget build(BuildContext context) {
    final settings = this.settings;
    if (settings == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        AdminCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            key: const ValueKey('live-enabled'),
            value: settings.enabled,
            onChanged: saving ? null : (value) => _toggleEnabled(context, value),
            secondary: Icon(Icons.live_tv, color: settings.enabled ? AdminUi.brand : AdminUi.muted),
            title: const Text('Canlı yayın açık', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              settings.enabled
                  ? 'Satıcılar aşağıdaki kurala göre yayın açabilir.'
                  : 'Yeni yayın açılamaz; izleyiciler "şu anda kapalı" görür.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Kimler yayın açabilir?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AdminUi.ink),
        ),
        const SizedBox(height: 8),
        _ModeOption(
          key: const ValueKey('live-access-open'),
          selected: !settings.inviteOnly,
          enabled: !saving,
          title: 'Tüm aktif mağazalar',
          subtitle: 'Onaylı her mağaza yayın açabilir; izni kaldırılanlar hariç.',
          onTap: () => _setAccess(context, 'open'),
        ),
        const SizedBox(height: 8),
        _ModeOption(
          key: const ValueKey('live-access-invite'),
          selected: settings.inviteOnly,
          enabled: !saving,
          title: 'Yalnız izin verdiğim mağazalar',
          subtitle: 'Mağaza İzinleri sekmesinden izin verdiğiniz mağazalar yayın açabilir.',
          onTap: () => _setAccess(context, 'invite'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Kullanıcılar (mağazası olmayanlar) yayın açabilir mi?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AdminUi.ink),
        ),
        const SizedBox(height: 8),
        _ModeOption(
          key: const ValueKey('live-user-mode-open'),
          selected: settings.userMode == 'open',
          enabled: !saving,
          title: 'Tüm aktif kullanıcılar',
          subtitle: 'Herkes Canlı Yayınlar › Yayın aç ile yayın açabilir; izni kaldırılanlar hariç.',
          onTap: () => _setUserMode(context, 'open'),
        ),
        const SizedBox(height: 8),
        _ModeOption(
          key: const ValueKey('live-user-mode-invite'),
          selected: settings.userMode == 'invite',
          enabled: !saving,
          title: 'Yalnız izin verdiğim kullanıcılar',
          subtitle: 'Kullanıcı İzinleri sekmesinden izin verdiğiniz kişiler yayın açabilir.',
          onTap: () => _setUserMode(context, 'invite'),
        ),
        const SizedBox(height: 8),
        _ModeOption(
          key: const ValueKey('live-user-mode-off'),
          selected: settings.userMode == 'off',
          enabled: !saving,
          title: 'Kapalı',
          subtitle: 'Yalnız mağazalar yayın açabilir.',
          onTap: () => _setUserMode(context, 'off'),
        ),
        const SizedBox(height: 20),
        _LiveOptionsSection(service: service),
        const SizedBox(height: 16),
        const AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nasıl çalışır?', style: TextStyle(fontWeight: FontWeight.w800, color: AdminUi.ink)),
              SizedBox(height: 6),
              Text(
                '• "Yayını kapat" yayını hemen bitirir; satıcı ve izleyiciler "Yayın yönetici '
                'tarafından kapatıldı" görür, satıcıya bildirim gider.\n'
                '• İzin ve ayar değişikliği yeni yayınları etkiler; izni kaldırılan mağazanın '
                'süren yayını hemen kapatılır.\n'
                '• Kapatma sırasında "süren yayınları da kapat" seçilmezse açık yayınlar satıcı '
                'bitirene kadar sürer.\n'
                '• Kullanıcı yayınında gizli hesabı yalnız takipçileri izler; engellenen kişiler '
                'göremez. "Yayın başladı" bildirimi yayıncının takipçilerine gider.',
                style: TextStyle(fontSize: 13, color: AdminUi.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ayarlar › Bildirimler, ana sayfa kartı ve geçmiş (`admin_live_options`).
/// Her değişiklik anında kaydedilir; sunucu sayıları sınırlarına sıkıştırır.
class _LiveOptionsSection extends StatefulWidget {
  const _LiveOptionsSection({required this.service});

  final AdminLiveService service;

  @override
  State<_LiveOptionsSection> createState() => _LiveOptionsSectionState();
}

class _LiveOptionsSectionState extends State<_LiveOptionsSection> {
  AdminLiveOptions? _options;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final options = await widget.service.fetchOptions();
      if (mounted) setState(() => _options = options);
    } catch (e) {
      if (mounted) setState(() => _error = AdminLiveService.errorMessage(e));
    }
  }

  Future<void> _save(Map<String, Object> changes, String message) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final options = await widget.service.saveOptions(changes);
      if (!mounted) return;
      setState(() => _options = options);
      _snack(context, message);
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminLiveService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editNumber({
    required String key,
    required String title,
    required String hint,
    required int current,
    required ({int min, int max}) range,
    required String Function(int value) message,
  }) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _NumberDialog(title: title, hint: hint, initial: current, min: range.min, max: range.max),
    );
    if (value == null || value == current || !mounted) return;
    await _save({key: value}, message(value));
  }

  Widget _switch({
    required String key,
    required bool value,
    required String title,
    required String subtitle,
    required IconData icon,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return SwitchListTile(
      key: ValueKey(key),
      value: value,
      onChanged: _saving || !enabled ? null : onChanged,
      secondary: Icon(icon, color: value && enabled ? AdminUi.brand : AdminUi.muted),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
    );
  }

  Widget _numberTile({
    required String key,
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return ListTile(
      key: ValueKey(key),
      enabled: enabled && !_saving,
      onTap: onTap,
      leading: Icon(icon, color: enabled ? AdminUi.brand : AdminUi.muted),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(value, style: const TextStyle(fontSize: 12.5)),
      trailing: const Icon(Icons.edit_outlined, size: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    if (options == null) {
      return AdminCard(
        child: _error == null
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bildirim ayarları alınamadı: $_error', style: const TextStyle(color: AdminUi.muted)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tekrar dene'),
                  ),
                ],
              ),
      );
    }
    final notify = options.notifyEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Yayın bildirimleri',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AdminUi.ink),
        ),
        const SizedBox(height: 4),
        const Text(
          'Satıcı yayına başlayınca uygulama içi + push bildirim. Mağazaya "Haberdar ol" diyenler hep '
          'alır; kullanıcı bildirim ayarlarından "Canlı Yayınlar"ı kapatabilir.',
          style: TextStyle(fontSize: 12.5, color: AdminUi.muted),
        ),
        const SizedBox(height: 8),
        AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _switch(
                key: 'live-opt-notify',
                value: notify,
                title: 'Yayın başlayınca bildirim gönder',
                subtitle: notify ? 'Açık' : 'Kapalı — kimseye yayın bildirimi gitmez',
                icon: Icons.notifications_active_outlined,
                onChanged: (v) => _save(
                  {'notify_enabled': v},
                  v ? 'Yayın bildirimleri açıldı' : 'Yayın bildirimleri kapatıldı',
                ),
              ),
              const Divider(height: 1),
              _switch(
                key: 'live-opt-followers',
                value: options.notifyFollowers,
                enabled: notify,
                title: 'Satıcının takipçileri',
                subtitle: 'Satıcı hesabını takip edenler',
                icon: Icons.people_outline,
                onChanged: (v) => _save({'notify_followers': v}, v ? 'Takipçilere bildirim açık' : 'Takipçilere bildirim kapalı'),
              ),
              _switch(
                key: 'live-opt-fans',
                value: options.notifyProductFans,
                enabled: notify,
                title: 'Ürünlerini favorileyenler',
                subtitle: 'Mağazanın bir ürününü favorilerine ekleyenler',
                icon: Icons.favorite_border,
                onChanged: (v) => _save(
                  {'notify_product_fans': v},
                  v ? 'Ürün favorileyenlere bildirim açık' : 'Ürün favorileyenlere bildirim kapalı',
                ),
              ),
              _switch(
                key: 'live-opt-customers',
                value: options.notifyCustomers,
                enabled: notify,
                title: 'Son 90 günün müşterileri',
                subtitle: 'Mağazadan sipariş vermiş kişiler',
                icon: Icons.shopping_bag_outlined,
                onChanged: (v) => _save(
                  {'notify_customers': v},
                  v ? 'Müşterilere bildirim açık' : 'Müşterilere bildirim kapalı',
                ),
              ),
              const Divider(height: 1),
              _numberTile(
                key: 'live-opt-cooldown',
                icon: Icons.timer_outlined,
                enabled: notify,
                title: 'Bekleme süresi',
                value: options.notifyCooldownHours == 0
                    ? 'Yok — her yayında bildirim'
                    : 'Aynı mağaza için ${options.notifyCooldownHours} saatte en çok bir bildirim',
                onTap: () => _editNumber(
                  key: 'notify_cooldown_hours',
                  title: 'Bekleme süresi (saat)',
                  hint: 'Bağlantısı kopup yeniden açılan yayın tekrar bildirmesin diye. 0 = yok.',
                  current: options.notifyCooldownHours,
                  range: AdminLiveOptions.cooldownRange,
                  message: (v) => 'Bekleme süresi: $v saat',
                ),
              ),
              _numberTile(
                key: 'live-opt-max',
                icon: Icons.groups_outlined,
                enabled: notify,
                title: 'En çok alıcı',
                value: 'Bir yayın en çok ${options.notifyMaxRecipients} kişiye bildirilir (önce aboneler)',
                onTap: () => _editNumber(
                  key: 'notify_max_recipients',
                  title: 'En çok alıcı',
                  hint: 'Önce abonelere, sonra takipçilere, sonra ürün favorileyenlere gider.',
                  current: options.notifyMaxRecipients,
                  range: AdminLiveOptions.maxRecipientsRange,
                  message: (v) => 'En çok alıcı: $v',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Ana sayfa ve geçmiş',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AdminUi.ink),
        ),
        const SizedBox(height: 8),
        AdminCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _switch(
                key: 'live-opt-home',
                value: options.homeCardEnabled,
                title: 'Ana sayfada canlı yayın kartı',
                subtitle: 'Şehiriçi kartının yanında; biten yayın hikâye gibi 24 saat görünür',
                icon: Icons.view_carousel_outlined,
                onChanged: (v) => _save(
                  {'home_card_enabled': v},
                  v ? 'Ana sayfa kartı açıldı' : 'Ana sayfa kartı kapatıldı',
                ),
              ),
              const Divider(height: 1),
              _numberTile(
                key: 'live-opt-history',
                icon: Icons.history,
                title: 'Yayın geçmişi',
                value: 'Biten yayınlar ${options.historyDays} gün listelenir',
                onTap: () => _editNumber(
                  key: 'history_days',
                  title: 'Yayın geçmişi (gün)',
                  hint: 'Canlı Yayınlar › Geçmiş sekmesi bu süreyi kullanır. Ana sayfa kartı biten yayını '
                      '24 saat gösterir; yayıncı kendi yayınlarını "Yayınlarım"da hep görür.',
                  current: options.historyDays,
                  range: AdminLiveOptions.historyDaysRange,
                  message: (v) => 'Yayın geçmişi: $v gün',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AdminCard(
          key: const ValueKey('live-opt-stats'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Son 30 gün', style: TextStyle(fontWeight: FontWeight.w800, color: AdminUi.ink)),
              const SizedBox(height: 6),
              Text(
                '${options.notifications30d} yayın bildirimi · ${options.recipients30d} kişiye ulaştı'
                '${options.cooldownSkips30d > 0 ? ' · ${options.cooldownSkips30d} bekleme süresine takıldı' : ''}\n'
                '"Haberdar ol" aboneliği: ${options.subscriptions} (${options.subscribedShops} mağaza)',
                style: const TextStyle(fontSize: 13, color: AdminUi.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tam sayı girişi (sınırlı). Vazgeçilirse null.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.min,
    required this.max,
  });

  final String title;
  final String hint;
  final int initial;
  final int min;
  final int max;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < widget.min || value > widget.max) {
      setState(() => _error = '${widget.min}–${widget.max} arası bir sayı girin');
      return;
    }
    Navigator.pop(context, value);
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
            Text(widget.hint, style: const TextStyle(fontSize: 13, color: AdminUi.muted)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('live-opt-number'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                errorText: _error,
                helperText: '${widget.min}–${widget.max}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    super.key,
    required this.selected,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      onTap: enabled ? onTap : null,
      borderColor: selected ? AdminUi.brand : null,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? AdminUi.brand : AdminUi.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AdminUi.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Onay + seçenek: vazgeçilirse null, onaylanırsa kutunun değeri.
class _ConfirmWithCheckbox extends StatefulWidget {
  const _ConfirmWithCheckbox({
    required this.title,
    required this.message,
    required this.checkboxLabel,
    required this.initialChecked,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String checkboxLabel;
  final bool initialChecked;
  final String confirmLabel;

  @override
  State<_ConfirmWithCheckbox> createState() => _ConfirmWithCheckboxState();
}

class _ConfirmWithCheckboxState extends State<_ConfirmWithCheckbox> {
  late bool _checked = widget.initialChecked;

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
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('live-confirm-checkbox'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _checked,
              onChanged: (value) => setState(() => _checked = value ?? false),
              title: Text(widget.checkboxLabel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _checked), child: Text(widget.confirmLabel)),
      ],
    );
  }
}
