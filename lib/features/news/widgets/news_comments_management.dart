import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin Panel Haber Yorumları Yönetimi
class NewsCommentsManagement extends StatefulWidget {
  const NewsCommentsManagement({super.key});

  @override
  State<NewsCommentsManagement> createState() => _NewsCommentsManagementState();
}

class _NewsCommentsManagementState extends State<NewsCommentsManagement> {
  final SupabaseClient _client = Supabase.instance.client;

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  String _filterStatus = 'all'; // all, hidden, reported

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() => _isLoading = true);

    try {
      late final List<Map<String, dynamic>> comments;

      switch (_filterStatus) {
        case 'hidden':
          comments = await _client
              .from('news_comments')
              .select('*, news(title)')
              .eq('is_hidden', true)
              .order('created_at', ascending: false);
          break;
        case 'reported':
          comments = await _client
              .from('news_comments')
              .select('*, news(title)')
              .gt('report_count', 0)
              .order('report_count', ascending: false);
          break;
        default:
          comments = await _client
              .from('news_comments')
              .select('*, news(title)')
              .order('created_at', ascending: false)
              .limit(100);
      }

      if (mounted) {
        setState(() {
          _comments = List<Map<String, dynamic>>.from(comments as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Yorum yükleme hatası: $e')),
        );
      }
    }
  }

  Future<void> _toggleHideComment(String commentId, bool isHidden) async {
    try {
      await _client
          .from('news_comments')
          .update({'is_hidden': !isHidden})
          .eq('id', commentId);

      _loadComments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!isHidden ? '✅ Yorum gizlendi' : '✅ Yorum gösterildi'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ İşlem başarısız: $e')),
        );
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _client.from('news_comments').delete().eq('id', commentId);
      _loadComments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Yorum silindi'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Silme hatası: $e')),
        );
      }
    }
  }

  Future<void> _pinComment(String commentId, bool isPinned) async {
    try {
      await _client
          .from('news_comments')
          .update({'is_pinned': !isPinned})
          .eq('id', commentId);

      _loadComments();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!isPinned ? '📌 Yorum sabitlendi' : '📌 Sabitlik kaldırıldı'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ İşlem başarısız: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                '💬 Yorum Yönetimi',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'Toplam: ${_comments.length}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        // Filtreler
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterButton('Tümü', 'all'),
                const SizedBox(width: 8),
                _buildFilterButton('Gizli', 'hidden'),
                const SizedBox(width: 8),
                _buildFilterButton('Raporlanan', 'reported'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Yorum listesi
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.comment_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            'Yorum bulunamadı',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) => _buildCommentTile(_comments[index]),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterButton(String label, String value) {
    final isSelected = _filterStatus == value;
    return OutlinedButton(
      onPressed: () {
        setState(() => _filterStatus = value);
        _loadComments();
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
        side: BorderSide(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[300]!,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.grey[700],
        ),
      ),
    );
  }

  Widget _buildCommentTile(Map<String, dynamic> comment) {
    final isHidden = comment['is_hidden'] as bool? ?? false;
    final isPinned = comment['is_pinned'] as bool? ?? false;
    final reportCount = comment['report_count'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isHidden ? Colors.grey[100] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık ve badge'ler
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment['user_name'] ?? 'Bilinmeyen',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Haber: ${comment['news']?['title'] ?? 'Silinmiş'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isPinned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '📌 Sabitli',
                      style: TextStyle(fontSize: 10, color: Colors.orange),
                    ),
                  ),
                if (isHidden)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '👁️ Gizli',
                      style: TextStyle(fontSize: 10, color: Colors.red),
                    ),
                  ),
                if (reportCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '⚠️ $reportCount Rapor',
                      style: TextStyle(fontSize: 10, color: Colors.red[900]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Yorum içeriği
            Text(
              comment['content'] ?? '',
              style: TextStyle(
                color: isHidden ? Colors.grey[500] : Colors.black87,
                fontSize: 14,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // Tarih ve aksiyonlar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(comment['created_at']),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                Row(
                  children: [
                    // Pin butonu
                    IconButton(
                      icon: Icon(
                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        color: isPinned ? Colors.orange : Colors.grey,
                        size: 18,
                      ),
                      onPressed: () => _pinComment(comment['id'] as String, isPinned),
                      tooltip: isPinned ? 'Sabitliği Kaldır' : 'Sabitli Yap',
                    ),
                    // Gizle/Göster butonu
                    IconButton(
                      icon: Icon(
                        isHidden ? Icons.visibility_off : Icons.visibility,
                        color: isHidden ? Colors.red : Colors.grey,
                        size: 18,
                      ),
                      onPressed: () => _toggleHideComment(comment['id'] as String, isHidden),
                      tooltip: isHidden ? 'Göster' : 'Gizle',
                    ),
                    // Sil butonu
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                      onPressed: () => _showDeleteConfirmation(comment['id'] as String),
                      tooltip: 'Sil',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inSeconds < 60) return 'Az önce';
      if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
      if (diff.inHours < 24) return '${diff.inHours} saat önce';
      if (diff.inDays < 7) return '${diff.inDays} gün önce';

      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  void _showDeleteConfirmation(String commentId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yorumu Sil'),
        content: const Text('Bu yorumu silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteComment(commentId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
