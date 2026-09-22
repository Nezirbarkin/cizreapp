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
/// ad + arama kelimeleri). Admin tek seferde BİRDEN ÇOK görsel seçip her birine
/// ayrı ad verebilir; ızgaradan arar, filtreler, sıralar, düzenler ve toplu
/// yayına alır / pasife çeker / siler.
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

enum _StatusFilter { all, active, passive }

enum _Sort { order, newest }

/// Türkçe harfleri sadeleştirip küçültür: "Çiğ Köfte" ile "cig kofte" eşleşsin.
const Map<String, String> _trFold = {
  'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g', //
  'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c',
};

String _fold(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_trFold[ch] ?? ch.toLowerCase());
  }
  return b.toString();
}

String _cleanError(Object e) =>
    e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

class _ProductImageLibraryContentState
    extends State<ProductImageLibraryContent> {
  late final ProductImagePresetService _service =
      widget.service ?? ProductImagePresetService();
  final TextEditingController _searchController = TextEditingController();

  List<ProductImagePreset> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;
  _Sort _sort = _Sort.order;
  final Set<String> _selected = {};
  bool _busy = false;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Veri
  // -------------------------------------------------------------------------

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _service.getAllPresetsForAdmin();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
        _error = null;
        _selected.removeWhere((id) => !list.any((p) => p.id == id));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Sessiz yenilemede eldeki liste bozulmasın.
        if (!silent || _all.isEmpty) _error = _cleanError(e);
      });
    }
  }

  List<ProductImagePreset> get _visible {
    final q = _fold(_query.trim());
    final list = _all.where((p) {
      if (_filter == _StatusFilter.active && !p.isActive) return false;
      if (_filter == _StatusFilter.passive && p.isActive) return false;
      if (q.isEmpty) return true;
      return _fold(p.name).contains(q) ||
          _fold(p.description ?? '').contains(q);
    }).toList();
    if (_sort == _Sort.newest) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  int get _nextOrder =>
      _all.isEmpty ? 1 : _all.map((p) => p.displayOrder).reduce(math.max) + 1;

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
        startOrder: _nextOrder,
      ),
    );
    if (saved != null && saved > 0) {
      _snack('$saved görsel kütüphaneye eklendi');
    }
    if (saved != null) await _load(silent: true);
  }

  Future<void> _openEdit(ProductImagePreset preset) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _EditPresetSheet(preset: preset, service: _service),
    );
    if (result == null) return;
    _snack(result == 'deleted' ? 'Görsel silindi' : 'Görsel güncellendi');
    await _load(silent: true);
  }

  Future<void> _setActive(List<ProductImagePreset> items, bool active) async {
    if (items.isEmpty || _busy) return;
    final ids = items.map((p) => p.id).toSet();
    final before = _all;
    setState(() {
      _busy = true;
      // İyimser güncelleme: arayüz anında değişsin, hata olursa geri alınır.
      _all = [
        for (final p in _all)
          ids.contains(p.id) ? p.copyWith(isActive: active) : p,
      ];
    });
    try {
      await _service.setActive(ids.toList(), active);
      if (!mounted) return;
      _snack(
        items.length == 1
            ? (active ? 'Görsel yayına alındı' : 'Görsel pasife alındı')
            : '${items.length} görsel ${active ? 'yayına alındı' : 'pasife alındı'}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _all = before);
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(List<ProductImagePreset> items) async {
    if (items.isEmpty || _busy) return;
    final single = items.length == 1;
    final ok = await _confirm(
      title: single
          ? 'Görsel silinsin mi?'
          : '${items.length} görsel silinsin mi?',
      message: single
          ? '"${items.first.name}" kütüphaneden kalıcı olarak kaldırılır. '
                'Bu görseli daha önce seçmiş ürünler etkilenmez.'
          : 'Seçili görseller kütüphaneden kalıcı olarak kaldırılır. '
                'Bunları daha önce seçmiş ürünler etkilenmez.',
      confirmLabel: 'Sil',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.deletePresets(items.map((p) => p.id).toList());
      if (!mounted) return;
      _selected.clear();
      _snack(single ? 'Görsel silindi' : '${items.length} görsel silindi');
      await _load(silent: true);
    } catch (e) {
      _snack(_cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  List<ProductImagePreset> get _selectedItems =>
      _all.where((p) => _selected.contains(p.id)).toList();

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
    final active = _all.where((p) => p.isActive).length;
    final passive = _all.length - active;

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
          Row(
            children: [
              Expanded(
                child: _FilterStat(
                  icon: Icons.grid_view_rounded,
                  label: 'Tümü',
                  value: _all.length,
                  color: AdminUi.brand,
                  selected: _filter == _StatusFilter.all,
                  onTap: () => setState(() => _filter = _StatusFilter.all),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterStat(
                  icon: Icons.visibility_rounded,
                  label: 'Yayında',
                  value: active,
                  color: Colors.green.shade600,
                  selected: _filter == _StatusFilter.active,
                  onTap: () => setState(() => _filter = _StatusFilter.active),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterStat(
                  icon: Icons.visibility_off_rounded,
                  label: 'Pasif',
                  value: passive,
                  color: Colors.blueGrey.shade500,
                  selected: _filter == _StatusFilter.passive,
                  onTap: () => setState(() => _filter = _StatusFilter.passive),
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
                  onChanged: (v) => setState(() => _query = v),
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
                              setState(() => _query = '');
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
              PopupMenuButton<_Sort>(
                tooltip: 'Sırala',
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _Sort.order,
                    child: Text('Sıra numarasına göre'),
                  ),
                  PopupMenuItem(
                    value: _Sort.newest,
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

  Widget _buildSelectionBar() {
    final items = _selectedItems;
    final visible = _visible;
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
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AdminUi.brand,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Görünenlerin tümünü seç',
            icon: const Icon(Icons.select_all_rounded),
            onPressed: () =>
                setState(() => _selected.addAll(visible.map((p) => p.id))),
          ),
          IconButton(
            tooltip: 'Yayına al',
            icon: Icon(Icons.visibility_rounded, color: Colors.green.shade700),
            onPressed: _busy ? null : () => _setActive(items, true),
          ),
          IconButton(
            tooltip: 'Pasife al',
            icon: Icon(
              Icons.visibility_off_rounded,
              color: Colors.blueGrey.shade600,
            ),
            onPressed: _busy ? null : () => _setActive(items, false),
          ),
          IconButton(
            tooltip: 'Sil',
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.red.shade600,
            ),
            onPressed: _busy ? null : () => _delete(items),
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
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tekrar dene'),
        ),
      );
    }

    if (_all.isEmpty) {
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

    final visible = _visible;
    if (visible.isEmpty) {
      return AdminEmpty(
        icon: Icons.search_off_rounded,
        title: 'Sonuç bulunamadı',
        subtitle: 'Aramayı ya da filtreyi değiştirmeyi dene.',
        action: TextButton(
          onPressed: () {
            _searchController.clear();
            setState(() {
              _query = '';
              _filter = _StatusFilter.all;
            });
          },
          child: const Text('Filtreleri temizle'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.8,
        ),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final p = visible[i];
          return _PresetTile(
            key: ValueKey(p.id),
            preset: p,
            selected: _selected.contains(p.id),
            selecting: _selecting,
            onTap: () => _selecting ? _toggleSelect(p.id) : _openEdit(p),
            onLongPress: () => _toggleSelect(p.id),
            onMenu: (v) {
              switch (v) {
                case 'edit':
                  _openEdit(p);
                case 'toggle':
                  _setActive([p], !p.isActive);
                case 'select':
                  _toggleSelect(p.id);
                case 'delete':
                  _delete([p]);
              }
            },
          );
        },
      ),
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
  });

  final ProductImagePreset preset;
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
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
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
    this.scrapeService,
  });

  final ProductImagePresetService service;
  final ProductImageScrapeService? scrapeService;
  final int startOrder;

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
  const _EditPresetSheet({required this.preset, required this.service});

  final ProductImagePreset preset;
  final ProductImagePresetService service;

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
      await widget.service.updatePreset(
        id: widget.preset.id,
        name: name,
        description: _keywords.text,
        imageUrl: newUrl,
        displayOrder:
            int.tryParse(_order.text.trim()) ?? widget.preset.displayOrder,
        isActive: _active,
      );
      if (mounted) Navigator.pop(context, 'saved');
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
      if (mounted) Navigator.pop(context, 'deleted');
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
