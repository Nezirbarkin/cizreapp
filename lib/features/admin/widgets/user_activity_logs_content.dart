// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_ui.dart';

/// Admin > Loglar > Kullanıcı Eylemleri.
///
/// Kullanıcıların uygulamadaki eylemleri (gönderi, yorum, beğeni, takip,
/// sipariş, mesaj, giriş, müzik, günün fırsatı tıklaması...) tek akışta.
/// Sunucu tetikleyicileri yazar (bkz. 20260920000001_user_activity_logs.sql);
/// admin burada arar, filtreler ve SİLER (tek tek, seçerek ya da toplu).
class UserActivityLogsContent extends StatefulWidget {
  /// Başka bir ekrandan (Kullanıcılar) bir kullanıcıya filtreli açmak için.
  final String? userId;
  final String? userLabel;

  /// Kullanıcı filtresi çipindeki ✕'e basılınca.
  final VoidCallback? onClearUser;

  const UserActivityLogsContent({
    super.key,
    this.userId,
    this.userLabel,
    this.onClearUser,
  });

  @override
  State<UserActivityLogsContent> createState() => _UserActivityLogsContentState();
}

class _UserActivityLogsContentState extends State<UserActivityLogsContent> {
  static const int _pageSize = 50;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  String? _category;
  int? _rangeDays = 7; // null = tüm zamanlar
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  Map<String, dynamic>? _stats;

