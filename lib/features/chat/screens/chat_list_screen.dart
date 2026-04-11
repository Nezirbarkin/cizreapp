// ignore_for_file: deprecated_member_use, unused_local_variable

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/conversation_model.dart';
import '../../../core/services/privacy_service.dart';
import '../services/chat_service.dart';
import '../services/group_chat_service.dart';
import 'chat_detail_screen.dart';
import 'chat_privacy_settings_screen.dart';
import 'group_list_screen.dart';
import '../../profile/screens/user_profile_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final GroupChatService _groupChatService = GroupChatService();
  List<Conversation> _conversations = [];
  List<Map<String, dynamic>> _activeUsers = [];
  bool _isLoading = true;
  bool _isLoadingActiveUsers = true;
  int _unreadCount = 0;
  int _groupUnreadCount = 0;
  RealtimeChannel? _channel;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadConversations();
    _loadUnreadCount();
    _loadGroupUnreadCount();
    _loadActiveUsers();
    _subscribeToConversations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadGroupUnreadCount() async {
    final count = await _groupChatService.getTotalUnreadCount();
    if (mounted) {
      setState(() => _groupUnreadCount = count);
    }
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    final conversations = await _chatService.getConversations();
    if (mounted) {
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUnreadCount() async {
    final count = await _chatService.getUnreadCount();
    if (mounted) {
      setState(() => _unreadCount = count);
    }
  }

  Future<void> _loadActiveUsers() async {
    setState(() => _isLoadingActiveUsers = true);
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        setState(() => _isLoadingActiveUsers = false);
        return;
      }

      // Tüm kullanıcıları getir (is_ghost_mode=false olanları)
      // is_online alanını da çekiyoruz
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, username, avatar_url, last_seen, status, is_ghost_mode, is_online')
          .neq('id', currentUserId)
          .or('is_ghost_mode.eq.false,is_ghost_mode.is.null')
          .limit(200);

      if (mounted) {
        final users = (response as List).cast<Map<String, dynamic>>();
        
        // Gerçek aktif kullanıcıları öne al, ardından son görülme tarihine göre sırala
        users.sort((a, b) {
          final aOnline = a['is_online'] as bool? ?? false;
          final bOnline = b['is_online'] as bool? ?? false;
          final aLastSeen = _parseDateTime(a['last_seen']);
          final bLastSeen = _parseDateTime(b['last_seen']);
          
          // Önce gerçek aktif olanlar (is_online=true VE last_seen son 3 dk içinde)
          final aActive = PrivacyService.isUserTrulyActive(aOnline, aLastSeen);
          final bActive = PrivacyService.isUserTrulyActive(bOnline, bLastSeen);
          
          if (aActive != bActive) {
            return aActive ? -1 : 1;
          }
          
          // Son görülme tarihine göre sırala
          
          if (aLastSeen != null && bLastSeen != null) {
            return bLastSeen.compareTo(aLastSeen);
          } else if (aLastSeen != null) {
            return -1;
          } else if (bLastSeen != null) {
            return 1;
          }
          return 0;
        });

        setState(() {
          _activeUsers = users;
          _isLoadingActiveUsers = false;
        });
      }
    } catch (e) {
      debugPrint('Kullanıcılar yüklenirken hata: $e');
      if (mounted) {
        setState(() => _isLoadingActiveUsers = false);
      }
    }
  }

  void _subscribeToConversations() {
    _channel = _chatService.subscribeToConversations((conversations) {
      if (mounted) {
        setState(() {
          _conversations = conversations;
        });
        _loadUnreadCount();
      }
    });
  }

  Future<void> _refreshConversations() async {
    await _loadConversations();
    await _loadUnreadCount();
    await _loadGroupUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final totalUnread = _unreadCount + _groupUnreadCount;
    
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: const Text('Mesajlar'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Sohbetler'),
                  if (_unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        _unreadCount > 9 ? '9+' : '$_unreadCount',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Gruplar'),
                  if (_groupUnreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        _groupUnreadCount > 9 ? '9+' : '$_groupUnreadCount',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Gizlilik Ayarları
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatPrivacySettingsScreen(),
                ),
              );
            },
            tooltip: 'Gizlilik Ayarları',
          ),
          // Toplam Okunmamış Mesaj Badge
          if (totalUnread > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Badge(
                label: Text('$totalUnread'),
                backgroundColor: Colors.white,
                textColor: theme.primaryColor,
                child: const Icon(Icons.notifications_outlined, color: Colors.white),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Bireysel Sohbetler Sekmesi
          _buildChatsTab(isDarkMode),
          // Gruplar Sekmesi
          const GroupListScreen(embedded: true),
        ],
      ),
    );
  }

  Widget _buildChatsTab(bool isDarkMode) {
    return Column(
      children: [
        // Kullanıcılar Bölümü (aktif olanlar en başta)
        if (!_isLoadingActiveUsers && _activeUsers.isNotEmpty)
          Container(
            height: 100,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[850] : Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _activeUsers.length,
              itemBuilder: (context, index) {
                final user = _activeUsers[index];
                final avatarUrl = user['avatar_url'] as String?;
                final fullName = user['full_name'] as String? ?? 'Kullanıcı';
                final status = user['status'] as String? ?? 'offline';
                final isOnline = user['is_online'] as bool? ?? false;
                
                // last_seen DateTime'a çevir
                final lastSeen = _parseDateTime(user['last_seen']);
                 
                // Kullanıcının aktif olup olmadığını kontrol et
                // is_online=true ise veya son 5 dakika içinde aktifse yeşil göster
                final isActive = _isUserActive(isOnline, lastSeen);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () => _openUserProfile(user['id'] as String),
                    onLongPress: () => _startChat(user, fullName, avatarUrl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.deepPurple[100],
                              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                              child: avatarUrl == null
                                  ? Text(
                                      fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepPurple[700],
                                      ),
                                    )
                                  : null,
                            ),
                            if (isActive)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.fromBorderSide(
                                      BorderSide(color: Colors.white, width: 2),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 60,
                          child: Text(
                            fullName,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        // Konuşmalar Listesi
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _conversations.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _refreshConversations,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          return _buildConversationTile(_conversations[index]);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz mesajınız yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Başka kullanıcılarla sohbet etmek için\nonların profiline gidin',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    final otherUser = conversation.otherUser;
    final avatarUrl = otherUser?['avatar_url'] as String?;
    final fullName = otherUser?['full_name'] as String? ?? 'Kullanıcı';
    final username = otherUser?['username'] as String?;
    final isOtherUserOnline = otherUser?['is_online'] as bool? ?? false;
    final otherUserLastSeen = _parseDateTime(otherUser?['last_seen']);
    // Gerçek aktiflik kontrolü: is_online=true VE last_seen son 3 dk içinde
    final isOtherUserTrulyActive = PrivacyService.isUserTrulyActive(isOtherUserOnline, otherUserLastSeen);
    
    // Son mesajı formatla - eğer paylaşılan gönderi ise özel metin göster
    String lastMessage = conversation.lastMessage ?? 'Henüz mesaj yok';
    if (lastMessage.startsWith('SHARED_POST:')) {
      lastMessage = '📤 Gönderi paylaştı';
    }
    
    final time = _formatTime(conversation.lastMessageTime);
    final hasUnread = conversation.unreadCount > 0;
    final lastMessageByMe = conversation.lastMessageByMe;
    final lastMessageRead = conversation.lastMessageRead;

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              conversationId: conversation.id,
              otherUserId: conversation.otherUserId,
              otherUserName: fullName,
              otherUserAvatar: avatarUrl,
            ),
          ),
        );
        // Mesajları okundu olarak işaretle ve listeyi yenile
        await _chatService.markMessagesAsRead(conversation.id);
        await _loadConversations();
        await _loadUnreadCount();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: hasUnread ? Colors.red.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasUnread ? Colors.red.withOpacity(0.3) : Colors.grey[200]!,
            width: hasUnread ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: hasUnread ? Colors.red[100] : Colors.deepPurple[100],
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(
                            fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: hasUnread ? Colors.red[700] : Colors.deepPurple[700],
                            ),
                          )
                        : null,
                  ),
                  // Çevrimiçi göstergesi (sağ alt köşe)
                  if (isOtherUserTrulyActive)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  // Okunmamış mesaj sayısı (sağ üst köşe)
                  if (hasUnread)
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
                          conversation.unreadCount > 9 ? '9+' : '${conversation.unreadCount}',
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            fullName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: hasUnread ? Colors.red[900] : Colors.grey[900],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (time != null)
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                              color: hasUnread ? Colors.red[700] : Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: hasUnread ? Colors.red[800] : Colors.grey[600],
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        // Benim mesajım okundu işaretleri
                        if (lastMessageByMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            lastMessageRead ? Icons.done_all : Icons.done,
                            size: 14,
                            color: lastMessageRead ? Colors.blue[300] : Colors.grey[400],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Silme butonu
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () => _showDeleteDialog(conversation),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(Conversation conversation) {
    final otherUser = conversation.otherUser;
    final fullName = otherUser?['full_name'] as String? ?? 'Kullanıcı';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konuşmayı Sil'),
        content: Text('$fullName ile olan konuşmayı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _chatService.deleteConversation(conversation.id);
              await _loadConversations();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  String? _formatTime(DateTime? time) {
    if (time == null) return null;
    
    // Türkiye saati (UTC+3)
    final turkeyTimeZone = Duration(hours: 3);
    final localTime = time.toUtc().add(turkeyTimeZone);
    final now = DateTime.now().toUtc().add(turkeyTimeZone);
    final difference = now.difference(localTime);
    
    if (difference.inMinutes < 1) {
      return 'Az önce';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} dk';
    } else if (difference.inDays < 1) {
      // Aynı gün - saat göster
      final hour = localTime.hour.toString().padLeft(2, '0');
      final minute = localTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (difference.inDays == 1) {
      return 'Dün ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün';
    } else {
      // Eski tarihler - tam tarih ve saat
      final day = localTime.day.toString().padLeft(2, '0');
      final month = localTime.month.toString().padLeft(2, '0');
      final year = localTime.year;
      final hour = localTime.hour.toString().padLeft(2, '0');
      final minute = localTime.minute.toString().padLeft(2, '0');
      return '$day.$month.$year $hour:$minute';
    }
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    try {
      if (value is String) {
        return DateTime.parse(value);
      } else if (value is DateTime) {
        return value;
      }
    } catch (e) {
      debugPrint('DateTime parse hatası: $e');
    }
    return null;
  }

  bool _isUserActive(bool isOnline, DateTime? lastSeen) {
    // is_online=true VE last_seen son 3 dakika içinde ise aktif kabul et
    // Bu sayede uygulama zorla kapatılsa bile kullanıcı aktif görünmez
    return PrivacyService.isUserTrulyActive(isOnline, lastSeen);
  }

  Future<void> _startChat(Map<String, dynamic> user, String fullName, String? avatarUrl) async {
    final userId = user['id'] as String;
    
    // Kullanıcının mesaj alma özelliğini kontrol et
    final targetProfile = await Supabase.instance.client
        .from('profiles')
        .select('messages_enabled')
        .eq('id', userId)
        .maybeSingle();
    
    if (targetProfile != null && targetProfile['messages_enabled'] == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu kullanıcının mesaj alma özelliği kapalı'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    final conversation = await _chatService.getOrCreateConversation(userId);
    
    if (conversation != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            conversationId: conversation.id,
            otherUserId: userId,
            otherUserName: fullName,
            otherUserAvatar: avatarUrl,
          ),
        ),
      );
      // Listeyi yenile
      _loadConversations();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konuşma başlatılamadı')),
      );
    }
  }

  void _openUserProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: userId),
      ),
    );
  }
}
