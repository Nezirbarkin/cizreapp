// ignore_for_file: unused_field, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
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
  int _commentCount = 0;
  NewsModel? _updatedNews;
  VideoPlayerController? _videoController;
  bool _isLoadingNews = true;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.news.likeCount;
    _viewCount = widget.news.viewCount;
    _commentCount = widget.news.commentCount;
    _isLiked = widget.news.isLikedByUser ?? false;
    _loadComments();
    _loadNewsMedia();
    _recordView();
  }

  Future<void> _loadNewsMedia() async {
    final news = await _newsService.getNewsById(widget.news.id);
    if (!mounted) return;
    if (news != null) {
      _updatedNews = news;
      if (news.videoUrl != null && news.videoUrl!.isNotEmpty) {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(news.videoUrl!),
        );
        try {
          await controller.initialize();
          await controller.setLooping(false);
          if (mounted) _videoController = controller;
        } catch (_) {
          await controller.dispose();
        }
      }
    }
    if (mounted) setState(() => _isLoadingNews = false);
  }

  @override
  void dispose() {
    _commentController.dispose();
    _videoController?.dispose();
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
        _commentCount = comments.length;
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

    // Optimistik UI güncellemesi - hemen UI'ı güncelle
    final wasPreviouslyLiked = _isLiked;
    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });

    try {
      // Database'e gönder
      final isNowLiked = await _newsService.toggleLike(widget.news.id);

      if (mounted) {
        // Database cevabına göre state'i doğru yap
        if (isNowLiked != _isLiked) {
          setState(() {
            _isLiked = isNowLiked;
            _likeCount += isNowLiked ? 1 : -1;
          });
        }
      }
    } catch (e) {
      // Hata durumunda geri al
      if (mounted) {
        setState(() {
          _isLiked = wasPreviouslyLiked;
          _likeCount += wasPreviouslyLiked ? 1 : -1;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Hata: $e')));
      }
    }
  }

  Future<void> _shareNews() async {
    final text =
        '${widget.news.title}\n\n${widget.news.summary ?? widget.news.content.substring(0, widget.news.content.length > 100 ? 100 : widget.news.content.length)}...';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _copyLink() async {
    final url = 'https://cizreapp.com/haber/${widget.news.slug}';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Link kopyalandı')));
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

    if (comment != null && mounted) {
      _commentController.clear();
      setState(() {
        _comments.insert(0, comment);
      });
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
                      placeholder: (_, __) =>
                          Container(color: Colors.grey[300]),
                      errorWidget: (_, __, ___) => _buildPlaceholderImage(),
                    )
                  : _buildPlaceholderImage(),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.share), onPressed: _shareNews),
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
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Linki Kopyala'),
                  ),
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Haberle İlgili Sorun Bildir'),
                  ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.3),
                            ),
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
                            child: const Icon(
                              Icons.business,
                              color: Colors.white,
                            ),
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
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (news.institutionLogoUrl != null)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(
                                          Icons.verified,
                                          color: Colors.blue,
                                          size: 16,
                                        ),
                                      ),
                                  ],
                                ),
                                Text(
                                  'tarafından paylaşıldı',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
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
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.grey[600],
                      ),
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
                        color: Colors.blue.withValues(alpha: 0.05),
                        border: const Border(
                          left: BorderSide(color: Colors.blue, width: 3),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        news.summary!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // İçerik
                  Text(
                    news.content,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                  const SizedBox(height: 24),

                  if (_isLoadingNews)
                    const Center(child: CircularProgressIndicator())
                  else if (_videoController != null || news.images.isNotEmpty)
                    _buildMediaArea(news.images),
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
                        label: '$_commentCount Yorum',
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
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
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
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 48,
                              color: Colors.grey[400],
                            ),
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
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
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

  Widget _buildMediaArea(List<NewsImageModel> images) {
    return Column(
      children: [
        if (_videoController != null) _buildVideoPlayer(),
        if (_videoController != null && images.isNotEmpty)
          const SizedBox(height: 12),
        if (images.isNotEmpty) _buildImageGrid(images),
      ],
    );
  }

  Widget _buildImageGrid(List<NewsImageModel> images) {
    if (images.length == 1) {
      return _buildImageTile(images.first, height: 260);
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (_, index) => _buildImageTile(images[index]),
    );
  }

  Widget _buildImageTile(NewsImageModel image, {double? height}) {
    return SizedBox(
      height: height,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showFullScreenImage(image.imageUrl),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: image.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 36),
                ),
              ),
              const Positioned(
                right: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(
                      Icons.open_in_full_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final controller = _videoController!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio > 0
              ? controller.value.aspectRatio
              : 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              AnimatedBuilder(
                animation: controller,
                builder: (_, __) => AnimatedOpacity(
                  opacity: controller.value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: IconButton.filled(
                    iconSize: 44,
                    onPressed: () {
                      controller.value.isPlaying
                          ? controller.pause()
                          : controller.play();
                      setState(() {});
                    },
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (_, __) => VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white24,
                    ),
                    padding: const EdgeInsets.only(top: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
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
                    comment.isLikedByUser == true
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 18,
                  ),
                  onPressed: () async {
                    // Optimistik UI güncellemesi
                    final wasLiked = comment.isLikedByUser ?? false;
                    final commentIndex = _comments.indexOf(comment);

                    if (commentIndex != -1) {
                      setState(() {
                        _comments[commentIndex] = _comments[commentIndex]
                            .copyWith(
                              isLikedByUser: !wasLiked,
                              likeCount: wasLiked
                                  ? _comments[commentIndex].likeCount - 1
                                  : _comments[commentIndex].likeCount + 1,
                            );
                      });
                    }

                    // Database'e gönder
                    await _newsService.toggleCommentLike(comment.id);
                  },
                  color: comment.isLikedByUser == true
                      ? Colors.red
                      : Colors.grey,
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
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              messenger.showSnackBar(
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
