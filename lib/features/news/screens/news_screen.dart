// ignore_for_file: unused_field, use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';
import 'news_detail_screen.dart';

/// Haberler Listesi Ekranı
class NewsScreen extends StatefulWidget {
  final String? categoryId;
  final String? categoryName;

  const NewsScreen({
    super.key,
    this.categoryId,
    this.categoryName,
  });

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final NewsService _newsService = NewsService();
  final ScrollController _scrollController = ScrollController();
  
  List<NewsModel> _news = [];
  List<NewsCategoryModel> _categories = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _selectedCategoryId;
  String _searchQuery = '';
  int _offset = 0;
  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.categoryId;
    _loadCategories();
    _loadNews();
    
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreNews();
      }
    }
  }

  Future<void> _loadCategories() async {
    final categories = await _newsService.getCategories();
    setState(() {
      _categories = categories;
    });
  }

  Future<void> _loadNews() async {
    setState(() {
      _isLoading = true;
      _offset = 0;
    });

    final news = await _newsService.getPublishedNews(
      limit: _limit,
      categoryId: _selectedCategoryId,
    );

    setState(() {
      _news = news;
      _isLoading = false;
      _hasMore = news.length >= _limit;
    });
  }

  Future<void> _loadMoreNews() async {
    if (_isLoadingMore) return;
    
    setState(() {
      _isLoadingMore = true;
      _offset += _limit;
    });

    final moreNews = await _newsService.getPublishedNews(
      limit: _limit,
      offset: _offset,
      categoryId: _selectedCategoryId,
    );

    setState(() {
      _news.addAll(moreNews);
      _isLoadingMore = false;
      _hasMore = moreNews.length >= _limit;
    });
  }

  Future<void> _searchNews(String query) async {
    if (query.isEmpty) {
      _loadNews();
      return;
    }

    setState(() {
      _isLoading = true;
      _searchQuery = query;
    });

    final results = await _newsService.searchNews(query);

    setState(() {
      _news = results;
      _isLoading = false;
      _hasMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName ?? 'Haberler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Kategori filtreleri
          if (_categories.isNotEmpty) _buildCategoryFilter(),
          
          // Haber listesi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _news.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadNews,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: _news.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _news.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            return _buildNewsCard(_news[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _categories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: const Text('Tümü'),
                selected: _selectedCategoryId == null,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedCategoryId = null);
                    _loadNews();
                  }
                },
              ),
            );
          }
          
          final category = _categories[index - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(category.name),
              selected: _selectedCategoryId == category.id,
              onSelected: (selected) {
                setState(() {
                  _selectedCategoryId = selected ? category.id : null;
                });
                _loadNews();
              },
            ),
          );
        },
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
          Text(
            _searchQuery.isNotEmpty ? 'Sonuç bulunamadı' : 'Henüz haber yok',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _searchQuery = '');
                _loadNews();
              },
              child: const Text('Filtreleri Temizle'),
            ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(NewsModel news) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NewsDetailScreen(news: news),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Görsel
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      news.thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: news.thumbnailUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: Colors.grey[300],
                                child: const Center(child: CircularProgressIndicator()),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.blue[100],
                                child: const Icon(Icons.newspaper, size: 40, color: Colors.blue),
                              ),
                            )
                          : Container(
                              color: Colors.blue[100],
                              child: const Icon(Icons.newspaper, size: 40, color: Colors.blue),
                            ),
                      if (news.isBreaking)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.flash_on, color: Colors.white, size: 10),
                                SizedBox(width: 2),
                                Text(
                                  'SON DAKİKA',
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // İçerik
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Kategori
                    if (news.categoryName != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          news.categoryName!,
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),

                    // Başlık
                    Text(
                      news.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Kurum
                    if (news.institutionName != null)
                      Row(
                        children: [
                          Icon(Icons.business, size: 12, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              news.institutionName!,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (news.institutionLogoUrl != null)
                            const Icon(Icons.verified, color: Colors.blue, size: 12),
                        ],
                      ),
                    const SizedBox(height: 4),

                    // Tarih ve istatistikler
                    Row(
                      children: [
                        Text(
                          news.publishedFormattedDate.isNotEmpty
                              ? news.publishedFormattedDate
                              : news.formattedDate,
                          style: TextStyle(color: Colors.grey[600], fontSize: 11),
                        ),
                        const Spacer(),
                        Icon(Icons.visibility, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 2),
                        Text('${news.viewCount}', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        const SizedBox(width: 8),
                        Icon(Icons.favorite, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 2),
                        Text('${news.likeCount}', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: _searchQuery);
        return AlertDialog(
          title: const Text('Haber Ara'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Haber başlığı veya içerik...',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (value) {
              Navigator.pop(context);
              _searchNews(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.clear();
                Navigator.pop(context);
                setState(() => _searchQuery = '');
                _loadNews();
              },
              child: const Text('Temizle'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _searchNews(controller.text);
              },
              child: const Text('Ara'),
            ),
          ],
        );
      },
    );
  }
}
