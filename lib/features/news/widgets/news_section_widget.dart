// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';
import '../screens/news_screen.dart';
import '../screens/news_detail_screen.dart';

/// Ana Sayfa "Bölgeden Haberler" Widget'ı
class NewsSectionWidget extends StatefulWidget {
  final int maxItems;
  final bool showViewAll;

  const NewsSectionWidget({
    super.key,
    this.maxItems = 5,
    this.showViewAll = true,
  });

  @override
  State<NewsSectionWidget> createState() => _NewsSectionWidgetState();
}

class _NewsSectionWidgetState extends State<NewsSectionWidget> {
  final NewsService _newsService = NewsService();
  List<NewsModel> _news = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    final news = await _newsService.getLatestNews(limit: widget.maxItems);
    setState(() {
      _news = news;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Başlık
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.newspaper, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'Bölgeden Haberler',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (widget.showViewAll)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NewsScreen(),
                      ),
                    );
                  },
                  child: const Text('Tümünü Gör'),
                ),
            ],
          ),
        ),

        // Haber listesi
        if (_isLoading)
          const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_news.isEmpty)
          const SizedBox(
            height: 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.newspaper, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Henüz haber yok', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 260,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _news.length,
              itemBuilder: (context, index) {
                return _buildNewsCard(_news[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildNewsCard(NewsModel news) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NewsDetailScreen(news: news),
          ),
        );
      },
      child: Container(
        width: 280,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Görsel
              SizedBox(
                height: 120,
                width: double.infinity,
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
                              color: Colors.grey[300],
                              child: const Icon(Icons.newspaper, size: 40),
                            ),
                          )
                        : Container(
                            color: Colors.blue[100],
                            child: const Center(
                              child: Icon(Icons.newspaper, size: 40, color: Colors.blue),
                            ),
                          ),
                    // Son dakika badge
                    if (news.isBreaking)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.flash_on, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'SON DAKİKA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Öne çıkan badge
                    if (news.isFeatured)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'ÖNE ÇIKAN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // İçerik
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
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
                      const SizedBox(height: 6),

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
                      const Spacer(),

                      // Kurum ve tarih
                      Row(
                        children: [
                          if (news.institutionName != null) ...[
                            Icon(Icons.business, size: 12, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                news.institutionName!,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            news.publishedFormattedDate.isNotEmpty
                                ? news.publishedFormattedDate
                                : news.formattedDate,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dikey haber listesi widget'ı (kompakt gösterim için)
class NewsListWidget extends StatelessWidget {
  final List<NewsModel> news;
  final bool showInstitution;

  const NewsListWidget({
    super.key,
    required this.news,
    this.showInstitution = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: news.map((item) => _buildNewsItem(context, item)).toList(),
    );
  }

  Widget _buildNewsItem(BuildContext context, NewsModel newsItem) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NewsDetailScreen(news: newsItem),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Görsel
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 80,
                child: newsItem.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: newsItem.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.newspaper),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.newspaper),
                        ),
                      )
                    : Container(
                        color: Colors.blue[100],
                        child: const Icon(Icons.newspaper, color: Colors.blue),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // İçerik
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge'ler
                  Row(
                    children: [
                      if (newsItem.isBreaking)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'SON DAKİKA',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (newsItem.categoryName != null) ...[
                        if (newsItem.isBreaking) const SizedBox(width: 4),
                        Text(
                          newsItem.categoryName!,
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Başlık
                  Text(
                    newsItem.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Kurum ve tarih
                  Row(
                    children: [
                      if (showInstitution && newsItem.institutionName != null) ...[
                        Icon(Icons.business, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          newsItem.institutionName!,
                          style: TextStyle(color: Colors.grey[600], fontSize: 10),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Spacer(),
                      Text(
                        newsItem.publishedFormattedDate.isNotEmpty
                            ? newsItem.publishedFormattedDate
                            : newsItem.formattedDate,
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
