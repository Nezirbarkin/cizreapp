// ignore_for_file: deprecated_member_use, use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/app_logger.dart';

class GroupsManagementContent extends StatefulWidget {
  const GroupsManagementContent({super.key});
  @override
  State<GroupsManagementContent> createState() => _GroupsManagementContentState();
}

class _GroupsManagementContentState extends State<GroupsManagementContent> with SingleTickerProviderStateMixin {
  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }
  late TabController _tabController;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _joinRequests = [];
  bool _isLoading = true;
  bool _isLoadingRequests = true;
  String _searchQuery = '';
  String _filterType = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadGroups();
    _loadJoinRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Birden fazla kullanicinin minimal profilini TEK RPC cagrisiyla getirir.
  ///
  /// admin_profiles_minimal zaten `p_user_ids uuid[]` aliyor; onceki kod her
  /// satir icin ayri cagri yapiyordu (N+1). 40 bekleyen istekte 40  agi gidis
  /// donusu demekti ve tek bir yavas cagri tum listeyi bekletiyordu.
  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final resp = await _supabase.rpc<List<dynamic>>(
        'admin_profiles_minimal',
        params: {'p_user_ids': ids},
      );
      return {
        for (final row in resp)
          if (Map<String, dynamic>.from(row as Map)['id'] is String)
            Map<String, dynamic>.from(row)['id'] as String:
                Map<String, dynamic>.from(row),
      };
    } catch (e) {
      AppLogger.error('admin_profiles_minimal error: $e');
      return {};
    }
  }

  Future<void> _loadGroups() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // RPC ile admin olarak tüm grupları getir
      final response = await _supabase.rpc('admin_get_all_groups');
      if (!mounted) return;
      setState(() { _groups = List<Map<String, dynamic>>.from(response ?? []); _isLoading = false; });
    } catch (e) {
      AppLogger.error('Admin groups RPC error: $e');
      // Fallback: doğrudan sorgu
      try {
        final response = await _supabase.from('groups').select().order('created_at', ascending: false);
        if (!mounted) return;
        setState(() { _groups = List<Map<String, dynamic>>.from(response); _isLoading = false; });
      } catch (e2) {
        AppLogger.error('Admin groups fallback error: $e2');
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showError('Gruplar yüklenemedi: $e2');
      }
    }
  }

  Future<void> _loadJoinRequests() async {
    if (!mounted) return;
    setState(() => _isLoadingRequests = true);
    try {
      // Once amaca ozel RPC: grup + kullanici profilini tek sorguda dondurur,
      // profiles/group_join_requests RLS'ine takilmaz. Onceki kod bu RPC'yi
      // hic kullanmiyor, tabloyu dogrudan sorgulayip her satir icin ayri
      // profil cagrisi yapiyordu.
      List<Map<String, dynamic>> list;
      try {
        final resp = await _supabase.rpc<List<dynamic>>(
          'admin_get_all_join_requests',
        );
        list = resp
            .map((r) => Map<String, dynamic>.from(r as Map))
            .where((r) => (r['status'] as String? ?? 'pending') == 'pending')
            .map((r) => <String, dynamic>{
                  'id': r['request_id'] ?? r['id'],
                  'group_id': r['group_id'],
                  'user_id': r['user_id'],
                  'message': r['message'],
                  'status': r['status'],
                  'created_at': r['created_at'],
                  'groups': {
                    'name': r['group_name'],
                    'avatar_url': r['group_avatar_url'],
                    'is_private': r['group_is_private'],
                  },
                  'profiles': {
                    'full_name': r['user_full_name'],
                    'username': r['user_username'],
                    'avatar_url': r['user_avatar_url'],
                  },
                })
            .toList();
      } catch (rpcError) {
        AppLogger.error('admin_get_all_join_requests error: $rpcError');
        // Fallback: tabloyu dogrudan sorgula + profilleri TEK cagrida topla.
        final response = await _supabase.from('group_join_requests')
            .select('*, groups(name, avatar_url, is_private)')
            .eq('status', 'pending').order('created_at', ascending: false);
        list = List<Map<String, dynamic>>.from(response);
        final profiles = await _fetchProfiles(
          list.map((r) => r['user_id'] as String?).whereType<String>(),
        );
        for (final row in list) {
          row['profiles'] = profiles[row['user_id']] ?? <String, dynamic>{};
        }
      }
      if (!mounted) return;
      setState(() { _joinRequests = list; _isLoadingRequests = false; });
    } catch (e) {
      AppLogger.error('Admin join requests error: $e');
      if (!mounted) return;
      setState(() { _joinRequests = []; _isLoadingRequests = false; });
      _showError('Katılma istekleri yüklenemedi: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showOk(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  List<Map<String, dynamic>> get _filteredGroups {
    var filtered = _groups;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((g) => (g['name'] as String? ?? '').toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    if (_filterType == 'public') filtered = filtered.where((g) => g['is_private'] != true).toList();
    if (_filterType == 'private') filtered = filtered.where((g) => g['is_private'] == true).toList();
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        child: TabBar(controller: _tabController, labelColor: Theme.of(context).primaryColor, unselectedLabelColor: Colors.grey, tabs: [
          const Tab(icon: Icon(Icons.groups), text: 'Gruplar'),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_add), const SizedBox(width: 4), const Text('İstekler'),
            if (_joinRequests.isNotEmpty) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)), child: Text('${_joinRequests.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))],
          ])),
        ]),
      ),
      Expanded(child: TabBarView(controller: _tabController, children: [_buildGroupsTab(), _buildJoinRequestsTab()])),
    ]);
  }

  Widget _buildGroupsTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: TextField(
          decoration: InputDecoration(hintText: 'Grup ara...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 16), isDense: true),
          onChanged: (v) => setState(() => _searchQuery = v),
        )),
        const SizedBox(width: 8),
        PopupMenuButton<String>(icon: const Icon(Icons.filter_list), onSelected: (v) => setState(() => _filterType = v), itemBuilder: (_) => [
          PopupMenuItem(value: 'all', child: Row(children: [const Icon(Icons.list, size: 18), const SizedBox(width: 8), const Text('Tümü'), if (_filterType == 'all') ...[const Spacer(), const Icon(Icons.check, size: 18, color: Colors.green)]])),
          PopupMenuItem(value: 'public', child: Row(children: [const Icon(Icons.public, size: 18), const SizedBox(width: 8), const Text('Açık'), if (_filterType == 'public') ...[const Spacer(), const Icon(Icons.check, size: 18, color: Colors.green)]])),
          PopupMenuItem(value: 'private', child: Row(children: [const Icon(Icons.lock, size: 18), const SizedBox(width: 8), const Text('Gizli'), if (_filterType == 'private') ...[const Spacer(), const Icon(Icons.check, size: 18, color: Colors.green)]])),
        ]),
        const SizedBox(width: 8),
        ElevatedButton.icon(onPressed: _showCreateGroupDialog, icon: const Icon(Icons.add, size: 18), label: const Text('Yeni Grup'), style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      ])),
      _buildGroupStatsBar(),
      Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _filteredGroups.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.groups_outlined, size: 64, color: Colors.grey[400]), const SizedBox(height: 16), Text('Henüz grup yok', style: TextStyle(fontSize: 18, color: Colors.grey[600]))]))
        : RefreshIndicator(onRefresh: _loadGroups, child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _filteredGroups.length, itemBuilder: (ctx, i) => _buildGroupCard(_filteredGroups[i])))),
    ]);
  }

  Widget _buildGroupStatsBar() {
    final total = _groups.length;
    final pub = _groups.where((g) => g['is_private'] != true).length;
    final priv = _groups.where((g) => g['is_private'] == true).length;
    final members = _groups.fold<int>(0, (s, g) => s + ((g['member_count'] as int?) ?? 0));
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.deepPurple.shade50, Colors.blue.shade50]), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _stat(Icons.groups, '$total', 'Toplam'), _stat(Icons.public, '$pub', 'Açık'), _stat(Icons.lock, '$priv', 'Gizli'), _stat(Icons.people, '$members', 'Üye'), _stat(Icons.pending, '${_joinRequests.length}', 'İstek'),
      ]));
  }

  Widget _stat(IconData icon, String value, String label) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 20, color: Colors.deepPurple), const SizedBox(height: 2),
    Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple)),
    Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
  ]);

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final isPrivate = group['is_private'] == true;
    final memberCount = group['member_count'] as int? ?? 0;
    final avatarUrl = group['avatar_url'] as String?;
    final createdAt = DateTime.tryParse(group['created_at'] ?? '');
    return Card(margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2,
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => _showGroupDetail(group), child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        CircleAvatar(radius: 28, backgroundColor: isPrivate ? Colors.orange[100] : Colors.green[100], backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null, child: avatarUrl == null ? Icon(isPrivate ? Icons.lock : Icons.groups, color: isPrivate ? Colors.orange[700] : Colors.green[700]) : null),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(group['name'] ?? 'İsimsiz', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: isPrivate ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
              child: Text(isPrivate ? 'Gizli' : 'Açık', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isPrivate ? Colors.orange[800] : Colors.green[800]))),
          ]),
          if (group['description'] != null) ...[const SizedBox(height: 4), Text(group['description'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey[600]))],
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.people, size: 14, color: Colors.grey[500]), const SizedBox(width: 4), Text('$memberCount üye', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            if (createdAt != null) ...[const SizedBox(width: 12), Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]), const SizedBox(width: 4), Text('${createdAt.day}/${createdAt.month}/${createdAt.year}', style: TextStyle(fontSize: 12, color: Colors.grey[600]))],
          ]),
        ])),
        PopupMenuButton<String>(onSelected: (a) => _handleGroupAction(a, group), itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit, color: Colors.blue), title: Text('Düzenle'))),
          const PopupMenuItem(value: 'members', child: ListTile(dense: true, leading: Icon(Icons.people, color: Colors.green), title: Text('Üyeler'))),
          const PopupMenuItem(value: 'requests', child: ListTile(dense: true, leading: Icon(Icons.person_add, color: Colors.orange), title: Text('İstekler'))),
          const PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete, color: Colors.red), title: Text('Sil', style: TextStyle(color: Colors.red)))),
        ]),
      ]))));
  }

  // ═══ KATILMA İSTEKLERİ TAB ═══
  Widget _buildJoinRequestsTab() {
    if (_isLoadingRequests) return const Center(child: CircularProgressIndicator());
    if (_joinRequests.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]), const SizedBox(height: 16), Text('Bekleyen istek yok', style: TextStyle(fontSize: 18, color: Colors.grey[600]))]));
    return RefreshIndicator(onRefresh: _loadJoinRequests, child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _joinRequests.length, itemBuilder: (ctx, i) => _buildRequestCard(_joinRequests[i])));
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final profile = request['profiles'] as Map<String, dynamic>?;
    final group = request['groups'] as Map<String, dynamic>?;
    final message = request['message'] as String?;
    final createdAt = DateTime.tryParse(request['created_at'] ?? '');
    final userName = profile?['full_name'] ?? profile?['username'] ?? 'Bilinmeyen';
    final userAvatar = profile?['avatar_url'] as String?;
    final groupName = group?['name'] ?? 'Bilinmeyen Grup';
    return Card(margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2,
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundImage: userAvatar != null ? NetworkImage(userAvatar) : null, child: userAvatar == null ? const Icon(Icons.person) : null),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Row(children: [Icon(Icons.arrow_forward, size: 14, color: Colors.grey[500]), const SizedBox(width: 4), Flexible(child: Text(groupName, style: TextStyle(fontSize: 13, color: Colors.grey[600]), overflow: TextOverflow.ellipsis))]),
          ])),
          if (createdAt != null) Text('${createdAt.day}/${createdAt.month}/${createdAt.year}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ]),
        if (message != null && message.isNotEmpty) ...[const SizedBox(height: 8), Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(Icons.message, size: 16, color: Colors.grey[500]), const SizedBox(width: 8), Expanded(child: Text(message, style: TextStyle(fontSize: 13, color: Colors.grey[700])))]))],
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton.icon(onPressed: () => _handleJoinRequest(request['id'], request, 'rejected'), icon: const Icon(Icons.close, size: 16), label: const Text('Reddet'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red))),
          const SizedBox(width: 8),
          ElevatedButton.icon(onPressed: () => _handleJoinRequest(request['id'], request, 'approved'), icon: const Icon(Icons.check, size: 16), label: const Text('Onayla'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
        ]),
      ])));
  }

  // ═══ AKSİYONLAR ═══
  void _handleGroupAction(String action, Map<String, dynamic> group) {
    switch (action) {
      case 'edit': _showEditGroupDialog(group); break;
      case 'members': _showMembersDialog(group); break;
      case 'requests': _showGroupRequestsDialog(group); break;
      case 'delete': _showDeleteConfirmation(group); break;
    }
  }

  /// Katilma istegini onaylar/reddeder.
  ///
  /// Iki hata duzeltildi:
  ///  1. RPC'lerin `boolean` donusu yok sayiliyordu. admin_approve_join_request
  ///     istek artik 'pending' degilse (baska bir admin islemis, kullanici
  ///     iptal etmis) `false` doner; eski kod yine "İstek onaylandı" yazip
  ///     listeyi yeniliyordu, admin de islemin gectigini saniyordu.
  ///  2. Fallback dali `group_join_requests.reviewed_at` yaziyordu; boyle bir
  ///     kolon YOK (tablo: id, group_id, user_id, message, status, created_at,
  ///     updated_at). PostgREST PGRST204 firlatiyordu. Bu, uyeyi
  ///     group_members'a EKLEDIKTEN ve member_count'u artirdiktan SONRA
  ///     patladigi icin istek 'pending' kaliyordu: admin tekrar onayladiginda
  ///     uye ikinci kez eklenmeye calisiliyor, member_count bir kez daha
  ///     artiyordu. Fallback artik once istek durumunu yaziyor, member_count'u
  ///     da elle degil gercek satir sayisindan hesapliyor.
  Future<void> _handleJoinRequest(String requestId, Map<String, dynamic> request, String status) async {
    final approved = status == 'approved';
    try {
      final ok = await _supabase.rpc<bool?>(
        approved ? 'admin_approve_join_request' : 'admin_reject_join_request',
        params: {'p_request_id': requestId},
      );
      if (ok == false) {
        _showError(
          'İstek işlenemedi: artık beklemede değil '
          '(başka bir admin işlem yapmış olabilir).',
        );
      } else {
        _showOk(approved ? 'İstek onaylandı' : 'İstek reddedildi');
      }
      await _loadJoinRequests();
      await _loadGroups();
    } catch (e) {
      AppLogger.error('Admin handle join request error: $e');
      // Fallback: doğrudan sorgu
      try {
        final groupId = request['group_id'] as String?;
        // Once istek durumunu yaz: bu adim ayni zamanda mukerrer onayin
        // idempotency korumasidir.
        await _supabase
            .from('group_join_requests')
            .update({'status': status})
            .eq('id', requestId);
        if (approved && groupId != null) {
          final userId = request['user_id'] as String;
          await _supabase.from('group_members').upsert(
            {'group_id': groupId, 'user_id': userId, 'role': 'member'},
            onConflict: 'group_id,user_id',
            ignoreDuplicates: true,
          );
          await _syncMemberCount(groupId);
        }
        _showOk(approved ? 'İstek onaylandı (fallback)' : 'İstek reddedildi (fallback)');
        await _loadJoinRequests();
        await _loadGroups();
      } catch (e2) {
        _showError('Hata: $e2');
      }
    }
  }

  /// `groups.member_count` denormalize kolonunu gercek satir sayisiyla esitler.
  ///
  /// Onceki kod her yerde `mevcut + 1` / `mevcut - 1` yapiyordu; iki admin ayni
  /// anda islem yaptiginda ya da araya bir hata girdiginde sayac kaliciolarak
  /// kayiyordu. Sayimi kaynaktan okumak bu kaymayi hem onler hem duzeltir.
  Future<void> _syncMemberCount(String groupId) async {
    try {
      final res = await _supabase
          .from('group_members')
          .select('id')
          .eq('group_id', groupId)
          .count();
      await _supabase
          .from('groups')
          .update({'member_count': res.count})
          .eq('id', groupId);
    } catch (e) {
      AppLogger.error('member_count senkronizasyonu basarisiz: $e');
    }
  }

  void _showCreateGroupDialog() {
    final nameC = TextEditingController(); final descC = TextEditingController(); bool isPrivate = false;
    // Controller'lar dialog kapaninca serbest birakilir; onceki surumde hic
    // dispose edilmiyorlardi (her dialog acilisi kalici leak).
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      title: const Text('Yeni Grup Oluştur'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Grup Adı', border: OutlineInputBorder(), prefixIcon: Icon(Icons.groups))),
        const SizedBox(height: 12),
        TextField(controller: descC, decoration: const InputDecoration(labelText: 'Açıklama', border: OutlineInputBorder(), prefixIcon: Icon(Icons.description)), maxLines: 3),
        const SizedBox(height: 12),
        SwitchListTile(title: const Text('Gizli Grup'), subtitle: const Text('Katılmak için istek gerekir'), value: isPrivate, onChanged: (v) => ss(() => isPrivate = v), secondary: Icon(isPrivate ? Icons.lock : Icons.public, color: isPrivate ? Colors.orange : Colors.green)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        ElevatedButton(onPressed: () async {
          if (nameC.text.trim().isEmpty) return;
          Navigator.pop(ctx);
          try {
            // RPC ile oluştur
            await _supabase.rpc('admin_create_group', params: {
              'p_name': nameC.text.trim(),
              'p_description': descC.text.trim().isEmpty ? null : descC.text.trim(),
              'p_is_private': isPrivate,
            });
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grup oluşturuldu'), backgroundColor: Colors.green));
            await _loadGroups();
          } catch (e) {
            AppLogger.error('Admin create group RPC error: $e');
            // Fallback
            try {
              await _supabase.from('groups').insert({'name': nameC.text.trim(), 'description': descC.text.trim().isEmpty ? null : descC.text.trim(), 'is_private': isPrivate, 'created_by': _supabase.auth.currentUser?.id, 'member_count': 0});
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grup oluşturuldu (fallback)'), backgroundColor: Colors.green));
              await _loadGroups();
            } catch (e2) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e2'), backgroundColor: Colors.red));
            }
          }
        }, child: const Text('Oluştur')),
      ],
    ))).whenComplete(() { nameC.dispose(); descC.dispose(); });
  }

  void _showEditGroupDialog(Map<String, dynamic> group) {
    final nameC = TextEditingController(text: group['name'] ?? ''); final descC = TextEditingController(text: group['description'] ?? ''); bool isPrivate = group['is_private'] == true;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      title: const Text('Grubu Düzenle'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Grup Adı', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: descC, decoration: const InputDecoration(labelText: 'Açıklama', border: OutlineInputBorder()), maxLines: 3),
        const SizedBox(height: 12),
        SwitchListTile(title: const Text('Gizli Grup'), value: isPrivate, onChanged: (v) => ss(() => isPrivate = v)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          try {
            // RPC ile güncelle. `boolean` doner: false = grup bulunamadi /
            // guncellenmedi. Eski kod donusu yok sayip her durumda
            // "Grup güncellendi" yaziyordu.
            final ok = await _supabase.rpc<bool?>('admin_update_group', params: {
              'p_group_id': group['id'],
              'p_name': nameC.text.trim(),
              'p_description': descC.text.trim().isEmpty ? null : descC.text.trim(),
              'p_is_private': isPrivate,
            });
            if (ok == false) {
              _showError('Grup güncellenemedi (bulunamadı).');
            } else {
              _showOk('Grup güncellendi');
            }
            await _loadGroups();
          } catch (e) {
            AppLogger.error('Admin update group RPC error: $e');
            // Fallback
            try {
              await _supabase.from('groups').update({'name': nameC.text.trim(), 'description': descC.text.trim().isEmpty ? null : descC.text.trim(), 'is_private': isPrivate}).eq('id', group['id']);
              _showOk('Grup güncellendi (fallback)');
              await _loadGroups();
            } catch (e2) {
              _showError('Hata: $e2');
            }
          }
        }, child: const Text('Kaydet')),
      ],
    ))).whenComplete(() { nameC.dispose(); descC.dispose(); });
  }

  void _showDeleteConfirmation(Map<String, dynamic> group) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Grubu Sil'), content: Text('"${group['name']}" grubunu silmek istediğinize emin misiniz?\n\nBu işlem geri alınamaz.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          try {
            // RPC ile sil (SECURITY DEFINER - RLS bypass)
            final result = await _supabase.rpc('admin_delete_group', params: {'p_group_id': group['id']});
            if (result == true) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grup silindi'), backgroundColor: Colors.green));
            } else {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grup silinemedi'), backgroundColor: Colors.red));
            }
            await _loadGroups(); await _loadJoinRequests();
          } catch (e) {
            AppLogger.error('Admin delete group RPC error: $e');
            // Fallback: doğrudan silmeyi dene
            try {
              await _supabase.from('group_join_requests').delete().eq('group_id', group['id']);
              await _supabase.from('group_messages').delete().eq('group_id', group['id']);
              await _supabase.from('group_members').delete().eq('group_id', group['id']);
              await _supabase.from('groups').delete().eq('id', group['id']);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grup silindi (fallback)'), backgroundColor: Colors.green));
              await _loadGroups(); await _loadJoinRequests();
            } catch (e2) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Silme hatası: $e2'), backgroundColor: Colors.red));
            }
          }
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Sil', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _showMembersDialog(Map<String, dynamic> group) {
    showDialog(context: context, builder: (ctx) => _MembersDialog(groupId: group['id'] as String, groupName: group['name'] as String? ?? 'Grup', supabase: _supabase, onChanged: _loadGroups));
  }

  void _showGroupRequestsDialog(Map<String, dynamic> group) {
    showDialog(context: context, builder: (ctx) => _GroupRequestsDialog(groupId: group['id'] as String, groupName: group['name'] as String? ?? 'Grup', supabase: _supabase, onChanged: () { _loadJoinRequests(); _loadGroups(); }));
  }

  void _showGroupDetail(Map<String, dynamic> group) {
    final isPrivate = group['is_private'] == true;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        CircleAvatar(radius: 20, backgroundColor: isPrivate ? Colors.orange[100] : Colors.green[100], backgroundImage: group['avatar_url'] != null ? NetworkImage(group['avatar_url']) : null, child: group['avatar_url'] == null ? Icon(isPrivate ? Icons.lock : Icons.groups, color: isPrivate ? Colors.orange[700] : Colors.green[700]) : null),
        const SizedBox(width: 12), Expanded(child: Text(group['name'] ?? 'Grup', overflow: TextOverflow.ellipsis)),
      ]),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (group['description'] != null) ...[Text('Açıklama:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])), const SizedBox(height: 4), Text(group['description']), const SizedBox(height: 12)],
        _infoRow('Tür', isPrivate ? 'Gizli' : 'Açık'), _infoRow('Üye Sayısı', '${group['member_count'] ?? 0}'), _infoRow('Oluşturulma', _fmtDate(group['created_at'])),
        if (group['last_message'] != null) _infoRow('Son Mesaj', group['last_message']),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        ElevatedButton.icon(onPressed: () { Navigator.pop(ctx); _showMembersDialog(group); }, icon: const Icon(Icons.people, size: 18), label: const Text('Üyeler')),
        ElevatedButton.icon(onPressed: () { Navigator.pop(ctx); _showEditGroupDialog(group); }, icon: const Icon(Icons.edit, size: 18), label: const Text('Düzenle')),
      ],
    ));
  }

  Widget _infoRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 120, child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700], fontSize: 13))), Expanded(child: Text(value, style: const TextStyle(fontSize: 13)))]));

  String _fmtDate(String? d) { if (d == null) return '-'; final dt = DateTime.tryParse(d); if (dt == null) return '-'; return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'; }
}

