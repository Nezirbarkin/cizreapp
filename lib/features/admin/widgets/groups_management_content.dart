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
  final _supabase = Supabase.instance.client;
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

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      // RPC ile admin olarak tüm grupları getir
      final response = await _supabase.rpc('admin_get_all_groups');
      setState(() { _groups = List<Map<String, dynamic>>.from(response ?? []); _isLoading = false; });
    } catch (e) {
      AppLogger.error('Admin groups RPC error: $e');
      // Fallback: doğrudan sorgu
      try {
        final response = await _supabase.from('groups').select().order('created_at', ascending: false);
        setState(() { _groups = List<Map<String, dynamic>>.from(response); _isLoading = false; });
      } catch (e2) {
        AppLogger.error('Admin groups fallback error: $e2');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadJoinRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      // RPC ile admin olarak tüm istekleri getir
      final response = await _supabase.rpc('admin_get_all_join_requests');
      if (response != null) {
        // RPC'den gelen veriyi dönüştür
        final list = (response as List).map((r) {
          final map = Map<String, dynamic>.from(r);
          // profiles ve groups alt objelerini oluştur (uyumluluk için)
          map['profiles'] = {
            'full_name': map['user_full_name'],
            'avatar_url': map['user_avatar_url'],
            'username': map['user_username'],
          };
          map['groups'] = {
            'name': map['group_name'],
            'avatar_url': map['group_avatar_url'],
            'is_private': map['group_is_private'],
          };
          return map;
        }).toList();
        setState(() { _joinRequests = list; _isLoadingRequests = false; });
      } else {
        setState(() { _joinRequests = []; _isLoadingRequests = false; });
      }
    } catch (e) {
      AppLogger.error('Admin join requests RPC error: $e');
      // Fallback - FK olmadığı için ayrı sorgular
      try {
        final response = await _supabase.from('group_join_requests')
            .select('*, groups(name, avatar_url, is_private)')
            .eq('status', 'pending').order('created_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(response);
        for (var i = 0; i < list.length; i++) {
          try {
            final profile = await _supabase.from('profiles')
                .select('full_name, avatar_url, username')
                .eq('id', list[i]['user_id']).maybeSingle();
            list[i]['profiles'] = profile ?? {};
          } catch (_) {
            list[i]['profiles'] = {};
          }
        }
        setState(() { _joinRequests = list; _isLoadingRequests = false; });
      } catch (e2) {
        AppLogger.error('Admin join requests fallback error: $e2');
        setState(() => _isLoadingRequests = false);
      }
    }
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

  Future<void> _handleJoinRequest(String requestId, Map<String, dynamic> request, String status) async {
    try {
      if (status == 'approved') {
        // RPC ile onayla
        await _supabase.rpc('admin_approve_join_request', params: {'p_request_id': requestId});
      } else {
        // RPC ile reddet
        await _supabase.rpc('admin_reject_join_request', params: {'p_request_id': requestId});
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'approved' ? 'İstek onaylandı' : 'İstek reddedildi'), backgroundColor: status == 'approved' ? Colors.green : Colors.red));
      await _loadJoinRequests();
      await _loadGroups();
    } catch (e) {
      AppLogger.error('Admin handle join request error: $e');
      // Fallback: doğrudan sorgu
      try {
        if (status == 'approved') {
          final groupId = request['group_id'] as String;
          final userId = request['user_id'] as String;
          await _supabase.from('group_members').insert({'group_id': groupId, 'user_id': userId, 'role': 'member'});
          final currentGroup = await _supabase.from('groups').select('member_count').eq('id', groupId).single();
          await _supabase.from('groups').update({'member_count': (currentGroup['member_count'] as int? ?? 0) + 1}).eq('id', groupId);
        }
        await _supabase.from('group_join_requests').update({'status': status, 'reviewed_at': DateTime.now().toIso8601String()}).eq('id', requestId);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'approved' ? 'İstek onaylandı (fallback)' : 'İstek reddedildi (fallback)'), backgroundColor: status == 'approved' ? Colors.green : Colors.red));
        await _loadJoinRequests();
        await _loadGroups();
      } catch (e2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e2'), backgroundColor: Colors.red));
      }
    }
  }

  void _showCreateGroupDialog() {
    final nameC = TextEditingController(); final descC = TextEditingController(); bool isPrivate = false;
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
    )));
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
            // RPC ile güncelle
            await _supabase.rpc('admin_update_group', params: {
              'p_group_id': group['id'],
              'p_name': nameC.text.trim(),
              'p_description': descC.text.trim().isEmpty ? null : descC.text.trim(),
              'p_is_private': isPrivate,
            });
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grup güncellendi'), backgroundColor: Colors.green));
            await _loadGroups();
          } catch (e) {
            AppLogger.error('Admin update group RPC error: $e');
            // Fallback
            try {
              await _supabase.from('groups').update({'name': nameC.text.trim(), 'description': descC.text.trim().isEmpty ? null : descC.text.trim(), 'is_private': isPrivate}).eq('id', group['id']);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grup güncellendi (fallback)'), backgroundColor: Colors.green));
              await _loadGroups();
            } catch (e2) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e2'), backgroundColor: Colors.red));
            }
          }
        }, child: const Text('Kaydet')),
      ],
    )));
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

  Future<void> _load() async {
    try {
      // RPC ile üyeleri getir
      final r = await widget.supabase.rpc('admin_get_group_members', params: {'p_group_id': widget.groupId});
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
        for (var i = 0; i < list.length; i++) {
          try {
            final profile = await widget.supabase.from('profiles')
                .select('full_name, avatar_url, username')
                .eq('id', list[i]['user_id']).maybeSingle();
            list[i]['profiles'] = profile ?? {};
          } catch (_) {
            list[i]['profiles'] = {};
          }
        }
        setState(() { _members = list; _isLoading = false; });
      } catch (e2) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    try {
      // RPC ile üye çıkar
      await widget.supabase.rpc('admin_remove_group_member', params: {
        'p_group_id': widget.groupId,
        'p_user_id': member['user_id'],
      });
      widget.onChanged(); await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Üye çıkarıldı'), backgroundColor: Colors.green));
    } catch (e) {
      // Fallback
      try {
        await widget.supabase.from('group_members').delete().eq('id', member['id']);
        final cg = await widget.supabase.from('groups').select('member_count').eq('id', widget.groupId).single();
        final c = (cg['member_count'] as int? ?? 1) - 1;
        await widget.supabase.from('groups').update({'member_count': c < 0 ? 0 : c}).eq('id', widget.groupId);
        widget.onChanged(); await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Üye çıkarıldı (fallback)'), backgroundColor: Colors.green));
      } catch (e2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e2'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _changeRole(Map<String, dynamic> member, String newRole) async {
    try {
      // RPC ile rol değiştir
      await widget.supabase.rpc('admin_change_member_role', params: {
        'p_group_id': widget.groupId,
        'p_user_id': member['user_id'],
        'p_new_role': newRole,
      });
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rol: $newRole'), backgroundColor: Colors.green));
    } catch (e) {
      // Fallback
      try {
        await widget.supabase.from('group_members').update({'role': newRole}).eq('id', member['id']);
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rol: $newRole (fallback)'), backgroundColor: Colors.green));
      } catch (e2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e2'), backgroundColor: Colors.red));
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

  Future<void> _load() async {
    try {
      // FK olmadığı için ayrı sorgu ile profil bilgilerini getir
      final r = await widget.supabase.from('group_join_requests').select('*').eq('group_id', widget.groupId).eq('status', 'pending').order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(r);
      // Her istek için profil bilgisini getir
      for (var i = 0; i < list.length; i++) {
        try {
          final profile = await widget.supabase.from('profiles').select('full_name, avatar_url, username').eq('id', list[i]['user_id']).maybeSingle();
          list[i]['profiles'] = profile ?? {};
        } catch (_) {
          list[i]['profiles'] = {};
        }
      }
      setState(() { _requests = list; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  Future<void> _handle(String requestId, String userId, String status) async {
    try {
      if (status == 'approved') {
        await widget.supabase.rpc('admin_approve_join_request', params: {'p_request_id': requestId});
      } else {
        await widget.supabase.rpc('admin_reject_join_request', params: {'p_request_id': requestId});
      }
      widget.onChanged(); await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'approved' ? 'Onaylandı' : 'Reddedildi'), backgroundColor: status == 'approved' ? Colors.green : Colors.red));
    } catch (e) {
      // Fallback
      try {
        if (status == 'approved') {
          await widget.supabase.from('group_members').insert({'group_id': widget.groupId, 'user_id': userId, 'role': 'member'});
          final cg = await widget.supabase.from('groups').select('member_count').eq('id', widget.groupId).single();
          await widget.supabase.from('groups').update({'member_count': (cg['member_count'] as int? ?? 0) + 1}).eq('id', widget.groupId);
        }
        await widget.supabase.from('group_join_requests').update({'status': status, 'reviewed_at': DateTime.now().toIso8601String()}).eq('id', requestId);
        widget.onChanged(); await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'approved' ? 'Onaylandı (fallback)' : 'Reddedildi (fallback)'), backgroundColor: status == 'approved' ? Colors.green : Colors.red));
      } catch (e2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e2'), backgroundColor: Colors.red));
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
