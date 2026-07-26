import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';
import '../screens/news_editor_screen.dart';

/// Haberci Paneli - Haber Yazarları için Yönetim Ekranı
class NewsReporterPanelScreen extends StatefulWidget {
  const NewsReporterPanelScreen({super.key});

  @override
  State<NewsReporterPanelScreen> createState() => _NewsReporterPanelScreenState();
}

class _NewsReporterPanelScreenState extends State<NewsReporterPanelScreen> {
  final NewsService _newsService = NewsService();

  List<NewsModel> _myNews = [];
  List<NewsCategoryModel> _categories = [];
  List<InstitutionModel> _institutions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _newsService.getMyNews(),
        _newsService.getCategories(),
        _newsService.getInstitutions(),
      ]);

      setState(() {
        _myNews = results[0] as List<NewsModel>;
        _categories = results[1] as List<NewsCategoryModel>;
        _institutions = results[2] as List<InstitutionModel>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Veri yükleme hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📰 Haberci Paneli'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                _buildStats(),
                Expanded(
                  child: _myNews.isEmpty
                      ? _buildEmptyState()
                      : _buildNewsList(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewsEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Haber'),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Text(
            'Haberlerim',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_myNews.length} Haber',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final published = _myNews.where((n) => n.isPublished).length;
    final draft = _myNews.where((n) => !n.isPublished).length;
    final featured = _myNews.where((n) => n.isFeatured).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatCard('✅ Yayınlanan', published, Colors.green),
            const SizedBox(width: 12),
            _buildStatCard('📝 Taslak', draft, Colors.orange),
            const SizedBox(width: 12),
            _buildStatCard('⭐ Öne Çıkan', featured, Colors.purple),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.newspaper, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Henüz haber yok', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _openNewsEditor(null),
            icon: const Icon(Icons.add),
            label: const Text('İlk Haberi Ekle'),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myNews.length,
      itemBuilder: (context, index) => _buildNewsCard(_myNews[index]),
    );
  }

  Widget _buildNewsCard(NewsModel news) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _openNewsEditor(news),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: news.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: news.thumbnailUrl!,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 100,
                        height: 100,
                        color: Colors.grey[300],
                        child: const Icon(Icons.newspaper, size: 40),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        if (news.isFeatured)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('⭐ ÖNE ÇIKAN',
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: news.isPublished ? Colors.green : Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            news.isPublished ? '✅ YAYINDA' : '📝 TASLAK',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      news.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      news.summary ?? news.content.substring(0, (news.content.length > 100 ? 100 : news.content.length)),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.visibility, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('${news.viewCount}', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        const SizedBox(width: 12),
                        Icon(Icons.favorite, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('${news.likeCount}', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        const Spacer(),
                        Text(news.formattedDate, style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'edit':
                      _openNewsEditor(news);
                      break;
                    case 'toggle_publish':
                      await _togglePublish(news);
                      break;
                    case 'delete':
                      await _deleteNews(news);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('✏️ Düzenle')),
                  PopupMenuItem(
                    value: 'toggle_publish',
                    child: Text(news.isPublished ? '📝 Taslağa Al' : '✅ Yayınla'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('🗑️ Sil', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNewsEditor(NewsModel? news) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => NewsEditorScreen(
          news: news,
          categories: _categories,
          institutions: _institutions,
        ),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _togglePublish(NewsModel news) async {
    try {
      await _newsService.updateNews(
        id: news.id,
        isPublished: !news.isPublished,
      );
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(news.isPublished ? '📝 Haber taslağa alındı' : '✅ Haber yayınlandı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Hata: $e')));
      }
    }
  }

  Future<void> _deleteNews(NewsModel news) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning, color: Colors.red, size: 32),
        title: const Text('🗑️ Haberi Sil'),
        content: Text('"${news.title}" haberini kalıcı olarak silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _newsService.deleteNews(news.id);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Haber silindi')),
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
  }
}
