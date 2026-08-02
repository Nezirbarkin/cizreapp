// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/news_model.dart';
import '../services/news_service.dart';
import 'news_detail_screen.dart';

/// Modern, responsive ve dinamik haber keşif ekranı.
class NewsScreen extends StatefulWidget {
  final String? categoryId;
  final String? categoryName;

  const NewsScreen({super.key, this.categoryId, this.categoryName});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final NewsService _newsService = NewsService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<NewsModel> _news = [];
  List<NewsCategoryModel> _categories = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isSearching = false;
  String? _errorMessage;
  String? _selectedCategoryId;
  String _searchQuery = '';
  int _offset = 0;
  Timer? _searchDebounce;

  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.categoryId;
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _newsService.getCategories(),
        _newsService.getPublishedNews(
          limit: _limit,
          categoryId: _selectedCategoryId,
        ),
      ]);
      if (!mounted) return;
      final loadedNews = results[1] as List<NewsModel>;
      setState(() {
        _categories = results[0] as List<NewsCategoryModel>;
        _news = loadedNews;
        _offset = 0;
        _hasMore = loadedNews.length >= _limit;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Haber akışı şu anda yüklenemiyor.';
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isSearching) return;
    if (_scrollController.position.extentAfter < 500 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreNews();
    }
  }

  Future<void> _loadNews() async {
    if (_searchQuery.isNotEmpty) {
      await _searchNews(_searchQuery);
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _offset = 0;
    });
    try {
      final news = await _newsService.getPublishedNews(
        limit: _limit,
        categoryId: _selectedCategoryId,
      );
      if (!mounted) return;
      setState(() {
        _news = news;
        _isLoading = false;
        _hasMore = news.length >= _limit;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Haber akışı yenilenemedi.';
      });
    }
  }

  Future<void> _loadMoreNews() async {
    setState(() => _isLoadingMore = true);
    final nextOffset = _offset + _limit;
    try {
      final moreNews = await _newsService.getPublishedNews(
        limit: _limit,
        offset: nextOffset,
        categoryId: _selectedCategoryId,
      );
      if (!mounted) return;
      setState(() {
        _offset = nextOffset;
        _news.addAll(moreNews);
        _hasMore = moreNews.length >= _limit;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _searchNews(value.trim());
    });
  }

  Future<void> _searchNews(String query) async {
    _searchQuery = query;
    if (query.isEmpty) {
      await _loadNews();
      return;
    }
    setState(() {
      _isLoading = true;
      _isSearching = true;
      _errorMessage = null;
    });
    try {
      final results = await _newsService.searchNews(query);
      if (!mounted || query != _searchQuery) return;
      setState(() {
        _news = results;
        _isLoading = false;
        _hasMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Arama tamamlanamadı.';
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _searchQuery = '';
    setState(() => _isSearching = false);
    _loadNews();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInitialData,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar.large(
                pinned: true,
                title: Text(widget.categoryName ?? 'Gündem'),
                actions: [
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: _loadInitialData,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(child: _buildDiscoveryHeader()),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildMessageState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Bağlantı kurulamadı',
                    message: _errorMessage!,
                    actionText: 'Tekrar dene',
                    onAction: _loadInitialData,
                  ),
                )
              else if (_news.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildMessageState(
                    icon: Icons.search_off_rounded,
                    title: _searchQuery.isEmpty
                        ? 'Henüz haber yok'
                        : 'Sonuç bulunamadı',
                    message: _searchQuery.isEmpty
                        ? 'Yeni gelişmeler burada yayınlanacak.'
                        : 'Farklı bir kelime veya kategori deneyin.',
                    actionText: _searchQuery.isEmpty ? null : 'Aramayı temizle',
                    onAction: _searchQuery.isEmpty ? null : _clearSearch,
                  ),
                )
              else ...[
                if (!_isSearching)
                  SliverToBoxAdapter(child: _buildTopStories()),
                SliverToBoxAdapter(child: _buildSectionTitle()),
                _buildNewsSliver(),
                if (_isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoveryHeader() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Haber, kurum veya gündem ara',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Temizle',
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: .55,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = index == 0 ? null : _categories[index - 1];
                  final selected = category == null
                      ? _selectedCategoryId == null
                      : _selectedCategoryId == category.id;
                  return ChoiceChip(
                    selected: selected,
                    avatar: category == null
                        ? const Icon(Icons.grid_view_rounded, size: 17)
                        : null,
                    label: Text(category?.name ?? 'Tümü'),
                    onSelected: (_) {
                      setState(() => _selectedCategoryId = category?.id);
                      _loadNews();
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopStories() {
    final featured = _news
        .where((item) => item.isBreaking || item.isFeatured)
        .toList();
    final stories = featured.isEmpty
        ? _news.take(3).toList()
        : featured.take(5).toList();
    if (stories.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 720
            ? 620.0
            : constraints.maxWidth - 32;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Öne çıkanlar',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 300,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: stories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, index) => SizedBox(
                  width: width,
                  child: _buildHeroCard(stories[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeroCard(NewsModel news) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openNews(news),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(news.thumbnailUrl, iconSize: 58),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xDD09111F)],
                  stops: [.25, 1],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      if (news.isBreaking)
                        _buildBadge('SON DAKİKA', Colors.redAccent),
                      if (news.categoryName != null)
                        _buildBadge(news.categoryName!, Colors.white24),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    news.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          news.institutionName ??
                              news.authorName ??
                              'Haber Merkezi',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const Icon(
                        Icons.schedule_rounded,
                        color: Colors.white70,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _newsDate(news),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
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

  Widget _buildSectionTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _isSearching ? 'Arama sonuçları' : 'Son gelişmeler',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '${_news.length} haber',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildNewsSliver() {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.crossAxisExtent >= 1100
            ? 3
            : constraints.crossAxisExtent >= 680
            ? 2
            : 1;
        if (crossAxisCount == 1) {
          return SliverList.builder(
            itemCount: _news.length,
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildCompactCard(_news[index]),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.builder(
            itemCount: _news.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.55,
            ),
            itemBuilder: (_, index) => _buildCompactCard(_news[index]),
          ),
        );
      },
    );
  }

  Widget _buildCompactCard(NewsModel news) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openNews(news),
        child: SizedBox(
          height: 142,
          child: Row(
            children: [
              SizedBox(
                width: 132,
                height: double.infinity,
                child: _buildImage(news.thumbnailUrl),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (news.isBreaking) ...[
                            const Icon(
                              Icons.bolt_rounded,
                              size: 15,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 3),
                          ],
                          Expanded(
                            child: Text(
                              news.categoryName?.toUpperCase() ?? 'GÜNDEM',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .4,
                              ),
                            ),
                          ),
                          Text(
                            _newsDate(news),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        news.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              news.institutionName ??
                                  news.authorName ??
                                  'Haber Merkezi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          _metric(Icons.visibility_outlined, news.viewCount),
                          const SizedBox(width: 9),
                          _metric(
                            Icons.favorite_border_rounded,
                            news.likeCount,
                          ),
                          const SizedBox(width: 9),
                          _metric(
                            Icons.chat_bubble_outline_rounded,
                            news.commentCount,
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

  Widget _buildImage(String? url, {double iconSize = 38}) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.newspaper_rounded,
          size: iconSize,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
    if (url == null || url.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _metric(IconData icon, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 3),
        Text(
          _compactNumber(count),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String message,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openNews(NewsModel news) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewsDetailScreen(news: news)),
    );
  }

  String _newsDate(NewsModel news) => news.publishedFormattedDate.isNotEmpty
      ? news.publishedFormattedDate
      : news.formattedDate;

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
