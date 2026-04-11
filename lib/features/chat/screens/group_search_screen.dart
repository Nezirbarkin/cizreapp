// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/widgets/group_avatar_viewer.dart';
import '../services/group_chat_service.dart';
import 'group_chat_screen.dart';
import '../../../core/models/group_model.dart';

class GroupSearchScreen extends StatefulWidget {
  const GroupSearchScreen({super.key});

  @override
  State<GroupSearchScreen> createState() => _GroupSearchScreenState();
}

class _GroupSearchScreenState extends State<GroupSearchScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    final results = await _groupChatService.searchGroups(query);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _joinGroup(Map<String, dynamic> group) async {
    final groupId = group['id'] as String;
    final isPrivate = group['is_private'] as bool? ?? false;

    if (isPrivate) {
      // Gizli gruba istek gönder
      final hasPending = await _groupChatService.hasPendingRequest(groupId);
      if (hasPending) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu gruba zaten bir katılma isteğiniz var'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // İstek gönderme dialogu
      if (mounted) {
        _showJoinRequestDialog(groupId);
      }
    } else {
      // Açık gruba doğrudan katıl
      final success = await _groupChatService.joinGroup(groupId);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gruba katıldınız!'),
              backgroundColor: Colors.green,
            ),
          );
          // Listeyi güncelle
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gruba katılma başarısız. Lütfen tekrar deneyin.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showJoinRequestDialog(String groupId) {
    final messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Katılma İsteği'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bu gizli bir grup. Katılmak için istek göndermeniz gerekiyor.'),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Mesaj (isteğe bağlı)',
                hintText: 'Neden katılmak istiyorsunuz?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              
              navigator.pop();
              final success = await _groupChatService.sendJoinRequest(
                groupId,
                message: messageController.text.trim().isEmpty
                    ? null
                    : messageController.text.trim(),
              );
              
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'Katılma isteği gönderildi. Admin onayını bekleyin.'
                        : 'İstek gönderilemedi. Lütfen tekrar deneyin.',
                  ),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
              
              messageController.dispose();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('İstek Gönder'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Ara'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: Column(
        children: [
          // Arama çubuğu
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[850] : Colors.white,
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                  color: Colors.black.withOpacity(0.05),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Grup adı ile ara...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isSearching ? null : _search,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Ara'),
                ),
              ],
            ),
          ),

          // Sonuçlar
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? _buildInitialState()
                    : _searchResults.isEmpty
                        ? _buildNoResultsState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              return _buildGroupSearchTile(_searchResults[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Gruplarda Ara',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Grup adı ile arama yapın',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Sonuç bulunamadı',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Farklı anahtar kelimelerle tekrar deneyin',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSearchTile(Map<String, dynamic> group) {
    final name = group['name'] as String;
    final description = group['description'] as String?;
    final isPrivate = group['is_private'] as bool? ?? false;
    final memberCount = group['member_count'] as int? ?? 0;
    final isMember = group['is_member'] as bool? ?? false;
    final avatarUrl = group['avatar_url'] as String?;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isMember ? Colors.green.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMember ? Colors.green.withOpacity(0.3) : Colors.grey[200]!,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: GestureDetector(
          onTap: avatarUrl != null
              ? () => showGroupAvatarFullscreen(
                    context: context,
                    imageUrl: avatarUrl,
                    title: name,
                  )
              : null,
          child: CircleAvatar(
            radius: 24,
            backgroundColor: isPrivate ? Colors.orange[100] : Colors.green[100],
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Icon(
                    isPrivate ? Icons.lock : Icons.groups,
                    color: isPrivate ? Colors.orange[700] : Colors.green[700],
                  )
                : null,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPrivate) ...[
              const SizedBox(width: 4),
              Icon(Icons.lock, size: 14, color: Colors.orange[700]),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.people, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '$memberCount üye',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        trailing: isMember
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green),
                ),
                child: const Text(
                  'Üye',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : ElevatedButton(
                onPressed: () => _joinGroup(group),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPrivate ? Colors.orange : theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(isPrivate ? 'İstek Gönder' : 'Katıl'),
              ),
        onTap: isMember
            ? () async {
                // Grup detaylarını al ve sohbet ekranına git
                final groupDetail = await _groupChatService.getGroupDetail(group['id']);
                if (groupDetail != null && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupChatScreen(group: groupDetail),
                    ),
                  );
                }
              }
            : null,
      ),
    );
  }
}
