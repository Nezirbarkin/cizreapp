// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/ai_quick_prompt_model.dart';
import '../theme/ai_chat_theme.dart';
import '../widgets/ai_message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../services/ai_chat_service.dart';
import 'ai_chat_list_screen.dart';

/// CizreApp AI Sohbet Ekranı
/// Meta AI tarzı modern tasarım
class AIMetaScreen extends StatefulWidget {
  final String? conversationId;

  const AIMetaScreen({super.key, this.conversationId});

  @override
  State<AIMetaScreen> createState() => _AIMetaScreenState();
}

class _AIMetaScreenState extends State<AIMetaScreen> with TickerProviderStateMixin {
  final AIChatService _service = AIChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isSending = false;
  String _userName = '';
  String _greeting = '';
  List<AIQuickPrompt> _quickPrompts = [];
  List<Map<String, dynamic>> _messages = [];

  List<Map<String, dynamic>> _pendingImages = [];

  // Animasyonlar
  late AnimationController _logoController;
  late Animation<double> _logoAnimation;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _logoAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prompts = await _service.getActiveQuickPrompts();
      await _loadUserName();

      if (mounted) {
        setState(() {
          _quickPrompts = prompts;
          _greeting = _getGreeting();
          _isLoading = false;
        });
        _logoController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUserName() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, username')
          .eq('id', userId)
          .maybeSingle();

      if (mounted && profile != null) {
        setState(() {
          _userName = (profile['full_name'] as String?)?.isNotEmpty == true
              ? profile['full_name'] as String
              : (profile['username'] as String?) ?? '';
        });
      }
    } catch (_) {}
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    String timeGreeting;

    if (hour < 12) {
      timeGreeting = 'Günaydın';
    } else if (hour < 18) {
      timeGreeting = 'İyi günler';
    } else {
      timeGreeting = 'İyi akşamlar';
    }

    if (_userName.isNotEmpty) {
      return '$timeGreeting $_userName';
    }
    return timeGreeting;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _canSend =>
      !_isSending &&
      (_messageController.text.trim().isNotEmpty || _pendingImages.isNotEmpty);

