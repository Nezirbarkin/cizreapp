// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/group_model.dart';
import '../../../core/models/group_message_model.dart';
import '../services/group_chat_service.dart';
import 'group_settings_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../../core/widgets/group_avatar_viewer.dart';
import 'package:intl/intl.dart';

class GroupChatScreen extends StatefulWidget {
  final ChatGroup group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  List<GroupMessage> _messages = [];
  List<GroupMember> _members = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isInitialLoad = true; // İlk yükleme flag'i - jumpTo için
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _readReceiptsChannel;
  late ChatGroup _currentGroup;
  int _pendingRequestCount = 0;

  // Reply state
  GroupMessage? _replyToMessage;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.group;
    _loadMessages();
    _loadMembers();
    _subscribeToMessages();
    _subscribeToReadReceipts();
    _loadPendingRequests();
    _groupChatService.markGroupMessagesReadReceipts(widget.group.id);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _messagesChannel?.unsubscribe();
    _readReceiptsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final messages = await _groupChatService.getGroupMessages(_currentGroup.id);
    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
        _isInitialLoad = true; // İlk yükleme - jumpTo kullanılacak
      });
      _scrollToBottom();
    }
  }

  Future<void> _loadMembers() async {
    final members = await _groupChatService.getGroupMembers(_currentGroup.id);
    if (mounted) {
      setState(() => _members = members);
    }
  }

  void _subscribeToMessages() {
    _messagesChannel = _groupChatService.subscribeToGroupMessages(
      _currentGroup.id,
      (messages) {
        if (mounted) {
          setState(() => _messages = messages);
          _scrollToBottom();
          _groupChatService.markGroupMessagesReadReceipts(_currentGroup.id);
        }
      },
    );
  }

  void _subscribeToReadReceipts() {
    _readReceiptsChannel = _groupChatService.subscribeToReadReceipts(
      _currentGroup.id,
      () {
        if (mounted) setState(() {});
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (_isInitialLoad) {
          // İlk yüklemede anında en alta atla (animasyon yok)
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          _isInitialLoad = false;
        } else {
          // Sonraki mesajlarda animasyonlu scroll
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    setState(() => _isSending = true);
    _messageController.clear();

    final replyTo = _replyToMessage;
    setState(() => _replyToMessage = null);

    final tempMessage = GroupMessage.createTemp(
      groupId: _currentGroup.id,
      senderId: currentUserId,
      content: content,
      replyToId: replyTo?.id,
      replyToContent: replyTo?.content,
      replyToSenderName: replyTo?.senderName,
    );

    setState(() {
      _messages.add(tempMessage);
      _scrollToBottom();
    });

    final message = await _groupChatService.sendGroupMessage(
      groupId: _currentGroup.id,
      content: content,
      replyToId: replyTo?.id,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        if (message != null) {
          final index = _messages.indexWhere((m) => m.id == tempMessage.id);
          if (index != -1) _messages[index] = message;
        } else {
          final index = _messages.indexWhere((m) => m.id == tempMessage.id);
          if (index != -1) {
            _messages[index] = tempMessage.copyWith(isFailed: true, isSending: false);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mesaj gönderilemedi'), backgroundColor: Colors.red),
          );
        }
      });
    }
  }

  void _setReplyToMessage(GroupMessage message) {
    setState(() => _replyToMessage = message);
    _messageFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyToMessage = null);
  }

  Future<void> _loadPendingRequests() async {
    if (!_currentGroup.isAdmin) return;
    try {
      final response = await Supabase.instance.client
          .from('group_join_requests')
          .select('id')
          .eq('group_id', _currentGroup.id)
          .eq('status', 'pending');
      if (mounted) {
        setState(() => _pendingRequestCount = (response as List).length);
      }
    } catch (_) {}
  }

  void _showPendingRequests() async {
    try {
      final requests = await Supabase.instance.client
          .from('group_join_requests')
          .select('*')
          .eq('group_id', _currentGroup.id)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(requests);

      for (var i = 0; i < list.length; i++) {
        try {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select('full_name, avatar_url, username')
              .eq('id', list[i]['user_id'])
              .maybeSingle();
          list[i]['profiles'] = profile ?? {};
        } catch (_) {
          list[i]['profiles'] = {};
        }
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx, setDState) {
            return AlertDialog(
              title: Text('Katılma İstekleri (${list.length})'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: list.isEmpty
                    ? const Center(child: Text('Bekleyen istek yok'))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final req = list[i];
                          final p = req['profiles'] as Map<String, dynamic>?;
                          final name = p?['full_name'] ?? p?['username'] ?? 'Bilinmeyen';
                          final avatar = p?['avatar_url'] as String?;
                          final msg = req['message'] as String?;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                                child: avatar == null ? const Icon(Icons.person) : null,
                              ),
                              title: Text(name),
                              subtitle: msg != null && msg.isNotEmpty ? Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.red),
                                    onPressed: () async {
                                      final success = await _groupChatService.rejectJoinRequest(req['id']);
                                      if (success && mounted) {
                                        setDState(() => list.removeAt(i));
                                        _loadPendingRequests();
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.check, color: Colors.green),
                                    onPressed: () async {
                                      final success = await _groupChatService.approveJoinRequest(req['id']);
                                      if (success && mounted) {
                                        setDState(() => list.removeAt(i));
                                        _loadPendingRequests();
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
            );
          });
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İstekler yüklenemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showMessageReadReceipts(GroupMessage message) async {
    if (message.id.startsWith('temp_')) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _MessageReadReceiptsSheet(
          message: message,
          groupChatService: _groupChatService,
          groupId: _currentGroup.id,
          totalMembers: _members.length,
        );
      },
    );
  }

  void _showSenderProfile(String senderId) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: senderId)));
  }

  void _openGroupSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => GroupSettingsScreen(group: _currentGroup)),
    );

    if (result is ChatGroup && mounted) {
      setState(() => _currentGroup = result);
    }
    if (result == false && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFFECE5DD),
      appBar: _buildAppBar(isDark, theme),
      body: Column(
        children: [
          // Mesajlar
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = message.senderId == currentUserId;
                          final showDate = index == 0 ||
                              !_isSameDay(_messages[index - 1].createdAt, message.createdAt);
                          final showSender = !isMe &&
                              (index == 0 || _messages[index - 1].senderId != message.senderId);

                          return Column(
                            children: [
                              if (showDate) _buildDateChip(message.createdAt, isDark),
                              _SwipeToReply(
                                onReply: () => _setReplyToMessage(message),
                                child: _buildMessageBubble(message, isMe, showSender, isDark, currentUserId),
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Reply bar
          if (_replyToMessage != null) _buildReplyBar(isDark),

          // Mesaj giriş alanı
          _buildMessageInput(isDark),
        ],
      ),
    );
  }

  // ─── AppBar ───
  PreferredSizeWidget _buildAppBar(bool isDark, ThemeData theme) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF1F2C33) : theme.primaryColor,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      elevation: 0.5,
      titleSpacing: 0,
      title: InkWell(
        onTap: _openGroupSettings,
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                if (_currentGroup.avatarUrl != null) {
                  showGroupAvatarFullscreen(
                    context: context,
                    imageUrl: _currentGroup.avatarUrl!,
                    title: _currentGroup.name,
                  );
                }
              },
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withOpacity(0.2),
                backgroundImage: _currentGroup.avatarUrl != null
                    ? NetworkImage(_currentGroup.avatarUrl!)
                    : null,
                child: _currentGroup.avatarUrl == null
                    ? Icon(
                        _currentGroup.isPrivate ? Icons.lock : Icons.groups,
                        size: 20,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentGroup.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_currentGroup.memberCount} üye',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_currentGroup.isAdmin && _pendingRequestCount > 0)
          Stack(
            children: [
              IconButton(icon: const Icon(Icons.person_add), onPressed: _showPendingRequests),
              Positioned(
                right: 6,
                top: 6,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('$_pendingRequestCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          )
        else if (_currentGroup.isAdmin)
          IconButton(icon: const Icon(Icons.person_add_outlined), onPressed: _showPendingRequests),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: _openGroupSettings),
      ],
    );
  }

  // ─── Tarih Chip ───
  Widget _buildDateChip(DateTime date, bool isDark) {
    const turkeyOffset = Duration(hours: 3);
    final turkeyDate = date.toUtc().add(turkeyOffset);
    final now = DateTime.now().toUtc().add(turkeyOffset);
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(turkeyDate.year, turkeyDate.month, turkeyDate.day);

    String text;
    if (msgDate == today) {
      text = 'Bugün';
    } else if (msgDate == today.subtract(const Duration(days: 1))) {
      text = 'Dün';
    } else {
      text = '${turkeyDate.day.toString().padLeft(2, '0')}.${turkeyDate.month.toString().padLeft(2, '0')}.${turkeyDate.year}';
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF182229) : const Color(0xFFE1F2FB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF667781),
          ),
        ),
      ),
    );
  }

  // ─── Mesaj Baloncuğu ───
  Widget _buildMessageBubble(GroupMessage message, bool isMe, bool showSender, bool isDark, String? currentUserId) {
    const turkeyOffset = Duration(hours: 3);
    final turkeyTime = message.createdAt.toUtc().add(turkeyOffset);
    final timeStr = '${turkeyTime.hour.toString().padLeft(2, '0')}:${turkeyTime.minute.toString().padLeft(2, '0')}';
    final isReadByAll = isMe && message.isReadByAll(_members.length);

    final bubbleColor = isMe
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (isDark ? const Color(0xFF1F2C33) : Colors.white);

    final textColor = isDark ? Colors.white : Colors.black87;
    final senderColor = _getSenderColor(message.senderId);

    return GestureDetector(
      onTap: isMe ? () => _showMessageReadReceipts(message) : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 52 : 8,
          right: isMe ? 8 : 52,
          bottom: 2,
          top: showSender && !isMe ? 8 : 2,
        ),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar
            if (!isMe && showSender)
              GestureDetector(
                onTap: () => _showSenderProfile(message.senderId),
                child: CircleAvatar(
                  radius: 15,
                  backgroundImage: message.senderAvatarUrl != null
                      ? NetworkImage(message.senderAvatarUrl!)
                      : null,
                  backgroundColor: senderColor.withOpacity(0.15),
                  child: message.senderAvatarUrl == null
                      ? Text(
                          (message.senderName ?? 'U')[0].toUpperCase(),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: senderColor),
                        )
                      : null,
                ),
              )
            else if (!isMe)
              const SizedBox(width: 30),

            if (!isMe) const SizedBox(width: 6),

            // Baloncuk
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                    bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      offset: const Offset(0, 1),
                      blurRadius: 1,
                      color: Colors.black.withOpacity(0.08),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gönderen adı
                    if (showSender && !isMe)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: GestureDetector(
                          onTap: () => _showSenderProfile(message.senderId),
                          child: Text(
                            message.senderName ?? 'Bilinmeyen',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: senderColor,
                            ),
                          ),
                        ),
                      ),

                    // Reply preview
                    if (message.replyToContent != null && message.replyToContent!.isNotEmpty)
                      _buildInlineReply(message, isMe, isDark),

                    // İçerik + saat + tik
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            message.content,
                            style: TextStyle(fontSize: 14.5, color: textColor, height: 1.3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? Colors.white54 : Colors.black38,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 3),
                              _buildTick(message, isReadByAll, isDark),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (isMe) const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  // ─── Inline Reply Preview (baloncuk içinde) ───
  Widget _buildInlineReply(GroupMessage message, bool isMe, bool isDark) {
    final replyColor = isMe
        ? const Color(0xFF025144)
        : (isDark ? const Color(0xFF283540) : const Color(0xFFE8E8E8));
    final barColor = _getSenderColor(message.senderId);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: replyColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.replyToSenderName ?? 'Bilinmeyen',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: barColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    message.replyToContent ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tik İkonu ───
  Widget _buildTick(GroupMessage message, bool isReadByAll, bool isDark) {
    if (message.isFailed) {
      return const Icon(Icons.error_outline, size: 14, color: Colors.red);
    }
    if (message.isSending) {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white54 : Colors.grey),
        ),
      );
    }
    if (isReadByAll) {
      // Tüm üyeler okudu → mavi çift tik
      return Icon(Icons.done_all, size: 16, color: isDark ? const Color(0xFF53BDEB) : const Color(0xFF53BDEB));
    }
    if (message.readByCount > 0) {
      // Bazıları okudu → gri çift tik
      return Icon(Icons.done_all, size: 16, color: isDark ? Colors.white54 : Colors.grey);
    }
    // Hiç kimse okumadı → tek tik
    return Icon(Icons.done, size: 16, color: isDark ? Colors.white54 : Colors.grey);
  }

  // ─── Reply Bar ───
  Widget _buildReplyBar(bool isDark) {
    final reply = _replyToMessage!;
    final senderColor = _getSenderColor(reply.senderId);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C33) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: senderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reply.senderName ?? 'Bilinmeyen',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: senderColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.content,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _cancelReply,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 16, color: isDark ? Colors.white70 : Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Mesaj Input ───
  Widget _buildMessageInput(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1F2C33) : Colors.white,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A3942) : Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                focusNode: _messageFocusNode,
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Mesaj yazın...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
                ),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF00A884),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, color: Colors.white, size: 22),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Boş Durum ───
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chat_bubble_outline, size: 48, color: isDark ? Colors.grey[500] : Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz mesaj yok',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[400] : Colors.grey[700]),
          ),
          const SizedBox(height: 6),
          Text(
            'Sohbeti başlatmak için bir mesaj gönderin',
            style: TextStyle(fontSize: 14, color: isDark ? Colors.grey[500] : Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───
  bool _isSameDay(DateTime d1, DateTime d2) =>
      d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;

  Color _getSenderColor(String senderId) {
    final colors = [
      const Color(0xFF06CF9C), const Color(0xFF25D366), const Color(0xFF53BDEB),
      const Color(0xFFE68B2A), const Color(0xFFE34170), const Color(0xFF7D67D7),
      const Color(0xFF20B2AA), const Color(0xFFFF6B6B),
    ];
    int hash = 0;
    for (int i = 0; i < senderId.length; i++) {
      hash = senderId.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }
}

// ════════════════════════════════════════════════════════════════
// Swipe To Reply Widget
// ════════════════════════════════════════════════════════════════

class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const _SwipeToReply({required this.child, required this.onReply});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragExtent = 0;
  static const double _replyThreshold = 60;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragExtent = (_dragExtent + details.delta.dx).clamp(-_replyThreshold * 1.5, 0);
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragExtent.abs() >= _replyThreshold) {
          widget.onReply();
        }
        setState(() => _dragExtent = 0);
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Reply ikonu
          if (_dragExtent.abs() > 10)
            Positioned(
              left: 8,
              child: Opacity(
                opacity: (_dragExtent.abs() / _replyThreshold).clamp(0, 1),
                child: Transform.scale(
                  scale: (_dragExtent.abs() / _replyThreshold).clamp(0.5, 1.0),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _dragExtent.abs() >= _replyThreshold
                          ? const Color(0xFF00A884)
                          : Colors.grey.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.reply,
                      size: 20,
                      color: _dragExtent.abs() >= _replyThreshold ? Colors.white : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
          // Mesaj
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Kimler Okudu? Bottom Sheet
// ════════════════════════════════════════════════════════════════

class _MessageReadReceiptsSheet extends StatefulWidget {
  final GroupMessage message;
  final GroupChatService groupChatService;
  final String groupId;
  final int totalMembers;

  const _MessageReadReceiptsSheet({
    required this.message,
    required this.groupChatService,
    required this.groupId,
    required this.totalMembers,
  });

  @override
  State<_MessageReadReceiptsSheet> createState() => _MessageReadReceiptsSheetState();
}

class _MessageReadReceiptsSheetState extends State<_MessageReadReceiptsSheet> {
  List<MessageReadReceipt> _receipts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final receipts = await widget.groupChatService.getMessageReadReceipts(widget.message.id);
    if (mounted) {
      setState(() {
        _receipts = receipts;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final readCount = _receipts.length;
    final unreadCount = widget.totalMembers - readCount - 1; // Göndereni hariç tut

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B141A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.done_all,
                      color: readCount > 0 ? const Color(0xFF53BDEB) : Colors.grey,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mesaj Bilgisi',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (!_isLoading)
                            Text(
                              '$readCount kişi okudu${unreadCount > 0 ? ' • $unreadCount bekliyor' : ''}',
                              style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Mesaj önizleme
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2C33) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.message.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(height: 8),

              // Liste
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _receipts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.visibility_off_outlined, size: 44, color: Colors.grey[500]),
                                const SizedBox(height: 10),
                                Text(
                                  'Henüz kimse okumadı',
                                  style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _receipts.length,
                            // ignore: unnecessary_underscores
                            separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.grey[800] : Colors.grey[200]),
                            itemBuilder: (context, index) {
                              final r = _receipts[index];
                              final isSelf = r.userId == currentUserId;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundImage: r.avatarUrl != null ? NetworkImage(r.avatarUrl!) : null,
                                  backgroundColor: Colors.grey[300],
                                  child: r.avatarUrl == null
                                      ? Text(
                                          r.displayName[0].toUpperCase(),
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700]),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  r.displayName + (isSelf ? ' (Siz)' : ''),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                subtitle: Text(
                                  _formatTime(r.readAt),
                                  style: TextStyle(fontSize: 12.5, color: isDark ? Colors.grey[500] : Colors.grey[600]),
                                ),
                                trailing: Icon(Icons.done_all, size: 16, color: const Color(0xFF53BDEB)),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    if (diff.inDays == 1) return 'Dün ${DateFormat.Hm().format(t)}';
    return DateFormat('dd MMM HH:mm').format(t);
  }
}
