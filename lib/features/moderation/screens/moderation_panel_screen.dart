import 'dart:async';

import 'package:flutter/material.dart';

import '../../admin/widgets/admin_live_content.dart';
import '../../admin/widgets/admin_ui.dart';
import '../../market/widgets/shop_card.dart' show formatShopMoney;
import '../models/moderation_models.dart';
import '../services/moderation_service.dart';

/// Moderasyon Paneli (Görev 4.6).
///
/// Yönetici olmayan moderatörlerin tek ekranı; yalnız yetkili olduğu
/// kapsamların sekmeleri görünür. Her işlem sunucuda kapsamla doğrulanır ve
/// denetim günlüğüne yazılır (`mod_*` RPC'leri); buradaki gizleme yalnız
/// arayüz içindir.
class ModerationPanelScreen extends StatefulWidget {
  const ModerationPanelScreen({super.key, this.service, this.access, this.liveTabBuilder});

  /// Testlerde sahte servis vermek için.
  final ModerationService? service;

  /// Testlerde yetkiyi doğrudan vermek için (yoksa sunucudan okunur).
  final ModerationAccess? access;

  /// Testlerde canlı yayın sekmesi yerine.
  final WidgetBuilder? liveTabBuilder;

  @override
  State<ModerationPanelScreen> createState() => _ModerationPanelScreenState();
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

class _ModerationPanelScreenState extends State<ModerationPanelScreen> {
  late final ModerationService _service = widget.service ?? ModerationService();
  ModerationAccess? _access;

  @override
  void initState() {
    super.initState();
    _access = widget.access;
    if (_access == null) {
      ModerationService.fetchMyAccess().then((access) {
        if (mounted) setState(() => _access = access);
      });
    }
  }

  Widget _tabFor(ModerationScope scope, ModerationAccess access) => _withCategories(
    scope,
    access.categoriesFor(scope),
    switch (scope) {
      ModerationScope.reports => _ReportsTab(service: _service, canHidePosts: access.can(ModerationScope.content)),
      ModerationScope.content => _PostsTab(service: _service),
      ModerationScope.ilanlar => _IlanlarTab(service: _service),
      ModerationScope.live =>
        widget.liveTabBuilder?.call(context) ?? const AdminLiveContent(moderatorMode: true),
    },
  );

