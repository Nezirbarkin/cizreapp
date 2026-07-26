// ignore_for_file: unused_field, use_build_context_synchronously, deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';
import '../screens/news_editor_screen.dart';

/// Admin Panel Haber Yönetimi İçeriği
class NewsManagementContent extends StatefulWidget {
  const NewsManagementContent({super.key});

  @override
  State<NewsManagementContent> createState() => _NewsManagementContentState();
}

class _NewsManagementContentState extends State<NewsManagementContent> {
  final NewsService _newsService = NewsService();
  
  List<NewsModel> _news = [];
  List<NewsCategoryModel> _categories = [];
  List<InstitutionModel> _institutions = [];
  bool _isLoading = true;
  
  // Filtreler
  String? _selectedCategory;
  bool? _isPublishedFilter;
  String _searchQuery = '';
  
  // İstatistikler
  Map<String, int> _stats = {'total': 0, 'published': 0, 'draft': 0, 'featured': 0, 'breaking': 0};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final results = await Future.wait([
        _newsService.getAllNewsForAdmin(
          categoryId: _selectedCategory,
          isPublished: _isPublishedFilter,
          searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        ),
        _newsService.getCategories(),
        _newsService.getInstitutions(),
        _newsService.getNewsStats(),
      ]);
      
      setState(() {
        _news = results[0] as List<NewsModel>;
        _categories = results[1] as List<NewsCategoryModel>;
        _institutions = results[2] as List<InstitutionModel>;
        _stats = results[3] as Map<String, int>;
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
    return Column(
      children: [
        _buildHeader(),
        _buildStatsCards(),
        _buildFilters(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _news.isEmpty
                  ? _buildEmptyState()
                  : _buildNewsList(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Text(
            '📰 Haber Yönetimi',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _openNewsEditor(null),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Haber'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatCard('📊 Toplam', _stats['total'] ?? 0, Colors.blue),
            const SizedBox(width: 12),
            _buildStatCard('✅ Yayınlanan', _stats['published'] ?? 0, Colors.green),
            const SizedBox(width: 12),
            _buildStatCard('📝 Taslak', _stats['draft'] ?? 0, Colors.orange),
            const SizedBox(width: 12),
            _buildStatCard('⭐ Öne Çıkan', _stats['featured'] ?? 0, Colors.purple),
            const SizedBox(width: 12),
            _buildStatCard('🚨 Son Dakika', _stats['breaking'] ?? 0, Colors.red),
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              decoration: InputDecoration(
                hintText: '🔍 Haber ara...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onChanged: (value) {
                _searchQuery = value;
                _loadData();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _selectedCategory,
              decoration: InputDecoration(
                labelText: 'Kategori',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tümü')),
                ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (value) {
                _selectedCategory = value;
                _loadData();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<bool?>(
              value: _isPublishedFilter,
              decoration: InputDecoration(
                labelText: 'Durum',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Tümü')),
                DropdownMenuItem(value: true, child: Text('Yayınlanan')),
                DropdownMenuItem(value: false, child: Text('Taslak')),
              ],
              onChanged: (value) {
                _isPublishedFilter = value;
                _loadData();
              },
            ),
          ),
        ],
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
          Text('Haber bulunamadı', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
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
      itemCount: _news.length,
      itemBuilder: (context, index) => _buildNewsCard(_news[index]),
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
                            child: const Text('⭐ ÖNE ÇIKAN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        if (news.isBreaking)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('🚨 SON DAKİKA', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
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
                    GestureDetector(
                      onTap: () => _editNewsTitle(news),
                      child: Text(
                        news.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                        const SizedBox(width: 12),
                        Icon(Icons.comment, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('${news.commentCount}', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
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
                    case 'toggle_featured':
                      await _toggleFeatured(news);
                      break;
                    case 'toggle_breaking':
                      await _toggleBreaking(news);
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
                  PopupMenuItem(
                    value: 'toggle_featured',
                    child: Text(news.isFeatured ? '⭐ Öne Çıkandan Kaldır' : '⭐ Öne Çıkan Yap'),
                  ),
                  PopupMenuItem(
                    value: 'toggle_breaking',
                    child: Text(news.isBreaking ? '🚨 Son Dakikadan Kaldır' : '🚨 Son Dakika Yap'),
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

  Future<void> _toggleFeatured(NewsModel news) async {
    try {
      await _newsService.updateNews(
        id: news.id,
        isFeatured: !news.isFeatured,
      );
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Hata: $e')));
      }
    }
  }

  Future<void> _toggleBreaking(NewsModel news) async {
    try {
      await _newsService.updateNews(
        id: news.id,
        isBreaking: !news.isBreaking,
      );
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Hata: $e')));
      }
    }
  }

  Future<void> _editNewsTitle(NewsModel news) async {
    final titleController = TextEditingController(text: news.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('✏️ Başlığı Düzenle'),
        content: TextField(
          controller: titleController,
          decoration: InputDecoration(
            hintText: 'Yeni başlık',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, titleController.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != news.title) {
      try {
        await _newsService.updateNews(
          id: news.id,
          title: newTitle,
        );
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Başlık güncellendi')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Güncelleme hatası: $e')),
          );
        }
      }
    }
    titleController.dispose();
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
