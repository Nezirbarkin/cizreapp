// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/product_image_preset_model.dart';
import '../../market/services/product_image_preset_service.dart';
import '../../market/services/product_image_scrape_service.dart';
import '../../market/widgets/product_image_link_sheet.dart';
import 'admin_ui.dart';

/// Admin > Ürün Görsel Kütüphanesi.
///
/// Satıcıların ürün eklerken kendi fotoğraflarını yüklemek yerine seçebileceği
/// hazır görseller. Her görsel bir `product_image_presets` satırıdır (görsel +
/// ad + arama kelimeleri) ve bir klasörde durabilir (Market, Kozmetik…).
/// Admin tek seferde BİRDEN ÇOK görsel seçip her birine ayrı ad verebilir;
/// ızgaradan arar, klasöre/duruma göre süzer, sıralar, düzenler, klasöre taşır
/// ve toplu yayına alır / pasife çeker / siler. Klasörler "Klasörler"
/// sayfasından eklenir, sıralanır, kapatılır (kapalı klasörün görselleri
/// satıcılara gösterilmez).
///
/// Kütüphane binlerce görsel olduğu için istemciye inmez: süzme, arama,
/// sıralama ve sayaçlar sunucuda (`admin_product_image_presets_page`), ızgara
/// kaydırdıkça sayfa sayfa yüklenir. Açılış = bir sayfa + kütüphane özeti.
class ProductImageLibraryContent extends StatefulWidget {
  const ProductImageLibraryContent({
    super.key,
    this.service,
    this.scrapeService,
  });

  /// Testlerde sahte servis vermek için; verilmezse gerçek servis kullanılır.
  final ProductImagePresetService? service;

  /// "Linkten ekle" için; testlerde sahte servis verilir.
  final ProductImageScrapeService? scrapeService;

  @override
  State<ProductImageLibraryContent> createState() =>
      _ProductImageLibraryContentState();
}

/// Klasör süzgecinde "tüm klasörler" ve "klasörsüz" değerleri (diğerleri
/// klasör id'si).
const String _allFolders = '';
const String _unfiled = '-';

/// Düzenleme sayfasının "silindi" sonucu (kaydedince güncel görsel döner).
const String _deletedResult = 'deleted';

String _cleanError(Object e) =>
    e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