  final Set<int> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  int _seq = 0;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant UserActivityLogsContent old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) {
      _selected.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Veri
  // -------------------------------------------------------------------------

  DateTime? get _from => _rangeDays == null
      ? null
      : DateTime.now().subtract(Duration(days: _rangeDays!));

  Future<Map<String, dynamic>> _fetch(int offset) async {
    final res = await _db.rpc(
      'admin_activity_logs_list',
      params: {
        'p_user_id': widget.userId,
        'p_category': _category,
        'p_search': _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        'p_from': _from?.toUtc().toIso8601String(),
        'p_limit': _pageSize,
        'p_offset': offset,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> page) =>
      List<Map<String, dynamic>>.from(
        (page['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );

  Future<void> _load({bool spinner = true}) async {
    final seq = ++_seq;
    if (spinner) setState(() => _loading = true);
    try {
      final page = await _fetch(0);
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = _rowsOf(page);
        _total = (page['total'] as num?)?.toInt() ?? _rows.length;
        _error = null;
        _loading = false;
        _selected.clear();
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _rows.length >= _total) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_rows.length);
      if (!mounted || seq != _seq) return;
      final more = _rowsOf(page);
      setState(() {
        final known = _rows.map((r) => r['id']).toSet();
        _rows = [..._rows, ...more.where((r) => !known.contains(r['id']))];
        _total = (page['total'] as num?)?.toInt() ?? _total;
      });
    } catch (e) {
      _snack('Daha fazla yüklenemedi: $e', error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final res = await _db.rpc('admin_activity_logs_stats', params: {'p_days': 7});
      if (!mounted) return;
      setState(() => _stats = Map<String, dynamic>.from(res as Map));
    } catch (e) {
      debugPrint('Eylem istatistiği yüklenemedi: $e');
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_load(spinner: false), _loadStats()]);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Silme
  // -------------------------------------------------------------------------

  Future<bool> _confirm(String title, String body, {String action = 'Sil'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteIds(List<int> ids) async {
    if (ids.isEmpty) return;
    if (!await _confirm(
      'Kayıtları sil',
      '${ids.length} eylem kaydı kalıcı olarak silinecek.',
    )) {
      return;
    }
    try {
      final n = await _db.rpc('admin_delete_activity_logs', params: {'p_ids': ids});
      _snack('${n ?? ids.length} kayıt silindi');
      _refresh();
    } catch (e) {
      _snack('Silinemedi: $e', error: true);
    }
  }

  Future<void> _clear({
    String? userId,
    String? category,
    int? olderThanDays,
    required String description,
    bool typeToConfirm = false,
  }) async {
    if (typeToConfirm) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Tüm kayıtları sil'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$description Bu işlem geri alınamaz.'),
                const SizedBox(height: 12),
                const Text('Onaylamak için SİL yazın:'),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  autocorrect: false,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: controller.text.trim().toUpperCase() == 'SİL' ||
                        controller.text.trim().toUpperCase() == 'SIL'
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Hepsini sil'),
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
    } else if (!await _confirm('Kayıtları sil', '$description Bu işlem geri alınamaz.')) {
      return;
    }

    try {
      final n = await _db.rpc(
        'admin_clear_activity_logs',
        params: {
          'p_user_id': userId,
          'p_category': category,
          'p_older_than_days': olderThanDays,
        },
      );
      _snack('${n ?? 0} kayıt silindi');
      _refresh();
    } catch (e) {
      _snack('Silinemedi: $e', error: true);
    }
  }

  Future<void> _pickOlderThan() async {
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Şundan eski kayıtları sil'),
        children: [
          for (final d in const [7, 30, 60, 90])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text('$d günden eski'),
            ),
        ],
      ),
    );
    if (days == null) return;
    await _clear(
      olderThanDays: days,
      description: '$days günden eski TÜM kullanıcıların eylem kayıtları silinecek.',
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AdminUi.page,
      child: Column(
        children: [
          if (_selecting) _buildSelectionBar() else _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    return Container(
      color: AdminUi.brandSoft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(_selected.clear),
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              '${_selected.length} seçildi',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _selected
                ..clear()
                ..addAll(_rows.map((r) => (r['id'] as num).toInt()));
            }),
            child: const Text('Sayfayı seç'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => _deleteIds(_selected.toList()),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final stats = _stats;
    final byCategory = (stats?['byCategory'] as Map?)?.cast<String, dynamic>() ?? {};
    final categoryKeys = byCategory.keys.toList()
      ..sort((a, b) => ((byCategory[b] as num?) ?? 0).compareTo((byCategory[a] as num?) ?? 0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.userId == null ? 'Kullanıcı eylemleri' : 'Eylemler · ${widget.userLabel ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AdminUi.ink),
                ),
              ),
              IconButton(
                tooltip: 'Yenile',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: 'Toplu silme',
                icon: const Icon(Icons.delete_sweep_outlined),
                onSelected: (v) {
                  switch (v) {
                    case 'user':
                      _clear(
                        userId: widget.userId,
                        description:
                            '${widget.userLabel ?? 'Bu kullanıcı'} için tüm eylem kayıtları silinecek.',
                      );
                      break;
                    case 'category':
                      _clear(
                        category: _category,
                        description:
                            '"${kAdminCategoryLabels[_category] ?? _category}" kategorisindeki tüm kullanıcıların kayıtları silinecek.',
                      );
                      break;
                    case 'older':
                      _pickOlderThan();
                      break;
                    case 'all':
                      _clear(
                        description: 'Tüm kullanıcıların TÜM eylem kayıtları silinecek.',
                        typeToConfirm: true,
                      );
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (widget.userId != null)
                    const PopupMenuItem(value: 'user', child: Text('Bu kullanıcının tüm kayıtlarını sil')),
                  if (_category != null)
                    const PopupMenuItem(value: 'category', child: Text('Seçili kategorinin tüm kayıtlarını sil')),
                  const PopupMenuItem(value: 'older', child: Text('Eski kayıtları sil…')),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'all',
                    child: Text('Tüm kayıtları sil', style: TextStyle(color: Colors.red.shade700)),
                  ),
                ],
              ),
            ],
          ),
          if (stats != null && widget.userId == null) ...[
            const SizedBox(height: 4),
            _buildStats(stats),
            const SizedBox(height: 10),
          ],
          if (widget.userId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.person, size: 16),
                  label: Text('Kullanıcı: ${widget.userLabel ?? widget.userId}'),
                  onDeleted: widget.onClearUser,
                ),
              ),
            ),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
            decoration: InputDecoration(
              hintText: 'Eylem, kullanıcı veya açıklama ara',
              hintStyle: const TextStyle(fontSize: 13.5),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        _load();
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AdminUi.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AdminUi.line),
              ),
            ),
          ),
          const SizedBox(height: 10),
          AdminChipBar<int?>(
            selected: _rangeDays,
            onSelected: (v) {
              setState(() => _rangeDays = v);
              _load();
            },
            color: Colors.teal,
            items: const [
              (value: 1, label: 'Bugün', icon: null, count: null),
              (value: 7, label: '7 gün', icon: null, count: null),
              (value: 30, label: '30 gün', icon: null, count: null),
              (value: null, label: 'Tümü', icon: null, count: null),
            ],
          ),
          const SizedBox(height: 8),
          AdminChipBar<String?>(
            selected: _category,
            onSelected: (v) {
              setState(() => _category = v);
              _load();
            },
            items: [
              (value: null, label: 'Tüm kategoriler', icon: null, count: null),
              for (final k in categoryKeys)
                (
                  value: k,
                  label: kAdminCategoryLabels[k] ?? k,
                  icon: null,
                  count: (byCategory[k] as num?)?.toInt(),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildStats(Map<String, dynamic> stats) {
    final daily = ((stats['daily'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final maxCount = daily.fold<int>(1, (m, d) => ((d['count'] as num).toInt() > m) ? (d['count'] as num).toInt() : m);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AdminMiniStat(
                icon: Icons.today_rounded,
                label: 'Bugün',
                value: adminCompact((stats['today'] as num?) ?? 0),
                color: Colors.purple,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AdminMiniStat(
                icon: Icons.date_range_rounded,
                label: 'Son 7 gün',
                value: adminCompact((stats['total'] as num?) ?? 0),
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AdminMiniStat(
                icon: Icons.groups_rounded,
                label: 'Aktif kişi',
                value: adminCompact((stats['activeUsers'] as num?) ?? 0),
                color: Colors.green,
              ),
            ),
          ],
        ),
        if (daily.length > 1) ...[
          const SizedBox(height: 8),
          AdminCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Günlük eylem sayısı (son 7 gün) · toplam kayıt: ${adminCompact((stats['totalAll'] as num?) ?? 0)}',
                  style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in daily)
                        Expanded(
                          child: Tooltip(
                            message: '${d['day']}: ${d['count']}',
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 6 + 40 * ((d['count'] as num).toInt() / maxCount),
                              decoration: BoxDecoration(
                                color: AdminUi.brand.withValues(alpha: 0.8),
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
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Kayıtlar yüklenemedi',
        subtitle: _error,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar dene'),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const AdminEmpty(
        icon: Icons.history_toggle_off_rounded,
        title: 'Kayıt yok',
        subtitle: 'Bu filtreyle eşleşen kullanıcı eylemi bulunamadı.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: _rows.length + 1,
        itemBuilder: (context, i) {
          if (i == _rows.length) {
            final remaining = _total - _rows.length;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: remaining <= 0
                    ? Text('$_total kayıt', style: const TextStyle(fontSize: 12, color: AdminUi.muted))
                    : OutlinedButton.icon(
                        onPressed: _loadingMore ? null : _loadMore,
                        icon: _loadingMore
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.expand_more_rounded),
                        label: Text('Daha fazla yükle ($remaining kaldı)'),
                      ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildRow(_rows[i]),
          );
        },
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> log) {
    final id = (log['id'] as num).toInt();
    final style = adminActionStyle((log['action'] as String?) ?? '');
    final selected = _selected.contains(id);
    final summary = (log['summary'] as String?)?.isNotEmpty == true ? log['summary'] as String : style.label;
    final created = adminParseDate(log['created_at']);
    final who = adminDisplayName(log);

    void toggle() => setState(() {
          if (!_selected.add(id)) _selected.remove(id);
        });

    return AdminCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: selected ? AdminUi.brandSoft : null,
      borderColor: selected ? AdminUi.brand : null,
      onTap: _selecting ? toggle : () => _showDetail(log),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: toggle,
        child: Row(
          children: [
            if (_selecting)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? AdminUi.brand : AdminUi.muted,
                  size: 22,
                ),
              )
            else
              Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, color: style.color, size: 20),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.ink),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (widget.userId == null) ...[
                        Flexible(
                          child: Text(
                            log['username'] != null ? '$who · @${log['username']}' : who,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AdminUi.muted),
                          ),
                        ),
                        const Text('  ·  ', style: TextStyle(color: AdminUi.muted)),
                      ],
                      Text(
                        adminTimeAgo(created),
                        style: const TextStyle(fontSize: 12, color: AdminUi.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (log['platform'] != null && !_selecting)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  {
                    'ios': Icons.phone_iphone_rounded,
                    'android': Icons.android_rounded,
                    'web': Icons.language_rounded,
                  }[log['platform']] ??
                      Icons.devices_other,
                  size: 16,
                  color: AdminUi.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> log) {
    final style = adminActionStyle((log['action'] as String?) ?? '');
    final meta = log['metadata'];
    final metaText = (meta is Map && meta.isNotEmpty)
        ? const JsonEncoder.withIndent('  ').convert(meta)
        : null;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AdminUi.page,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: style.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(style.icon, color: style.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        (log['summary'] as String?)?.isNotEmpty == true ? log['summary'] as String : style.label,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AdminUi.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AdminCard(
                  child: Column(
                    children: [
                      _kv('Kullanıcı', '${adminDisplayName(log)}${log['username'] != null ? '  (@${log['username']})' : ''}'),
                      _kv('Eylem', '${style.label}  ·  ${log['action']}'),
                      _kv('Kategori', kAdminCategoryLabels[log['category']] ?? '${log['category']}'),
                      _kv('Zaman', adminDateTime(adminParseDate(log['created_at']))),
                      if (log['platform'] != null) _kv('Platform', '${log['platform']}'),
                      if (log['entity_type'] != null) _kv('Varlık', '${log['entity_type']} · ${log['entity_id'] ?? '-'}'),
                    ],
                  ),
                ),
                if (metaText != null) ...[
                  const SizedBox(height: 10),
                  AdminCard(
                    child: SelectableText(
                      metaText,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AdminUi.ink),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteIds([(log['id'] as num).toInt()]);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Bu kaydı sil'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(k, style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.ink)),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Yönetici işlemleri (admin_audit_log)
// ===========================================================================

/// Admin > Loglar > Yönetici İşlemleri: hangi admin, ne zaman, neyi yaptı
/// (kullanıcı silme, hesap askıya alma, günlük temizleme...).
class AdminAuditLogContent extends StatefulWidget {
  const AdminAuditLogContent({super.key});

  @override
  State<AdminAuditLogContent> createState() => _AdminAuditLogContentState();
}

class _AdminAuditLogContentState extends State<AdminAuditLogContent> {
  static const int _pageSize = 50;

  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _fetch(int offset) async {
    final res = await Supabase.instance.client.rpc(
      'admin_audit_log_list',
      params: {'p_limit': _pageSize, 'p_offset': offset},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(
          (page['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _total = (page['total'] as num?)?.toInt() ?? _rows.length;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_rows.length);
      if (!mounted) return;
      setState(() {
        _rows = [
          ..._rows,
          ...List<Map<String, dynamic>>.from(
            (page['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          ),
        ];
      });
    } catch (_) {
      // sessizce bırak; kullanıcı tekrar dener
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  static ({String label, IconData icon, Color color}) _style(String action) {
    switch (action) {
      case 'delete_user':
        return (label: 'Kullanıcı sildi', icon: Icons.delete_forever_rounded, color: Colors.red);
      case 'set_user_status':
        return (label: 'Hesap durumunu değiştirdi', icon: Icons.block_rounded, color: Colors.deepOrange);
      case 'delete_activity_logs':
        return (label: 'Eylem kayıtlarını sildi', icon: Icons.delete_outline, color: Colors.blueGrey);
      case 'clear_activity_logs':
        return (label: 'Eylem kayıtlarını temizledi', icon: Icons.delete_sweep_outlined, color: Colors.blueGrey);
      case 'clear_music_stats':
        return (label: 'Müzik istatistiğini temizledi', icon: Icons.music_off_outlined, color: Colors.deepPurple);
      case 'clear_daily_deal_clicks':
        return (label: 'Fırsat tıklamalarını temizledi', icon: Icons.local_fire_department_outlined, color: Colors.deepOrange);
      default:
        return (label: action, icon: Icons.admin_panel_settings_outlined, color: Colors.purple);
    }
  }

  String _detail(Map<String, dynamic> row) {
    final data = row['new_data'];
    if (data is! Map) return '';
    final parts = <String>[];
    data.forEach((k, v) {
      if (v == null || (v is List && v.isEmpty)) return;
      parts.add('$k: $v');
    });
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AdminUi.page,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AdminEmpty(
                  icon: Icons.error_outline,
                  title: 'Yüklenemedi',
                  subtitle: _error,
                  action: FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Tekrar dene')),
                )
              : _rows.isEmpty
                  ? const AdminEmpty(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Henüz yönetici işlemi yok',
                      subtitle: 'Kullanıcı silme, askıya alma ve kayıt temizleme işlemleri burada listelenir.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                        itemCount: _rows.length + 1,
                        itemBuilder: (context, i) {
                          if (i == _rows.length) {
                            final remaining = _total - _rows.length;
                            return remaining <= 0
                                ? const SizedBox(height: 4)
                                : Center(
                                    child: OutlinedButton(
                                      onPressed: _loadingMore ? null : _loadMore,
                                      child: Text('Daha fazla yükle ($remaining kaldı)'),
                                    ),
                                  );
                          }
                          final row = _rows[i];
                          final style = _style((row['action'] as String?) ?? '');
                          final detail = _detail(row);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AdminCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      color: style.color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(style.icon, color: style.color, size: 20),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          style.label,
                                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AdminUi.ink),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${adminDisplayName({'full_name': row['admin_name'], 'username': row['admin_username']})}'
                                          '  ·  ${adminDateTime(adminParseDate(row['created_at']))}',
                                          style: const TextStyle(fontSize: 12, color: AdminUi.muted),
                                        ),
                                        if (detail.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            detail,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, color: AdminUi.muted),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
