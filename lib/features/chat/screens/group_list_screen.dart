// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/group_model.dart';
import '../services/group_chat_service.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';
import 'group_detail_screen.dart';
import 'group_search_screen.dart';
import '../../../core/widgets/group_avatar_viewer.dart';

class GroupListScreen extends StatefulWidget {
  final bool embedded; // TabBarView içinde gömülü mü?
  const GroupListScreen({super.key, this.embedded = false});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  List<ChatGroup> _groups = [];
  bool _isLoading = true;
  int _totalUnreadCount = 0;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _loadUnreadCount();
    _subscribeToGroups();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    final groups = await _groupChatService.getAllGroups();
    if (mounted) {
      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUnreadCount() async {
    final count = await _groupChatService.getTotalUnreadCount();
    if (mounted) {
      setState(() => _totalUnreadCount = count);
    }
  }

  void _subscribeToGroups() {
    _channel = _groupChatService.subscribeToUserGroups((groups) {
      if (mounted) {
        setState(() => _groups = groups);
        _loadUnreadCount();
      }
    });
  }

  Future<void> _refreshGroups() async {
    await _loadGroups();
    await _loadUnreadCount();
  }

  Future<void> _createGroup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
    );

    if (result is ChatGroup && mounted) {
      await _loadGroups();
      // Yeni oluşturulan gruba git
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupChatScreen(group: result),
          ),
        );
      }
    }
  }

  Future<void> _searchGroups() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GroupSearchScreen()),
    );

    // Arama sonucundan bir gruba katıldıysa listeyi yenile
    if (result == true && mounted) {
      await _loadGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _groups.isEmpty
            ? _buildEmptyState()
            : RefreshIndicator(
                onRefresh: _refreshGroups,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    return _buildGroupTile(_groups[index]);
                  },
                ),
              );

    // Gömülü modda (TabBarView içinde) Scaffold kullanma
    if (widget.embedded) {
      return Stack(
        children: [
          body,
          // Sağ alt köşede FAB benzeri butonlar (bottom navigation bar ile çakışmayı önle)
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 80, // bottom bar + margin
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'search_groups',
                  onPressed: _searchGroups,
                  backgroundColor: theme.primaryColor,
                  child: const Icon(Icons.search, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'create_group',
                  onPressed: _createGroup,
                  backgroundColor: theme.primaryColor,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: const Text('Grup Sohbetleri'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        actions: [
          // Arama butonu
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _searchGroups,
            tooltip: 'Grup Ara',
          ),
          // Grup oluştur butonu
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createGroup,
            tooltip: 'Grup Oluştur',
          ),
          // Okunmamış mesaj badge
          if (_totalUnreadCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Badge(
                label: Text('$_totalUnreadCount'),
                backgroundColor: Colors.white,
                textColor: theme.primaryColor,
                child: const Icon(Icons.notifications_outlined, color: Colors.white),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.groups_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz grup yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Yeni bir grup oluşturun veya\nmevcut gruplara katılın',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createGroup,
            icon: const Icon(Icons.add),
            label: const Text('Grup Oluştur'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _searchGroups,
            icon: const Icon(Icons.search),
            label: const Text('Grup Ara'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleGroupTap(ChatGroup group) async {
    if (group.isMember) {
      // Üye ise direkt sohbete git
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GroupChatScreen(group: group),
        ),
      );
      await _loadGroups();
      await _loadUnreadCount();
    } else {
      // Üye değil → grup detay ekranını göster
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GroupDetailScreen(group: group),
        ),
      );
      // Gruba katıldıysa listeyi yenile
      if (result == true && mounted) {
        await _loadGroups();
        await _loadUnreadCount();
      }
    }
  }

  void _showJoinRequestDialog(ChatGroup group) {
    final messageController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${group.name} grubuna katıl'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Bu gizli bir grup. Katılmak için istek göndermeniz gerekiyor.'),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Mesaj (isteğe bağlı)',
                hintText: 'Neden katılmak istiyorsunuz?',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _groupChatService.sendJoinRequest(
                group.id,
                message: messageController.text.trim().isEmpty
                    ? null
                    : messageController.text.trim(),
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Katılma isteği gönderildi!'
                        : 'İstek gönderilemedi'),
                  ),
                );
                if (success) {
                  await _loadGroups();
                }
              }
            },
            child: const Text('İstek Gönder'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTile(ChatGroup group) {
    final hasUnread = group.unreadCount > 0;
    final isMember = group.isMember;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _handleGroupTap(group),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: !isMember
              ? Colors.orange.withOpacity(0.06)
              : hasUnread
                  ? Colors.deepPurple.withOpacity(0.08)
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !isMember
                ? Colors.orange.withOpacity(0.4)
                : hasUnread
                    ? Colors.deepPurple.withOpacity(0.3)
                    : Colors.grey[200]!,
            width: !isMember ? 2 : hasUnread ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (group.avatarUrl != null) {
                        showGroupAvatarFullscreen(
                          context: context,
                          imageUrl: group.avatarUrl!,
                          title: group.name,
                        );
                      }
                    },
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: !isMember
                          ? Colors.orange[100]
                          : hasUnread
                              ? Colors.deepPurple[100]
                              : Colors.green[100],
                      backgroundImage: group.avatarUrl != null ? NetworkImage(group.avatarUrl!) : null,
                      child: group.avatarUrl == null
                          ? Icon(
                              group.isPrivate ? Icons.lock : Icons.groups,
                              size: 28,
                              color: !isMember
                                  ? Colors.orange[700]
                                  : hasUnread
                                      ? Colors.deepPurple[700]
                                      : Colors.green[700],
                            )
                          : null,
                    ),
                  ),
                  // Okunmamış mesaj sayısı badge (sadece üyeler için)
                  if (hasUnread && isMember)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          group.unreadCount > 9 ? '9+' : '${group.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // İçerik
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  group.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: !isMember
                                        ? Colors.orange[900]
                                        : hasUnread
                                            ? Colors.deepPurple[900]
                                            : Colors.grey[900],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (group.isPrivate) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.lock,
                                  size: 14,
                                  color: Colors.orange[700],
                                ),
                              ],
                              if (isMember && group.isAdmin) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.admin_panel_settings,
                                  size: 14,
                                  color: Colors.blue[700],
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Üye olmayanlar için Katıl/İstek butonu
                        if (!isMember)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: group.hasPendingJoinRequest
                                  ? Colors.grey
                                  : group.isPrivate
                                      ? Colors.orange
                                      : theme.primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              group.hasPendingJoinRequest
                                  ? 'İstek Gönderildi'
                                  : group.isPrivate
                                      ? 'İstek Gönder'
                                      : 'Katıl',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else if (group.lastMessageTime != null)
                          Text(
                            _formatTime(group.lastMessageTime!),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                              color: hasUnread ? Colors.deepPurple[700] : Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${group.memberCount} üye',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (isMember && group.lastMessage != null) ...[
                          const SizedBox(width: 8),
                          const Text('•', style: TextStyle(color: Colors.grey)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              group.lastMessage!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: hasUnread ? Colors.deepPurple[800] : Colors.grey[600],
                                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ] else if (!isMember && group.lastMessage != null) ...[
                          const SizedBox(width: 8),
                          const Text('•', style: TextStyle(color: Colors.grey)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              group.lastMessage!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    const turkeyOffset = Duration(hours: 3);
    final turkeyTime = time.toUtc().add(turkeyOffset);
    final now = DateTime.now().toUtc().add(turkeyOffset);
    final difference = now.difference(turkeyTime);

    if (difference.inMinutes < 1) {
      return 'Şimdi';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}dk';
    } else if (difference.inDays < 1) {
      final hour = turkeyTime.hour.toString().padLeft(2, '0');
      final minute = turkeyTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (difference.inDays == 1) {
      return 'Dün';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}g';
    } else {
      final day = turkeyTime.day.toString().padLeft(2, '0');
      final month = turkeyTime.month.toString().padLeft(2, '0');
      return '$day.$month';
    }
  }
}
