import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';
import 'news_editor_screen.dart';

// ignore_for_file: use_build_context_synchronously

/// Haberci Paneli - Haber Yazarları için Yönetim Ekranı
class NewsReporterPanelScreen extends StatefulWidget {
  const NewsReporterPanelScreen({super.key});

  @override
  State<NewsReporterPanelScreen> createState() =>
      _NewsReporterPanelScreenState();
}

class _NewsReporterPanelScreenState extends State<NewsReporterPanelScreen> {
  final NewsService _newsService = NewsService();
  final TextEditingController _searchController = TextEditingController();

  List<NewsModel> _myNews = [];
  List<NewsCategoryModel> _categories = [];
  List<InstitutionModel> _institutions = [];
  bool _isLoading = true;
  String _statusFilter = 'all';
  String _searchQuery = '';
  String _sortMode = 'newest';

  List<NewsModel> get _filteredNews {
    final result = _myNews.where((news) {
      final matchesStatus = switch (_statusFilter) {
        'published' => news.isPublished,
        'draft' => !news.isPublished,
        'featured' => news.isFeatured,
        'breaking' => news.isBreaking,
        _ => true,
      };
      final query = _searchQuery.toLowerCase();
      final matchesSearch =
          query.isEmpty ||
          news.title.toLowerCase().contains(query) ||
          (news.summary?.toLowerCase().contains(query) ?? false) ||
          (news.categoryName?.toLowerCase().contains(query) ?? false);
      return matchesStatus && matchesSearch;
    }).toList();
    switch (_sortMode) {
      case 'views':
        result.sort((a, b) => b.viewCount.compareTo(a.viewCount));
      case 'engagement':
        result.sort((a, b) => _engagement(b).compareTo(_engagement(a)));
      case 'oldest':
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      default:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _newsService.getMyNews(limit: 100),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Veri yükleme hatası: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Haber Stüdyosu'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverToBoxAdapter(child: _buildStats()),
                  SliverToBoxAdapter(child: _buildPerformanceInsight()),
                  SliverToBoxAdapter(child: _buildWorkspaceControls()),
                  if (_filteredNews.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  else
                    _buildNewsList(),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewsEditor(null),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Haber oluştur'),
      ),
    );
  }

