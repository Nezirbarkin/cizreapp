// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/news_model.dart';
import '../screens/news_editor_screen.dart';
import '../services/news_service.dart';
import 'news_comments_management.dart';

/// Admin paneli için responsive haber operasyon merkezi.
class NewsManagementContent extends StatefulWidget {
  const NewsManagementContent({super.key});

  @override
  State<NewsManagementContent> createState() => _NewsManagementContentState();
}

class _NewsManagementContentState extends State<NewsManagementContent> {
  final NewsService _newsService = NewsService();
  final TextEditingController _searchController = TextEditingController();

  List<NewsModel> _news = [];
  List<NewsCategoryModel> _categories = [];
  List<InstitutionModel> _institutions = [];
  Map<String, int> _stats = const {};
  int _selectedTab = 0;
  bool _isLoading = true;
  String? _error;
  String? _selectedCategory;
  String _status = 'all';
  String _sort = 'newest';
  String _searchQuery = '';
  Timer? _searchDebounce;

  List<NewsModel> get _visibleNews {
    final items = [..._news];
    switch (_sort) {
      case 'views':
        items.sort((a, b) => b.viewCount.compareTo(a.viewCount));
      case 'engagement':
        items.sort((a, b) => _engagement(b).compareTo(_engagement(a)));
      case 'oldest':
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      default:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final publishedFilter = switch (_status) {
        'published' => true,
        'draft' => false,
        _ => null,
      };
      final results = await Future.wait([
        _newsService.getAllNewsForAdmin(
          limit: 100,
          categoryId: _selectedCategory,
          isPublished: publishedFilter,
          searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
        ),
        _newsService.getCategories(),
        _newsService.getInstitutions(),
        _newsService.getNewsStats(),
      ]);
      if (!mounted) return;
      var loadedNews = results[0] as List<NewsModel>;
      if (_status == 'featured') {
        loadedNews = loadedNews.where((news) => news.isFeatured).toList();
      } else if (_status == 'breaking') {
        loadedNews = loadedNews.where((news) => news.isBreaking).toList();
      }
      setState(() {
        _news = loadedNews;
        _categories = results[1] as List<NewsCategoryModel>;
        _institutions = results[2] as List<InstitutionModel>;
        _stats = results[3] as Map<String, int>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Yönetim verileri yüklenemedi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopNavigation(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _selectedTab == 0
                ? _buildNewsWorkspace()
                : const NewsCommentsManagement(key: ValueKey('comments')),
          ),
        ),
      ],
    );
  }