class _ProductImageLibraryContentState
    extends State<ProductImageLibraryContent> {
  late final ProductImagePresetService _service =
      widget.service ?? ProductImagePresetService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Arama kutusu yazmanın durmasını bu kadar bekler (her harfte istek
  /// gitmesin).
  static const Duration _searchDelay = Duration(milliseconds: 275);

  /// Listenin sonuna bu kadar piksel kala sonraki sayfa istenir (~4–5 sıra).
  /// Yükleme ızgaranın ön yükleme alanına (cacheExtent) değil kaydırma yerine
  /// bakar: açılışta geniş ekranda da yalnız bir sayfa iner.
  static const double _loadAhead = 1000;

  /// Aynı süzgeç yenilenirken en fazla bu kadar satır yeniden istenir
  /// (sunucunun üst sınırı).
  static const int _maxReload = 500;

  /// Yüklenmiş sayfalar: süzgece uyan sıralı listenin BAŞI.
  List<ProductImagePreset> _items = const [];

  /// Süzgece uyan toplam (sunucudan); `_items`'tan fazlaysa sonraki sayfa var.
  int _total = 0;

  /// Kütüphanenin tamamının sayaçları (klasör çipleri, durum kutuları);
  /// açılışta ve her değişiklikten sonra sunucudan tazelenir.
  ProductImageLibrarySummary _summary = const ProductImageLibrarySummary();
  bool _summaryLoaded = false;

  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _loadMoreScheduled = false;
  String? _error;
  String? _pageError;

  /// Arama kutusundaki metin (anında) ve sunucuya giden arama (bekleyişten
  /// sonra).
  String _query = '';
  String _search = '';
  Timer? _searchTimer;

  String _folderFilter = _allFolders;
  ProductImageAdminStatus _filter = ProductImageAdminStatus.all;
  ProductImageAdminSort _sort = ProductImageAdminSort.order;
  final Set<String> _selected = {};
  bool _busy = false;
  bool _selectingAll = false;

  /// Her yeni ilk sayfa isteğinde artar; eski süzgecin yanıtı atılır.
  int _listGen = 0;

  /// Sonraki sayfa isteğinin kuşağı: yerel değişiklik (silme, taşıma)
  /// ofseti kaydırdığı için süren sayfa isteği geçersiz sayılır.
  int _pageGen = 0;

  /// Yalnız en son sayaç tazelemesinin yanıtı uygulanır.
  int _countsGen = 0;

  bool get _selecting => _selected.isNotEmpty;

  bool get _hasMore => _items.length < _total;

  ProductImageAdminQuery get _currentQuery => ProductImageAdminQuery(
    folderId: _folderFilter == _allFolders || _folderFilter == _unfiled
        ? null
        : _folderFilter,
    unfiled: _folderFilter == _unfiled,
    status: _filter,
    search: _search,
    sort: _sort,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _reload();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Veri
  // -------------------------------------------------------------------------

  /// Süzgecin ilk sayfasını ister.
  ///
  /// [keep] true ise aynı süzgeç yenileniyor (aşağı çekme; ekleme, düzenleme,
  /// klasör değişikliğinden sonra): eldeki kadar satır yeniden istenir ki
  /// kaydırma yeri korunsun, özet de tazelenir, hata olursa liste bozulmaz.
  /// false ise süzgeç değişti: tek sayfa.
  Future<void> _reload({bool keep = false}) async {
    final gen = ++_listGen;
    _pageGen++;
    _countsGen++;
    final withSummary = keep || !_summaryLoaded;
    final limit = keep
        ? _items.length.clamp(
            ProductImagePresetService.adminPageSize,
            _maxReload,
          )
        : ProductImagePresetService.adminPageSize;
    setState(() {
      _loadingMore = false;
      _pageError = null;
      if (!_loading) _refreshing = true;
      if (!keep) _error = null;
    });
    try {
      final page = await _service.getAdminPage(
        _currentQuery,
        limit: limit,
        withSummary: withSummary,
      );
      if (!mounted || gen != _listGen) return;
      // Yeni süzgecin listesi baştan gösterilir.
      if (!keep && _scroll.hasClients) _scroll.jumpTo(0);
      var folderGone = false;
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
        _refreshing = false;
        _error = null;
        if (page.summary != null) folderGone = _applySummary(page.summary!);
      });
      if (folderGone) await _reload();
    } catch (e) {
      if (!mounted || gen != _listGen) return;
      final quiet = keep && _summaryLoaded;
      setState(() {
        _loading = false;
        _refreshing = false;
        // Yenilemede eldeki liste bozulmasın.
        if (!quiet) _error = _cleanError(e);
      });
      if (quiet) _snack(_cleanError(e), error: true);
    }
  }

  /// Özeti uygular (setState içinde). Süzülen klasör artık yoksa (silindi)
  /// tüm klasörlere döner ve true döndürür: çağıran o listeyi istemeli.
  bool _applySummary(ProductImageLibrarySummary summary) {
    _summary = summary;
    _summaryLoaded = true;
    if (_folderFilter != _allFolders &&
        _folderFilter != _unfiled &&
        !summary.folders.any((f) => f.id == _folderFilter)) {
      _folderFilter = _allFolders;
      return true;
    }
    return false;
  }

  /// Değişiklikten sonra sayaçlar (özet + süzgece uyan toplam) sunucudan
  /// tazelenir; yüklü liste yerelde zaten güncel.
  Future<void> _refreshCounts() async {
    final gen = ++_countsGen;
    final listGen = _listGen;
    try {
      final page = await _service.getAdminPage(
        _currentQuery,
        limit: 0,
        withSummary: true,
      );
      if (!mounted || gen != _countsGen) return;
      var folderGone = false;
      setState(() {
        if (listGen == _listGen) _total = page.total;
        if (page.summary != null) folderGone = _applySummary(page.summary!);
      });
      if (folderGone) await _reload();
    } catch (_) {
      // Sayaçlar bir sonraki yenilemede düzelir; eldeki liste bozulmasın.
    }
  }

  /// Kare çizildikten sonra kaydırma yerine bakılır (liste ekranı
  /// doldurmuyorsa ya da işlem bitip ızgara yeniden kurulduysa).
  void _scheduleLoadMore() {
    if (_loadMoreScheduled || !_hasMore || _pageError != null) return;
    _loadMoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreScheduled = false;
      if (mounted) _maybeLoadMore();
    });
  }

  /// Listenin sonuna [_loadAhead]'den az kaldıysa sonraki sayfa istenir.
  void _maybeLoadMore() {
    if (!_hasMore) return;
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      if (pos.hasContentDimensions && pos.extentAfter > _loadAhead) return;
    }
    _loadMore();
  }

  /// Sonraki sayfa. Toplu işlem sürerken istenmez: sunucu henüz eski
  /// durumdayken yerelde çıkarılan görseller yeniden gelirdi (işlem bitince
  /// ızgara yeniden kurulur ve istek o zaman gider).
  Future<void> _loadMore() async {
    if (!_hasMore ||
        _loading ||
        _refreshing ||
        _loadingMore ||
        _busy ||
        _pageError != null ||
        _error != null) {
      return;
    }
    final listGen = _listGen;
    final pageGen = _pageGen;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.getAdminPage(
        _currentQuery,
        offset: _items.length,
      );
      if (!mounted || listGen != _listGen || pageGen != _pageGen) return;
      final have = {for (final p in _items) p.id};
      final fresh = page.items.where((p) => !have.contains(p.id)).toList();
      setState(() {
        _items = [..._items, ...fresh];
        // Sunucu listesi arada kaydıysa (başka cihazdan ekleme) yalnız
        // eldeki satırlar gelebilir; ilerleme yoksa durulur ki istek döngüsü
        // olmasın (aşağı çekince tazelenir).
        _total = fresh.isEmpty ? _items.length : page.total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || listGen != _listGen || pageGen != _pageGen) return;
      setState(() {
        _loadingMore = false;
        _pageError = _cleanError(e);
      });
    }
  }

  /// Süzgeç, sıralama ya da arama değişti: ilk sayfa istenir. Bekleyen arama
  /// metni de hemen uygulanır.
  void _setQuery(VoidCallback change) {
    _searchTimer?.cancel();
    final before = _currentQuery;
    change();
    _search = _query.trim();
    if (_currentQuery == before) {
      setState(() {});
      return;
    }
    _reload();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDelay, () {
      if (mounted) _setQuery(() {});
    });
  }

  /// Süren sonraki sayfa isteğini geçersiz kılar (setState içinde): yerel
  /// değişiklik ofseti kaydırır, sayfa yeniden istenir.
  void _dropPendingPage() {
    _pageGen++;
    _loadingMore = false;
  }

  bool _matchesFilter(ProductImagePreset p) {
    final inFolder = switch (_folderFilter) {
      _allFolders => true,
      _unfiled => p.folderId == null,
      final id => p.folderId == id,
    };
    final inStatus = switch (_filter) {
      ProductImageAdminStatus.all => true,
      ProductImageAdminStatus.active => p.isActive,
      ProductImageAdminStatus.passive => !p.isActive,
    };
    return inFolder && inStatus;
  }

  /// Yüklü listede [ids]'e [change] uygulanır (null = silindi; setState
  /// içinde). Süzgece artık uymayanlar listeden çıkar, toplam o kadar azalır.
  /// Ad değişikliği aramayla yeniden karşılaştırılmaz (yeni düzenlenen görsel
  /// gözden kaybolmasın).
  void _applyLocal(
    Set<String> ids,
    ProductImagePreset? Function(ProductImagePreset p) change,
  ) {
    final next = <ProductImagePreset>[];
    for (final p in _items) {
      if (!ids.contains(p.id)) {
        next.add(p);
        continue;
      }
      final changed = change(p);
      if (changed != null && _matchesFilter(changed)) next.add(changed);
    }
    _total -= _items.length - next.length;
    _items = next;
  }

  bool _allLoaded(Set<String> ids) {
    var n = 0;
    for (final p in _items) {
      if (ids.contains(p.id)) n++;
    }
    return n == ids.length;
  }

  /// İşlemden sonra: etkilenenlerin hepsi yüklüyse yerel liste doğru, yalnız
  /// sayaçlar tazelenir. Yüklenmemiş görsel de etkilendiyse ("süzgece
  /// uyanların tümü" seçimi) ya da işlem yarıda kaldıysa (toplu işlem parça
  /// parça gider) liste de sunucudan yeniden istenir.
  Future<void> _syncAfterChange({required bool listExact}) =>
      listExact ? _refreshCounts() : _reload(keep: true);

  /// Klasör başına görsel sayısı (tüm durumlar); null anahtarı = klasörsüz.
  Map<String?, ({int all, int active})> get _folderCounts => {
    for (final f in _summary.folders)
      f.id: (all: f.imageCount, active: f.activeImageCount),
    null: (all: _summary.unfiledCount, active: _summary.unfiledActiveCount),
  };

  /// Seçili klasör kapsamındaki sayılar (durum kutuları; aramadan bağımsız).
  ({int all, int active}) get _scopeCounts {
    switch (_folderFilter) {
      case _allFolders:
        return (all: _summary.totalCount, active: _summary.activeCount);
      case _unfiled:
        return (
          all: _summary.unfiledCount,
          active: _summary.unfiledActiveCount,
        );
    }
    for (final f in _summary.folders) {
      if (f.id == _folderFilter) {
        return (all: f.imageCount, active: f.activeImageCount);
      }
    }
    return (all: 0, active: 0);
  }

  String? _folderName(String? id) {
    if (id == null) return null;
    for (final f in _summary.folders) {
      if (f.id == id) return f.name;
    }
    return null;
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.red.shade700 : null,
        ),
      );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // -------------------------------------------------------------------------
  // Eylemler
  // -------------------------------------------------------------------------

  Future<void> _openAdd() async {
    final saved = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => _AddImagesSheet(
        service: _service,
        scrapeService: widget.scrapeService,
        startOrder: _summary.maxDisplayOrder + 1,
        folders: _summary.folders,
        // Bir klasör süzülüyorsa yeni görseller oraya eklenir.
        initialFolderId:
            _folderFilter == _allFolders || _folderFilter == _unfiled
            ? null
            : _folderFilter,
      ),
    );
    if (saved != null && saved > 0) {
      _snack('$saved görsel kütüphaneye eklendi');
    }
    if (saved != null && mounted) await _reload(keep: true);
  }

  Future<void> _openEdit(ProductImagePreset preset) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _EditPresetSheet(
        preset: preset,
        service: _service,
        folders: _summary.folders,
      ),
    );
    if (result == null || !mounted) return;
    final deleted = result == _deletedResult;
    setState(() {
      _dropPendingPage();
      // Sıra numarası/adı değiştiyse yeni yerini bir sonraki yenilemede alır.
      _applyLocal({
        preset.id,
      }, (_) => result is ProductImagePreset ? result : null);
      if (deleted) _selected.remove(preset.id);
    });
    _snack(deleted ? 'Görsel silindi' : 'Görsel güncellendi');
    await _refreshCounts();
  }

  Future<void> _openFolders() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _FoldersSheet(
        service: _service,
        folders: _summary.folders,
        counts: _folderCounts,
      ),
    );
    if (changed == true && mounted) await _reload(keep: true);
  }

  Future<void> _move(Set<String> ids) async {
    if (ids.isEmpty || _busy) return;
    final known = _items.where((p) => ids.contains(p.id)).toList();
    final allLoaded = known.length == ids.length;
    final picked = await showModalBottomSheet<_FolderChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (_) => _FolderPickerSheet(
        service: _service,
        folders: _summary.folders,
        count: ids.length,
        // Yüklenmemiş görsellerin klasörü bilinmez: "şu anki" işaretlenmez.
        current: allLoaded
            ? {for (final p in known) p.folderId}
            : const <String?>{},
      ),
    );
    if (picked == null || !mounted) return;

    final target = picked.folderId;
    final beforeItems = _items;
    final beforeTotal = _total;
    var ok = false;
    setState(() {
      _busy = true;
      _dropPendingPage();
      if (picked.created != null) {
        _summary = _summary.copyWith(
          folders: [..._summary.folders, picked.created!],
        );
      }
      // İyimser güncelleme: arayüz anında değişsin, hata olursa geri alınır.
      _applyLocal(ids, (p) => p.withFolder(target));
    });
    try {
      await _service.moveToFolder(ids.toList(), target);
      ok = true;
      if (!mounted) return;
      _selected.clear();
      final where = target == null
          ? 'klasörsüz bırakıldı'
          : '"${_folderName(target) ?? 'klasör'}" klasörüne taşındı';
      _snack(ids.length == 1 ? 'Görsel $where' : '${ids.length} görsel $where');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = beforeItems;
        _total = beforeTotal;
      });
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _syncAfterChange(listExact: ok && allLoaded);
  }

  Future<void> _setActive(Set<String> ids, bool active) async {
    if (ids.isEmpty || _busy) return;
    final allLoaded = _allLoaded(ids);
    final beforeItems = _items;
    final beforeTotal = _total;
    var ok = false;
    setState(() {
      _busy = true;
      _dropPendingPage();
      // İyimser güncelleme: arayüz anında değişsin, hata olursa geri alınır.
      _applyLocal(ids, (p) => p.copyWith(isActive: active));
    });
    try {
      await _service.setActive(ids.toList(), active);
      ok = true;
      if (!mounted) return;
      _snack(
        ids.length == 1
            ? (active ? 'Görsel yayına alındı' : 'Görsel pasife alındı')
            : '${ids.length} görsel ${active ? 'yayına alındı' : 'pasife alındı'}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = beforeItems;
        _total = beforeTotal;
      });
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _syncAfterChange(listExact: ok && allLoaded);
  }

  Future<void> _delete(Set<String> ids) async {
    if (ids.isEmpty || _busy) return;
    final known = _items.where((p) => ids.contains(p.id)).toList();
    final allLoaded = known.length == ids.length;
    final single = ids.length == 1;
    final ok = await _confirm(
      title: single
          ? 'Görsel silinsin mi?'
          : '${ids.length} görsel silinsin mi?',
      message: single && known.isNotEmpty
          ? '"${known.first.name}" kütüphaneden kalıcı olarak kaldırılır. '
                'Bu görseli daha önce seçmiş ürünler etkilenmez.'
          : 'Seçili görseller kütüphaneden kalıcı olarak kaldırılır. '
                'Bunları daha önce seçmiş ürünler etkilenmez.',
      confirmLabel: 'Sil',
    );
    if (!ok || !mounted || _busy) return;

    final beforeItems = _items;
    final beforeTotal = _total;
    var done = false;
    setState(() {
      _busy = true;
      _dropPendingPage();
      _applyLocal(ids, (_) => null);
    });
    try {
      await _service.deletePresets(ids.toList());
      done = true;
      if (!mounted) return;
      _selected.removeAll(ids);
      _snack(single ? 'Görsel silindi' : '${ids.length} görsel silindi');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = beforeItems;
        _total = beforeTotal;
      });
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _syncAfterChange(listExact: done && allLoaded);
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  /// "Süzgece uyanların tümünü seç": yalnız yüklü sayfalar değil, klasör /
  /// durum / arama süzgecine uyan TÜM görseller seçilir; yüklenmemişlerin
  /// yalnız kimlikleri sunucudan gelir. Hepsi zaten yüklüyse istek gitmez.
  /// Sonuç gelmeden süzgeç değişirse yok sayılır.
  Future<void> _selectAllMatching() async {
    if (_selectingAll) return;
    if (!_hasMore) {
      setState(() => _selected.addAll(_items.map((p) => p.id)));
      return;
    }
    final listGen = _listGen;
    setState(() => _selectingAll = true);
    try {
      final ids = await _service.getAdminPresetIds(_currentQuery);
      if (!mounted || listGen != _listGen) return;
      setState(() => _selected.addAll(ids));
      _snack('Süzgece uyan ${ids.length} görselin tümü seçildi');
    } catch (e) {
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _selectingAll = false);
    }
  }

  // -------------------------------------------------------------------------
  // Arayüz
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AdminUi.page,
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxWidth < 600;
          return Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    children: [
                      _buildHeader(compact),
                      Expanded(child: _buildBody()),
                    ],
                  ),
                ),
              ),
              if (compact && !_selecting && !_loading && _error == null)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    onPressed: _openAdd,
                    backgroundColor: AdminUi.brand,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('Görsel Ekle'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    final scope = _scopeCounts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selecting)
            _buildSelectionBar()
          else
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AdminUi.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.photo_library_rounded,
                    color: AdminUi.brand,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ürün Görsel Kütüphanesi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AdminUi.ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Satıcılar ürün eklerken buradan hazır görsel seçer',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AdminUi.muted),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _openAdd,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('Görsel Ekle'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminUi.brand,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 14),
          _buildFolderBar(compact),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FilterStat(
                  icon: Icons.grid_view_rounded,
                  label: 'Tümü',
                  value: scope.all,
                  color: AdminUi.brand,
                  selected: _filter == ProductImageAdminStatus.all,
                  onTap: () =>
                      _setQuery(() => _filter = ProductImageAdminStatus.all),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterStat(
                  icon: Icons.visibility_rounded,
                  label: 'Yayında',
                  value: scope.active,
                  color: Colors.green.shade600,
                  selected: _filter == ProductImageAdminStatus.active,
                  onTap: () =>
                      _setQuery(() => _filter = ProductImageAdminStatus.active),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterStat(
                  icon: Icons.visibility_off_rounded,
                  label: 'Pasif',
                  value: scope.all - scope.active,
                  color: Colors.blueGrey.shade500,
                  selected: _filter == ProductImageAdminStatus.passive,
                  onTap: () => _setQuery(
                    () => _filter = ProductImageAdminStatus.passive,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _setQuery(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Görsel adı veya arama kelimesi ara',
                    hintStyle: const TextStyle(
                      fontSize: 13.5,
                      color: AdminUi.muted,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 22),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: 'Temizle',
                            onPressed: () {
                              _searchController.clear();
                              _setQuery(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AdminUi.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AdminUi.brand, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ProductImageAdminSort>(
                tooltip: 'Sırala',
                initialValue: _sort,
                onSelected: (v) => _setQuery(() => _sort = v),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: ProductImageAdminSort.order,
                    child: Text('Sıra numarasına göre'),
                  ),
                  PopupMenuItem(
                    value: ProductImageAdminSort.newest,
                    child: Text('En yeni önce'),
                  ),
                ],
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AdminUi.line),
                  ),
                  child: const Icon(
                    Icons.swap_vert_rounded,
                    color: AdminUi.ink,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Klasör çipleri (tümü / her klasör / klasörsüz) + klasör yönetimi.
  /// Dar ekranda yönetim düğmesi yalnız simgedir ki çiplere yer kalsın.
  Widget _buildFolderBar(bool compact) {
    final unfiled = _summary.unfiledCount;
    return Row(
      children: [
        Expanded(
          child: AdminChipBar<String>(
            selected: _folderFilter,
            onSelected: (v) => _setQuery(() => _folderFilter = v),
            items: [
              (
                value: _allFolders,
                label: 'Tüm klasörler',
                icon: Icons.folder_copy_rounded,
                count: _summary.totalCount,
              ),
              for (final f in _summary.folders)
                (
                  value: f.id,
                  label: f.isActive ? f.name : '${f.name} (kapalı)',
                  icon: f.isActive
                      ? Icons.folder_rounded
                      : Icons.visibility_off_rounded,
                  count: f.imageCount,
                ),
              if (unfiled > 0 || _folderFilter == _unfiled)
                (
                  value: _unfiled,
                  label: 'Klasörsüz',
                  icon: Icons.folder_off_outlined,
                  count: unfiled,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (compact)
          IconButton.outlined(
            tooltip: 'Klasörler',
            onPressed: _loading ? null : _openFolders,
            icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: AdminUi.brand,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AdminUi.line),
              fixedSize: const Size(38, 38),
              minimumSize: const Size(38, 38),
              padding: EdgeInsets.zero,
            ),
          )
        else
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _openFolders,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Klasörler'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminUi.brand,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AdminUi.line),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSelectionBar() {
    final locked = _busy || _selectingAll;
    return AdminCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: AdminUi.brandSoft,
      borderColor: AdminUi.brand.withValues(alpha: 0.3),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Seçimi bırak',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(_selected.clear),
          ),
          Expanded(
            child: Text(
              '${_selected.length} seçildi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AdminUi.brand,
              ),
            ),
          ),
          IconButton(
            // Yalnız yüklü sayfalar değil, süzgece uyan TÜM görseller.
            tooltip: 'Süzgece uyanların tümünü seç',
            icon: _selectingAll
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.select_all_rounded),
            onPressed: locked ? null : _selectAllMatching,
          ),
          IconButton(
            tooltip: 'Klasöre taşı',
            icon: Icon(Icons.drive_file_move_outline, color: AdminUi.brand),
            onPressed: locked ? null : () => _move({..._selected}),
          ),
          IconButton(
            tooltip: 'Yayına al',
            icon: Icon(Icons.visibility_rounded, color: Colors.green.shade700),
            onPressed: locked ? null : () => _setActive({..._selected}, true),
          ),
          IconButton(
            tooltip: 'Pasife al',
            icon: Icon(
              Icons.visibility_off_rounded,
              color: Colors.blueGrey.shade600,
            ),
            onPressed: locked ? null : () => _setActive({..._selected}, false),
          ),
          IconButton(
            tooltip: 'Sil',
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.red.shade600,
            ),
            onPressed: locked ? null : () => _delete({..._selected}),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildSkeleton();

    if (_error != null) {
      return AdminEmpty(
        icon: Icons.cloud_off_rounded,
        title: 'Görseller yüklenemedi',
        subtitle: _error,
        action: OutlinedButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tekrar dene'),
        ),
      );
    }

    if (_summary.totalCount == 0 && _total == 0 && !_refreshing) {
      return AdminEmpty(
        icon: Icons.photo_library_outlined,
        title: 'Henüz görsel eklenmedi',
        subtitle:
            'Birden fazla görseli aynı anda seçip her birine ayrı ad '
            'verebilirsin.',
        action: FilledButton.icon(
          onPressed: _openAdd,
          icon: const Icon(Icons.add_photo_alternate_rounded),
          label: const Text('İlk görselleri ekle'),
          style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
        ),
      );
    }

    if (_items.isEmpty) {
      // Yeni süzgecin ilk sayfası ya da (yerel çıkarmalardan sonra) sonraki
      // sayfa bekleniyor.
      if (_refreshing) return _buildSkeleton();
      if (_hasMore) {
        _scheduleLoadMore();
        return _buildFooter();
      }
      if (_scopeCounts.all == 0 && _folderFilter != _unfiled) {
        return AdminEmpty(
          icon: Icons.folder_open_rounded,
          title: 'Bu klasörde henüz görsel yok',
          subtitle:
              'Görsel eklerken bu klasör seçili gelir; başka klasördeki '
              'görselleri "Klasöre taşı" ile buraya alabilirsin.',
          action: FilledButton.icon(
            onPressed: _openAdd,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text('Bu klasöre görsel ekle'),
            style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
          ),
        );
      }
      return AdminEmpty(
        icon: Icons.search_off_rounded,
        title: 'Sonuç bulunamadı',
        subtitle: 'Aramayı ya da filtreyi değiştirmeyi dene.',
        action: TextButton(
          onPressed: () {
            _searchController.clear();
            _setQuery(() {
              _query = '';
              _filter = ProductImageAdminStatus.all;
              _folderFilter = _allFolders;
            });
          },
          child: const Text('Filtreleri temizle'),
        ),
      );
    }

    final items = _items;
    _scheduleLoadMore();
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _reload(keep: true),
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            // Görseller ekrana girmeden ~bir ekran önce yüklenmeye başlar.
            cacheExtent: 900,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final p = items[i];
                    return _PresetTile(
                      key: ValueKey(p.id),
                      preset: p,
                      // Tek klasöre bakarken her kartta klasör adı tekrar
                      // etmesin.
                      folderName: _folderFilter == _allFolders
                          ? _folderName(p.folderId)
                          : null,
                      selected: _selected.contains(p.id),
                      selecting: _selecting,
                      onTap: () =>
                          _selecting ? _toggleSelect(p.id) : _openEdit(p),
                      onLongPress: () => _toggleSelect(p.id),
                      onMenu: (v) {
                        switch (v) {
                          case 'edit':
                            _openEdit(p);
                          case 'move':
                            _move({p.id});
                          case 'toggle':
                            _setActive({p.id}, !p.isActive);
                          case 'select':
                            _toggleSelect(p.id);
                          case 'delete':
                            _delete({p.id});
                        }
                      },
                    );
                  }, childCount: items.length),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                sliver: SliverToBoxAdapter(child: _buildFooter()),
              ),
            ],
          ),
        ),
        // Süzgeç değişti ya da yenileniyor: eski liste yeni sayfa gelene
        // kadar kalır.
        if (_refreshing)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  /// Izgaranın altı: sonraki sayfa yükleniyor / yüklenemedi. Dönen gösterge
  /// yalnız istek sürerken kurulur (sürekli dönen gösterge ekran dışında da
  /// kare çizdirir).
  Widget _buildFooter() {
    if (_pageError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Devamı yüklenemedi: $_pageError',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _pageError = null);
                _loadMore();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: _hasMore ? 56 : 0,
      child: _loadingMore
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : null,
    );
  }

  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE9EAF0),
      highlightColor: const Color(0xFFF7F8FB),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.8,
        ),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Izgara parçaları