  Widget _buildHeader() {
    final colors = Theme.of(context).colorScheme;
    final totalViews = _myNews.fold<int>(
      0,
      (sum, item) => sum + item.viewCount,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [colors.primary, colors.tertiary]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: .2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white70),
          const SizedBox(height: 12),
          const Text(
            'İçeriğini yönet,\netkini büyüt.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${_myNews.length} içerikle toplam ${_compactNumber(totalViews)} görüntülenme',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: colors.primary,
            ),
            onPressed: () => _openNewsEditor(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Yeni içerik'),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final published = _myNews.where((n) => n.isPublished).length;
    final draft = _myNews.where((n) => !n.isPublished).length;
    final featured = _myNews.where((n) => n.isFeatured).length;

    final engagement = _myNews.fold<int>(
      0,
      (sum, n) => sum + n.likeCount + n.commentCount + n.shareCount,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 18),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatCard(
              'Yayında',
              published,
              Colors.green,
              Icons.public_rounded,
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              'Taslak',
              draft,
              Colors.orange,
              Icons.edit_note_rounded,
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              'Öne çıkan',
              featured,
              Colors.purple,
              Icons.star_rounded,
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              'Etkileşim',
              engagement,
              Colors.blue,
              Icons.trending_up_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color, IconData icon) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .15),
            foregroundColor: color,
            child: Icon(icon, size: 19),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _compactNumber(count),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(title, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceInsight() {
    if (_myNews.isEmpty) return const SizedBox.shrink();
    final ranked = [..._myNews]
      ..sort(
        (a, b) => (b.viewCount + _engagement(b) * 3).compareTo(
          a.viewCount + _engagement(a) * 3,
        ),
      );
    final best = ranked.first;
    final published = _myNews.where((item) => item.isPublished).length;
    final publishRate = (published / _myNews.length * 100).round();
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_rounded, color: colors.secondary),
                    const SizedBox(width: 7),
                    const Text(
                      'Performans özeti',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'En güçlü içeriğin: “${best.title}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Text(
                  '${_compactNumber(best.viewCount)} görüntülenme • ${_compactNumber(_engagement(best))} etkileşim',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 78,
            height: 78,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: publishRate / 100,
                  strokeWidth: 7,
                  backgroundColor: colors.surface,
                  color: colors.secondary,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '%$publishRate',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const Text('yayın', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceControls() {
    const filters = <(String, String)>[
      ('all', 'Tümü'),
      ('published', 'Yayında'),
      ('draft', 'Taslak'),
      ('featured', 'Öne çıkan'),
      ('breaking', 'Son dakika'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'İçerik çalışma alanı',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
            decoration: InputDecoration(
              hintText: 'Haberlerimde ara',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...filters.map(
                  (filter) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter.$2),
                      selected: _statusFilter == filter.$1,
                      onSelected: (_) =>
                          setState(() => _statusFilter = filter.$1),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Sırala',
                  initialValue: _sortMode,
                  onSelected: (value) => setState(() => _sortMode = value),
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
                    avatar: Icon(Icons.sort_rounded, size: 18),
                    label: Text('Sırala'),
                  ),
                ),
              ],
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
          Text(
            _myNews.isEmpty ? 'Henüz haber yok' : 'Eşleşen içerik bulunamadı',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          if (_myNews.isEmpty)
            FilledButton.icon(
              onPressed: () => _openNewsEditor(null),
              icon: const Icon(Icons.add),
              label: const Text('İlk haberi oluştur'),
            ),
        ],
      ),
    );
  }

  Widget _buildNewsList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: _filteredNews.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildNewsCard(_filteredNews[index]),
      ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '⭐ ÖNE ÇIKAN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: news.isPublished
                                ? Colors.green
                                : Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            news.isPublished ? '✅ YAYINDA' : '📝 TASLAK',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      news.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      news.summary ??
                          news.content.substring(
                            0,
                            (news.content.length > 100
                                ? 100
                                : news.content.length),
                          ),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.visibility,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${news.viewCount}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.favorite, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${news.likeCount}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.comment, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${news.commentCount}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          news.formattedDate,
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
              PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'edit':
                      _openNewsEditor(news);
                      break;
                    case 'toggle_publish':
                      await _togglePublish(news);
                      break;
                    case 'engagements':
                      await _showEngagementDetails(news);
                      break;
                    case 'delete':
                      await _deleteNews(news);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('✏️ Düzenle')),
                  const PopupMenuItem(
                    value: 'engagements',
                    child: Text('📊 Etkileşim Detayları'),
                  ),
                  PopupMenuItem(
                    value: 'toggle_publish',
                    child: Text(
                      news.isPublished ? '📝 Taslağa Al' : '✅ Yayınla',
                    ),
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

  Future<void> _showEngagementDetails(NewsModel news) async {
    final detailsFuture = _newsService.getEngagementDetails(news.id);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
          child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
            future: detailsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Etkileşim detayları yüklenemedi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${snapshot.error}', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Kapat'),
                      ),
                    ],
                  ),
                );
              }

              final details = snapshot.data!;
              final viewers = details['viewers'] ?? const [];
              final likes = details['likes'] ?? const [];
              final comments = details['comments'] ?? const [];

              return DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Etkileşim Detayları',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  news.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Kapat',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(
                          text: 'Görüntüleyenler (${viewers.length})',
                          icon: const Icon(Icons.visibility),
                        ),
                        Tab(
                          text: 'Beğenenler (${likes.length})',
                          icon: const Icon(Icons.favorite),
                        ),
                        Tab(
                          text: 'Yorumlar (${comments.length})',
                          icon: const Icon(Icons.comment),
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildPeopleList(
                            viewers,
                            emptyText: 'Henüz görüntüleme yok',
                            subtitleBuilder: (item) {
                              final count =
                                  item['interaction_count'] as int? ?? 1;
                              return '$count görüntüleme • ${_formatInteractionDate(item['last_viewed_at'])}';
                            },
                          ),
                          _buildPeopleList(
                            likes,
                            emptyText: 'Henüz beğeni yok',
                            subtitleBuilder: (item) =>
                                'Beğendi • ${_formatInteractionDate(item['created_at'])}',
                          ),
                          _buildCommentList(comments),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPeopleList(
    List<Map<String, dynamic>> items, {
    required String emptyText,
    required String Function(Map<String, dynamic>) subtitleBuilder,
  }) {
    if (items.isEmpty) return _buildInteractionEmptyState(emptyText);

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: _buildUserAvatar(
            item['avatar_url'] as String?,
            item['user_name'] as String?,
          ),
          title: Text(item['user_name'] as String? ?? 'Kullanıcı'),
          subtitle: Text(subtitleBuilder(item)),
        );
      },
    );
  }

  Widget _buildCommentList(List<Map<String, dynamic>> comments) {
    if (comments.isEmpty) return _buildInteractionEmptyState('Henüz yorum yok');

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: comments.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final comment = comments[index];
        final isReply = comment['parent_id'] != null;
        return ListTile(
          leading: _buildUserAvatar(
            comment['avatar_url'] as String?,
            comment['user_name'] as String?,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(comment['user_name'] as String? ?? 'Kullanıcı'),
              ),
              if (isReply)
                const Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Yanıt', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(comment['content'] as String? ?? ''),
              const SizedBox(height: 4),
              Text(
                '${comment['like_count'] ?? 0} beğeni • ${_formatInteractionDate(comment['created_at'])}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInteractionEmptyState(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(String? avatarUrl, String? name) {
    final initial = (name?.trim().isNotEmpty ?? false)
        ? name!.trim().substring(0, 1).toUpperCase()
        : '?';
    return CircleAvatar(
      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
          ? CachedNetworkImageProvider(avatarUrl)
          : null,
      child: avatarUrl == null || avatarUrl.isEmpty ? Text(initial) : null,
    );
  }

  String _formatInteractionDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Tarih bilinmiyor';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.${date.year} $hour:$minute';
  }

  String _compactNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}B';
    }
    return '$value';
  }

  int _engagement(NewsModel news) =>
      news.likeCount + news.commentCount + news.shareCount;

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
          SnackBar(
            content: Text(
              news.isPublished
                  ? '📝 Haber taslağa alındı'
                  : '✅ Haber yayınlandı',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Hata: $e')));
      }
    }
  }

  Future<void> _deleteNews(NewsModel news) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning, color: Colors.red, size: 32),
        title: const Text('🗑️ Haberi Sil'),
        content: Text(
          '"${news.title}" haberini kalıcı olarak silmek istediğinizden emin misiniz?',
        ),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('✅ Haber silindi')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('❌ Silme hatası: $e')));
        }
      }
    }
  }
}
