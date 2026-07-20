// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/ai_conversation_model.dart';
import '../services/ai_chat_service.dart';
import 'ai_chat_meta_screen.dart';

/// AI sohbetleri listesi ekranı.
///
/// Yeni sohbet başlatma butonu + geçmiş sohbetler listesi.
class AIChatListScreen extends StatefulWidget {
  const AIChatListScreen({super.key});

  @override
  State<AIChatListScreen> createState() => _AIChatListScreenState();
}

class _AIChatListScreenState extends State<AIChatListScreen> {
  final AIChatService _service = AIChatService();
  List<AIConversation> _conversations = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _includeArchived = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final conversations = await _service.getConversations(includeArchived: _includeArchived);
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sohbetler yüklenemedi: $e')),
        );
      }
    }
  }

  List<AIConversation> get _filteredConversations {
    if (_searchQuery.isEmpty) return _conversations;
    final q = _searchQuery.toLowerCase();
    return _conversations.where((c) {
      final title = c.displayTitle.toLowerCase();
      return title.contains(q);
    }).toList();
  }

  void _startNewChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AIMetaScreen(conversationId: null),
      ),
    ).then((_) => _loadConversations());
  }

  void _openConversation(AIConversation conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIMetaScreen(conversationId: conversation.id),
      ),
    ).then((_) => _loadConversations());
  }

  Future<void> _deleteConversation(AIConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sohbeti Sil'),
        content: const Text('Bu sohbeti kalıcı olarak silmek istediğinize emin misiniz? Tüm mesajlar silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteConversation(conversation.id);
      if (mounted) {
        setState(() => _conversations.removeWhere((c) => c.id == conversation.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sohbet silindi'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silme hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                ),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('CizreApp AI'),
          ],
        ),
        backgroundColor: const Color(0xFF6C5CE7),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(_includeArchived ? Icons.archive : Icons.archive_outlined),
            tooltip: 'Arşivlenmişler',
            onPressed: () {
              setState(() => _includeArchived = !_includeArchived);
              _loadConversations();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _loadConversations,
          ),
        ],
      ),
      body: Column(
        children: [
          // Yeni sohbet CTA
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _buildNewChatButton(theme),
          ),
          // Arama
          if (_conversations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Sohbetlerde ara...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDarkMode ? Colors.grey[800] : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          const SizedBox(height: 8),
          // Liste
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _hasError && _conversations.isEmpty
                    ? _buildErrorState(theme)
                    : _conversations.isEmpty
                        ? _buildEmptyState(theme)
                        : RefreshIndicator(
                        onRefresh: _loadConversations,
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _filteredConversations.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final conv = _filteredConversations[index];
                            return _buildConversationTile(conv, theme, isDarkMode);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewChatButton(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C5CE7).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _startNewChat,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.add_circle, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Yeni Sohbet Başlat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Soru sor, resim üret veya sohbet et',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversationTile(AIConversation conv, ThemeData theme, bool isDarkMode) {
    return Dismissible(
      key: Key(conv.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _deleteConversation(conv);
        return true;
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
            ),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
        ),
        title: Text(
          conv.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                conv.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
            if (conv.isArchived) ...[
              const SizedBox(width: 8),
              Icon(Icons.archive, size: 14, color: Colors.grey.shade400),
            ],
          ],
        ),
        trailing: Text(
          _formatDate(conv.lastMessageAt),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
        onTap: () => _openConversation(conv),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Sohbetler yüklenemedi', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Bağlantınızı kontrol edip tekrar deneyin.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadConversations,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
                ),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 50),
            ),
            const SizedBox(height: 24),
            const Text(
              'Henüz Sohbet Yok',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Soru sorun, resim üretin veya sohbet ederek başlayın.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _startNewChat,
              icon: const Icon(Icons.add),
              label: const Text('Yeni Sohbet'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _providerColor(String provider) {
    switch (provider.toLowerCase()) {
      case 'gemini':
        return Colors.blue.shade700;
      case 'groq':
        return Colors.orange.shade700;
      case 'openrouter':
        return Colors.purple.shade700;
      case 'openai':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inHours < 1) return '${diff.inMinutes} dk';
    if (diff.inDays < 1) return '${diff.inHours} sa';
    if (diff.inDays == 1) return 'Dün';
    if (diff.inDays < 7) return '${diff.inDays} gün';
    return '${date.day}.${date.month}.${date.year}';
  }
}