// ===========================================================================

/// Üstteki özet kutusu: sayıyı gösterir, dokununca filtre olur.
class _FilterStat extends StatelessWidget {
  const _FilterStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      color: selected ? color.withValues(alpha: 0.08) : null,
      borderColor: selected ? color : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(height: 5),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AdminUi.ink,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? color : AdminUi.muted,
            ),
          ),
        ],
      ),
    );
  }
}

const ColorFilter _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    super.key,
    required this.preset,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
    this.folderName,
  });

  final ProductImagePreset preset;

  /// Verilirse görselin sağ altında klasör etiketi gösterilir.
  final String? folderName;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final active = preset.isActive;
    final keywords = (preset.description ?? '').trim();

    Widget image = CachedNetworkImage(
      imageUrl: preset.imageUrl,
      fit: BoxFit.cover,
      memCacheWidth: 480,
      // Varsayılan 500+1000 ms geçiş kaydırırken ağır hissettirir.
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFFEDEEF3)),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFFEDEEF3),
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: AdminUi.muted),
        ),
      ),
    );
    if (!active) image = ColorFiltered(colorFilter: _grayscale, child: image);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AdminUi.brand : AdminUi.line,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image,
                      if (!active)
                        ColoredBox(color: Colors.white.withValues(alpha: 0.35)),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _OverlayPill(text: '#${preset.displayOrder}'),
                      ),
                      if (folderName != null)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          left: 56,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _OverlayPill(
                              text: folderName!,
                              icon: Icons.folder_rounded,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: selecting
                            ? _CheckDot(checked: selected)
                            : (active
                                  ? const SizedBox.shrink()
                                  : const _OverlayPill(
                                      text: 'Pasif',
                                      icon: Icons.visibility_off_rounded,
                                    )),
                      ),
                      if (!selecting)
                        Positioned(right: 6, top: 6, child: _buildMenu(active)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AdminUi.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        keywords.isEmpty ? 'Arama kelimesi yok' : keywords,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: keywords.isEmpty
                              ? AdminUi.muted.withValues(alpha: 0.6)
                              : AdminUi.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(bool active) {
    return PopupMenuButton<String>(
      tooltip: 'İşlemler',
      padding: EdgeInsets.zero,
      onSelected: onMenu,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: _MenuRow(Icons.edit_rounded, 'Düzenle'),
        ),
        const PopupMenuItem(
          value: 'move',
          child: _MenuRow(Icons.drive_file_move_outline, 'Klasöre taşı'),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: _MenuRow(
            active ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            active ? 'Pasife al' : 'Yayına al',
          ),
        ),
        const PopupMenuItem(
          value: 'select',
          child: _MenuRow(Icons.check_circle_outline_rounded, 'Seç'),
        ),
        PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            Icons.delete_outline_rounded,
            'Sil',
            color: Colors.red.shade600,
          ),
        ),
      ],
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: AdminUi.ink,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: color ?? AdminUi.ink),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 3),
          ],
          // Dar yerde (ör. kartta klasör adı) üç noktayla kısalır.
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: checked ? AdminUi.brand : Colors.white.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: checked ? AdminUi.brand : Colors.black26,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
          : null,
    );
  }
}

