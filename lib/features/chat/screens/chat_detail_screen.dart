// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/message_model.dart';
import '../../../core/models/post_model.dart';
import '../services/chat_service.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../social/screens/post_detail_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> with WidgetsBindingObserver {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isInitialLoad = true; // İlk yükleme flag'i - jumpTo için
  RealtimeChannel? _messagesChannel;
  final Map<String, bool> _pendingMessages = {}; // Temp ID -> bool (isFailed)
  String? _currentUserId; // Cache current user ID
  bool _isAtBottom = true; // Kullanıcı en altta mı?
  DateTime? _lastReadTime; // Son okundu işaretleme zamanı (debounce)
  
  // Yanıt özelliği için
  Message? _replyToMessage;
  final FocusNode _messageFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _markSenderMessagesAsRead();
    _loadMessages();
    _subscribeToMessages();
    // Mesajları okundu olarak işaretle (bana gelen mesajlar)
    _chatService.markMessagesAsRead(widget.conversationId);
    
    // Scroll pozisyonunu takip et
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // En alt 50px içindeyse "en altta" say
    _isAtBottom = (maxScroll - currentScroll) < 50;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama ön plana geldiğinde mesajları okundu işaretle
    if (state == AppLifecycleState.resumed && mounted) {
      _chatService.markMessagesAsRead(widget.conversationId);
      _chatService.markSenderMessagesAsRead(widget.conversationId);
    }
  }

  /// Karşı tarafın gönderdiği mesajları okundu olarak işaretle
  /// (Benim mesajlarımın okundu olduğunu göstermek için)
  Future<void> _markSenderMessagesAsRead() async {
    await _chatService.markSenderMessagesAsRead(widget.conversationId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _messagesChannel?.unsubscribe();
    super.dispose();
  }
  
  /// Yanıtlanacak mesajı ayarla
  void _setReply(Message message) {
    setState(() {
      _replyToMessage = message;
    });
    _messageFocusNode.requestFocus();
  }
  
  /// Yanıtı iptal et
  void _cancelReply() {
    setState(() {
      _replyToMessage = null;
    });
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final messages = await _chatService.getMessages(widget.conversationId);
    if (mounted) {
      setState(() {
        _messages = messages;
        _isLoading = false;
        _isInitialLoad = true; // İlk yükleme - jumpTo kullanılacak
      });
      _scrollToBottom();
    }
  }

  void _subscribeToMessages() {
    _messagesChannel = _chatService.subscribeToMessagesChannel(
      widget.conversationId,
      (messages) {
        if (mounted) {
          // DÜZELTME: Önceki kontrol sadece mesaj sayısını ve son ID'yi kontrol ediyordu,
          // bu yüzden is_read değişse bile UI güncellenmiyordu. Artık içerik (ID + is_read)
          // bazında karşılaştırma yapıyoruz.
          bool hasChanged = _messages.length != messages.length;
          if (!hasChanged) {
            // Her mesajı karşılaştır: ID ve is_read
            for (int i = 0; i < _messages.length && i < messages.length; i++) {
              if (_messages[i].id != messages[i].id ||
                  _messages[i].isRead != messages[i].isRead) {
                hasChanged = true;
                break;
              }
            }
          }
          if (!hasChanged) return; // Değişiklik yoksa gereksiz rebuild'i önle
          
          setState(() {
            _messages = messages;
          });
          // Sadece kullanıcı en alttaysa scroll yap
          if (_isAtBottom) {
            _scrollToBottom();
          }
          // Okundu işaretle - debounce ile (her değişiklikte değil)
          final now = DateTime.now();
          if (_lastReadTime == null || now.difference(_lastReadTime!).inSeconds >= 2) {
            _lastReadTime = now;
            _chatService.markMessagesAsRead(widget.conversationId);
          }
        }
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
          // Sonraki mesajlarda animasyonlu scroll - sadece kullanıcı en alttaysa
          if (_isAtBottom) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        }
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    if (_currentUserId == null) {
      _currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (_currentUserId == null) return;
    }

    setState(() => _isSending = true);
    _messageController.clear();

    // Yanıt bilgilerini al
    final replyToId = _replyToMessage?.id;
    final replyToContent = _replyToMessage?.content;
    final replyToSenderName = _replyToMessage?.senderId == _currentUserId
        ? 'Sen'
        : widget.otherUserName;

    // Optimistic: Geçici mesaj ekle
    final tempMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: widget.conversationId,
      senderId: _currentUserId!,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isSending: true,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
    );

    setState(() {
      _messages.add(tempMessage);
      _pendingMessages[tempMessage.id] = false; // Failed değil
      _replyToMessage = null; // Yanıtı temizle
    });
    _scrollToBottom();

    // Mesajı gönder
    final message = await _chatService.sendMessage(
      conversationId: widget.conversationId,
      content: content,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        
        if (message != null) {
          // Temp mesajı gerçek mesajla değiştir
          final index = _messages.indexWhere((m) => m.id == tempMessage.id);
          if (index != -1) {
            _messages[index] = message;
          }
          _pendingMessages.remove(tempMessage.id);
        } else {
          // Hata durumunda temp mesajı failed yap
          final index = _messages.indexWhere((m) => m.id == tempMessage.id);
          if (index != -1) {
            _messages[index] = tempMessage.copyWith(isFailed: true, isSending: false);
            _pendingMessages[tempMessage.id] = true;
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mesaj gönderilemedi. İnternet bağlantınızı kontrol edin.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cache current user ID if not set
    _currentUserId ??= Supabase.instance.client.auth.currentUser?.id;
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        title: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(userId: widget.otherUserId),
              ),
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withOpacity(0.2),
                backgroundImage: widget.otherUserAvatar != null
                    ? NetworkImage(widget.otherUserAvatar!)
                    : null,
                child: widget.otherUserAvatar == null
                    ? Text(
                        widget.otherUserName.isNotEmpty
                            ? widget.otherUserName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.otherUserName,
                  style: const TextStyle(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Mesajlar listesi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : _buildOptimizedMessageList(),
          ),

          // Mesaj gönderme alanı - SafeArea ile cihazın alt navigasyon barı için padding ekle
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: const [
                  BoxShadow(
                    offset: Offset(0, -2),
                    blurRadius: 8,
                    color: Color(0x0D000000), // Siyah %5 opacity
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Yanıt gösterimi
                  if (_replyToMessage != null) _buildReplyPreview(),
                  
                  // Mesaj gönderme alanı
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: _messageController,
                              focusNode: _messageFocusNode,
                              decoration: const InputDecoration(
                                hintText: 'Mesaj yazın...',
                                border: InputBorder.none,
                              ),
                              maxLines: null,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.deepPurple,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: _isSending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send, color: Colors.white),
                            onPressed: _isSending ? null : _sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Optimizasyonlu mesaj listesi - gereksiz rebuild'leri önler
  Widget _buildOptimizedMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length,
      // PERFORMANCE: Cache ve repaint optimizasyonları
      cacheExtent: 300.0, // Ekran dışında 300px cache
      addRepaintBoundaries: true, // Gereksiz repaint'leri önle
      addAutomaticKeepAlives: false, // Bellek tasarrufu için kapat
      itemBuilder: (context, index) {
        // PERFORMANCE: RepaintBoundary ile sar
        return RepaintBoundary(
          child: Hero(
            tag: 'msg_${_messages[index].id}',
            child: Material(
              type: MaterialType.transparency,
              child: _buildMessageItem(index),
            ),
          ),
        );
      },
    );
  }

  /// Performans için mesaj öğesi oluşturucu
  Widget _buildMessageItem(int index) {
    final message = _messages[index];
    final isMe = message.senderId == _currentUserId;
    final showDate = index == 0 ||
        !_isSameDay(
          _messages[index - 1].createdAt,
          message.createdAt,
        );

    return Column(
      children: [
        if (showDate) _buildDateDivider(message.createdAt),
        _buildMessageBubble(message, isMe),
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
            'Henüz mesaj yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'İlk mesajı göndererek sohbete başlayın',
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

  Widget _buildDateDivider(DateTime date) {
    // Türkiye saati (UTC+3)
    const turkeyOffset = Duration(hours: 3);
    final turkeyDate = date.toUtc().add(turkeyOffset);
    final now = DateTime.now().toUtc().add(turkeyOffset);
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(turkeyDate.year, turkeyDate.month, turkeyDate.day);
    
    String dateText;
    if (messageDate == today) {
      dateText = 'Bugün';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      dateText = 'Dün';
    } else {
      final day = turkeyDate.day.toString().padLeft(2, '0');
      final month = turkeyDate.month.toString().padLeft(2, '0');
      dateText = '$day.$month.${turkeyDate.year}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              dateText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    // DEBUG: Okundu durumu detaylı log
    debugPrint('🔵 _buildMessageBubble: isMe=$isMe isRead=${message.isRead} messageStatus=${message.messageStatus} senderId=${message.senderId.substring(0, 8)}...');
    
    // PERFORMANCE: TimeOfDay yerine direkt hesaplama (daha hafif)
    final turkeyTime = message.createdAt.toUtc().add(const Duration(hours: 3));
    final timeString = '${turkeyTime.hour.toString().padLeft(2, '0')}:${turkeyTime.minute.toString().padLeft(2, '0')}';

    // Paylaşılan gönderi mi kontrol et
    if (message.isSharedPost) {
      return _buildSharedPostBubble(message, isMe, timeString);
    }

    // PERFORMANCE: MediaQuery'i bir kez al
    final screenWidth = MediaQuery.of(context).size.width;
    // PERFORMANCE: Renk ve stil değerlerini önceden hesapla (withOpacity tekrarlarını önle)
    final bubbleColor = isMe ? Colors.deepPurple : Colors.white;
    final textColor = isMe ? Colors.white : Colors.grey[900]!;
    final timeColor = isMe ? Colors.white70 : Colors.grey[600]!;
    
    // Yanıt gösterimi için
    final hasReply = message.replyToId != null;

    // Sağa kaydırarak yanıtla - Dismissible yerine GestureDetector ile swipe
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          // Sola doğru hızlı kaydırma = yanıtla
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            _setReply(message);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: screenWidth * 0.75,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
            ),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 1),
                blurRadius: 2,
                color: Color(0x1A000000), // Siyah %10 opacity (withOpacity yerine)
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Yanıt gösterimi (varsa)
              if (hasReply) ...[
                Container(
                  padding: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: isMe ? Colors.white54 : Colors.deepPurple.shade300,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.replyToSenderName ?? 'Yanıt',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isMe ? Colors.white70 : Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message.replyToContent ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: isMe ? Colors.white60 : Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Text(
                message.content,
                style: TextStyle(
                  fontSize: 15,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeString,
                    style: TextStyle(
                      fontSize: 11,
                      color: timeColor,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildMessageStatusIcon(message.messageStatus, isMe: isMe),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Yanıt önizlemesi göster
  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          left: BorderSide(
            color: Colors.deepPurple.shade300,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyToMessage?.senderId == _currentUserId
                      ? 'Kendinize yanıt'
                      : 'Yanıt',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade300,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyToMessage?.content ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.grey[600], size: 20),
            onPressed: _cancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// WhatsApp benzeri mesaj durumu ikonu
  Widget _buildMessageStatusIcon(String status, {required bool isMe}) {
    // DEBUG: Okundu durumu logla
    debugPrint('🔔 _buildMessageStatusIcon: status=$status isMe=$isMe');
    
    switch (status) {
      case 'failed':
        return const Icon(
          Icons.error_outline,
          size: 16,
          color: Colors.red,
        );
      case 'sending':
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        );
      case 'sent':
        return const Icon(
          Icons.done_all,
          size: 16,
          color: Colors.white70,
        );
      case 'read':
        return const Icon(
          Icons.done_all,
          size: 16,
          color: Color(0xFF4FC3F7), // Açık mavi (görüldü)
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// Paylaşılan gönderi için özel bubble
  Widget _buildSharedPostBubble(Message message, bool isMe, String timeString) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, 1),
              blurRadius: 4,
              color: Colors.black.withOpacity(0.1),
            ),
          ],
        ),
        child: InkWell(
          onTap: () async {
            // Gönderi detayına git
            if (message.sharedPostId != null) {
              // Gönderiyi veritabanından al
              try {
                final postData = await Supabase.instance.client
                    .from('posts')
                    .select('*')
                    .eq('id', message.sharedPostId!)
                    .maybeSingle();
                
                if (postData != null && mounted) {
                  final post = Post.fromJson(postData);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostDetailScreen(post: post),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Gönderi yüklenirken hata: $e');
              }
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gönderi başlığı
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.article, size: 16, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    const Text(
                      'Paylaşılan Gönderi',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),
              // Gönderi içeriği
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.sharedPostAuthorName != null) ...[
                      Text(
                        message.sharedPostAuthorName!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (message.sharedPostContent != null && message.sharedPostContent!.isNotEmpty)
                      Text(
                        message.sharedPostContent!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[800],
                        ),
                      ),
                    if (message.sharedPostImageUrl != null && message.sharedPostImageUrl!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          message.sharedPostImageUrl!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox.shrink(); // Resim yüklenemezse gizle
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Alt bilgi (zaman + tik)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeString,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildMessageStatusIconForSharedPost(message.messageStatus),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Paylaşılan gönderi için mesaj durumu ikonu (arka plan beyaz olduğu için farklı renkler)
  Widget _buildMessageStatusIconForSharedPost(String status) {
    switch (status) {
      case 'failed':
        return const Icon(
          Icons.error_outline,
          size: 14,
          color: Colors.red,
        );
      case 'sending':
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        );
      case 'sent':
        return const Icon(
          Icons.done_all,
          size: 14,
          color: Colors.grey,
        );
      case 'read':
        return const Icon(
          Icons.done_all,
          size: 14,
          color: Color(0xFF4FC3F7), // Açık mavi (görüldü)
        );
      default:
        return const SizedBox.shrink();
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
