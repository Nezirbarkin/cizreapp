// ignore_for_file: unused_field, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';

/// Haber Detay Ekranı
class NewsDetailScreen extends StatefulWidget {
  final NewsModel news;

  const NewsDetailScreen({super.key, required this.news});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  final NewsService _newsService = NewsService();
  final TextEditingController _commentController = TextEditingController();
  
  List<NewsCommentModel> _comments = [];
  bool _isLoadingComments = true;
  bool _isLiked = false;
  int _likeCount = 0;
  int _viewCount = 0;
  NewsModel? _updatedNews;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.news.likeCount;
    _viewCount = widget.news.viewCount;
    _isLiked = widget.news.isLikedByUser ?? false;
    _loadComments();
    _recordView();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _recordView() async {
    await _newsService.recordView(widget.news.id);
    if (mounted) {
      setState(() => _viewCount++);
    }
  }

  Future<void> _loadComments() async {
    final comments = await _newsService.getComments(widget.news.id);
    if (mounted) {
      setState(() {
        _comments = comments;
        _isLoadingComments = false;
      });
    }
  }

  Future<void> _toggleLike() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beğenmek için giriş yapın')),
      );
      return;
    }

    final isNowLiked = await _newsService.toggleLike(widget.news.id);
    if (mounted) {
      setState(() {
        _isLiked = isNowLiked;
        _likeCount += isNowLiked ? 1 : -1;
      });
    }
  }

  Future<void> _shareNews() async {
    final text = '${widget.news.title}\n\n${widget.news.summary ?? widget.news.content.substring(0, widget.news.content.length > 100 ? 100 : widget.news.content.length)}...';
    await Share.share(text);
  }

  Future<void> _copyLink() async {
    final url = 'https://cizreapp.com/haber/${widget.news.slug}';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link kopyalandı')),
      );
    }
  }

  Future<void> _addComment() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yorum yapmak için giriş yapın')),
      );
      return;
    }

    if (_commentController.text.trim().isEmpty) return;

    final comment = await _newsService.addComment(
      newsId: widget.news.id,
      content: _commentController.text.trim(),
    );

    if (comment != null) {
      _commentController.clear();
      _loadComments();
    }
  }

  @override
  Widget build(BuildContext context) {
    final news = _updatedNews ?? widget.news;
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: news.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: news.thumbnailUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey[300]),
                      errorWidget: (_, __, ___) => _buildPlaceholderImage(),
                    )
                  : _buildPlaceholderImage(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _shareNews,
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'copy':
                      _copyLink();
                      break;
                    case 'report':
                      _showReportDialog();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'copy', child: Text('Linki Kopyala')),
                  const PopupMenuItem(value: 'report', child: Text('Haberle İlgili Sorun Bildir')),
                ],
              ),
            ],
          ),

          // İçerik
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge'ler
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (news.isBreaking)
                        _buildBadge('SON DAKİKA', Colors.red, Icons.flash_on),
                      if (news.isFeatured)
                        _buildBadge('ÖNE ÇIKAN', Colors.purple, Icons.star),
                      if (news.categoryName != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Text(
                            news.categoryName!,
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Başlık
                  Text(
                    news.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Kurum bilgisi
                  if (news.institutionName != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: const Icon(Icons.business, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      news.institutionName!,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    if (news.institutionLogoUrl != null)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(Icons.verified, color: Colors.blue, size: 16),
                                      ),
                                  ],
                                ),
                                Text(
                                  'tarafından paylaşıldı',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Tarih ve yazar
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        news.publishedFormattedDate.isNotEmpty
                            ? news.publishedFormattedDate
                            : news.formattedDate,
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.person, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        news.authorName ?? 'Bilinmeyen',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Özet
                  if (news.summary != null && news.summary!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.05),
                        border: const Border(
                          left: BorderSide(color: Colors.blue, width: 3),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        news.summary!,
                        style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // İçerik
                  Text(
                    news.content,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                  const SizedBox(height: 24),

                  // Galeri
                  if (news.images.isNotEmpty) _buildGallery(news.images),
                  const SizedBox(height: 24),

                  // Etkileşim butonları
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildInteractionButton(
                        icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                        label: '$_likeCount Beğeni',
                        color: _isLiked ? Colors.red : Colors.grey,
                        onTap: _toggleLike,
                      ),
                      _buildInteractionButton(
                        icon: Icons.visibility,
                        label: '$_viewCount Görüntülenme',
                        color: Colors.grey,
                        onTap: () {},
                      ),
                      _buildInteractionButton(
                        icon: Icons.comment,
                        label: '${news.commentCount} Yorum',
                        color: Colors.grey,
                        onTap: () {
                          // Yorumlara scroll
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Yorumlar
                  const Text(
                    'Yorumlar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Yorum formu
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: 'Yorum yazın...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _addComment,
                        icon: const Icon(Icons.send),
                        color: Theme.of(context).primaryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Yorum listesi
                  if (_isLoadingComments)
                    const Center(child: CircularProgressIndicator())
                  else if (_comments.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              'Henüz yorum yapılmamış',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._comments.map((comment) => _buildCommentCard(comment)),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.blue[100],
      child: Center(
        child: Icon(Icons.newspaper, size: 64, color: Colors.blue[400]),
      ),
    );
  }

  Widget _buildInteractionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildGallery(List<NewsImageModel> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Galeri',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            itemBuilder: (context, index) {
              final image = images[index];
              return GestureDetector(
                onTap: () => _showFullScreenImage(image.imageUrl),
                child: Container(
                  width: 200,
                  margin: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: image.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Colors.grey[300]),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCommentCard(NewsCommentModel comment) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: comment.userAvatarUrl != null
                      ? NetworkImage(comment.userAvatarUrl!)
                      : null,
                  child: comment.userAvatarUrl == null
                      ? Text(comment.userName[0].toUpperCase())
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            comment.userName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (comment.isEdited)
                            Text(
                              ' (düzenlendi)',
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                        ],
                      ),
                      Text(
                        comment.formattedDate,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comment.content),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    comment.isLikedByUser == true ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                  ),
                  onPressed: () async {
                    await _newsService.toggleCommentLike(comment.id);
                    _loadComments();
                  },
                  color: comment.isLikedByUser == true ? Colors.red : Colors.grey,
                ),
                Text('${comment.likeCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Haber Bildir'),
        content: const Text('Bu haberi neden bildirmek istiyorsunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Bildiriminiz için teşekkürler')),
              );
            },
            child: const Text('Bildir'),
          ),
        ],
      ),
    );
  }
}