// ===========================================================================
// Ortak form parçaları
// ===========================================================================

InputDecoration _fieldDecoration(
  String label, {
  String? hint,
  String? errorText,
  IconData? icon,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: errorText,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    isDense: true,
    filled: true,
    fillColor: AdminUi.page,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: border(AdminUi.line),
    disabledBorder: border(AdminUi.line),
    focusedBorder: border(AdminUi.brand, 1.5),
    errorBorder: border(Colors.red.shade400),
    focusedErrorBorder: border(Colors.red.shade400, 1.5),
  );
}

/// Alt sayfaların içinde bildirim: SnackBar sayfanın ARKASINDA kalacağı için
/// (sayfa ekranın çoğunu kaplar) mesajlar sayfa içi şeritte gösterilir.
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade50,
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: Colors.red.shade800),
            ),
          ),
          IconButton(
            tooltip: 'Kapat',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.red.shade700,
            ),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.onClose,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AdminUi.muted,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AdminUi.line),
      ],
    );
  }
}

const RoundedRectangleBorder _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

const int _maxImageBytes = 2 * 1024 * 1024; // bucket sınırı: 2 MB

String _megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';

/// Ekleme ve düzenleme sayfalarındaki klasör seçimi. [value] null =
/// klasörsüz. Listede olmayan id (ör. başka sekmede silinmiş) klasörsüz
/// gösterilir; Dropdown, listede olmayan değerde assert'e düşerdi.
Widget _folderDropdown({
  required List<ProductImageFolder> folders,
  required String? value,
  required bool enabled,
  required ValueChanged<String?> onChanged,
}) {
  final known = value != null && folders.any((f) => f.id == value);
  return DropdownButtonFormField<String>(
    initialValue: known ? value : '',
    isExpanded: true,
    decoration: _fieldDecoration('Klasör', icon: Icons.folder_outlined),
    items: [
      const DropdownMenuItem(value: '', child: Text('Klasörsüz')),
      for (final f in folders)
        DropdownMenuItem(
          value: f.id,
          child: Text(
            f.isActive ? f.name : '${f.name} (kapalı)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: enabled
        ? (v) => onChanged(v == null || v.isEmpty ? null : v)
        : null,
  );
}

/// Dosya adından öneri ad üretir: "domates_kirmizi.jpg" -> "Domates kirmizi".
/// Kamera/ekran görüntüsü gibi anlamsız adlar boş bırakılır (admin yazsın).
String _nameFromFile(String fileName) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  var s = base.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '');
  s = s
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final junk = RegExp(
    r'^(img|dsc|pxl|image|screenshot|photo|foto|whatsapp|resim|unnamed)\b',
    caseSensitive: false,
  );
  final letters = RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').allMatches(s).length;
  if (s.isEmpty || letters < 3 || junk.hasMatch(s)) return '';
  final first = s[0] == 'i' ? 'İ' : s[0].toUpperCase();
  return '$first${s.substring(1)}';
}

// ===========================================================================
// Çoklu ekleme sayfası
// ===========================================================================

enum _DraftStatus { idle, uploading, done, failed }

class _Draft {
  _Draft({
    required this.fileName,
    required this.bytes,
    required String initialName,
  }) : name = TextEditingController(text: initialName),
       keywords = TextEditingController();

  /// Yalnızca uzantıyı belirlemek için (galeri dosyası ya da linkten gelen).
  final String fileName;
  final Uint8List bytes;
  final TextEditingController name;
  final TextEditingController keywords;
  bool showKeywords = false;
  bool nameError = false;
  _DraftStatus status = _DraftStatus.idle;
  String? error;

  /// Yükleme başarılı olup satır eklenemezse tekrarda dosya yeniden yüklenmesin.
  String? uploadedUrl;

  void dispose() {
    name.dispose();
    keywords.dispose();
  }
}

class _AddImagesSheet extends StatefulWidget {
  const _AddImagesSheet({
    required this.service,
    required this.startOrder,
    required this.folders,
    this.initialFolderId,
    this.scrapeService,
  });

  final ProductImagePresetService service;
  final ProductImageScrapeService? scrapeService;
  final int startOrder;
  final List<ProductImageFolder> folders;

  /// Görsellerin ekleneceği klasörün ilk değeri (null = klasörsüz).
  final String? initialFolderId;

  @override
  State<_AddImagesSheet> createState() => _AddImagesSheetState();
}

class _AddImagesSheetState extends State<_AddImagesSheet> {
  static const int _maxBatch = 30;
  static const int _parallel = 3;

  final List<_Draft> _drafts = [];
  final String _seed = math.Random().nextInt(1 << 30).toRadixString(36);
  int _tag = 0;

  bool _publishNow = true;
  late String? _folderId = widget.initialFolderId;
  bool _picking = false;
  bool _uploading = false;
  int _saved = 0;
  int _runTotal = 0;
  int _runFinished = 0;
  String? _notice;
  late int _nextOrder = widget.startOrder;

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _snack(String message) {
    if (mounted) setState(() => _notice = message);
  }

  Future<void> _pick() async {
    if (_uploading || _picking) return;
    final room = _maxBatch - _drafts.length;
    if (room <= 0) {
      _snack('Tek seferde en fazla $_maxBatch görsel eklenebilir');
      return;
    }
    setState(() => _picking = true);
    try {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (files.isEmpty || !mounted) return;

      final added = <_Draft>[];
      for (final f in files.take(room)) {
        final bytes = await f.readAsBytes();
        added.add(
          _Draft(
            fileName: f.name,
            bytes: bytes,
            initialName: _nameFromFile(f.name),
          ),
        );
      }
      if (!mounted) {
        for (final d in added) {
          d.dispose();
        }
        return;
      }
      setState(() => _drafts.addAll(added));
      if (files.length > room) {
        _snack('Yalnızca ilk $room görsel eklendi (en fazla $_maxBatch)');
      }
    } catch (e) {
      _snack('Görseller seçilemedi: ${_cleanError(e)}');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _addFromLink() async {
    if (_uploading || _picking) return;
    if (_drafts.length >= _maxBatch) {
      _snack('Tek seferde en fazla $_maxBatch görsel eklenebilir');
      return;
    }
    final image = await showProductImageLinkSheet(
      context,
      accent: AdminUi.brand,
      service: widget.scrapeService,
    );
    if (image == null || !mounted) return;
    if (image.bytes.length > _maxImageBytes) {
      _snack(
        'Görsel ${_megabytes(image.bytes.length)}; en fazla 2 MB olabilir. '
        'Daha küçük bir görsel deneyin.',
      );
      return;
    }
    // Sayfa başlığı ad alanına öneri olarak girer; admin düzenleyebilir.
    final title = image.title ?? '';
    setState(() {
      _notice = null;
      _drafts.add(
        _Draft(
          fileName: image.fileName,
          bytes: image.bytes,
          initialName: title.length > 80 ? title.substring(0, 80) : title,
        ),
      );
    });
  }

  void _remove(_Draft d) {
    setState(() => _drafts.remove(d));
    // TextField bu karede hâlâ controller'a bağlı; sonraki karede at.
    WidgetsBinding.instance.addPostFrameCallback((_) => d.dispose());
  }

  Future<void> _upload() async {
    if (_uploading) return;
    final todo = _drafts.where((d) => d.status != _DraftStatus.done).toList();
    if (todo.isEmpty) return;

    var missingName = false;
    for (final d in todo) {
      d.nameError = d.name.text.trim().isEmpty;
      missingName |= d.nameError;
    }
    if (missingName) {
      setState(() {});
      _snack('Her görsel için bir ad girin');
      return;
    }

    final orderOf = <_Draft, int>{
      for (var i = 0; i < todo.length; i++) todo[i]: _nextOrder + i,
    };
    setState(() {
      _notice = null;
      _uploading = true;
      _runTotal = todo.length;
      _runFinished = 0;
      _nextOrder += todo.length;
      for (final d in todo) {
        d.status = _DraftStatus.idle;
        d.error = null;
      }
    });

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < todo.length) {
        final d = todo[cursor++];
        await _uploadOne(d, orderOf[d]!);
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(_parallel, todo.length); i++) worker(),
    ]);
    if (!mounted) return;

    final failed = todo.where((d) => d.status == _DraftStatus.failed).length;
    setState(() => _uploading = false);
    if (failed == 0) {
      Navigator.pop(context, _saved);
    } else {
      _snack(
        '$failed görsel yüklenemedi. Hatalı satırları düzeltip tekrar dene.',
      );
    }
  }

  Future<void> _uploadOne(_Draft d, int order) async {
    if (mounted) setState(() => d.status = _DraftStatus.uploading);
    try {
      if (d.bytes.length > _maxImageBytes) {
        throw Exception(
          'Dosya ${_megabytes(d.bytes.length)}; en fazla 2 MB olabilir',
        );
      }
      d.uploadedUrl ??= await widget.service.uploadImage(
        bytes: d.bytes,
        fileName: d.fileName,
        uniqueTag: '${_seed}_${_tag++}',
      );
      final kw = d.keywords.text.trim();
      await widget.service.addPreset(
        name: d.name.text.trim(),
        description: kw.isEmpty ? null : kw,
        imageUrl: d.uploadedUrl!,
        displayOrder: order,
        isActive: _publishNow,
        folderId: _folderId,
      );
      d.status = _DraftStatus.done;
      _saved++;
    } catch (e) {
      d.status = _DraftStatus.failed;
      d.error = _cleanError(e);
    }
    _runFinished++;
    if (mounted) setState(() {});
  }

  Future<void> _requestClose() async {
    if (_uploading) {
      _snack('Yükleme sürüyor, lütfen bekle');
      return;
    }
    final pending = _drafts.where((d) => d.status != _DraftStatus.done).length;
    if (pending > 0) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Vazgeçilsin mi?'),
          content: Text(
            'Yüklenmemiş $pending görsel ve girdiğin adlar silinecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Düzenlemeye dön'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Vazgeç'),
            ),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (mounted) Navigator.pop(context, _saved);
  }

  @override
  Widget build(BuildContext context) {
    final todo = _drafts.where((d) => d.status != _DraftStatus.done).length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: Material(
            color: Colors.white,
            shape: _sheetShape,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SheetHeader(
                  title: 'Görselleri Ekle',
                  subtitle: _drafts.isEmpty
                      ? 'Birden fazla görsel seçip her birine ad ver'
                      : '${_drafts.length} görsel hazır · adları kontrol et',
                  onClose: _requestClose,
                ),
                if (_notice != null)
                  _NoticeBar(
                    message: _notice!,
                    onClose: () => setState(() => _notice = null),
                  ),
                Expanded(
                  child: _drafts.isEmpty ? _buildPickZone() : _buildList(),
                ),
                if (_drafts.isNotEmpty) _buildFooter(todo),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickZone() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _pick,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: AdminUi.brandSoft,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AdminUi.brand.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: _picking
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 34,
                              color: AdminUi.brand,
                            ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Görselleri seç',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Galeriden birden fazla görseli aynı anda seçebilirsin.\n'
                      'Sonraki adımda her birine ayrı ad verirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AdminUi.muted),
                    ),
                    const SizedBox(height: 16),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _InfoChip('JPG · PNG · WebP · GIF'),
                        _InfoChip('Görsel başına en fazla 2 MB'),
                        _InfoChip('Tek seferde en fazla $_maxBatch'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildLinkButton(),
          ],
        ),
      ),
    );
  }

  /// Bir ürün sayfası linkinden görsel getirir (og:image kazıma).
  Widget _buildLinkButton() {
    return OutlinedButton.icon(
      onPressed: (_uploading || _picking) ? null : _addFromLink,
      icon: const Icon(Icons.link_rounded),
      label: const Text('Ürün linkinden ekle'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminUi.brand,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: AdminUi.brand.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: _drafts.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: (_uploading || _picking) ? null : _pick,
                icon: _picking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(
                  'Daha fazla görsel ekle (${_drafts.length}/$_maxBatch)',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminUi.brand,
                  side: BorderSide(color: AdminUi.brand.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              _buildLinkButton(),
            ],
          );
        }
        final d = _drafts[i - 1];
        return _buildDraft(d, i);
      },
    );
  }

  Widget _buildDraft(_Draft d, int number) {
    final locked = _uploading || d.status == _DraftStatus.done;
    final Color? border = switch (d.status) {
      _DraftStatus.failed => Colors.red.shade300,
      _DraftStatus.done => Colors.green.shade300,
      _ => null,
    };

    return AdminCard(
      key: ObjectKey(d),
      padding: const EdgeInsets.all(10),
      borderColor: border,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    d.bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 240,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0xFFEDEEF3),
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                  if (d.status != _DraftStatus.idle)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.42),
                      child: Center(child: _statusIcon(d.status)),
                    ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: _OverlayPill(text: '$number'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: d.name,
                  enabled: !locked,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  decoration: _fieldDecoration(
                    'Görsel adı *',
                    hint: 'örn. Kırmızı domates',
                    errorText: d.nameError ? 'Ad gerekli' : null,
                  ),
                  onChanged: (v) {
                    if (d.nameError && v.trim().isNotEmpty) {
                      setState(() => d.nameError = false);
                    }
                  },
                ),
                if (d.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      d.error!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                if (d.showKeywords || d.keywords.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: d.keywords,
                      enabled: !locked,
                      decoration: _fieldDecoration(
                        'Arama kelimeleri (opsiyonel)',
                        hint: 'örn. sebze, salata, kırmızı',
                      ),
                    ),
                  )
                else if (!locked)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => d.showKeywords = true),
                      icon: const Icon(Icons.sell_outlined, size: 15),
                      label: const Text(
                        'Arama kelimesi ekle',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AdminUi.muted,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!locked)
            IconButton(
              tooltip: 'Listeden kaldır',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 20),
              color: AdminUi.muted,
              onPressed: () => _remove(d),
            ),
        ],
      ),
    );
  }

  Widget _statusIcon(_DraftStatus s) => switch (s) {
    _DraftStatus.uploading => const SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
    ),
    _DraftStatus.done => const Icon(
      Icons.check_circle_rounded,
      color: Colors.white,
      size: 32,
    ),
    _DraftStatus.failed => const Icon(
      Icons.error_rounded,
      color: Colors.white,
      size: 32,
    ),
    _DraftStatus.idle => const SizedBox.shrink(),
  };

  Widget _buildFooter(int todo) {
    final failed = _drafts.any((d) => d.status == _DraftStatus.failed);
    final label = todo == 0
        ? 'Tamamlandı'
        : failed
        ? 'Kalan $todo görseli tekrar dene'
        : '$todo görseli kütüphaneye ekle';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdminUi.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _folderDropdown(
            folders: widget.folders,
            value: _folderId,
            enabled: !_uploading,
            onChanged: (v) => setState(() => _folderId = v),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hemen yayınla',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AdminUi.ink,
                      ),
                    ),
                    Text(
                      'Kapalıysa görseller pasif eklenir, sonra açabilirsin',
                      style: TextStyle(fontSize: 11.5, color: AdminUi.muted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _publishNow,
                activeThumbColor: AdminUi.brand,
                onChanged: _uploading
                    ? null
                    : (v) => setState(() => _publishNow = v),
              ),
            ],
          ),
          if (_uploading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: _runTotal == 0 ? null : _runFinished / _runTotal,
                color: AdminUi.brand,
                backgroundColor: AdminUi.brandSoft,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Yükleniyor… $_runFinished / $_runTotal',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AdminUi.muted),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: (_uploading || todo == 0) ? null : _upload,
            style: FilledButton.styleFrom(
              backgroundColor: AdminUi.brand,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminUi.line),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
      ),
    );
  }
}

