// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../leaderboard/leaderboard.dart';
import 'admin_ui.dart';

/// Admin > Kullanıcılar.
///
/// Arama, rol/durum filtreleri ve sıralama SUNUCUDA çalışır (admin_users_page):
/// eski ekran yalnızca en yeni 100 profili çekip aramayı o listede istemcide
/// yapıyordu, yani 100. kullanıcıdan eskisi aramayla bile bulunamıyordu.
/// Liste sayfa sayfa yüklenir.
///
/// Bir kullanıcıya dokununca detay çekmecesi açılır: bilgiler, sayaçlar, son
/// eylemleri ve düzenle / rol / askıya al / şüpheli işaretle / SİL işlemleri.
class AdminUsersContent extends StatefulWidget {
  /// "Tüm eylemleri gör" — Loglar > Kullanıcı Eylemleri'ni bu kullanıcıya
  /// filtreli açar.
  final void Function(String userId, String label)? onOpenUserLogs;

  const AdminUsersContent({super.key, this.onOpenUserLogs});

  @override
  State<AdminUsersContent> createState() => _AdminUsersContentState();
}

class _AdminUsersContentState extends State<AdminUsersContent> {
  static const int _pageSize = 30;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String? _role;
  String? _filter; // online | new | suspicious | suspended | verified
  String _sort = 'newest';

  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  Map<String, int> _roleCounts = {};
  int _onlineCount = 0;
  int _newCount = 0;
  int _suspendedCount = 0;

  // Yarışları önler: yavaş dönen eski istek yeni sonucu ezmesin.
  int _requestSeq = 0;