  // Görsel seç
  Future<void> _pickImage(ImageSource source) async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );

      if (xFile != null && mounted) {
        setState(() {
          _pendingImages.add({
            'file': xFile,
            'path': xFile.path,
          });
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resim seçilemedi: $e')),
        );
      }
    }
  }

  // Ek seçeneklerini göster
  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Ekle',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Seçenekler
              _buildOptionTile(
                icon: Icons.photo_outlined,
                title: 'Galeriden Resim',
                color: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              _buildOptionTile(
                icon: Icons.camera_alt_outlined,
                title: 'Kamera ile Çek',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Kullanıcı mesajını ekle
    final userMsg = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'content': text,
      'role': 'user',
      'createdAt': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(userMsg);
      _isSending = true;
      _messageController.clear();
      _pendingImages.clear();
    });
    _scrollToBottom();

    try {
      final response = await _service.sendTextMessage(
        conversationId: widget.conversationId,
        message: text,
      );

      if (mounted) {
        // Kullanıcı mesajını güncelle
        final msgIndex = _messages.indexWhere((m) => m['id'] == userMsg['id']);
        if (msgIndex >= 0) {
          _messages[msgIndex] = {
            'id': response.userMessageId,
            'content': text,
            'role': 'user',
            'createdAt': DateTime.now().toIso8601String(),
          };
        }

        // AI yanıtını ekle
        _messages.add({
          'id': response.assistantMessageId,
          'content': response.assistantContent,
          'role': 'assistant',
          'createdAt': DateTime.now().toIso8601String(),
        });

        setState(() => _isSending = false);
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        _messages.add({
          'id': 'error_${DateTime.now().millisecondsSinceEpoch}',
          'content': 'Hata: $e',
          'role': 'assistant',
          'isError': true,
          'createdAt': DateTime.now().toIso8601String(),
        });
        _scrollToBottom();
      }
    }
  }

  void _selectPrompt(AIQuickPrompt prompt) {
    _messageController.text = prompt.prompt;
    _sendMessage();
  }

  // Geçmiş sohbetler ekranını aç
  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AIChatListScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Meta AI koyu tema renkleri
    const backgroundColor = Color(0xFF121212);
    const surfaceColor = Color(0xFF1E1E1E);
    const cardColor = Color(0xFF2C2C2C);
    const primaryPurple = Color(0xFF8B5CF6);
    const primaryPink = Color(0xFFEC4899);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // CizreApp AI Logo
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [primaryPurple, primaryPink],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'CizreApp AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          // Saat - tıklandığında geçmiş sohbetler
          IconButton(
            icon: const Icon(Icons.access_time, color: Colors.white),
            tooltip: 'Geçmiş Sohbetler',
            onPressed: _openHistory,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primaryPurple),
            )
          : Column(
              children: [
                // Ana içerik
                Expanded(
                  child: _messages.isEmpty
                      ? _buildWelcomeView(
                          backgroundColor: backgroundColor,
                          surfaceColor: surfaceColor,
                          cardColor: cardColor,
                          primaryPurple: primaryPurple,
                          primaryPink: primaryPink,
                        )
                      : _buildMessageList(),
                ),
                // Bekleyen görseller
                if (_pendingImages.isNotEmpty) _buildPendingImages(),
                // Mesaj giriş alanı
                _buildInputBar(
                  surfaceColor: surfaceColor,
                  primaryPurple: primaryPurple,
                ),
              ],
            ),
    );
  }

  /// Bekleyen görselleri göster
  Widget _buildPendingImages() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        itemBuilder: (context, index) {
          final image = _pendingImages[index];
          return Stack(
            children: [
              Container(
                width: 70,
                height: 70,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: FileImage(File(image['path'])),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _pendingImages.removeAt(index);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// CizreApp AI Hoşgeldin Görünümü
  Widget _buildWelcomeView({
    required Color backgroundColor,
    required Color surfaceColor,
    required Color cardColor,
    required Color primaryPurple,
    required Color primaryPink,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // AI Logo - Animasyonlu
          AnimatedBuilder(
            animation: _logoAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _logoAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [primaryPurple, primaryPink],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: primaryPurple.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Hoşgeldin mesajı
          Text(
            _greeting,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Öneri Kartları
          if (_quickPrompts.isNotEmpty)
            _buildSuggestionGrid(
              cardColor: cardColor,
              primaryPurple: primaryPurple,
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Öneri Kartları Grid
  Widget _buildSuggestionGrid({
    required Color cardColor,
    required Color primaryPurple,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Size nasıl yardımcı olabilirim?',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.8,
          ),
          itemCount: _quickPrompts.length.clamp(0, 6),
          itemBuilder: (context, index) {
            final prompt = _quickPrompts[index];
            return _buildSuggestionCard(
              prompt: prompt,
              cardColor: cardColor,
              primaryPurple: primaryPurple,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSuggestionCard({
    required AIQuickPrompt prompt,
    required Color cardColor,
    required Color primaryPurple,
  }) {
    final baseColor = AIQuickPrompt.getColorFromString(
      prompt.thumbnailColor ?? '#8B5CF6',
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectPrompt(prompt),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                AIQuickPrompt.getIconData(prompt.icon) ?? Icons.lightbulb_outline,
                color: baseColor,
                size: 20,
              ),
              const Spacer(),
              Text(
                prompt.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mesaj Listesi
  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isSending && index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.only(left: 16, top: 8),
            child: TypingIndicator(),
          );
        }

        final msg = _messages[index];
        final isUser = msg['role'] == 'user';
        final isError = msg['isError'] == true;

        return AIMessageBubble(
          message: msg['content'] as String,
          isUser: isUser,
          onCopy: isError ? null : () {},
        );
      },
    );
  }

  /// Mesaj Giriş Alanı - WhatsApp Tarzı
  Widget _buildInputBar({
    required Color surfaceColor,
    required Color primaryPurple,
  }) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          top: BorderSide(color: Color(0xFF333333)),
        ),
      ),
      child: Row(
        children: [
          // Emoji butonu
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white54),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Emoji özelliği yakında eklenecek')),
              );
            },
          ),

          // Mesaj giriş alanı
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Mesaj yazın...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onChanged: (value) => setState(() {}),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),

          const SizedBox(width: 4),

          // Ataç butonu - çalışıyor
          IconButton(
            icon: const Icon(Icons.attach_file, color: Colors.white54),
            onPressed: _showAttachmentSheet,
          ),

          // Kamera butonu - çalışıyor
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.white54),
            onPressed: () => _showAttachmentSheet(),
          ),

          // Gönder/Mikrofon butonu - çalışıyor
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF00A884),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _canSend ? Icons.send : Icons.mic,
                color: Colors.white,
                size: 20,
              ),
              onPressed: _canSend ? _sendMessage : null,
            ),
          ),
        ],
      ),
    );
  }
}