// ===========================================================================
// Tek görsel düzenleme sayfası
// ===========================================================================

class _EditPresetSheet extends StatefulWidget {
  const _EditPresetSheet({
    required this.preset,
    required this.service,
    required this.folders,
  });

  final ProductImagePreset preset;
  final ProductImagePresetService service;
  final List<ProductImageFolder> folders;

  @override
  State<_EditPresetSheet> createState() => _EditPresetSheetState();
}

class _EditPresetSheetState extends State<_EditPresetSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.preset.name,
  );
  late final TextEditingController _keywords = TextEditingController(
    text: widget.preset.description ?? '',
  );
  late final TextEditingController _order = TextEditingController(
    text: '${widget.preset.displayOrder}',
  );
  late bool _active = widget.preset.isActive;
  // Listede olmayan (silinmiş) klasör kaydedilirken FK hatası vermesin.
  late String? _folderId =
      widget.folders.any((f) => f.id == widget.preset.folderId)
      ? widget.preset.folderId
      : null;

  XFile? _newFile;
  Uint8List? _newBytes;
  bool _saving = false;
  bool _nameError = false;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    _order.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    if (mounted) setState(() => _notice = message);
  }

  Future<void> _replaceImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxImageBytes) {
        _snack(
          'Görsel ${_megabytes(bytes.length)}; en fazla 2 MB olabilir',
          error: true,
        );
        return;
      }
      setState(() {
        _newFile = picked;
        _newBytes = bytes;
      });
    } catch (e) {
      _snack('Görsel seçilemedi: ${_cleanError(e)}', error: true);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      return;
    }
    setState(() {
      _notice = null;
      _saving = true;
    });
    try {
      String? newUrl;
      if (_newFile != null && _newBytes != null) {
        newUrl = await widget.service.uploadImage(
          bytes: _newBytes!,
          fileName: _newFile!.name,
          uniqueTag: 'edit${widget.preset.id.substring(0, 6)}',
        );
      }
      final updated = await widget.service.updatePreset(
        id: widget.preset.id,
        name: name,
        description: _keywords.text,
        imageUrl: newUrl,
        displayOrder:
            int.tryParse(_order.text.trim()) ?? widget.preset.displayOrder,
        isActive: _active,
        setFolder: true,
        folderId: _folderId,
      );
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(_cleanError(e), error: true);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Görsel silinsin mi?'),
        content: Text(
          '"${widget.preset.name}" kütüphaneden kalıcı olarak kaldırılır. '
          'Bu görseli daha önce seçmiş ürünler etkilenmez. '
          'Geçici olarak gizlemek için bunun yerine "Yayında" anahtarını kapat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.service.deletePreset(widget.preset.id);
      if (mounted) Navigator.pop(context, _deletedResult);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(_cleanError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: Colors.white,
        shape: _sheetShape,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHeader(
              title: 'Görseli Düzenle',
              onClose: () => Navigator.pop(context),
            ),
            if (_notice != null)
              _NoticeBar(
                message: _notice!,
                onClose: () => setState(() => _notice = null),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        height: 220,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Color(0xFFEDEEF3)),
                            if (_newBytes != null)
                              Image.memory(_newBytes!, fit: BoxFit.contain)
                            else
                              CachedNetworkImage(
                                imageUrl: widget.preset.imageUrl,
                                fit: BoxFit.contain,
                                errorWidget: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: AdminUi.muted,
                                ),
                              ),
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: FilledButton.tonalIcon(
                                onPressed: _saving ? null : _replaceImage,
                                icon: const Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _newBytes == null
                                      ? 'Görseli değiştir'
                                      : 'Başka seç',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.94,
                                  ),
                                  foregroundColor: AdminUi.ink,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                            if (_newBytes != null)
                              const Positioned(
                                left: 10,
                                top: 10,
                                child: _OverlayPill(
                                  text: 'Yeni görsel · kaydedince geçerli olur',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _fieldDecoration(
                        'Görsel adı *',
                        errorText: _nameError ? 'Ad gerekli' : null,
                        icon: Icons.label_outline_rounded,
                      ),
                      onChanged: (v) {
                        if (_nameError && v.trim().isNotEmpty) {
                          setState(() => _nameError = false);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keywords,
                      enabled: !_saving,
                      minLines: 1,
                      maxLines: 3,
                      decoration: _fieldDecoration(
                        'Arama kelimeleri (opsiyonel)',
                        hint: 'Satıcılar bu kelimelerle de bulur',
                        icon: Icons.sell_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _folderDropdown(
                      folders: widget.folders,
                      value: _folderId,
                      enabled: !_saving,
                      onChanged: (v) => setState(() => _folderId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _order,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _fieldDecoration(
                        'Sıra numarası',
                        hint: 'Küçük olan önce görünür',
                        icon: Icons.format_list_numbered_rounded,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Yayında',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Kapalıysa satıcılara gösterilmez'),
                      value: _active,
                      activeThumbColor: AdminUi.brand,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _active = v),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                14 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    label: const Text('Sil'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      side: BorderSide(color: Colors.red.shade200),
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminUi.brand,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Kaydet',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
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

// ===========================================================================
// Klasörler
// ===========================================================================

/// Klasör seçicinin sonucu. [folderId] null = klasörsüz; [created] seçicinin
/// içinden yeni açılan klasör.
class _FolderChoice {
  const _FolderChoice(this.folderId, {this.created});

  final String? folderId;
  final ProductImageFolder? created;
}

Future<String?> _askFolderName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FolderNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initial: initial,
    ),
  );
}

/// Klasör adı soran kutu (yeni klasör / yeniden adlandırma). Boş ad
/// gönderilemez; sonuç kırpılmış addır.
class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initial = '',
  });

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  bool _empty = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _empty = true);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (v) {
          if (_empty && v.trim().isNotEmpty) setState(() => _empty = false);
        },
        decoration: _fieldDecoration(
          'Klasör adı',
          hint: 'örn. Kozmetik',
          errorText: _empty ? 'Ad gerekli' : null,
          icon: Icons.folder_outlined,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// "Klasöre taşı": hedef klasörü seçtirir; içinden yeni klasör de açılabilir.
class _FolderPickerSheet extends StatefulWidget {
  const _FolderPickerSheet({
    required this.service,
    required this.folders,
    required this.count,
    required this.current,
  });

  final ProductImagePresetService service;
  final List<ProductImageFolder> folders;

  /// Taşınacak görsel sayısı (başlık için).
  final int count;

  /// Taşınan görsellerin şu anki klasörleri (null = klasörsüz). Tek bir
  /// değerse o satır "Şu anki" diye işaretlenir ve seçilemez.
  final Set<String?> current;

  @override
  State<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<_FolderPickerSheet> {
  bool _creating = false;
  String? _notice;

  bool _isCurrent(String? id) =>
      widget.current.length == 1 && widget.current.first == id;

  Future<void> _create() async {
    final name = await _askFolderName(
      context,
      title: 'Yeni klasör',
      confirmLabel: 'Oluştur',
    );
    if (name == null || !mounted) return;
    setState(() {
      _creating = true;
      _notice = null;
    });
    try {
      final order =
          widget.folders.fold<int>(0, (m, f) => math.max(m, f.displayOrder)) +
          1;
      final folder = await widget.service.addFolder(
        name: name,
        displayOrder: order,
      );
      if (mounted) {
        Navigator.pop(context, _FolderChoice(folder.id, created: folder));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _notice = _cleanError(e);
        });
      }
    }
  }

  Widget _option({
    required IconData icon,
    required String title,
    String? subtitle,
    required String? folderId,
    Color? color,
  }) {
    final current = _isCurrent(folderId);
    return ListTile(
      leading: Icon(icon, color: color ?? AdminUi.brand),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AdminUi.ink,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: AdminUi.muted),
            ),
      trailing: current
          ? const AdminPill(label: 'Şu anki', color: AdminUi.muted)
          : null,
      onTap: (_creating || current)
          ? null
          : () => Navigator.pop(context, _FolderChoice(folderId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: _sheetShape,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(
            title: 'Klasöre taşı',
            subtitle: widget.count == 1
                ? 'Görselin gideceği klasörü seç'
                : '${widget.count} görselin gideceği klasörü seç',
            onClose: () => Navigator.pop(context),
          ),
          if (_notice != null)
            _NoticeBar(
              message: _notice!,
              onClose: () => setState(() => _notice = null),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                4,
                6,
                4,
                10 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                for (final f in widget.folders)
                  _option(
                    icon: f.isActive
                        ? Icons.folder_rounded
                        : Icons.visibility_off_rounded,
                    title: f.name,
                    subtitle: f.isActive
                        ? null
                        : 'Kapalı · satıcılar bu klasörü görmez',
                    folderId: f.id,
                  ),
                _option(
                  icon: Icons.folder_off_outlined,
                  title: 'Klasörsüz',
                  subtitle: 'Satıcılar yalnız "Tümü" ve aramada görür',
                  folderId: null,
                  color: AdminUi.muted,
                ),
                const Divider(height: 16, color: AdminUi.line),
                ListTile(
                  leading: _creating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Icon(
                          Icons.create_new_folder_outlined,
                          color: AdminUi.brand,
                        ),
                  title: Text(
                    'Yeni klasör oluştur',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AdminUi.brand,
                    ),
                  ),
                  onTap: _creating ? null : _create,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Klasör yönetimi: ekle, yeniden adlandır, sürükleyerek sırala, aç/kapat,
/// sil. Her değişiklik anında kaydedilir; "Kapat" ile çıkınca bir şey
/// değiştiyse true döner (üst ekran listeyi tazeler).
class _FoldersSheet extends StatefulWidget {
  const _FoldersSheet({
    required this.service,
    required this.folders,
    required this.counts,
  });

  final ProductImagePresetService service;
  final List<ProductImageFolder> folders;

  /// Klasör başına görsel sayıları (üst ekranın yerel listesinden).
  final Map<String?, ({int all, int active})> counts;

  @override
  State<_FoldersSheet> createState() => _FoldersSheetState();
}

class _FoldersSheetState extends State<_FoldersSheet> {
  late List<ProductImageFolder> _items = [...widget.folders];
  final TextEditingController _newName = TextEditingController();
  bool _busy = false;
  bool _changed = false;
  String? _notice;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  /// [action] sırasında düğmeler kilitlenir; hata sayfa içi şeritte gösterilir.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action();
      _changed = true;
    } catch (e) {
      if (mounted) _notice = _cleanError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = _newName.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = 'Klasör adı yaz');
      return;
    }
    await _run(() async {
      final order =
          _items.fold<int>(0, (m, f) => math.max(m, f.displayOrder)) + 1;
      final folder = await widget.service.addFolder(
        name: name,
        displayOrder: order,
      );
      _items = [..._items, folder];
      _newName.clear();
    });
  }

  Future<void> _rename(ProductImageFolder f) async {
    final name = await _askFolderName(
      context,
      title: 'Klasörü yeniden adlandır',
      confirmLabel: 'Kaydet',
      initial: f.name,
    );
    if (name == null || name == f.name || !mounted) return;
    await _run(() async {
      await widget.service.updateFolder(id: f.id, name: name);
      _items = [
        for (final x in _items) x.id == f.id ? x.copyWith(name: name) : x,
      ];
    });
  }

  Future<void> _toggle(ProductImageFolder f, bool active) async {
    await _run(() async {
      await widget.service.updateFolder(id: f.id, isActive: active);
      _items = [
        for (final x in _items) x.id == f.id ? x.copyWith(isActive: active) : x,
      ];
    });
  }

  Future<void> _delete(ProductImageFolder f) async {
    final n = widget.counts[f.id]?.all ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Klasör silinsin mi?'),
        content: Text(
          n == 0
              ? '"${f.name}" klasörü silinir.'
              : '"${f.name}" klasörü silinir. İçindeki $n görsel SİLİNMEZ, '
                    'klasörsüz kalır; sonra başka klasöre taşıyabilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await widget.service.deleteFolder(f.id);
      _items = _items.where((x) => x.id != f.id).toList();
    });
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_busy) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final before = _items;
    final next = [..._items];
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() {
      // İyimser: liste anında yeni sırada görünsün, hata olursa geri alınır.
      _items = [
        for (var i = 0; i < next.length; i++)
          next[i].copyWith(displayOrder: i + 1),
      ];
      _busy = true;
      _notice = null;
    });
    try {
      await widget.service.reorderFolders([for (final f in next) f.id]);
      _changed = true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = before;
          _notice = _cleanError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: Colors.white,
        shape: _sheetShape,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHeader(
              title: 'Klasörler',
              subtitle:
                  'Sürükleyerek sırala · kapalı klasörün görselleri '
                  'satıcılara gösterilmez',
              onClose: () => Navigator.pop(context, _changed),
            ),
            if (_notice != null)
              _NoticeBar(
                message: _notice!,
                onClose: () => setState(() => _notice = null),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newName,
                      enabled: !_busy,
                      maxLength: 40,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _add(),
                      decoration: _fieldDecoration(
                        'Yeni klasör adı',
                        hint: 'örn. Kırtasiye',
                        icon: Icons.create_new_folder_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _add,
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminUi.brand,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Ekle'),
                  ),
                ],
              ),
            ),
            if (_items.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                child: const Text(
                  'Henüz klasör yok. Market, Kozmetik gibi bir klasör ekle.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AdminUi.muted),
                ),
              )
            else
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.fromLTRB(
                    4,
                    4,
                    8,
                    12 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: _items.length,
                  onReorder: _reorder,
                  itemBuilder: (context, i) => _buildRow(_items[i], i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(ProductImageFolder f, int index) {
    final c = widget.counts[f.id];
    final all = c?.all ?? 0;
    final active = c?.active ?? 0;
    return Material(
      key: ValueKey(f.id),
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.only(right: 4),
        leading: ReorderableDragStartListener(
          index: index,
          enabled: !_busy,
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.drag_indicator_rounded, color: AdminUi.muted),
          ),
        ),
        title: Text(
          f.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: f.isActive ? AdminUi.ink : AdminUi.muted,
          ),
        ),
        subtitle: Text(
          f.isActive
              ? '$all görsel · $active yayında'
              : '$all görsel · kapalı, satıcılar görmez',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AdminUi.muted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: f.isActive,
              activeThumbColor: AdminUi.brand,
              onChanged: _busy ? null : (v) => _toggle(f, v),
            ),
            PopupMenuButton<String>(
              tooltip: 'İşlemler',
              enabled: !_busy,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (v) => v == 'rename' ? _rename(f) : _delete(f),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: _MenuRow(Icons.edit_rounded, 'Yeniden adlandır'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: _MenuRow(
                    Icons.delete_outline_rounded,
                    'Sil',
                    color: Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