  Widget _buildTopNavigation() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: .5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.newspaper_rounded),
                  label: Text('İçerikler'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.forum_rounded),
                  label: Text('Moderasyon'),
                ),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selection) =>
                  setState(() => _selectedTab = selection.first),
            ),
          ),
          if (_selectedTab == 0) ...[
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: 'Yenile',
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNewsWorkspace() {
    return RefreshIndicator(
      key: const ValueKey('news'),
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildCommandHeader()),
          SliverToBoxAdapter(child: _buildStats()),
          SliverToBoxAdapter(child: _buildFilters()),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmpty(
                Icons.cloud_off_rounded,
                'Veriler yüklenemedi',
                _error!,
                retry: true,
              ),
            )
          else if (_visibleNews.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmpty(
                Icons.inbox_rounded,
                'İçerik bulunamadı',
                'Filtreleri değiştirin veya yeni bir haber oluşturun.',
              ),
            )
          else
            _buildResponsiveNewsList(),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildCommandHeader() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.tertiaryContainer],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yayın Operasyon Merkezi',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'İçerikleri yönetin, gündemi düzenleyin ve yayın performansını takip edin.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: () => _openNewsEditor(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Yeni haber'),
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 18), button],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 20),
                    button,
                  ],
                );
        },
      ),
    );
  }

  Widget _buildStats() {
    final totalViews = _news.fold<int>(0, (sum, news) => sum + news.viewCount);
    final totalEngagement = _news.fold<int>(
      0,
      (sum, news) => sum + _engagement(news),
    );
    final data = <(String, int, IconData, Color)>[
      (
        'Toplam',
        _stats['total'] ?? 0,
        Icons.library_books_rounded,
        Colors.blue,
      ),
      ('Yayında', _stats['published'] ?? 0, Icons.public_rounded, Colors.green),
      ('Taslak', _stats['draft'] ?? 0, Icons.edit_note_rounded, Colors.orange),
      ('Son dakika', _stats['breaking'] ?? 0, Icons.bolt_rounded, Colors.red),
      ('Görüntülenme', totalViews, Icons.visibility_rounded, Colors.indigo),
      ('Etkileşim', totalEngagement, Icons.trending_up_rounded, Colors.purple),
    ];
    return SizedBox(
      height: 108,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: data.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final item = data[index];
          return Container(
            width: 154,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: item.$4.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: item.$4.withValues(alpha: .18)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: item.$4.withValues(alpha: .14),
                  foregroundColor: item.$4,
                  child: Icon(item.$3, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _compactNumber(item.$2),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: item.$4,
                        ),
                      ),
                      Text(
                        item.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    const statuses = <(String, String)>[
      ('all', 'Tümü'),
      ('published', 'Yayında'),
      ('draft', 'Taslak'),
      ('featured', 'Öne çıkan'),
      ('breaking', 'Son dakika'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: _searchController,
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 450),
                    () {
                      _searchQuery = value.trim();
                      _loadData();
                    },
                  );
                },
                decoration: InputDecoration(
                  hintText: 'Başlık veya içerik ara',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              );
              final category = DropdownButtonFormField<String?>(
                initialValue: _selectedCategory,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Kategori',
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Tüm kategoriler'),
                  ),
                  ..._categories.map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  _selectedCategory = value;
                  _loadData();
                },
              );
              if (constraints.maxWidth < 650) {
                return Column(
                  children: [search, const SizedBox(height: 10), category],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 2, child: search),
                  const SizedBox(width: 12),
                  Expanded(child: category),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: statuses
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(item.$2),
                              selected: _status == item.$1,
                              onSelected: (_) {
                                _status = item.$1;
                                _loadData();
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Sırala',
                initialValue: _sort,
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'newest', child: Text('En yeni')),
                  PopupMenuItem(value: 'oldest', child: Text('En eski')),
                  PopupMenuItem(
                    value: 'views',
                    child: Text('En çok görüntülenen'),
                  ),
                  PopupMenuItem(
                    value: 'engagement',
                    child: Text('En çok etkileşim'),
                  ),
                ],
                child: const Chip(
                  avatar: Icon(Icons.swap_vert_rounded, size: 18),
                  label: Text('Sırala'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveNewsList() {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.crossAxisExtent >= 1100 ? 2 : 1;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.builder(
            itemCount: _visibleNews.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              mainAxisExtent: 176,
            ),
            itemBuilder: (_, index) => _buildNewsCard(_visibleNews[index]),
          ),
        );
      },
    );
  }

  Widget _buildNewsCard(NewsModel news) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openNewsEditor(news),
        child: Row(
          children: [
            SizedBox(
              width: 138,
              height: double.infinity,
              child: _image(news.thumbnailUrl),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _badge(
                          news.isPublished ? 'YAYINDA' : 'TASLAK',
                          news.isPublished ? Colors.green : Colors.orange,
                        ),
                        if (news.isFeatured) _badge('ÖNE ÇIKAN', Colors.purple),
                        if (news.isBreaking) _badge('SON DAKİKA', Colors.red),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      news.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${news.categoryName ?? 'Kategorisiz'} • ${news.authorName ?? 'Editör'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.outline, fontSize: 11),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _metric(Icons.visibility_outlined, news.viewCount),
                        const SizedBox(width: 10),
                        _metric(Icons.favorite_border_rounded, news.likeCount),
                        const SizedBox(width: 10),
                        _metric(
                          Icons.chat_bubble_outline_rounded,
                          news.commentCount,
                        ),
                        const Spacer(),
                        Text(
                          news.formattedDate,
                          style: TextStyle(color: colors.outline, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _handleAction(value, news),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_rounded),
                    title: Text('Düzenle'),
                  ),
                ),
                PopupMenuItem(
                  value: 'publish',
                  child: ListTile(
                    leading: Icon(
                      news.isPublished
                          ? Icons.unpublished_rounded
                          : Icons.publish_rounded,
                    ),
                    title: Text(news.isPublished ? 'Taslağa al' : 'Yayınla'),
                  ),
                ),
                PopupMenuItem(
                  value: 'featured',
                  child: ListTile(
                    leading: const Icon(Icons.star_rounded),
                    title: Text(
                      news.isFeatured ? 'Öne çıkarmayı kaldır' : 'Öne çıkar',
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'breaking',
                  child: ListTile(
                    leading: const Icon(Icons.bolt_rounded),
                    title: Text(
                      news.isBreaking
                          ? 'Son dakikadan kaldır'
                          : 'Son dakika yap',
                    ),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                    title: Text('Sil', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _image(String? url) {
    final fallback = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.newspaper_rounded, size: 42)),
    );
    if (url == null || url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900),
    ),
  );

  Widget _metric(IconData icon, int value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14),
      const SizedBox(width: 3),
      Text(_compactNumber(value), style: const TextStyle(fontSize: 11)),
    ],
  );

  Widget _buildEmpty(
    IconData icon,
    String title,
    String message, {
    bool retry = false,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: retry ? _loadData : () => _openNewsEditor(null),
            icon: Icon(retry ? Icons.refresh_rounded : Icons.add_rounded),
            label: Text(retry ? 'Tekrar dene' : 'Yeni haber'),
          ),
        ],
      ),
    ),
  );

  Future<void> _handleAction(String action, NewsModel news) async {
    switch (action) {
      case 'edit':
        await _openNewsEditor(news);
      case 'publish':
        await _updateFlag(
          news,
          isPublished: !news.isPublished,
          message: news.isPublished
              ? 'Haber taslağa alındı'
              : 'Haber yayınlandı',
        );
      case 'featured':
        await _updateFlag(
          news,
          isFeatured: !news.isFeatured,
          message: 'Öne çıkan durumu güncellendi',
        );
      case 'breaking':
        await _updateFlag(
          news,
          isBreaking: !news.isBreaking,
          message: 'Son dakika durumu güncellendi',
        );
      case 'delete':
        await _deleteNews(news);
    }
  }

  Future<void> _openNewsEditor(NewsModel? news) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewsEditorScreen(
          news: news,
          categories: _categories,
          institutions: _institutions,
        ),
      ),
    );
    if (changed == true) await _loadData();
  }

  Future<void> _updateFlag(
    NewsModel news, {
    bool? isPublished,
    bool? isFeatured,
    bool? isBreaking,
    required String message,
  }) async {
    final success = await _newsService.updateNews(
      id: news.id,
      isPublished: isPublished,
      isFeatured: isFeatured,
      isBreaking: isBreaking,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadData();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem tamamlanamadı')));
    }
  }

  Future<void> _deleteNews(NewsModel news) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.red,
          size: 38,
        ),
        title: const Text('Haberi kalıcı olarak sil'),
        content: Text(
          '“${news.title}” içeriği geri alınamaz biçimde silinecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await _newsService.deleteNews(news.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'Haber silindi' : 'Haber silinemedi')),
    );
    if (success) await _loadData();
  }

  int _engagement(NewsModel news) =>
      news.likeCount + news.commentCount + news.shareCount;

  String _compactNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}B';
    }
    return '$value';
  }
}
