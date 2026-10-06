import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/product_image_preset_model.dart';
import '../services/product_image_preset_service.dart';

/// Satıcının ürün eklerken admin kütüphanesinden hazır görsel seçtiği alt
/// sayfayı açar. Seçilen görsel döner; kapatılırsa `null`.
///
/// [initialQuery] arama kutusuna önceden yazılır (ürün adı). [addedUrls]
/// ürüne zaten eklenmiş görseller; bunlar "Eklendi" diye işaretlenir ve
/// seçilemez.
Future<ProductImagePreset?> showProductImageLibrarySheet(
  BuildContext context, {
  String initialQuery = '',
  Set<String> addedUrls = const {},
  ProductImagePresetService? service,
}) {
  return showModalBottomSheet<ProductImagePreset>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => ProductImageLibrarySheet(
      service: service ?? ProductImagePresetService(),
      initialQuery: initialQuery,
      addedUrls: addedUrls,
    ),
  );
}

/// Kütüphane görsel seçicisi: arama (Türkçe/aksan duyarsız, yazım hatasına
/// toleranslı — sunucuda), klasör çipleri, kaydırdıkça sayfa yükleme.
///
/// Tüm kelimeleriyle eşleşen görsel yoksa ve sorgu birden çok kelimeyse
/// ("domates 1 kg"), kelimelerden biriyle eşleşenler gösterilir ve bu
/// belirtilir.
class ProductImageLibrarySheet extends StatefulWidget {
  const ProductImageLibrarySheet({
    super.key,
    required this.service,
    this.initialQuery = '',
    this.addedUrls = const {},
  });

  final ProductImagePresetService service;
  final String initialQuery;
  final Set<String> addedUrls;

  @override
  State<ProductImageLibrarySheet> createState() =>
      _ProductImageLibrarySheetState();
}

class _ProductImageLibrarySheetState extends State<ProductImageLibrarySheet> {
  static const int _pageSize = ProductImagePresetService.pageSize;

  late final TextEditingController _search = TextEditingController(
    text: widget.initialQuery.trim(),
  );
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;

  List<ProductImageFolder> _folders = [];

  /// Seçili klasör; null = tümü.
  String? _folderId;

  final List<ProductImagePreset> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreFailed = false;
  bool _hasMore = false;

  /// Son sonuçlar "kelimelerden biri yeter" modunda mı (tam eşleşme yoktu).
  bool _matchAny = false;
  String? _error;

  /// Her yeni aramada artar; eski isteklerin geç gelen cevabı yok sayılır.
  int _request = 0;

  String get _query => _search.text.trim();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _loadFolders();
    _fetchFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await widget.service.getFolders();
      if (!mounted) return;
      // Satıcı yalnız açık klasörleri ve yayındaki görselleri sayar (RLS);
      // boş klasör çipi gösterilmez.
      setState(() => _folders = folders.where((f) => f.imageCount > 0).toList());
    } catch (_) {
      // Çipler isteğe bağlı; arama klasörsüz çalışmaya devam eder.
    }
  }

  /// Arama/klasör değişince: eldeki sonuçlar yenisi gelene kadar görünür
  /// kalır (üstte ince ilerleme çubuğu), sonra ilk sayfa yüklenir.
  Future<void> _reload() async {
    _debounce?.cancel();
    setState(() {
      _loading = true;
      _loadingMore = false;
      _moreFailed = false;
      _error = null;
    });
    await _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    final req = ++_request;
    final query = _query;
    final folderId = _folderId;
    try {
      var matchAny = false;
      var page = await widget.service.searchPresets(
        query,
        folderId: folderId,
        limit: _pageSize,
      );
      if (page.isEmpty && query.split(RegExp(r'\s+')).length > 1) {
        matchAny = true;
        page = await widget.service.searchPresets(
          query,
          folderId: folderId,
          limit: _pageSize,
          matchAny: true,
        );
      }
      if (!mounted || req != _request) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page);
        _matchAny = matchAny;
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    } catch (_) {
      if (!mounted || req != _request) return;
      setState(() {
        _loading = false;
        _error = 'Görseller yüklenemedi. Bağlantını kontrol edip tekrar dene.';
      });
    }
  }

  void _maybeLoadMore() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 400) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _moreFailed) return;
    final req = _request;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.searchPresets(
        _query,
        folderId: _folderId,
        limit: _pageSize,
        offset: _items.length,
        matchAny: _matchAny,
      );
      if (!mounted || req != _request) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || req != _request) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  void _onSearchChanged(String _) {
    setState(() {}); // temizle düğmesi
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  void _selectFolder(String? id) {
    if (_folderId == id) return;
    setState(() => _folderId = id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Material(
          color: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: _buildSearchField(accent),
              ),
              if (_folders.isNotEmpty) _buildFolderChips(accent),
              if (_matchAny && _items.isNotEmpty) _buildMatchAnyNote(),
              SizedBox(
                height: 2,
                child: _loading && _items.isNotEmpty
                    ? LinearProgressIndicator(
                        minHeight: 2,
                        color: accent,
                        backgroundColor: Colors.transparent,
                      )
                    : null,
              ),
              Expanded(child: _buildBody(accent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Görsel Kütüphanesi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ürününe uygun hazır görseli seç',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(Color accent) {
    return TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      onSubmitted: (_) => _reload(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Ürün adı ile ara (örn. domates)',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Temizle',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _search.clear();
                  setState(() {});
                  _reload();
                },
              ),
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildFolderChips(Color accent) {
    Widget chip(String? id, String label, {int? count}) {
      final selected = _folderId == id;
      return ChoiceChip(
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => _selectFolder(id),
        selectedColor: accent,
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? accent : Colors.grey.shade300),
        label: Text(
          count == null ? label : '$label · $count',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade800,
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        children: [
          chip(null, 'Tümü'),
          for (final f in _folders) ...[
            const SizedBox(width: 8),
            chip(f.id, f.name, count: f.imageCount),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchAnyNote() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '"$_query" için tam eşleşme yok; kelimelerinden biriyle '
              'eşleşenler gösteriliyor.',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(Color accent) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: 'Görseller yüklenemedi',
        subtitle: _error!,
        action: OutlinedButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tekrar dene'),
        ),
      );
    }
    if (_items.isEmpty) {
      final q = _query;
      return _Message(
        icon: Icons.image_search_rounded,
        title: q.isEmpty
            ? 'Bu klasörde görsel yok'
            : '"$q" için görsel bulunamadı',
        subtitle:
            'Farklı bir kelime dene ya da kendi fotoğrafını ekle. '
            'Kütüphaneye düzenli olarak yeni görseller ekleniyor.',
      );
    }

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              childAspectRatio: 0.8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildTile(_items[i], accent),
              childCount: _items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Center(child: _buildFooter()),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (_moreFailed) {
      return TextButton.icon(
        onPressed: () {
          setState(() => _moreFailed = false);
          _loadMore();
        },
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Devamı yüklenemedi · tekrar dene'),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTile(ProductImagePreset preset, Color accent) {
    final added = widget.addedUrls.contains(preset.imageUrl);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: added ? null : () => Navigator.pop(context, preset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.grey.shade100),
                  CachedNetworkImage(
                    imageUrl: preset.imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 360,
                    placeholder: (_, __) =>
                        ColoredBox(color: Colors.grey.shade100),
                    errorWidget: (_, __, ___) => Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  if (added)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Eklendi',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            preset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
