// ignore_for_file: unused_field, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';

/// Haberci Paneli - Sadece "news" rolüne sahip kullanıcılar için
class NewsPanelScreen extends StatefulWidget {
  const NewsPanelScreen({super.key});

  @override
  State<NewsPanelScreen> createState() => _NewsPanelScreenState();
}

class _NewsPanelScreenState extends State<NewsPanelScreen> {
  final NewsService _newsService = NewsService();
  
  List<NewsModel> _myNews = [];
  List<NewsCategoryModel> _categories = [];
  List<InstitutionModel> _institutions = [];
  bool _isLoading = true;
  bool _isSaving = false;

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
          SnackBar(content: Text('Veri yükleme hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Haberci Paneli'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // İstatistikler
                  SliverToBoxAdapter(
                    child: _buildStatsSection(),
                  ),
                  
                  // Haberler listesi
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text(
                            'Haberleriniz',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _showNewsDialog(null),
                            icon: const Icon(Icons.add),
                            label: const Text('Yeni Haber'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  if (_myNews.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.newspaper, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Henüz haber paylaşmadınız',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => _showNewsDialog(null),
                              icon: const Icon(Icons.add),
                              label: const Text('İlk Haberi Paylaş'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildNewsCard(_myNews[index]),
                        childCount: _myNews.length,
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewsDialog(null),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Haber'),
      ),
    );
  }

  Widget _buildStatsSection() {
    final published = _myNews.where((n) => n.isPublished).length;
    final draft = _myNews.where((n) => !n.isPublished).length;
    final totalViews = _myNews.fold<int>(0, (sum, n) => sum + n.viewCount);
    final totalLikes = _myNews.fold<int>(0, (sum, n) => sum + n.likeCount);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[400]!, Colors.blue[600]!],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'İstatistikleriniz',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem('Toplam', _myNews.length.toString(), Icons.article),
              _buildStatItem('Yayınlanan', published.toString(), Icons.check_circle),
              _buildStatItem('Taslak', draft.toString(), Icons.edit_note),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatItem('Görüntülenme', totalViews.toString(), Icons.visibility),
              _buildStatItem('Beğeni', totalLikes.toString(), Icons.favorite),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsCard(NewsModel news) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showNewsDialog(news),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Görsel
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: news.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: news.thumbnailUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey[300],
                          child: const Icon(Icons.image),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey[300],
                          child: const Icon(Icons.newspaper),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 80,
                        color: Colors.blue[100],
                        child: const Icon(Icons.newspaper, color: Colors.blue),
                      ),
              ),
              const SizedBox(width: 12),
              
              // Bilgiler
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: news.isPublished ? Colors.green : Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            news.isPublished ? 'YAYINDA' : 'TASLAK',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                        if (news.isFeatured) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ÖNE ÇIKAN',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      news.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.visibility, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('${news.viewCount}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        const SizedBox(width: 8),
                        Icon(Icons.favorite, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('${news.likeCount}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        const SizedBox(width: 8),
                        Icon(Icons.comment, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('${news.commentCount}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              
              // İşlemler
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _showNewsDialog(news);
                      break;
                    case 'publish':
                      _togglePublish(news);
                      break;
                    case 'delete':
                      _deleteNews(news);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  PopupMenuItem(
                    value: 'publish',
                    child: Text(news.isPublished ? 'Yayını Kaldır' : 'Yayınla'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Sil', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNewsDialog(NewsModel? news) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => NewsEditDialogForNewsRole(
        news: news,
        categories: _categories,
        institutions: _institutions,
      ),
    );
    
    if (result == true) {
      _loadData();
    }
  }

  Future<void> _togglePublish(NewsModel news) async {
    final success = await _newsService.updateNews(
      id: news.id,
      isPublished: !news.isPublished,
    );
    
    if (success) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(news.isPublished ? 'Haber yayından kaldırıldı' : 'Haber yayınlandı'),
          ),
        );
      }
    }
  }

  Future<void> _deleteNews(NewsModel news) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Haberi Sil'),
        content: Text('"${news.title}" haberini silmek istediğinizden emin misiniz?'),
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
      final success = await _newsService.deleteNews(news.id);
      if (success) {
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Haber silindi')),
          );
        }
      }
    }
  }
}

/// Haber Düzenleme Dialog (Haberci rolü için)
class NewsEditDialogForNewsRole extends StatefulWidget {
  final NewsModel? news;
  final List<NewsCategoryModel> categories;
  final List<InstitutionModel> institutions;

  const NewsEditDialogForNewsRole({
    super.key,
    this.news,
    required this.categories,
    required this.institutions,
  });

  @override
  State<NewsEditDialogForNewsRole> createState() => _NewsEditDialogForNewsRoleState();
}

class _NewsEditDialogForNewsRoleState extends State<NewsEditDialogForNewsRole> {
  final _formKey = GlobalKey<FormState>();
  final _newsService = NewsService();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _summaryController = TextEditingController();
  
  String? _selectedCategory;
  String? _selectedInstitution;
  bool _isPublished = false;
  String? _thumbnailUrl;
  bool _isSaving = false;

  bool get isEditing => widget.news != null;

  @override
  void initState() {
    super.initState();
    if (widget.news != null) {
      _titleController.text = widget.news!.title;
      _contentController.text = widget.news!.content;
      _summaryController.text = widget.news!.summary ?? '';
      _selectedCategory = widget.news!.categoryId;
      _selectedInstitution = widget.news!.institutionId;
      _isPublished = widget.news!.isPublished;
      _thumbnailUrl = widget.news!.thumbnailUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        child: Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'Haberi Düzenle' : 'Yeni Haber'),
            actions: [
              if (_isSaving)
                const Center(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ))
              else
                TextButton(
                  onPressed: _saveNews,
                  child: const Text('Kaydet'),
                ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Başlık
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Başlık *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Başlık gerekli';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Özet
                  TextFormField(
                    controller: _summaryController,
                    decoration: const InputDecoration(
                      labelText: 'Özet',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  
                  // İçerik
                  TextFormField(
                    controller: _contentController,
                    decoration: const InputDecoration(
                      labelText: 'İçerik *',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 8,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'İçerik gerekli';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Kategori ve Kurum
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Kategori',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                            ...widget.categories.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            )),
                          ],
                          onChanged: (value) => setState(() => _selectedCategory = value),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedInstitution,
                          decoration: const InputDecoration(
                            labelText: 'Kurum',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                            ...widget.institutions.map((i) => DropdownMenuItem(
                              value: i.id,
                              child: Text(i.name),
                            )),
                          ],
                          onChanged: (value) => setState(() => _selectedInstitution = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Yayınla seçeneği
                  SwitchListTile(
                    title: const Text('Haberi hemen yayınla'),
                    value: _isPublished,
                    onChanged: (v) => setState(() => _isPublished = v),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveNews() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      bool success;

      if (isEditing) {
        success = await _newsService.updateNews(
          id: widget.news!.id,
          title: _titleController.text,
          content: _contentController.text,
          summary: _summaryController.text.isEmpty ? null : _summaryController.text,
          categoryId: _selectedCategory,
          institutionId: _selectedInstitution,
          isPublished: _isPublished,
        );
      } else {
        final created = await _newsService.createNews(
          title: _titleController.text,
          content: _contentController.text,
          summary: _summaryController.text.isEmpty ? null : _summaryController.text,
          categoryId: _selectedCategory,
          institutionId: _selectedInstitution,
          isPublished: _isPublished,
        );
        success = created != null;
      }

      if (success && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEditing ? 'Haber güncellendi' : 'Haber oluşturuldu')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }
}