  /// Yönetici kategori atadıysa sekmenin üstünde hangi kategorilerde yetkili
  /// olunduğu yazar (liste sunucuda zaten süzülür).
  Widget _withCategories(ModerationScope scope, List<ModCategory>? categories, Widget child) {
    if (categories == null) return child;
    final names = modCategoryNames(categories)!;
    final kind = scope == ModerationScope.ilanlar ? 'ilan' : 'mağaza';
    return Column(
      children: [
        Material(
          key: ValueKey('mod-categories-${scope.key}'),
          color: const Color(0xFFEFF6FF),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.filter_alt_outlined, size: 18, color: AdminUi.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    names.isEmpty
                        ? 'Sana atanmış $kind kategorisi kalmadı; yönetimle iletişime geç.'
                        : 'Yalnız şu $kind kategorileri: $names',
                    style: const TextStyle(fontSize: 12.5, color: AdminUi.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Moderasyon Paneli')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final scopes = [
      for (final scope in ModerationScope.values)
        if (access.can(scope)) scope,
    ];
    if (scopes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Moderasyon Paneli')),
        body: const AdminEmpty(
          icon: Icons.shield_outlined,
          title: 'Moderatör yetkin yok',
          subtitle: 'Yetkilerin kaldırılmış olabilir. Sorun olduğunu düşünüyorsan yönetimle iletişime geç.',
        ),
      );
    }
    return DefaultTabController(
      length: scopes.length,
      child: Scaffold(
        backgroundColor: AdminUi.page,
        appBar: AppBar(
          title: const Text('Moderasyon Paneli'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final scope in scopes) Tab(icon: Icon(scope.icon, size: 20), text: scope.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [for (final scope in scopes) _tabFor(scope, access)],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ortak parçalar
// ---------------------------------------------------------------------------

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.items, required this.selected, required this.onSelected});

  final List<({String value, String label})> items;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('mod-filter-${item.value}'),
                selected: selected == item.value,
                showCheckmark: false,
                selectedColor: AdminUi.brand,
                backgroundColor: Colors.white,
                side: BorderSide(color: selected == item.value ? AdminUi.brand : AdminUi.line),
                onSelected: (_) => onSelected(item.value),
                label: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected == item.value ? Colors.white : AdminUi.ink,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _loadMoreButton({required bool loading, required int remaining, required VoidCallback onPressed}) {
  return Center(
    child: loading
        ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
        : OutlinedButton(
            onPressed: onPressed,
            child: Text('Daha fazla yükle ($remaining kaldı)', textAlign: TextAlign.center),
          ),
  );
}

/// Not/neden penceresi: vazgeçilirse null, onaylanırsa metin (boş olabilir).
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.fieldLabel,
    this.required = false,
    this.destructive = false,
    this.checkboxLabel,
    this.checkboxInitial = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String fieldLabel;
  final bool required;
  final bool destructive;

  /// Verilirse ek seçenek (ör. "Gönderiyi de gizle").
  final String? checkboxLabel;
  final bool checkboxInitial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _text = TextEditingController();
  late bool _checked = widget.checkboxInitial;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = _text.text.trim();
    if (widget.required && value.isEmpty) {
      setState(() => _error = 'Bu alan gerekli');
      return;
    }
    Navigator.pop(context, (text: value, checked: _checked));
  }

  @override
  Widget build(BuildContext context) {
    final checkboxLabel = widget.checkboxLabel;
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
              key: const ValueKey('mod-note'),
              controller: _text,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            if (checkboxLabel != null)
              CheckboxListTile(
                key: const ValueKey('mod-note-checkbox'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _checked,
                onChanged: (value) => setState(() => _checked = value ?? false),
                title: Text(checkboxLabel),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: _confirm,
          style: widget.destructive ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

Future<({String text, bool checked})?> _askNote(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String fieldLabel,
  bool required = false,
  bool destructive = false,
  String? checkboxLabel,
  bool checkboxInitial = false,
}) => showDialog<({String text, bool checked})>(
  context: context,
  builder: (_) => _NoteDialog(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    fieldLabel: fieldLabel,
    required: required,
    destructive: destructive,
    checkboxLabel: checkboxLabel,
    checkboxInitial: checkboxInitial,
  ),
);

// ---------------------------------------------------------------------------
// Şikayetler
// ---------------------------------------------------------------------------

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({required this.service, required this.canHidePosts});

  final ModerationService service;
  final bool canHidePosts;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  String _status = 'open';
  List<ModReport> _rows = const [];
  int _total = 0;
  int _open = 0;
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

  Future<void> _load({bool silent = false}) async {
    final seq = ++_seq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.service.reports(status: _status, limit: _pageSize);
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = page.rows;
        _total = page.total;
        _open = page.open;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        if (!silent || _rows.isEmpty) _error = ModerationService.errorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.reports(status: _status, limit: _pageSize, offset: _rows.length);
      if (!mounted || seq != _seq) return;
      final known = {for (final r in _rows) '${r.kind}-${r.id}'};
      setState(() {
        _rows = [..._rows, ...page.rows.where((r) => !known.contains('${r.kind}-${r.id}'))];
        _total = page.total;
      });
    } catch (e) {
      if (mounted) _snack(context, ModerationService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _act(ModReport report, String status) async {
    String? response;
    var hidePost = false;
    if (status != 'reviewing') {
      final canHide = widget.canHidePosts && report.isPost && report.postActive && report.postId != null;
      final result = await _askNote(
        context,
        title: status == 'resolved' ? 'Şikayet sonuçlandırılsın mı?' : 'Şikayet reddedilsin mi?',
        message: status == 'resolved'
            ? 'Şikayet haklı bulundu. Şikayet eden kişiye bilgi verilir.'
            : 'Kurallara aykırı bir durum bulunmadı. Şikayet eden kişiye bilgi verilir.',
        confirmLabel: status == 'resolved' ? 'Sonuçlandır' : 'Reddet',
        fieldLabel: 'Şikayet edene not (isteğe bağlı)',
        destructive: status == 'rejected',
        checkboxLabel: status == 'resolved' && canHide ? 'Gönderiyi gizle' : null,
        checkboxInitial: true,
      );
      if (result == null || !mounted) return;
      response = result.text;
      hidePost = status == 'resolved' && canHide && result.checked;
    }
    final key = '${report.kind}-${report.id}';
    setState(() {
      _busy.add(key);
    });
    try {
      await widget.service.resolveReport(report, status: status, response: response, hidePost: hidePost);
      if (!mounted) return;
      _snack(
        context,
        switch (status) {
          'reviewing' => 'İncelemeye alındı',
          'resolved' => hidePost ? 'Sonuçlandırıldı ve gönderi gizlendi' : 'Sonuçlandırıldı',
          _ => 'Şikayet reddedildi',
        },
      );
    } catch (e) {
      if (!mounted) return;
      _snack(context, ModerationService.errorMessage(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(key);
        });
      }
    }
    await _load(silent: true);
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Şikayetler alınamadı',
        subtitle: _error,
        action: OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
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
                  icon: Icons.verified_user_outlined,
                  title: _status == 'open' ? 'Bekleyen şikayet yok' : 'Kayıt yok',
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: _rows.length + (remaining > 0 ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == _rows.length) {
                  return _loadMoreButton(loading: _loadingMore, remaining: remaining, onPressed: _loadMore);
                }
                final report = _rows[index];
                return _ReportCard(
                  report: report,
                  busy: _busy.contains('${report.kind}-${report.id}'),
                  onAction: (status) => _act(report, status),
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
        _FilterChips(
          items: [
            (value: 'open', label: _open > 0 ? 'Açık · $_open' : 'Açık'),
            (value: 'closed', label: 'Kapananlar'),
            (value: 'all', label: 'Tümü'),
          ],
          selected: _status,
          onSelected: (value) {
            if (value == _status) return;
            setState(() => _status = value);
            _load();
          },
        ),
        Expanded(child: _body()),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.busy, required this.onAction});

  final ModReport report;
  final bool busy;
  final ValueChanged<String> onAction;

  Color get _statusColor => switch (report.status) {
    'pending' => Colors.orange.shade800,
    'reviewing' => Colors.blue.shade700,
    'resolved' => Colors.green.shade700,
    _ => Colors.grey.shade700,
  };

  @override
  Widget build(BuildContext context) {
    final target = report.targetUser;
    return AdminCard(
      key: ValueKey('mod-report-${report.kind}-${report.id}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AdminPill(
                label: report.isPost ? 'Gönderi şikayeti' : 'Kullanıcı şikayeti',
                color: report.isPost ? Colors.indigo : Colors.purple,
                icon: report.isPost ? Icons.article_outlined : Icons.person_outline,
              ),
              AdminPill(label: reportReasonLabel(report.reason), color: Colors.red.shade700),
              AdminPill(label: report.statusLabel, color: _statusColor),
            ],
          ),
          if (report.description != null) ...[
            const SizedBox(height: 8),
            Text(report.description!, style: const TextStyle(fontSize: 13.5, color: AdminUi.ink)),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AdminUi.page,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminUi.line),
            ),
            child: report.isPost
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Yazar: ${report.postAuthorName ?? 'Bilinmiyor'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (!report.postActive) AdminPill(label: 'Gizli', color: Colors.grey.shade700),
                          if (report.postId == null) AdminPill(label: 'Silinmiş', color: Colors.grey.shade700),
                        ],
                      ),
                      if (report.postContent != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          report.postContent!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AdminUi.ink),
                        ),
                      ] else if (report.postImageUrl != null)
                        const Text('Fotoğraflı gönderi', style: TextStyle(fontSize: 12.5, color: AdminUi.muted)),
                    ],
                  )
                : Row(
                    children: [
                      AdminAvatar(url: target?.avatarUrl, name: target?.name ?? '?', radius: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          target == null
                              ? 'Silinmiş kullanıcı'
                              : '${target.name}${target.username == null ? '' : ' · @${target.username}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (target?.status == 'suspended') AdminPill(label: 'Askıda', color: Colors.red.shade700),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            'Şikayet eden: ${report.reporter?.name ?? 'Bilinmiyor'} · ${adminTimeAgo(report.createdAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AdminUi.muted),
          ),
          if (report.adminResponse != null)
            Text('Yanıt: ${report.adminResponse}', style: const TextStyle(fontSize: 12.5, color: AdminUi.ink)),
          if (report.isOpen) ...[
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
                    if (report.status == 'pending')
                      TextButton(onPressed: () => onAction('reviewing'), child: const Text('İncelemeye al')),
                    OutlinedButton(
                      onPressed: () => onAction('rejected'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                      child: const Text('Reddet'),
                    ),
                    FilledButton(onPressed: () => onAction('resolved'), child: const Text('Sonuçlandır')),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// İçerik (gönderiler)
// ---------------------------------------------------------------------------

class _PostsTab extends StatefulWidget {
  const _PostsTab({required this.service});

  final ModerationService service;

  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  final _search = TextEditingController();
  Timer? _debounce;
  String _filter = 'recent';
  List<ModPost> _rows = const [];
  int _total = 0;
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
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
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
      final page = await widget.service.posts(filter: _filter, search: _search.text, limit: _pageSize);
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
        if (!silent || _rows.isEmpty) _error = ModerationService.errorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.posts(
        filter: _filter,
        search: _search.text,
        limit: _pageSize,
        offset: _rows.length,
      );
      if (!mounted || seq != _seq) return;
      final known = {for (final p in _rows) p.id};
      setState(() {
        _rows = [..._rows, ...page.rows.where((p) => !known.contains(p.id))];
        _total = page.total;
      });
    } catch (e) {
      if (mounted) _snack(context, ModerationService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggle(ModPost post) async {
    String? reason;
    if (post.isActive) {
      final result = await _askNote(
        context,
        title: 'Gönderi gizlensin mi?',
        message: 'Gönderi herkesten gizlenir; yazara nedeniyle birlikte bildirim gider.',
        confirmLabel: 'Gizle',
        fieldLabel: 'Neden (yazara gösterilir)',
        destructive: true,
      );
      if (result == null || !mounted) return;
      reason = result.text;
    }
    setState(() {
      _busy.add(post.id);
    });
    try {
      await widget.service.setPostActive(post.id, !post.isActive, reason: reason);
      if (!mounted) return;
      _snack(context, post.isActive ? 'Gönderi gizlendi' : 'Gönderi yeniden yayında');
      setState(() {
        _rows = [
          for (final p in _rows)
            if (p.id != post.id)
              p
            else if (_filter != 'hidden' || !post.isActive)
              p.copyWith(isActive: !post.isActive),
        ];
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context, ModerationService.errorMessage(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(post.id);
        });
      }
    }
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Gönderiler alınamadı',
        subtitle: _error,
        action: OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
      );
    }
    final remaining = _total - _rows.length;
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [AdminEmpty(icon: Icons.article_outlined, title: 'Gönderi yok')],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: _rows.length + (remaining > 0 ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == _rows.length) {
                  return _loadMoreButton(loading: _loadingMore, remaining: remaining, onPressed: _loadMore);
                }
                final post = _rows[index];
                return _PostCard(post: post, busy: _busy.contains(post.id), onToggle: () => _toggle(post));
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            key: const ValueKey('mod-posts-search'),
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Metin ya da yazar ara',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        _FilterChips(
          items: const [
            (value: 'recent', label: 'Son gönderiler'),
            (value: 'reported', label: 'Şikayetli'),
            (value: 'hidden', label: 'Gizlenenler'),
          ],
          selected: _filter,
          onSelected: (value) {
            if (value == _filter) return;
            setState(() => _filter = value);
            _load();
          },
        ),
        Expanded(child: _body()),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.busy, required this.onToggle});

  final ModPost post;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    return AdminCard(
      key: ValueKey('mod-post-${post.id}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminAvatar(url: author?.avatarUrl, name: author?.name ?? '?', radius: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${author?.name ?? 'Bilinmiyor'}${author?.username == null ? '' : ' · @${author!.username}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Text(adminTimeAgo(post.createdAt), style: const TextStyle(fontSize: 11.5, color: AdminUi.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            post.content ?? (post.imageUrl != null ? 'Fotoğraflı gönderi' : '(boş)'),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, color: AdminUi.ink),
          ),
          if (post.imageUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                post.imageUrl!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (!post.isActive) AdminPill(label: 'Gizli', color: Colors.grey.shade700, icon: Icons.visibility_off_outlined),
              if (post.openReports > 0)
                AdminPill(label: '${post.openReports} açık şikayet', color: Colors.red.shade700, icon: Icons.report_outlined),
              AdminPill(label: '${post.likesCount} beğeni', color: Colors.pink),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : post.isActive
                ? OutlinedButton.icon(
                    onPressed: onToggle,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: const Text('Gizle'),
                  )
                : FilledButton.icon(
                    onPressed: onToggle,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Geri aç'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// İlanlar
// ---------------------------------------------------------------------------

class _IlanlarTab extends StatefulWidget {
  const _IlanlarTab({required this.service});

  final ModerationService service;

  @override
  State<_IlanlarTab> createState() => _IlanlarTabState();
}

class _IlanlarTabState extends State<_IlanlarTab> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  List<ModIlan> _rows = const [];
  int _total = 0;
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

  Future<void> _load({bool silent = false}) async {
    final seq = ++_seq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.service.pendingIlanlar(limit: _pageSize);
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
        if (!silent || _rows.isEmpty) _error = ModerationService.errorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.pendingIlanlar(limit: _pageSize, offset: _rows.length);
      if (!mounted || seq != _seq) return;
      final known = {for (final i in _rows) i.id};
      setState(() {
        _rows = [..._rows, ...page.rows.where((i) => !known.contains(i.id))];
        _total = page.total;
      });
    } catch (e) {
      if (mounted) _snack(context, ModerationService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _review(ModIlan ilan, bool approve) async {
    String? reason;
    if (approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('İlan onaylansın mı?'),
          content: Text('"${ilan.title}" yayına alınır; sahibine bildirim gider.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Onayla')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    } else {
      final result = await _askNote(
        context,
        title: 'İlan reddedilsin mi?',
        message: ilan.paidFee > 0
            ? 'Sahibine nedeniyle birlikte bildirim gider; ödediği yayın ücreti (${formatShopMoney(ilan.paidFee)}) bakiyesine iade edilir.'
            : 'Sahibine nedeniyle birlikte bildirim gider.',
        confirmLabel: 'Reddet',
        fieldLabel: 'Ret nedeni',
        required: true,
        destructive: true,
      );
      if (result == null || !mounted) return;
      reason = result.text;
    }
    setState(() {
      _busy.add(ilan.id);
    });
    try {
      await widget.service.reviewIlan(ilan.id, approve: approve, reason: reason);
      if (!mounted) return;
      _snack(context, approve ? 'İlan yayına alındı' : 'İlan reddedildi');
      setState(() {
        _rows = [for (final i in _rows) if (i.id != ilan.id) i];
        _total = _total > 0 ? _total - 1 : 0;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context, ModerationService.errorMessage(e), error: true);
      await _load(silent: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(ilan.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'İlanlar alınamadı',
        subtitle: _error,
        action: OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
      );
    }
    final remaining = _total - _rows.length;
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                AdminEmpty(icon: Icons.task_alt_rounded, title: 'Onay bekleyen ilan yok'),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: _rows.length + (remaining > 0 ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == _rows.length) {
                  return _loadMoreButton(loading: _loadingMore, remaining: remaining, onPressed: _loadMore);
                }
                final ilan = _rows[index];
                return _IlanCard(
                  ilan: ilan,
                  busy: _busy.contains(ilan.id),
                  onApprove: () => _review(ilan, true),
                  onReject: () => _review(ilan, false),
                );
              },
            ),
    );
  }
}

class _IlanCard extends StatelessWidget {
  const _IlanCard({required this.ilan, required this.busy, required this.onApprove, required this.onReject});

  final ModIlan ilan;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final owner = ilan.owner;
    final price = ilan.price;
    return AdminCard(
      key: ValueKey('mod-ilan-${ilan.id}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ilan.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminUi.ink),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (ilan.categoryName != null) AdminPill(label: ilan.categoryName!, color: Colors.indigo),
              if (price != null) AdminPill(label: formatShopMoney(price), color: Colors.green.shade800),
              if (ilan.location.isNotEmpty)
                AdminPill(label: ilan.location, color: Colors.blueGrey, icon: Icons.place_outlined),
              if (ilan.paidFee > 0)
                AdminPill(label: 'Ücret ödendi: ${formatShopMoney(ilan.paidFee)}', color: Colors.orange.shade800),
            ],
          ),
          if (ilan.description != null) ...[
            const SizedBox(height: 8),
            Text(
              ilan.description!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AdminUi.ink),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Sahibi: ${owner?.name ?? 'Bilinmiyor'}${owner?.username == null ? '' : ' · @${owner!.username}'}'
            ' · ${adminTimeAgo(ilan.createdAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AdminUi.muted),
          ),
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
                  OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                    child: const Text('Reddet'),
                  ),
                  FilledButton(onPressed: onApprove, child: const Text('Onayla')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