// ═══ ÜYELER DİALOG ═══
class _MembersDialog extends StatefulWidget {
  final String groupId; final String groupName; final SupabaseClient supabase; final VoidCallback onChanged;
  const _MembersDialog({required this.groupId, required this.groupName, required this.supabase, required this.onChanged});
  @override
  State<_MembersDialog> createState() => _MembersDialogState();
}

class _MembersDialogState extends State<_MembersDialog> {
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _load(); }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _load() async {
    try {
      // RPC ile üyeleri getir
      final r = await widget.supabase.rpc('admin_get_group_members', params: {'p_group_id': widget.groupId});
      if (!mounted) return;
      if (r != null) {
        // RPC'den gelen veriyi dönüştür
        final list = (r as List).map((m) {
          final map = Map<String, dynamic>.from(m);
          map['profiles'] = {
            'full_name': map['user_full_name'],
            'avatar_url': map['user_avatar_url'],
            'username': map['user_username'],
          };
          return map;
        }).toList();
        setState(() { _members = list; _isLoading = false; });
      } else {
        setState(() { _members = []; _isLoading = false; });
      }
    } catch (e) {
      // Fallback
      try {
        final r = await widget.supabase.from('group_members').select('*').eq('group_id', widget.groupId).order('role', ascending: true);
        final list = List<Map<String, dynamic>>.from(r);
        // 20260803000006 sonrasında profiles üzerinde authenticated SELECT
        // policy'si yok; SECURITY DEFINER admin_profiles_minimal RPC'si
        // kullanilir. RPC dizi aldigi icin TEK cagri yeter (onceki kod uye
        // basina bir cagri yapiyordu).
        final ids = list.map((m) => m['user_id'] as String?).whereType<String>().toSet().toList();
        var profiles = <String, Map<String, dynamic>>{};
        if (ids.isNotEmpty) {
          try {
            final resp = await widget.supabase.rpc<List<dynamic>>(
              'admin_profiles_minimal',
              params: {'p_user_ids': ids},
            );
            profiles = {
              for (final row in resp)
                if (Map<String, dynamic>.from(row as Map)['id'] is String)
                  Map<String, dynamic>.from(row)['id'] as String:
                      Map<String, dynamic>.from(row),
            };
          } catch (_) {
            profiles = {};
          }
        }
        for (final m in list) {
          m['profiles'] = profiles[m['user_id']] ?? <String, dynamic>{};
        }
        if (!mounted) return;
        setState(() { _members = list; _isLoading = false; });
      } catch (e2) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _snack('Üyeler yüklenemedi: $e2', Colors.red);
      }
    }
  }

  /// `groups.member_count`'u gercek satir sayisindan tazeler.
  /// Elle +1/-1 aritmetigi eszamanli iki admin isleminde kalici kayma
  /// uretiyordu (ve hata arasina girdiginde sayac gercekten kaymis kaliyordu).
  Future<void> _syncMemberCount() async {
    try {
      final res = await widget.supabase
          .from('group_members')
          .select('id')
          .eq('group_id', widget.groupId)
          .count();
      await widget.supabase
          .from('groups')
          .update({'member_count': res.count})
          .eq('id', widget.groupId);
    } catch (_) {
      // Sayac tazeleme kritik degil; asil islem zaten yapildi.
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    try {
      // RPC `boolean` doner; false = uye zaten yok / cikarilmadi.
      final ok = await widget.supabase.rpc<bool?>('admin_remove_group_member', params: {
        'p_group_id': widget.groupId,
        'p_user_id': member['user_id'],
      });
      widget.onChanged(); await _load();
      if (ok == false) {
        _snack('Üye çıkarılamadı (grupta bulunamadı).', Colors.red);
      } else {
        _snack('Üye çıkarıldı', Colors.green);
      }
    } catch (e) {
      // Fallback
      try {
        await widget.supabase.from('group_members').delete().eq('id', member['id']);
        await _syncMemberCount();
        widget.onChanged(); await _load();
        _snack('Üye çıkarıldı (fallback)', Colors.green);
      } catch (e2) {
        _snack('Hata: $e2', Colors.red);
      }
    }
  }

  Future<void> _changeRole(Map<String, dynamic> member, String newRole) async {
    try {
      // RPC `boolean` doner; false = satir guncellenmedi.
      final ok = await widget.supabase.rpc<bool?>('admin_change_member_role', params: {
        'p_group_id': widget.groupId,
        'p_user_id': member['user_id'],
        'p_new_role': newRole,
      });
      await _load();
      if (ok == false) {
        _snack('Rol değiştirilemedi (üye bulunamadı).', Colors.red);
      } else {
        _snack('Rol: $newRole', Colors.green);
      }
    } catch (e) {
      // Fallback
      try {
        await widget.supabase.from('group_members').update({'role': newRole}).eq('id', member['id']);
        await _load();
        _snack('Rol: $newRole (fallback)', Colors.green);
      } catch (e2) {
        _snack('Hata: $e2', Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.groupName} - Üyeler (${_members.length})'),
      content: SizedBox(width: double.maxFinite, height: 400,
        child: _isLoading ? const Center(child: CircularProgressIndicator()) : _members.isEmpty ? const Center(child: Text('Üye yok'))
          : ListView.builder(itemCount: _members.length, itemBuilder: (ctx, i) {
            final m = _members[i]; final p = m['profiles'] as Map<String, dynamic>?;
            final name = p?['full_name'] ?? p?['username'] ?? 'Bilinmeyen'; final avatar = p?['avatar_url'] as String?; final role = m['role'] as String? ?? 'member';
            return ListTile(
              leading: CircleAvatar(backgroundImage: avatar != null ? NetworkImage(avatar) : null, child: avatar == null ? const Icon(Icons.person) : null),
              title: Text(name),
              subtitle: Text(role.toUpperCase(), style: TextStyle(color: role == 'admin' ? Colors.blue : role == 'moderator' ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
              trailing: PopupMenuButton<String>(onSelected: (a) { if (a == 'remove') _removeMember(m); else _changeRole(m, a); }, itemBuilder: (_) => [
                const PopupMenuItem(value: 'admin', child: Text('Admin Yap')),
                const PopupMenuItem(value: 'moderator', child: Text('Moderatör Yap')),
                const PopupMenuItem(value: 'member', child: Text('Üye Yap')),
                const PopupMenuItem(value: 'remove', child: Text('Çıkar', style: TextStyle(color: Colors.red))),
              ]),
            );
          }),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}

// ═══ GRUP İSTEKLERİ DİALOG ═══
class _GroupRequestsDialog extends StatefulWidget {
  final String groupId; final String groupName; final SupabaseClient supabase; final VoidCallback onChanged;
  const _GroupRequestsDialog({required this.groupId, required this.groupName, required this.supabase, required this.onChanged});
  @override
  State<_GroupRequestsDialog> createState() => _GroupRequestsDialogState();
}

class _GroupRequestsDialogState extends State<_GroupRequestsDialog> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _load(); }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _load() async {
    try {
      // FK olmadığı için ayrı sorgu ile profil bilgilerini getir
      final r = await widget.supabase.from('group_join_requests').select('*').eq('group_id', widget.groupId).eq('status', 'pending').order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(r);
      // 20260803000006 sonrasında profiles üzerinde authenticated SELECT
      // policy'si yok; SECURITY DEFINER admin_profiles_minimal RPC'si dizi
      // aldigi icin TEK cagri yeter (onceki kod istek basina cagri yapiyordu).
      final ids = list.map((m) => m['user_id'] as String?).whereType<String>().toSet().toList();
      var profiles = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        try {
          final resp = await widget.supabase.rpc<List<dynamic>>(
            'admin_profiles_minimal',
            params: {'p_user_ids': ids},
          );
          profiles = {
            for (final row in resp)
              if (Map<String, dynamic>.from(row as Map)['id'] is String)
                Map<String, dynamic>.from(row)['id'] as String:
                    Map<String, dynamic>.from(row),
          };
        } catch (_) {
          profiles = {};
        }
      }
      for (final m in list) {
        m['profiles'] = profiles[m['user_id']] ?? <String, dynamic>{};
      }
      if (!mounted) return;
      setState(() { _requests = list; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('İstekler yüklenemedi: $e', Colors.red);
    }
  }

  /// Bkz. _GroupsManagementContentState._handleJoinRequest — ayni iki hata
  /// (boolean donusun yok sayilmasi + var olmayan `reviewed_at` kolonu)
  /// burada da vardi.
  Future<void> _handle(String requestId, String userId, String status) async {
    final approved = status == 'approved';
    try {
      final ok = await widget.supabase.rpc<bool?>(
        approved ? 'admin_approve_join_request' : 'admin_reject_join_request',
        params: {'p_request_id': requestId},
      );
      widget.onChanged(); await _load();
      if (ok == false) {
        _snack('İstek işlenemedi: artık beklemede değil.', Colors.red);
      } else {
        _snack(approved ? 'Onaylandı' : 'Reddedildi', approved ? Colors.green : Colors.orange);
      }
    } catch (e) {
      // Fallback
      try {
        // Once istek durumu (mukerrer onaya karsi koruma), sonra uyelik.
        await widget.supabase
            .from('group_join_requests')
            .update({'status': status})
            .eq('id', requestId);
        if (approved) {
          await widget.supabase.from('group_members').upsert(
            {'group_id': widget.groupId, 'user_id': userId, 'role': 'member'},
            onConflict: 'group_id,user_id',
            ignoreDuplicates: true,
          );
          try {
            final res = await widget.supabase
                .from('group_members')
                .select('id')
                .eq('group_id', widget.groupId)
                .count();
            await widget.supabase
                .from('groups')
                .update({'member_count': res.count})
                .eq('id', widget.groupId);
          } catch (_) {
            // Sayac tazeleme kritik degil.
          }
        }
        widget.onChanged(); await _load();
        _snack(approved ? 'Onaylandı (fallback)' : 'Reddedildi (fallback)', approved ? Colors.green : Colors.orange);
      } catch (e2) {
        _snack('Hata: $e2', Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.groupName} - İstekler'),
      content: SizedBox(width: double.maxFinite, height: 400,
        child: _isLoading ? const Center(child: CircularProgressIndicator()) : _requests.isEmpty ? const Center(child: Text('Bekleyen istek yok'))
          : ListView.builder(itemCount: _requests.length, itemBuilder: (ctx, i) {
            final req = _requests[i]; final p = req['profiles'] as Map<String, dynamic>?;
            final name = p?['full_name'] ?? p?['username'] ?? 'Bilinmeyen'; final avatar = p?['avatar_url'] as String?; final msg = req['message'] as String?;
            return Card(child: ListTile(
              leading: CircleAvatar(backgroundImage: avatar != null ? NetworkImage(avatar) : null, child: avatar == null ? const Icon(Icons.person) : null),
              title: Text(name), subtitle: msg != null && msg.isNotEmpty ? Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _handle(req['id'], req['user_id'], 'rejected'), tooltip: 'Reddet'),
                IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _handle(req['id'], req['user_id'], 'approved'), tooltip: 'Onayla'),
              ]),
            ));
          }),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}