  // Liderler Tablosu'ndan gizlenen kullanıcılar (id -> kim gizledi). Listeden
  // bağımsız bir küme; rozet ve menü eylemi için.
  Map<String, LeaderboardVisibility> _lbHidden = {};

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSummary();
    _loadLeaderboardHidden();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Veri
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _fetchPage({
    required int offset,
    int limit = _pageSize,
    String? role,
    String? filter,
    String? search,
    String sort = 'newest',
  }) async {
    final res = await _db.rpc(
      'admin_users_page',
      params: {
        'p_search': search,
        'p_role': role,
        'p_filter': filter,
        'p_sort': sort,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> _load({bool showSpinner = true}) async {
    final seq = ++_requestSeq;
    if (showSpinner) setState(() => _loading = true);
    try {
      final page = await _fetchPage(
        offset: 0,
        role: _role,
        filter: _filter,
        search: _searchController.text.trim(),
        sort: _sort,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(
          (page['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _total = (page['total'] as num?)?.toInt() ?? _rows.length;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _rows.length >= _total) return;
    final seq = _requestSeq;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchPage(
        offset: _rows.length,
        role: _role,
        filter: _filter,
        search: _searchController.text.trim(),
        sort: _sort,
      );
      if (!mounted || seq != _requestSeq) return;
      final more = List<Map<String, dynamic>>.from(
        (page['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
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

  /// Üstteki sayaçlar (rol dağılımı + çevrimiçi/yeni/askıda) — liste sayfasından
  /// bağımsız, sunucuda sayılır.
  Future<void> _loadSummary() async {
    try {
      final results = await Future.wait<dynamic>([
        _db.rpc('admin_user_role_counts'),
        _fetchPage(offset: 0, limit: 1, filter: 'online'),
        _fetchPage(offset: 0, limit: 1, filter: 'new'),
        _fetchPage(offset: 0, limit: 1, filter: 'suspended'),
      ]);
      final counts = <String, int>{};
      for (final row in (results[0] as List)) {
        final role = row['role'] as String?;
        if (role != null) counts[role] = (row['user_count'] as num?)?.toInt() ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _roleCounts = counts;
        _onlineCount = ((results[1] as Map)['total'] as num?)?.toInt() ?? 0;
        _newCount = ((results[2] as Map)['total'] as num?)?.toInt() ?? 0;
        _suspendedCount = ((results[3] as Map)['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      debugPrint('Kullanıcı özeti yüklenemedi: $e');
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _load(showSpinner: false),
      _loadSummary(),
      _loadLeaderboardHidden(),
    ]);
  }

  /// Rozet için: liderlik listelerinden gizli olan herkes. Okunamazsa rozetsiz
  /// devam edilir; kullanıcı listesi bunun yüzünden bozulmasın.
  Future<void> _loadLeaderboardHidden() async {
    try {
      final map = await LeaderboardService.adminHiddenUsers();
      if (!mounted) return;
      setState(() => _lbHidden = map);
    } catch (e) {
      debugPrint('Liderlik gizleme listesi yüklenemedi: $e');
    }
  }

  /// Admin gizlemesini açar/kapatır. Kullanıcının kendi tercihine dokunmaz.
  Future<void> _toggleLeaderboardHidden(Map<String, dynamic> user) async {
    final id = user['id'] as String?;
    if (id == null) return;
    final hideNow = !(_lbHidden[id]?.adminHidden ?? false);
    try {
      await LeaderboardService.adminSetHidden(id, hideNow);
      _snack(
        hideNow
            ? '${adminDisplayName(user)} liderlik listelerinden gizlendi'
            : '${adminDisplayName(user)} liderlik listelerinde yeniden görünebilir',
      );
      await _loadLeaderboardHidden();
    } catch (e) {
      _snack('Değiştirilemedi: $e', error: true);
    }
  }

  void _onSearchChanged(String _) {
    setState(() {}); // temizle düğmesi için
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _setRole(String? role) {
    if (_role == role) return;
    setState(() => _role = role);
    _load();
  }

  void _setFilter(String? filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _load();
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
  // Görsel yardımcılar
  // -------------------------------------------------------------------------

  static ({String label, Color color, IconData icon}) _roleStyle(String? role) {
    switch (role) {
      case 'admin':
        return (label: 'Admin', color: Colors.purple, icon: Icons.admin_panel_settings);
      case 'seller':
        return (label: 'Satıcı', color: Colors.orange, icon: Icons.store);
      case 'courier':
        return (label: 'Kurye', color: Colors.teal, icon: Icons.delivery_dining);
      case 'driver':
        return (label: 'Şoför', color: Colors.indigo, icon: Icons.directions_bus);
      case 'news':
        return (label: 'Haberci', color: Colors.blueGrey, icon: Icons.newspaper);
      default:
        return (label: 'Müşteri', color: Colors.blue, icon: Icons.person);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final totalAll = _roleCounts.values.fold<int>(0, (a, b) => a + b);

    return Container(
      color: AdminUi.page,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Kullanıcılar',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AdminUi.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Listeyi CSV olarak kopyala',
                      onPressed: _rows.isEmpty ? null : _copyCsv,
                      icon: const Icon(Icons.file_download_outlined),
                    ),
                    IconButton(
                      tooltip: 'Yenile',
                      onPressed: _refreshAll,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildSummary(totalAll),
                const SizedBox(height: 12),
                _buildSearchField(),
                const SizedBox(height: 10),
                AdminChipBar<String?>(
                  selected: _role,
                  onSelected: _setRole,
                  items: [
                    (value: null, label: 'Tümü', icon: Icons.people_alt_outlined, count: totalAll == 0 ? null : totalAll),
                    (value: 'customer', label: 'Müşteri', icon: Icons.person_outline, count: _roleCounts['customer']),
                    (value: 'seller', label: 'Satıcı', icon: Icons.store_outlined, count: _roleCounts['seller']),
                    (value: 'courier', label: 'Kurye', icon: Icons.delivery_dining, count: _roleCounts['courier']),
                    (value: 'driver', label: 'Şoför', icon: Icons.directions_bus_outlined, count: _roleCounts['driver']),
                    (value: 'news', label: 'Haberci', icon: Icons.newspaper, count: _roleCounts['news']),
                    (value: 'admin', label: 'Admin', icon: Icons.admin_panel_settings_outlined, count: _roleCounts['admin']),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: AdminChipBar<String?>(
                        selected: _filter,
                        onSelected: _setFilter,
                        color: Colors.teal,
                        items: const [
                          (value: null, label: 'Hepsi', icon: null, count: null),
                          (value: 'online', label: 'Çevrimiçi', icon: Icons.circle, count: null),
                          (value: 'new', label: 'Yeni (7 gün)', icon: Icons.fiber_new, count: null),
                          (value: 'suspicious', label: 'Şüpheli', icon: Icons.warning_amber_rounded, count: null),
                          (value: 'suspended', label: 'Askıda/Silinmiş', icon: Icons.block, count: null),
                          (value: 'verified', label: 'Onaylı', icon: Icons.verified_outlined, count: null),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Sırala',
                      icon: const Icon(Icons.sort_rounded),
                      initialValue: _sort,
                      onSelected: (v) {
                        setState(() => _sort = v);
                        _load();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'newest', child: Text('En yeni kayıt')),
                        PopupMenuItem(value: 'oldest', child: Text('En eski kayıt')),
                        PopupMenuItem(value: 'last_seen', child: Text('Son görülme')),
                        PopupMenuItem(value: 'name', child: Text('Ada göre (A-Z)')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildSummary(int totalAll) {
    Widget tile(IconData icon, String label, String value, Color color,
        {VoidCallback? onTap}) {
      return Expanded(
        child: AdminMiniStat(
          icon: icon,
          label: label,
          value: value,
          color: color,
          onTap: onTap,
        ),
      );
    }

    return Row(
      children: [
        tile(Icons.groups_rounded, 'Toplam', '$totalAll', Colors.purple,
            onTap: () {
          _setRole(null);
          _setFilter(null);
        }),
        const SizedBox(width: 8),
        tile(Icons.circle, 'Çevrimiçi', '$_onlineCount', Colors.green,
            onTap: () => _setFilter('online')),
        const SizedBox(width: 8),
        tile(Icons.fiber_new_rounded, 'Yeni (7g)', '$_newCount', Colors.blue,
            onTap: () => _setFilter('new')),
        const SizedBox(width: 8),
        tile(Icons.block_rounded, 'Askıda', '$_suspendedCount', Colors.red,
            onTap: () => _setFilter('suspended')),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'İsim, @kullanıcı adı, e-posta veya telefon ara',
        hintStyle: const TextStyle(fontSize: 13.5),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
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
          borderSide: BorderSide(color: AdminUi.brand, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Kullanıcılar yüklenemedi',
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
        icon: Icons.person_search_outlined,
        title: 'Kullanıcı bulunamadı',
        subtitle: 'Arama ya da filtreleri değiştirmeyi deneyin.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _rows.length + 1,
        itemBuilder: (context, i) {
          if (i == _rows.length) return _buildFooter();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildUserCard(_rows[i]),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    final remaining = _total - _rows.length;
    if (remaining <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            '$_total kullanıcı gösteriliyor',
            style: const TextStyle(fontSize: 12, color: AdminUi.muted),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _loadingMore ? null : _loadMore,
          icon: _loadingMore
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more_rounded),
          label: Text('Daha fazla yükle ($remaining kaldı)'),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final role = _roleStyle(user['role'] as String?);
    final status = user['status'] as String? ?? 'active';
    final isOnline = user['is_online'] == true;
    final isSuspicious = user['is_suspicious'] == true;
    final isVerified = user['is_verified'] == true;
    final createdAt = adminParseDate(user['created_at']);
    final lastSeen = adminParseDate(user['last_seen']);
    final isNew = createdAt != null &&
        DateTime.now().difference(createdAt) < const Duration(days: 7);
    final username = (user['username'] as String?) ?? '';
    final email = (user['email'] as String?) ?? '';
    final dimmed = status != 'active';

    return Opacity(
      opacity: dimmed ? 0.65 : 1,
      child: AdminCard(
        onTap: () => _showUserSheet(user),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminAvatar(
              url: user['avatar_url'] as String?,
              name: adminDisplayName(user),
              radius: 24,
              online: isOnline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          adminDisplayName(user),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.ink,
                          ),
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, size: 15, color: Colors.blue.shade600),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (username.isNotEmpty) '@$username',
                      if (email.isNotEmpty) email,
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AdminUi.muted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      AdminBadge(label: role.label, color: role.color, icon: role.icon),
                      if (status == 'suspended')
                        const AdminBadge(label: 'Askıda', color: Colors.red, icon: Icons.block),
                      if (status == 'deleted')
                        const AdminBadge(label: 'Silinmiş', color: Colors.grey, icon: Icons.delete_outline),
                      if (isSuspicious)
                        const AdminBadge(label: 'Şüpheli', color: Colors.deepOrange, icon: Icons.warning_amber_rounded),
                      if (isNew)
                        const AdminBadge(label: 'Yeni', color: Colors.green, icon: Icons.fiber_new),
                      if (_lbHidden[user['id']]?.hidden == true)
                        AdminBadge(
                          label: _lbHidden[user['id']]!.label,
                          color: Colors.blueGrey,
                          icon: Icons.visibility_off_rounded,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _miniStat(Icons.article_outlined, user['posts_count']),
                      _miniStat(Icons.people_alt_outlined, user['followers_count']),
                      _miniStat(Icons.person_add_alt_outlined, user['following_count']),
                      const Spacer(),
                      Text(
                        isOnline ? 'Çevrimiçi' : (lastSeen == null ? '' : adminTimeAgo(lastSeen)),
                        style: TextStyle(
                          fontSize: 11,
                          color: isOnline ? Colors.green.shade700 : AdminUi.muted,
                          fontWeight: isOnline ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AdminUi.muted),
              onSelected: (v) => _onMenu(v, user),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'detail', child: _MenuRow(Icons.info_outline, 'Detay')),
                const PopupMenuItem(value: 'edit', child: _MenuRow(Icons.edit_outlined, 'Düzenle')),
                const PopupMenuItem(value: 'role', child: _MenuRow(Icons.admin_panel_settings_outlined, 'Rol değiştir')),
                const PopupMenuItem(value: 'logs', child: _MenuRow(Icons.history_rounded, 'Eylemlerini gör')),
                PopupMenuItem(
                  value: 'leaderboard',
                  child: _MenuRow(
                    Icons.emoji_events_outlined,
                    (_lbHidden[user['id']]?.adminHidden ?? false)
                        ? 'Liderlikte göster'
                        : 'Liderlikten gizle',
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'status',
                  child: _MenuRow(
                    status == 'suspended' ? Icons.lock_open_rounded : Icons.block_rounded,
                    status == 'suspended' ? 'Hesabı aktifleştir' : 'Hesabı askıya al',
                    color: Colors.orange.shade800,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: _MenuRow(Icons.delete_forever_rounded, 'Kullanıcıyı sil', color: Colors.red.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, dynamic value) {
    final n = (value as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AdminUi.muted),
          const SizedBox(width: 3),
          Text(
            adminCompact(n),
            style: const TextStyle(fontSize: 12, color: AdminUi.muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _onMenu(String value, Map<String, dynamic> user) {
    switch (value) {
      case 'detail':
        _showUserSheet(user);
        break;
      case 'edit':
        _showEditDialog(user);
        break;
      case 'role':
        _showRoleDialog(user);
        break;
      case 'logs':
        _openLogs(user);
        break;
      case 'leaderboard':
        _toggleLeaderboardHidden(user);
        break;
      case 'status':
        _toggleStatus(user);
        break;
      case 'delete':
        _showDeleteDialog(user);
        break;
    }
  }

  void _openLogs(Map<String, dynamic> user) {
    final id = user['id'] as String?;
    if (id == null) return;
    widget.onOpenUserLogs?.call(id, adminDisplayName(user));
  }

  Future<void> _copyCsv() async {
    String esc(dynamic v) {
      final s = (v ?? '').toString().replaceAll('"', '""');
      return '"$s"';
    }

    const cols = [
      'id', 'username', 'full_name', 'email', 'phone', 'role', 'status',
      'created_at', 'last_seen',
    ];
    final buf = StringBuffer(cols.join(','))..writeln();
    for (final r in _rows) {
      buf.writeln(cols.map((c) => esc(r[c])).join(','));
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    _snack('${_rows.length} kullanıcı panoya CSV olarak kopyalandı');
  }

  // -------------------------------------------------------------------------
  // Detay çekmecesi
  // -------------------------------------------------------------------------

  void _showUserSheet(Map<String, dynamic> user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UserDetailSheet(
        user: user,
        leaderboard: _lbHidden[user['id']],
        onLeaderboard: () {
          Navigator.pop(ctx);
          _toggleLeaderboardHidden(user);
        },
        onEdit: () {
          Navigator.pop(ctx);
          _showEditDialog(user);
        },
        onRole: () {
          Navigator.pop(ctx);
          _showRoleDialog(user);
        },
        onStatus: () {
          Navigator.pop(ctx);
          _toggleStatus(user);
        },
        onSuspicious: (flag) async {
          Navigator.pop(ctx);
          await _setSuspicious(user, flag);
        },
        onLogs: () {
          Navigator.pop(ctx);
          _openLogs(user);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _showDeleteDialog(user);
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // İşlemler
  // -------------------------------------------------------------------------

  Future<void> _showEditDialog(Map<String, dynamic> user) async {
    final nameController = TextEditingController(text: user['full_name'] as String? ?? '');
    final usernameController = TextEditingController(text: user['username'] as String? ?? '');
    final email = (user['email'] as String?) ?? '-';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Kullanıcıyı düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: TextEditingController(text: email),
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'E-posta (salt okunur)',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Ad Soyad',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Kullanıcı adı',
                  prefixText: '@',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );

    if (saved != true) return;
    try {
      await _db.rpc(
        'admin_update_user_identity',
        params: {
          'p_target_user_id': user['id'],
          'p_full_name': nameController.text.trim(),
          'p_username': usernameController.text.trim(),
        },
      );
      _snack('Kullanıcı güncellendi');
      _refreshAll();
    } catch (e) {
      _snack('Güncellenemedi: $e', error: true);
    }
  }

  Future<void> _showRoleDialog(Map<String, dynamic> user) async {
    String selected = (user['role'] as String?) ?? 'customer';
    const roles = ['customer', 'seller', 'courier', 'driver', 'news', 'admin'];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Rol değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${adminDisplayName(user)} için yeni rol:',
                style: const TextStyle(color: AdminUi.muted),
              ),
              const SizedBox(height: 8),
              for (final r in roles)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => setLocal(() => selected = r),
                  leading: Icon(_roleStyle(r).icon, size: 20, color: _roleStyle(r).color),
                  title: Text(_roleStyle(r).label),
                  trailing: Icon(
                    selected == r ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected == r ? AdminUi.brand : AdminUi.muted,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );

    if (ok != true || selected == (user['role'] ?? 'customer')) return;
    try {
      await _db.rpc(
        'admin_set_user_role',
        params: {
          'p_target_user_id': user['id'],
          'p_new_role': selected,
          'p_reason': 'admin_dashboard_change',
        },
      );
      _snack('Rol güncellendi: ${_roleStyle(selected).label}');
      _refreshAll();
    } catch (e) {
      _snack('Rol güncellenemedi: $e', error: true);
    }
  }

  Future<void> _setSuspicious(Map<String, dynamic> user, bool flag) async {
    try {
      await _db.rpc(
        'admin_set_user_suspicious',
        params: {
          'target_user_id': user['id'],
          'flagged': flag,
          'reason': 'admin_dashboard_flag',
        },
      );
      _snack(flag ? 'Şüpheli olarak işaretlendi' : 'Şüpheli işareti kaldırıldı');
      _refreshAll();
    } catch (e) {
      _snack('İşlem başarısız: $e', error: true);
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> user) async {
    final suspended = (user['status'] as String?) == 'suspended';
    final reasonController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(suspended ? 'Hesabı aktifleştir' : 'Hesabı askıya al'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              suspended
                  ? '${adminDisplayName(user)} yeniden giriş yapabilecek.'
                  : '${adminDisplayName(user)} yeniden giriş yapamayacak ve açık '
                      'oturumları kapatılacak. Verileri silinmez; istediğiniz '
                      'zaman geri açabilirsiniz.',
            ),
            if (!suspended) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Neden (isteğe bağlı)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: suspended ? Colors.green.shade700 : Colors.orange.shade800,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(suspended ? 'Aktifleştir' : 'Askıya al'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _db.rpc(
        'admin_set_user_status',
        params: {
          'p_target': user['id'],
          'p_status': suspended ? 'active' : 'suspended',
          'p_reason': reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
        },
      );
      _snack(suspended ? 'Hesap aktifleştirildi' : 'Hesap askıya alındı');
      _refreshAll();
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  Future<void> _showDeleteDialog(Map<String, dynamic> user) async {
    final username = (user['username'] as String?) ?? '';
    final confirmController = TextEditingController();
    final reasonController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final matches = confirmController.text.trim().toLowerCase() == username.toLowerCase() &&
              username.isNotEmpty;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.delete_forever_rounded, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Text('Kullanıcıyı sil'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${adminDisplayName(user)} (@$username) kalıcı olarak silinecek: '
                      'profil, gönderiler, hikayeler, yorumlar, takipler ve giriş '
                      'bilgileri. Bu işlem GERİ ALINAMAZ.\n\n'
                      'Kullanıcının dijital sipariş/ödeme gibi finansal kaydı varsa '
                      'bu kayıtlar korunur; hesap silinmek yerine kişisel verileri '
                      'temizlenip kalıcı olarak kapatılır.',
                      style: TextStyle(fontSize: 13, height: 1.4, color: Colors.red.shade900),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Neden (isteğe bağlı)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Onaylamak için kullanıcı adını yazın: @$username',
                    style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmController,
                    autocorrect: false,
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      hintText: username,
                      prefixText: '@',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Kalıcı olarak sil'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    try {
      final res = await _db.rpc(
        'admin_delete_user',
        params: {
          'p_target': user['id'],
          'p_reason': reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
        },
      );
      final mode = (res is Map ? res['mode'] : null) as String?;
      _snack(
        mode == 'soft'
            ? 'Finansal kaydı olduğu için hesap kapatıldı ve kişisel verileri temizlendi (kayıtlar korundu)'
            : 'Kullanıcı kalıcı olarak silindi',
      );
      _refreshAll();
    } catch (e) {
      _snack(_friendlyError(e), error: true);
    }
  }

  String _friendlyError(Object e) {
    final msg = e is PostgrestException ? e.message : e.toString();
    if (msg.contains('owns shop')) {
      return 'Bu kullanıcının bir dükkanı var. Önce dükkanı silin veya başka bir hesaba devredin.';
    }
    if (msg.contains('has balance')) {
      return 'Kullanıcının cüzdanında bakiye var. Önce bakiyeyi sıfırlayın.';
    }
    if (msg.contains('target is admin')) {
      return 'Admin hesabı silinemez/askıya alınamaz. Önce rolünü değiştirin.';
    }
    if (msg.contains('cannot delete self') || msg.contains('cannot change own')) {
      return 'Kendi hesabınız üzerinde bu işlemi yapamazsınız.';
    }
    if (msg.contains('already deleted') || msg.contains('user deleted')) {
      return 'Bu hesap zaten silinmiş.';
    }
    if (msg.contains('not admin')) return 'Bu işlem için admin yetkisi gerekir.';
    return 'İşlem başarısız: $msg';
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuRow(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? AdminUi.ink),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

// ===========================================================================
// Detay çekmecesi
// ===========================================================================

class _UserDetailSheet extends StatefulWidget {
  final Map<String, dynamic> user;

  /// Liderler Tablosu'ndan gizlenme durumu (yoksa görünür).
  final LeaderboardVisibility? leaderboard;
  final VoidCallback onLeaderboard;
  final VoidCallback onEdit;
  final VoidCallback onRole;
  final VoidCallback onStatus;
  final ValueChanged<bool> onSuspicious;
  final VoidCallback onLogs;
  final VoidCallback onDelete;

  const _UserDetailSheet({
    required this.user,
    required this.leaderboard,
    required this.onLeaderboard,
    required this.onEdit,
    required this.onRole,
    required this.onStatus,
    required this.onSuspicious,
    required this.onLogs,
    required this.onDelete,
  });

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _recent = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = Supabase.instance.client;
    final id = widget.user['id'];
    try {
      final results = await Future.wait([
        db.rpc('admin_user_detail', params: {'p_target': id}),
        db.rpc(
          'admin_activity_logs_list',
          params: {'p_user_id': id, 'p_limit': 12, 'p_offset': 0},
        ),
      ]);
      if (!mounted) return;
      final logs = Map<String, dynamic>.from(results[1] as Map);
      setState(() {
        _detail = Map<String, dynamic>.from(results[0] as Map);
        _recent = List<Map<String, dynamic>>.from(
          (logs['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
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

  @override
  Widget build(BuildContext context) {
    final d = _detail ?? widget.user;
    final status = (d['status'] as String?) ?? 'active';
    final role = _AdminUsersContentState._roleStyle(d['role'] as String?);

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AdminUi.page,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                AdminAvatar(
                  url: d['avatar_url'] as String?,
                  name: adminDisplayName(d),
                  radius: 34,
                  online: d['is_online'] == true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        adminDisplayName(d),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AdminUi.ink),
                      ),
                      Text(
                        '@${d['username'] ?? '-'}',
                        style: const TextStyle(color: AdminUi.muted),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          AdminBadge(label: role.label, color: role.color, icon: role.icon),
                          if (status == 'suspended')
                            const AdminBadge(label: 'Askıda', color: Colors.red, icon: Icons.block),
                          if (status == 'deleted')
                            const AdminBadge(label: 'Silinmiş', color: Colors.grey),
                          if (d['is_suspicious'] == true)
                            const AdminBadge(label: 'Şüpheli', color: Colors.deepOrange, icon: Icons.warning_amber_rounded),
                          if (d['is_verified'] == true)
                            const AdminBadge(label: 'Onaylı', color: Colors.blue, icon: Icons.verified),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              AdminCard(
                child: Text('Detay yüklenemedi: $_error', style: const TextStyle(color: Colors.red)),
              )
            else ...[
              _buildStats(d),
              const SizedBox(height: 12),
              _buildInfo(d),
              const SizedBox(height: 12),
              _buildActions(d, status),
              const SizedBox(height: 16),
              _buildRecent(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStats(Map<String, dynamic> d) {
    final balance = (d['balance'] as num?)?.toDouble() ?? 0;
    final tiles = <(IconData, String, String, Color)>[
      (Icons.article_outlined, 'Gönderi', '${d['posts_count'] ?? 0}', Colors.blue),
      (Icons.people_alt_outlined, 'Takipçi', '${d['followers_count'] ?? 0}', Colors.purple),
      (Icons.person_add_alt_outlined, 'Takip', '${d['following_count'] ?? 0}', Colors.teal),
      (Icons.shopping_bag_outlined, 'Sipariş', '${d['orders_count'] ?? 0}', Colors.orange),
      (Icons.bolt_rounded, 'Dijital sipariş', '${d['digital_orders_count'] ?? 0}', Colors.amber.shade800),
      (Icons.account_balance_wallet_outlined, 'Bakiye', '₺${balance.toStringAsFixed(2)}', Colors.green),
      (Icons.stars_rounded, 'Puan', '${d['points'] ?? 0}', Colors.pink),
      (Icons.history_rounded, 'Kayıtlı eylem', '${d['activity_count'] ?? 0}', Colors.indigo),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tiles)
              SizedBox(
                width: w,
                child: AdminStatTile(icon: t.$1, label: t.$2, value: t.$3, color: t.$4),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInfo(Map<String, dynamic> d) {
    Widget row(IconData icon, String label, String? value, {bool copy = false}) {
      final v = (value == null || value.trim().isEmpty) ? '-' : value;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AdminUi.muted),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(fontSize: 12.5, color: AdminUi.muted)),
            ),
            Expanded(
              child: Text(
                v,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminUi.ink),
              ),
            ),
            if (copy && v != '-')
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: v));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label kopyalandı'), behavior: SnackBarBehavior.floating),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.copy_rounded, size: 15, color: AdminUi.muted),
                ),
              ),
          ],
        ),
      );
    }

    final provider = d['provider'] as String?;
    final banned = adminParseDate(d['banned_until']);
    return AdminCard(
      child: Column(
        children: [
          row(Icons.email_outlined, 'E-posta', d['email'] as String?, copy: true),
          row(Icons.phone_outlined, 'Telefon', d['phone'] as String?, copy: true),
          row(
            Icons.key_outlined,
            'Giriş yöntemi',
            provider == null
                ? null
                : {'email': 'E-posta / şifre', 'google': 'Google', 'apple': 'Apple'}[provider] ?? provider,
          ),
          row(Icons.event_outlined, 'Kayıt', adminDateTime(adminParseDate(d['created_at']))),
          row(Icons.login_rounded, 'Son giriş', adminDateTime(adminParseDate(d['last_sign_in_at']))),
          row(Icons.visibility_outlined, 'Son görülme', adminDateTime(adminParseDate(d['last_seen']))),
          row(Icons.devices_outlined, 'Platform', d['platform'] as String?),
          row(
            Icons.emoji_events_outlined,
            'Liderlik',
            widget.leaderboard?.hidden == true
                ? widget.leaderboard!.label
                : 'Listelerde görünür',
          ),
          row(Icons.location_on_outlined, 'Konum', d['location'] as String?),
          if ((d['shop_name'] as String?)?.isNotEmpty == true)
            row(Icons.storefront_outlined, 'Dükkan', d['shop_name'] as String?),
          if (banned != null)
            row(Icons.block, 'Giriş engeli', 'Süresiz'),
          if ((d['suspicious_reason'] as String?)?.isNotEmpty == true)
            row(Icons.warning_amber_rounded, 'Şüphe nedeni', d['suspicious_reason'] as String?),
        ],
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> d, String status) {
    final suspended = status == 'suspended';
    final suspicious = d['is_suspicious'] == true;
    final deleted = status == 'deleted';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: deleted ? null : widget.onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Düzenle'),
        ),
        OutlinedButton.icon(
          onPressed: deleted ? null : widget.onRole,
          icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
          label: const Text('Rol'),
        ),
        OutlinedButton.icon(
          onPressed: widget.onLogs,
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('Tüm eylemleri gör'),
        ),
        OutlinedButton.icon(
          onPressed: deleted ? null : widget.onLeaderboard,
          icon: const Icon(Icons.emoji_events_outlined, size: 18),
          label: Text(
            (widget.leaderboard?.adminHidden ?? false)
                ? 'Liderlikte göster'
                : 'Liderlikten gizle',
          ),
        ),
        OutlinedButton.icon(
          onPressed: deleted ? null : () => widget.onSuspicious(!suspicious),
          icon: Icon(Icons.warning_amber_rounded, size: 18, color: Colors.deepOrange.shade700),
          label: Text(suspicious ? 'Şüpheli işaretini kaldır' : 'Şüpheli işaretle'),
        ),
        OutlinedButton.icon(
          onPressed: deleted ? null : widget.onStatus,
          icon: Icon(
            suspended ? Icons.lock_open_rounded : Icons.block_rounded,
            size: 18,
            color: Colors.orange.shade800,
          ),
          label: Text(suspended ? 'Aktifleştir' : 'Askıya al'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: deleted ? null : widget.onDelete,
          icon: const Icon(Icons.delete_forever_rounded, size: 18),
          label: const Text('Sil'),
        ),
      ],
    );
  }

  Widget _buildRecent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Son eylemler',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminUi.ink),
        ),
        const SizedBox(height: 8),
        if (_recent.isEmpty)
          const AdminCard(
            child: Text(
              'Bu kullanıcı için kayıtlı eylem yok.',
              style: TextStyle(color: AdminUi.muted),
            ),
          )
        else
          AdminCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < _recent.length; i++) ...[
                  _recentRow(_recent[i]),
                  if (i != _recent.length - 1) const Divider(height: 1, color: AdminUi.line),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _recentRow(Map<String, dynamic> log) {
    final style = adminActionStyle((log['action'] as String?) ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, size: 16, color: style.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              (log['summary'] as String?)?.isNotEmpty == true ? log['summary'] as String : style.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AdminUi.ink),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            adminTimeAgo(adminParseDate(log['created_at'])),
            style: const TextStyle(fontSize: 11, color: AdminUi.muted),
          ),
        ],
      ),
    );
  }
}
