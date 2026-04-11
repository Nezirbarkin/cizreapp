// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../services/profile_service.dart';
import '../../../core/providers/theme_provider.dart';

class SupportCenterScreen extends StatefulWidget {
  const SupportCenterScreen({super.key});

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _profileService = ProfileService();
  List<Map<String, dynamic>> _myTickets = [];
  List<Map<String, dynamic>> _faqs = [];
  bool _isLoadingTickets = true;
  bool _isLoadingFAQs = true;
  
  // Yeni talep formu için state
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  String _selectedCategory = 'general';
  List<XFile> _selectedImages = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final tabCount = userId == null ? 1 : 3; // Misafir için sadece 1 tab (SSS)
    _tabController = TabController(length: tabCount, vsync: this);
    _loadFAQs();
    if (userId != null) {
      _loadMyTickets(); // Sadece giriş yapanlar için
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMyTickets() async {
    setState(() => _isLoadingTickets = true);
    try {
      final tickets = await _profileService.getUserSupportTickets();
      setState(() {
        _myTickets = tickets;
        _isLoadingTickets = false;
      });
    } catch (e) {
      debugPrint('Destek talepleri yüklenemedi: $e');
      setState(() => _isLoadingTickets = false);
    }
  }

  Future<void> _loadFAQs() async {
    setState(() => _isLoadingFAQs = true);
    try {
      final faqs = await _profileService.getFAQs();
      setState(() {
        _faqs = faqs;
        _isLoadingFAQs = false;
      });
    } catch (e) {
      debugPrint('SSS yüklenemedi: $e');
      setState(() => _isLoadingFAQs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final isGuest = userId == null;
    
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: themeProvider.primaryColor,
        elevation: 0,
        title: const Text(
          'Destek Merkezi',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: isGuest
            ? const [Tab(text: 'SSS')]
            : const [
                Tab(text: 'SSS'),
                Tab(text: 'Taleplerim'),
                Tab(text: 'Yeni Talep'),
              ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: isGuest
          ? [_buildFAQTab()]
          : [
              _buildFAQTab(),
              _buildMyTicketsTab(),
              _buildNewTicketTab(),
            ],
      ),
    );
  }

  Widget _buildFAQTab() {
    if (_isLoadingFAQs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_faqs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.help_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Henüz SSS bulunmuyor',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _faqs.length,
      itemBuilder: (context, index) {
        final faq = _faqs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(
              faq['question'] ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  faq['answer'] ?? '',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyTicketsTab() {
    if (_isLoadingTickets) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_myTickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Henüz destek talebiniz yok',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyTickets,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myTickets.length,
        itemBuilder: (context, index) {
          final ticket = _myTickets[index];
          final status = ticket['status'] ?? 'open';
          final createdAt = DateTime.parse(ticket['created_at']);
          
          Color statusColor;
          String statusText;
          switch (status) {
            case 'open':
              statusColor = Colors.orange;
              statusText = 'Beklemede';
              break;
            case 'in_progress':
              statusColor = Colors.blue;
              statusText = 'İnceleniyor';
              break;
            case 'resolved':
              statusColor = Colors.green;
              statusText = 'Çözüldü';
              break;
            case 'closed':
              statusColor = Colors.grey;
              statusText = 'Kapatıldı';
              break;
            default:
              statusColor = Colors.grey;
              statusText = 'Bilinmiyor';
          }

          return InkWell(
            onTap: () => _openTicketDetail(ticket),
            borderRadius: BorderRadius.circular(12),
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket['subject'] ?? 'Konu Yok',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      ticket['message'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDate(createdAt),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewTicketTab() {
    return SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).padding.bottom + 20, // Alt bar için padding
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          const Text(
            'Destek Talebi Oluştur',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sorunuz veya probleminiz hakkında detaylı bilgi verin',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          
          // Kategori
          const Text(
            'Kategori',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _selectedCategory,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            items: const [
              DropdownMenuItem(value: 'general', child: Text('Genel')),
              DropdownMenuItem(value: 'account', child: Text('Hesap Sorunu')),
              DropdownMenuItem(value: 'payment', child: Text('Ödeme Sorunu')),
              DropdownMenuItem(value: 'order', child: Text('Sipariş Sorunu')),
              DropdownMenuItem(value: 'technical', child: Text('Teknik Sorun')),
              DropdownMenuItem(value: 'other', child: Text('Diğer')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCategory = value);
              }
            },
          ),
          
          const SizedBox(height: 20),
          
          // Konu
          const Text(
            'Konu',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _subjectController,
            decoration: InputDecoration(
              hintText: 'Kısa bir başlık yazın',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Mesaj
          const Text(
            'Mesajınız',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'Sorununuzu detaylı olarak açıklayın...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Görsel Ekleme
          const Text(
            'Görseller (Opsiyonel)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                if (_selectedImages.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(
                                  image: FileImage(File(_selectedImages[index].path)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedImages.removeAt(index);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                if (_selectedImages.isNotEmpty) const SizedBox(height: 12),
                if (_selectedImages.length < 5)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final images = await picker.pickMultiImage(
                        maxWidth: 1920,
                        maxHeight: 1080,
                        imageQuality: 85,
                      );
                      if (images.isNotEmpty) {
                        setState(() {
                          _selectedImages.addAll(images.take(5 - _selectedImages.length));
                        });
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate),
                    label: Text(
                      _selectedImages.isEmpty
                          ? 'Görsel Ekle (Maks. 5)'
                          : 'Daha Fazla Ekle (${5 - _selectedImages.length} kaldı)',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 40),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Sorunla ilgili ekran görüntüsü veya fotoğraf ekleyebilirsiniz',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Gönder Butonu
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : () async {
                debugPrint('Talep Oluştur butonuna tıklandı');
                
                if (_subjectController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen konu başlığı girin')),
                  );
                  return;
                }
                
                if (_messageController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen mesajınızı yazın')),
                  );
                  return;
                }

                setState(() => _isSubmitting = true);

                try {
                  debugPrint('Destek talebi gönderiliyor...');
                  final success = await _profileService.createSupportTicket(
                    subject: _subjectController.text.trim(),
                    category: _selectedCategory,
                    message: _messageController.text.trim(),
                  );

                  debugPrint('Destek talebi sonucu: $success');

                  if (success && mounted) {
                    _subjectController.clear();
                    _messageController.clear();
                    setState(() {
                      _selectedCategory = 'general';
                      _selectedImages.clear();
                    });
                    
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Destek talebiniz başarıyla oluşturuldu'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    
                    _tabController.animateTo(1); // Taleplerim tab'ına geç
                    await _loadMyTickets();
                  } else {
                    throw Exception('Talep oluşturulamadı');
                  }
                } catch (e) {
                  debugPrint('Destek talebi hatası: $e');
                  if (mounted) {
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: $e')),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isSubmitting = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Provider.of<ThemeProvider>(context).primaryColor,
                disabledBackgroundColor: Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Talep Oluştur',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          ],
        ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Bugün ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Dün';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} gün önce';
    } else {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
  }

  // Talep detay ekranını aç
  void _openTicketDetail(Map<String, dynamic> ticket) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _TicketDetailScreen(
          ticket: ticket,
          onTicketUpdated: _loadMyTickets,
        ),
      ),
    );
  }
}

// Talep Detay Ekranı
class _TicketDetailScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onTicketUpdated;

  const _TicketDetailScreen({
    required this.ticket,
    required this.onTicketUpdated,
  });

  @override
  State<_TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<_TicketDetailScreen> {
  final _messageController = TextEditingController();
  // ignore: unused_field
  final _profileService = ProfileService();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    final ticketId = widget.ticket['id'];
    _channel = Supabase.instance.client
        .channel('ticket_messages_$ticketId')
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
            _loadMessages();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: ticketId,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() {
                final newData = payload.newRecord;
                widget.ticket['status'] = newData['status'];
                widget.ticket['admin_response'] = newData['admin_response'];
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final ticketId = widget.ticket['id'];
      
      // Önce eski admin_response varsa onu mesaj olarak ekle
      final messages = <Map<String, dynamic>>[];
      
      // İlk mesaj kullanıcının opening mesajı
      messages.add({
        'id': 'initial',
        'message': widget.ticket['message'] ?? '',
        'sender_id': widget.ticket['user_id'],
        'sender_type': 'user',
        'created_at': widget.ticket['created_at'],
      });
      
      // Admin response varsa ekle (eski sistem için)
      if (widget.ticket['admin_response'] != null && widget.ticket['admin_response'].toString().isNotEmpty) {
        messages.add({
          'id': 'admin_old',
          'message': widget.ticket['admin_response'],
          'sender_id': 'admin',
          'sender_type': 'admin',
          'created_at': widget.ticket['updated_at'] ?? widget.ticket['created_at'],
        });
      }
      
      // Yeni mesajlaşma sisteminden mesajları çek
      final newMessages = await Supabase.instance.client
          .from('support_ticket_messages')
          .select('*')
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: true);
      
      messages.addAll(List<Map<String, dynamic>>.from(newMessages));
      
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Mesajlar yüklenemedi: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() => _isSending = true);

    try {
      final ticketId = widget.ticket['id'];
      final userId = Supabase.instance.client.auth.currentUser?.id;

      await Supabase.instance.client
          .from('support_ticket_messages')
          .insert({
            'ticket_id': ticketId,
            'sender_id': userId,
            'sender_type': 'user',
            'message': _messageController.text.trim(),
          });

      _messageController.clear();
      
      // Ticket durumunu güncelle (eğer kapalıysa açık yap)
      if (widget.ticket['status'] == 'closed') {
        await Supabase.instance.client
            .from('support_tickets')
            .update({'status': 'open'})
            .eq('id', ticketId);
      }
    } catch (e) {
      debugPrint('Mesaj gönderilemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _formatFullDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
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
        return 'Beklemede';
      case 'in_progress':
        return 'İnceleniyor';
      case 'resolved':
        return 'Çözüldü';
      case 'closed':
        return 'Kapatıldı';
      default:
        return 'Bilinmiyor';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final status = widget.ticket['status'] ?? 'open';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Destek Talebi'),
        backgroundColor: Provider.of<ThemeProvider>(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Talep bilgileri
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.ticket['subject'] ?? 'Konu Yok',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kategori: ${_getCategoryText(widget.ticket['category'] ?? 'general')}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Oluşturulma: ${_formatFullDate(DateTime.parse(widget.ticket['created_at']))}',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Mesajlar
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Henüz mesaj yok',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isAdmin = message['sender_type'] == 'admin';
                          final isMe = message['sender_id'] == currentUserId && !isAdmin;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              constraints: const BoxConstraints(
                                maxWidth: 280,
                              ),
                              decoration: BoxDecoration(
                                color: isAdmin
                                    ? Colors.blue.shade50
                                    : isMe
                                        ? Provider.of<ThemeProvider>(context).primaryColor
                                        : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isAdmin)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        'Destek Ekibi',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    message['message'] ?? '',
                                    style: TextStyle(
                                      color: isMe && !isAdmin ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatFullDate(DateTime.parse(message['created_at'])),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: (isMe && !isAdmin) ? Colors.white70 : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Mesaj gönderme alanı
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Mesajınızı yazın...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.send,
                            color: Provider.of<ThemeProvider>(context).primaryColor,
                          ),
                    style: IconButton.styleFrom(
                      backgroundColor: Provider.of<ThemeProvider>(context).primaryColor.withOpacity(0.1),
                      padding: const EdgeInsets.all(12),
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

  String _getCategoryText(String category) {
    switch (category) {
      case 'general':
        return 'Genel';
      case 'account':
        return 'Hesap Sorunu';
      case 'payment':
        return 'Ödeme Sorunu';
      case 'order':
        return 'Sipariş Sorunu';
      case 'technical':
        return 'Teknik Sorun';
      case 'other':
        return 'Diğer';
      default:
        return 'Genel';
    }
  }
}
