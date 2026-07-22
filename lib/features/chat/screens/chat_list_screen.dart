// ignore_for_file: deprecated_member_use, unused_local_variable

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/conversation_model.dart';
import '../../../core/services/privacy_service.dart';
import '../services/chat_service.dart';
import '../services/group_chat_service.dart';
import '../services/presence_service.dart';
import 'chat_detail_screen.dart';
import 'chat_privacy_settings_screen.dart';
import 'group_list_screen.dart';
import 'members_screen.dart';
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
  bool _isLoadingActiveUsers = false;
  int _unreadCount = 0;
  int _groupUnreadCount = 0;
  bool _showActiveUsersHeader = true;
  RealtimeChannel? _channel;
  late TabController _tabController;

  // Realtime presence state — onlineIds stream'den gelir
  StreamSubscription<List<String>>? _onlineSub;
  Set<String> _onlineIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadConversations();
    _loadUnreadCount();
    _loadGroupUnreadCount();
    _loadActiveUsers();
    _subscribeToConversations();
    _subscribeOnlinePresence();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _channel?.unsubscribe();
    _onlineSub?.cancel();
    super.dispose();
  }

  void _subscribeOnlinePresence() {
    _onlineSub = PresenceService.instance.onlineUsersStream.listen((ids) {
      if (!mounted) return;
      setState(() => _onlineIds = ids.toSet());
    }, onError: (e) {
      debugPrint('online presence stream error: $e');
    });
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
    if (_isLoadingActiveUsers) return; // Prevent duplicate loads
    setState(() => _isLoadingActiveUsers = true);
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        setState(() => _isLoadingActiveUsers = false);
        return;
      }

      // ÖNEMLI DÜZELTME (2026-07-02):
      // Önce yeni get_online_users RPC'sini dene - hızlı ve doğru sonuç
      List<Map<String, dynamic>> users = [];
      try {
        final rpcResponse = await Supabase.instance.client.rpc(
          'get_online_users',
          params: {'p_exclude_user_id': currentUserId},
        );
        if (rpcResponse != null) {
          users = (rpcResponse as List).cast<Map<String, dynamic>>();
          debugPrint('✅ get_online_users RPC: ${users.length} users');
        }
      } catch (e) {
        debugPrint('get_online_users RPC başarısız, fallback: $e');
        // Fallback: eski sorgu
        try {
          final response = await Supabase.instance.client
              .from('profiles')
              .select(
                  'id, full_name, avatar_url, last_seen, is_online, is_ghost_mode, is_online_enabled')
              .neq('id', currentUserId)
              .or('is_ghost_mode.eq.false,is_ghost_mode.is.null')
              .limit(50);
          users = (response as List).cast<Map<String, dynamic>>();
        } catch (e2) {
          // Son fallback: basit sorgu
          final response = await Supabase.instance.client
              .from('profiles')
              .select('id, full_name, avatar_url, last_seen, is_online')
              .neq('id', currentUserId)
              .limit(50);
          users = (response as List).cast<Map<String, dynamic>>();
        }
      }

      if (mounted) {
        // Aktiflik durumunu hesapla
        // RPC'den geldiyse is_truly_active kolonu var
        // Fallback'ten geldiyse hesaplamamız gerek
        for (var user in users) {
          user['id'] ??= user['user_id'] ?? user['p_user_id'];
          final isOnline = user['is_online'] as bool? ?? false;
          final lastSeen = _parseDateTime(user['last_seen']);
          final isOnlineEnabled = user['is_online_enabled'] as bool? ?? true;
          final isGhostMode = user['is_ghost_mode'] as bool? ?? false;

          // RPC'den is_truly_active geldiyse onu kullan
          final rpcTrulyActive = user['is_truly_active'] as bool?;
          if (rpcTrulyActive != null) {
            user['_isActive'] = rpcTrulyActive;
          } else {
            // Hesapla
            final trulyActive = isOnlineEnabled && !isGhostMode
                ? PrivacyService.isUserTrulyActive(isOnline, lastSeen)
                : false;
            user['_isActive'] = trulyActive;
          }
        }

        // Aktif kullanıcıları presence stream + DB bilgisine göre ayır
        final activeUsers = users.where((u) {
          final uid = u['id'] as String?;
          final dbActive = u['_isActive'] == true;
          return uid != null && (_onlineIds.contains(uid) || dbActive);
        }).toList();
        final inactiveUsers = users.where((u) {
          final uid = u['id'] as String?;
          final dbActive = u['_isActive'] == true;
          return uid == null || (!_onlineIds.contains(uid) && !dbActive);
        }).toList();

        // Presence'de olanlar en üstte, sonra DB'de aktif, en altta inaktif
        final presenceOnline = activeUsers.where((u) {
          final uid = u['id'] as String?;
          return uid != null && _onlineIds.contains(uid);
        }).toList();
        final dbOnlineOnly = activeUsers.where((u) {
          final uid = u['id'] as String?;
          return uid == null || !_onlineIds.contains(uid);
        }).toList();
        presenceOnline.shuffle();
        dbOnlineOnly.shuffle();
        inactiveUsers.shuffle();

        final sortedUsers = [...presenceOnline, ...dbOnlineOnly, ...inactiveUsers];

        setState(() {
          _activeUsers = sortedUsers;
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
    // PERFORMANCE: Paralel olarak yükle
    await Future.wait([
      _loadConversations(),
      _loadUnreadCount(),
      _loadGroupUnreadCount(),
    ]);
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
          // Arkadaş Ekle
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MembersScreen(),
                ),
              );
            },
            tooltip: 'Arkadaş Ekle',
          ),
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
    // Aktif kullanıcılar bölümü: aşağı kaydırınca AnimatedSize ile kapanır,
    // en üste dönünce geri gelir. Fonksiyonların davranışı bozulmaz; sadece
    // görünürlük state'i değişir.
    final showHeader = _showActiveUsersHeader &&
        !_isLoadingActiveUsers &&
        _activeUsers.isNotEmpty;

    return Column(
      children: [
        // Aktif kullanıcılar bölümü
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: showHeader
              ? RepaintBoundary(
                  child: Container(
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
                      cacheExtent: 300.0,
                      itemBuilder: (context, index) {
                        final user = _activeUsers[index];
                        final avatarUrl = user['avatar_url'] as String?;
                        final fullName =
                            user['full_name'] as String? ?? 'Kullanıcı';
                        // Presence stream'den realtime online bilgisi, DB fallback ile kombine
                        final dbActive = user['_isActive'] as bool? ?? false;
                        final userId = user['id'] as String?;
                        final isActive = userId != null
                            ? (_onlineIds.contains(userId) || dbActive)
                            : dbActive;
                        return RepaintBoundary(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: GestureDetector(
                              onTap: userId != null
                                  ? () => _openUserProfile(userId)
                                  : null,
                              onLongPress: () =>
                                  _startChat(user, fullName, avatarUrl),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 26,
                                        backgroundColor:
                                            Colors.deepPurple[100],
                                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                            ? NetworkImage(avatarUrl)
                                            : null,
                                        child: (avatarUrl == null || avatarUrl.isEmpty)
                                            ? Text(
                                                fullName.isNotEmpty
                                                    ? fullName[0].toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors
                                                      .deepPurple[700],
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
                                                BorderSide(
                                                    color: Colors.white,
                                                    width: 2),
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
                          ),
                        );
                      },
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        // Sohbetler listesi - scroll yönünü izle ve header'ı gizle/göster
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Dikey konum 8px'ten aşağıdaysa header'ı gizle,
              // en üste (0) dönüldüyse tekrar göster.
              if (notification is ScrollUpdateNotification) {
                final pixels = notification.metrics.pixels;
                if (pixels > 8 && _showActiveUsersHeader) {
                  if (mounted) {
                    setState(() => _showActiveUsersHeader = false);
                  }
                } else if (pixels <= 0 && !_showActiveUsersHeader) {
                  if (mounted) {
                    setState(() => _showActiveUsersHeader = true);
                  }
                }
              }
              return false;
            },
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _conversations.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _refreshConversations,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _conversations.length,
                          cacheExtent: 400.0,
                          itemBuilder: (context, index) {
                            return RepaintBoundary(
                              child:
                                  _buildConversationTile(_conversations[index]),
                            );
                          },
                        ),
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
    // Gerçek aktiflik kontrolü: presence stream VEYA (is_online VE last_seen son 3 dk)
    final otherId = otherUser?['id'] as String?;
    final isOnPresence = otherId != null && _onlineIds.contains(otherId);
    final isDbTrulyActive = PrivacyService.isUserTrulyActive(isOtherUserOnline, otherUserLastSeen);
    final isOtherUserTrulyActive = isOnPresence || isDbTrulyActive;
    
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
              GestureDetector(
                onTap: otherId != null ? () => _openUserProfile(otherId) : null,
                child: Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: hasUnread ? Colors.red[100] : Colors.deepPurple[100],
                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
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

  Future<void> _showDeleteDialog(Conversation conversation) async {
    final otherUser = conversation.otherUser;
    final fullName = otherUser?['full_name'] as String? ?? 'Kullanıcı';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konuşmayı Sil'),
        content: Text(
          '$fullName ile olan konuşma tüm mesajları ile birlikte silinecek. '
          'Emin misin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Yükleniyor bilgisi (delete uzun sürebilir)
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Sohbet siliniyor...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // PROJE_HAVIZA notu: delete_conversation_with_partner RPC kullanılıyor.
      // Hem mevcut satırı hem karşı tarafın ters satırını atomik siler
      // (ON DELETE CASCADE ile mesajlar da silinir). SECURE: bool döner.
      final ok = await _chatService.deleteConversation(conversation.id);
      if (!mounted) return;
      if (ok) {
        // İlk sohbet listede kalmış olabilir → _loadConversations sonrası
        // realtime channel de UI'ı günceller.
        await _loadConversations();
        await _loadUnreadCount();
        messenger.showSnackBar(
          SnackBar(
            content: Text('$fullName ile olan sohbet silindi'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
                'Sohbet silinemedi (yetkiniz olmayabilir veya zaten silinmiş)'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('deleteConversation UI hata: $e\n$st');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Silme hatası: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
