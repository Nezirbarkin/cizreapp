// Admin Destek Talebi Detay Dialog Widget
// Bu dosya admin_dashboard_screen.dart'dan ayrıştırılmıştır

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin Destek Talebi Detay Dialog Widget
/// Destek taleplerini görüntüleme ve yanıtlama işlevselliği sağlar
class AdminTicketDetailDialog extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onUpdate;

  const AdminTicketDetailDialog({
    super.key,
    required this.ticket,
    required this.onUpdate,
  });

  @override
  State<AdminTicketDetailDialog> createState() => AdminTicketDetailDialogState();
}

class AdminTicketDetailDialogState extends State<AdminTicketDetailDialog> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String _selectedStatus = 'open';
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.ticket['status'] ?? 'open';
    _loadMessages();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    final ticketId = widget.ticket['id'].toString();
    _messagesChannel = Supabase.instance.client
        .channel('admin_ticket_messages_$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_ticket_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: ticketId,
          ),
          callback: (payload) {
            final newMessage = payload.newRecord;
            setState(() {
              _messages.add(newMessage);
            });
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final ticketId = widget.ticket['id'].toString();
      final response = await Supabase.instance.client
          .from('support_ticket_messages')
          .select()
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: true);
      
      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Mesajlar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'open':
        return 'Açık';
      case 'in_progress':
        return 'İşleniyor';
      case 'resolved':
        return 'Çözüldü';
      case 'closed':
        return 'Kapalı';
      default:
        return 'Bilinmiyor';
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '-';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inMinutes < 1) {
        return 'Az önce';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} dakika önce';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} saat önce';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} gün önce';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return '-';
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    
    final message = _messageController.text.trim();
    _messageController.clear();
    
    try {
      final ticketId = widget.ticket['id'].toString();
      final adminId = Supabase.instance.client.auth.currentUser?.id;
      
      await Supabase.instance.client
          .from('support_ticket_messages')
          .insert({
            'ticket_id': ticketId,
            'sender_id': adminId,
            'sender_type': 'admin',
            'message': message,
          });
      
      // Kullanıcıya bildirim gönder
      if (widget.ticket['user_id'] != null) {
        final shortMessage = message.length > 50
            ? '${message.substring(0, 50)}...'
            : message;
        
        await Supabase.instance.client.from('notifications').insert({
          'user_id': widget.ticket['user_id'],
          'type': 'support_response',
          'title': 'Destek Talebinize Yanıt Geldi',
          'content': 'Destek talebinize admin yanıt verdi: $shortMessage',
          'entity_id': widget.ticket['id'].toString(),
          'is_read': false,
        });
      }
    } catch (e) {
      debugPrint('Mesaj gönderilirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await Supabase.instance.client
          .from('support_tickets')
          .update({'status': newStatus, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', widget.ticket['id']);
      
      setState(() {
        _selectedStatus = newStatus;
      });
      
      // Kullanıcıya bildirim gönder
      if (widget.ticket['user_id'] != null) {
        await Supabase.instance.client.from('notifications').insert({
          'user_id': widget.ticket['user_id'],
          'type': 'support_status',
          'title': 'Destek Talebi Durumu Güncellendi',
          'content': 'Destek talebinizin durumu "${_getStatusText(newStatus)}" olarak güncellendi.',
          'entity_id': widget.ticket['id'].toString(),
          'is_read': false,
        });
      }
      
      widget.onUpdate();
    } catch (e) {
      debugPrint('Durum güncellenirken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.support_agent, size: 28, color: Colors.purple),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ticket['subject'] ?? 'Destek Talebi',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '#${widget.ticket['id']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(_selectedStatus).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getStatusColor(_selectedStatus),
                      width: 1,
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedStatus,
                    style: TextStyle(
                      color: _getStatusColor(_selectedStatus),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    underline: const SizedBox.shrink(),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: _getStatusColor(_selectedStatus),
                      size: 20,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('Açık')),
                      DropdownMenuItem(value: 'in_progress', child: Text('İşleniyor')),
                      DropdownMenuItem(value: 'resolved', child: Text('Çözüldü')),
                      DropdownMenuItem(value: 'closed', child: Text('Kapalı')),
                    ],
                    onChanged: (value) {
                      if (value != null && value != _selectedStatus) {
                        _updateStatus(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            
            const Divider(height: 24),
            
            // User Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.ticket['user_email'] ?? 'Bilinmeyen Kullanıcı',
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(widget.ticket['created_at']),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Messages List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                   size: 48,
                                   color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'Henüz mesaj yok',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'İlk mesajı gönderin',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isAdmin = message['sender_type'] == 'admin';
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: isAdmin
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isAdmin) ...[
                                        const Icon(Icons.person,
                                                  size: 14,
                                                  color: Colors.grey),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        isAdmin ? 'Admin' : 'Kullanıcı',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isAdmin
                                              ? Colors.purple
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                      if (isAdmin) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.support_agent,
                                                  size: 14,
                                                  color: Colors.purple),
                                      ],
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatDate(message['created_at']),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 300,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isAdmin
                                          ? Colors.purple.shade100
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      message['message'] ?? '',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            
            const Divider(),
            
            // Message Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Colors.purple, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
