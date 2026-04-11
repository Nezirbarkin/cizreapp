// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/group_model.dart';
import '../services/group_chat_service.dart';
import 'group_chat_screen.dart';
import '../../../core/widgets/group_avatar_viewer.dart';

/// Üye olmayan kullanıcılar için grup detay ekranı
/// Grup bilgilerini, üyeleri ve katılım butonunu gösterir
class GroupDetailScreen extends StatefulWidget {
  final ChatGroup group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _members = [];
  Map<String, dynamic>? _creatorProfile;

  @override
  void initState() {
    super.initState();
    _loadGroupDetails();
  }

  Future<void> _loadGroupDetails() async {
    setState(() => _isLoading = true);
    try {
      // Üyeleri getir (doğrudan Supabase sorgusu - üye olmayanlar da görebilmeli)
      final membersResponse = await Supabase.instance.client
          .from('group_members')
          .select('user_id, role, joined_at')
          .eq('group_id', widget.group.id)
          .order('role', ascending: true)
          .limit(10);

      final memberList = List<Map<String, dynamic>>.from(membersResponse);

      // Her üyenin profil bilgisini al
      for (var i = 0; i < memberList.length; i++) {
        try {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select('full_name, avatar_url, username')
              .eq('id', memberList[i]['user_id'])
              .maybeSingle();
          if (profile != null) {
            memberList[i]['full_name'] = profile['full_name'];
            memberList[i]['avatar_url'] = profile['avatar_url'];
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _members = memberList);

        // Grup kurucusunun profilini getir
        try {
          final creator = await Supabase.instance.client
              .from('profiles')
              .select('full_name, avatar_url, username')
              .eq('id', widget.group.createdBy)
              .maybeSingle();
          if (mounted && creator != null) {
            setState(() => _creatorProfile = creator);
          }
        } catch (_) {}
      }
    } catch (e) {
      // Sessizce devam et
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final group = widget.group;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // App bar with group avatar
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: theme.primaryColor,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [theme.primaryColor, theme.primaryColor.withOpacity(0.8)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
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
                        radius: 50,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        backgroundImage: group.avatarUrl != null ? NetworkImage(group.avatarUrl!) : null,
                        child: group.avatarUrl == null
                            ? Icon(
                                group.isPrivate ? Icons.lock : Icons.groups,
                                size: 50,
                                color: Colors.white.withOpacity(0.8),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      group.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bilgi kartları
                      _buildInfoCards(theme, isDarkMode),

                      // Açıklama
                      if (group.description != null && group.description!.isNotEmpty)
                        _buildSection(
                          'Açıklama',
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.grey[850] : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Text(
                              group.description!,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),

                      // Grup kurucusu (gizli değilse göster)
                      if (_creatorProfile != null && !group.hideCreator)
                        _buildSection(
                          'Grup Kurucusu',
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.grey[850] : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundImage: _creatorProfile?['avatar_url'] != null
                                      ? NetworkImage(_creatorProfile!['avatar_url'])
                                      : null,
                                  child: _creatorProfile?['avatar_url'] == null
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _creatorProfile?['full_name'] ?? 'Bilinmeyen',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        'Kurucu',
                                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Üyeler (ilk 5) - hideCreator ise kurucuyu gizle
                      if (_members.isNotEmpty)
                        _buildSection(
                          'Üyeler (${widget.group.memberCount})',
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.grey[850] : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Column(
                              children: [
                                ..._members.where((m) =>
                                  !(widget.group.hideCreator && m['user_id'] == widget.group.createdBy)
                                ).take(5).map((m) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundImage: m['avatar_url'] != null
                                        ? NetworkImage(m['avatar_url'])
                                        : null,
                                    child: m['avatar_url'] == null
                                        ? const Icon(Icons.person, size: 18)
                                        : null,
                                  ),
                                  title: Text(
                                    m['full_name'] ?? 'Bilinmeyen',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  trailing: _buildRoleBadge(m['role'] as String? ?? 'member'),
                                )),
                                if (_members.length > 5)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      've ${_members.length - 5} üye daha...',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                      // Katılım butonu
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildJoinButton(theme),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    Color color;
    String label;
    switch (role) {
      case 'admin':
        color = Colors.blue;
        label = 'Admin';
        break;
      case 'moderator':
        color = Colors.orange;
        label = 'Mod';
        break;
      default:
        color = Colors.grey;
        label = 'Üye';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoCards(ThemeData theme, bool isDarkMode) {
    final group = widget.group;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _infoCard(
              icon: Icons.people,
              label: 'Üye',
              value: '${group.memberCount}',
              color: Colors.blue,
              isDarkMode: isDarkMode,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _infoCard(
              icon: group.isPrivate ? Icons.lock : Icons.public,
              label: group.isPrivate ? 'Gizli' : 'Açık',
              value: group.isPrivate ? 'Davet' : 'Herkese Açık',
              color: group.isPrivate ? Colors.orange : Colors.green,
              isDarkMode: isDarkMode,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _infoCard(
              icon: Icons.calendar_today,
              label: 'Oluşturulma',
              value: _formatDate(group.createdAt),
              color: Colors.purple,
              isDarkMode: isDarkMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildJoinButton(ThemeData theme) {
    final group = widget.group;

    if (group.hasPendingJoinRequest) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.grey),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text('İstek Gönderildi', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (group.isPrivate) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _sendJoinRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.send),
              SizedBox(width: 8),
              Text('Katılma İsteği Gönder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _joinGroup,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_add),
            SizedBox(width: 8),
            Text('Gruba Katıl', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _joinGroup() async {
    setState(() => _isLoading = true);
    final success = await _groupChatService.joinGroup(widget.group.id);
    if (mounted) {
      if (success) {
        // Grup detayını güncelle ve sohbete yönlendir
        final updatedGroup = await _groupChatService.getGroupDetail(widget.group.id);
        if (mounted && updatedGroup != null) {
          Navigator.of(context).pop(); // Detay ekranını kapat
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => GroupChatScreen(group: updatedGroup)),
          );
        } else if (mounted) {
          Navigator.of(context).pop(true); // Result döndür
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.group.name} grubuna katıldınız!')),
          );
        }
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gruba katılırken hata oluştu'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendJoinRequest() async {
    final messageController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${widget.group.name} grubuna katıl'),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, messageController.text.trim()),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      final success = await _groupChatService.sendJoinRequest(
        widget.group.id,
        message: result.isEmpty ? null : result,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Katılma isteği gönderildi!' : 'İstek gönderilemedi'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        if (success) {
          Navigator.of(context).pop(true);
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}
