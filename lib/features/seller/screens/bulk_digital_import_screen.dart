import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/smm_provider_model.dart';
import '../../../core/services/smm_service.dart';
import '../../market/widgets/product_image_library_sheet.dart';
import '../models/bulk_product_draft.dart';
import '../services/bulk_product_service.dart';
import '../widgets/common/seller_section_card.dart';
import 'smm_provider_settings_screen.dart';

/// SMM sağlayıcısının servislerini toplu olarak dijital ürüne çevirir.
///
/// Satıcı sağlayıcıyı seçer, servisleri arar/süzer ve işaretler; kâr oranı,
/// kategori, kullanıcı başına limit ve ortak kapak görseli bir kez girilir.
/// Fiyat = sağlayıcı fiyatı × (1 + kâr%), kuruşa yukarı yuvarlanır. Sağlayıcı
/// fiyatı ürüne değil, ayrı karşılaştırma tabanına yazılır (sağlayıcıda fiyat
/// ya da servis değişirse smm-sync-products ürünü otomatik kapatır).
class BulkDigitalImportScreen extends StatefulWidget {
  const BulkDigitalImportScreen({
    super.key,
    this.service,
    this.smmService,
    @visibleForTesting this.debugContext,
    @visibleForTesting this.debugProviders,
    @visibleForTesting this.debugServices,
  });

  final BulkProductService? service;
  final SmmService? smmService;
  final BulkShopContext? debugContext;
  final List<SmmProvider>? debugProviders;
  final List<SmmProviderServiceInfo>? debugServices;

  /// Satış fiyatı: kuruşa YUKARI yuvarlanır (kâr oranının altına düşmesin).
  static double salePrice(double rate, double markupPercent) {
    final raw = rate * (1 + markupPercent / 100);
    return ((raw * 100) - 1e-9).ceil() / 100;
  }

  @override
  State<BulkDigitalImportScreen> createState() => _BulkDigitalImportScreenState();
}

/// Kategori seçimi: sağlayıcınınki, tek bir mağaza kategorisi ya da hiçbiri.
const String _categoryFromProvider = '__provider__';
const String _categoryNone = '__none__';

class _BulkDigitalImportScreenState extends State<BulkDigitalImportScreen> {
  late final BulkProductService _service = widget.service ?? BulkProductService();
  late final SmmService _smm = widget.smmService ?? SmmService();

  bool _loading = true;
  String? _loadError;
  BulkShopContext? _ctx;
  List<SmmProvider> _providers = [];
  String? _providerId;

  bool _loadingServices = false;
  String? _servicesError;
  List<SmmProviderServiceInfo> _services = [];
  String _query = '';
  String? _categoryFilter;
  final Set<String> _selected = {};
  final Map<String, String> _nameOverrides = {};

  final _markupController = TextEditingController(text: '30');
  final _limitController = TextEditingController();
  String _category = _categoryFromProvider;
  BulkImage? _cover;
  bool _hideWithoutImage = true;

  bool _uploading = false;
  int _done = 0;
  int _total = 0;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _markupController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _markupController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final ctx = widget.debugContext ?? await _service.loadShopContext();
      final providers = widget.debugProviders ?? await _smm.getProviders();
      if (!mounted) return;
      // Sunucu kuralıyla aynı: yalnız bu mağazanın aktif sağlayıcıları.
      final usable = providers
          .where((p) => p.isActive && p.ownerType == 'seller' && p.ownerId == ctx.shopId)
          .toList();
      setState(() {
        _ctx = ctx;
        _providers = usable;
        _providerId = usable.length == 1 ? usable.first.id : null;
        _loading = false;
      });
      if (_providerId != null) await _loadServices();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadServices() async {
    final id = _providerId;
    if (id == null) return;
    setState(() {
      _loadingServices = true;
      _servicesError = null;
      _services = [];
      _selected.clear();
      _nameOverrides.clear();
      _categoryFilter = null;
    });
    try {
      final list = widget.debugServices ?? await _smm.getProviderServices(id);
      if (!mounted || id != _providerId) return;
      setState(() => _services = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _servicesError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingServices = false);
    }
  }

  // ── Hesaplar ────────────────────────────────────────────────────────────────

  double? get _markup {
    final v = BulkValues.parseNumber(_markupController.text);
    if (v == null || v < 0 || v > 10000) return null;
    return v;
  }

  static double salePrice(double rate, double markupPercent) =>
      BulkDigitalImportScreen.salePrice(rate, markupPercent);

  Set<String> get _existingServiceIds => {
    for (final p in _ctx?.products ?? const [])
      if (p.isDigital && p.smmProviderId == _providerId && p.smmServiceId != null) p.smmServiceId!,
  };

  /// Ürün yapılamayacak servisin nedeni (fiyat/aralık yok, zaten ekli).
  String? _blockReason(SmmProviderServiceInfo s, Set<String> existing) {
    if (existing.contains(s.service)) return 'Zaten ekli';
    if (s.rate == null || s.rate! < 0) return 'Fiyat yok';
    if (s.min == null || s.max == null || s.min! <= 0 || s.max! < s.min!) return 'Miktar aralığı yok';
    if ((s.name ?? '').trim().length < 2 && !_nameOverrides.containsKey(s.service)) return 'Adı yok';
    return null;
  }

  List<String> get _providerCategories {
    final counts = <String, int>{};
    for (final s in _services) {
      final c = (s.category ?? '').trim();
      if (c.isEmpty) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<SmmProviderServiceInfo> get _visible {
    final q = BulkValues.nameKey(_query);
    return _services.where((s) {
      if (_categoryFilter != null && (s.category ?? '').trim() != _categoryFilter) return false;
      if (q.isEmpty) return true;
      final hay = BulkValues.nameKey('${s.name ?? ''} ${s.category ?? ''} ${s.service}');
      return q.split(' ').every(hay.contains);
    }).toList();
  }

  String _productName(SmmProviderServiceInfo s) {
    final name = (_nameOverrides[s.service] ?? s.name ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return name.length > 200 ? name.substring(0, 200).trim() : name;
  }

  String? _categoryFor(SmmProviderServiceInfo s) {
    switch (_category) {
      case _categoryNone:
        return null;
      case _categoryFromProvider:
        final c = (s.category ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (c.isEmpty) return null;
        return c.length > 60 ? c.substring(0, 60).trim() : c;
      default:
        return _category;
    }
  }

  // ── Eylemler ────────────────────────────────────────────────────────────────

  void _toggleAllVisible(List<SmmProviderServiceInfo> visible) {
    final existing = _existingServiceIds;
    final selectable = visible.where((s) => _blockReason(s, existing) == null).map((s) => s.service).toList();
    setState(() {
      if (selectable.every(_selected.contains)) {
        _selected.removeAll(selectable);
      } else {
        _selected.addAll(selectable);
      }
    });
  }

  Future<void> _renameService(SmmProviderServiceInfo s) async {
    final controller = TextEditingController(text: _productName(s));
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürün adı'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(helperText: 'Sağlayıcıdaki ad: ${s.name ?? '-'}', helperMaxLines: 3),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Kaydet')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    setState(() {
      final t = name.trim();
      if (t.length < 2 || t == (s.name ?? '').trim()) {
        _nameOverrides.remove(s.service);
      } else {
        _nameOverrides[s.service] = t;
      }
    });
  }

  Future<void> _pickCoverFromGallery() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (x == null || !mounted) return;
      setState(() => _cover = BulkImage.file(x.name, x.readAsBytes));
    } catch (e) {
      debugPrint('Kapak görseli seçilemedi: $e');
    }
  }

  Future<void> _pickCoverFromLibrary() async {
    final preset = await showProductImageLibrarySheet(context, initialQuery: 'sosyal medya');
    if (preset == null || !mounted) return;
    setState(() => _cover = BulkImage.library(preset.imageUrl, preset.name));
  }

  Future<void> _import() async {
    final ctx = _ctx;
    final providerId = _providerId;
    final markup = _markup;
    if (ctx == null || providerId == null) return;
    if (markup == null) {
      _toast('Geçerli bir kâr oranı girin');
      return;
    }
    final limitText = _limitController.text.trim();
    final limit = limitText.isEmpty ? null : int.tryParse(limitText);
    if (limitText.isNotEmpty && (limit == null || limit <= 0)) {
      _toast('Kullanıcı başına limit 1 veya daha büyük bir tam sayı olmalı');
      return;
    }

    final existing = _existingServiceIds;
    final chosen = _services
        .where((s) => _selected.contains(s.service) && _blockReason(s, existing) == null)
        .toList();
    if (chosen.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünler eklensin mi?'),
        content: Text(
          '${chosen.length} servis, sağlayıcı fiyatının %${_fmtNum(markup)} üstüyle dijital ürün olarak eklenecek.'
          '${_cover == null && _hideWithoutImage ? '\n\nKapak görseli seçmediğin için ürünler satışa kapalı eklenecek.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ekle')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _uploading = true;
      _done = 0;
      _total = chosen.length;
      _cancelRequested = false;
    });

    String? coverUrl;
    if (_cover != null) {
      final failures = <String>[];
      final urls = await _service.prepareImages(ctx.shopId, [_cover!], failures: failures);
      coverUrl = urls.isEmpty ? null : urls.first;
      if (failures.isNotEmpty) _toast('Kapak görseli yüklenemedi: ${failures.first}');
    }

    var created = 0;
    final failures = <({String name, String error})>[];
    final addedCategories = <String>[];
    var cancelled = 0;
    for (var start = 0; start < chosen.length; start += BulkProductService.rpcChunkSize) {
      if (_cancelRequested) {
        cancelled = chosen.length - start;
        break;
      }
      final chunk = chosen.sublist(start, min(start + BulkProductService.rpcChunkSize, chosen.length));
      final items = [
        for (final s in chunk)
          {
            'product_type': 'digital',
            'name': _productName(s),
            'description': (s.name ?? '').trim(),
            'category': _categoryFor(s),
            'smm_provider_id': providerId,
            'smm_service_id': s.service,
            'price_per_1000': salePrice(s.rate!, markup),
            'min_quantity': s.min,
            'max_quantity': s.max,
            'max_orders_per_user': limit,
            'provider_rate': s.rate,
            'service_name': s.name,
            'image_url': coverUrl,
            'is_available': coverUrl != null || !_hideWithoutImage,
          },
      ];
      try {
        final res = await _service.upsert(ctx.shopId, items);
        created += res.created;
        for (final c in res.addedCategories) {
          if (!addedCategories.contains(c)) addedCategories.add(c);
        }
        for (final r in res.rows) {
          if (!r.ok && r.index >= 0 && r.index < chunk.length) {
            failures.add((name: _productName(chunk[r.index]), error: r.error ?? 'Kaydedilemedi'));
          }
        }
      } catch (e) {
        debugPrint('Toplu dijital ürün parçası başarısız: $e');
        for (final s in chunk) {
          failures.add((name: _productName(s), error: 'Bağlantı ya da sunucu hatası'));
        }
      }
      if (!mounted) return;
      setState(() => _done += chunk.length);
    }

    if (!mounted) return;
    setState(() => _uploading = false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          failures.isEmpty ? Icons.check_circle_rounded : Icons.info_rounded,
          color: failures.isEmpty ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
          size: 44,
        ),
        title: Text('$created ürün eklendi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cancelled > 0) Text('$cancelled servis durdurulduğu için eklenmedi.'),
              if (addedCategories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Mağazana eklenen kategoriler: ${addedCategories.join(', ')}'),
                ),
              if (failures.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${failures.length} servis eklenemedi:', style: const TextStyle(fontWeight: FontWeight.w600)),
                for (final f in failures.take(30))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• ${f.name}: ${f.error}', style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
        ],
      ),
    );
    if (!mounted) return;
    if (created > 0) {
      Navigator.of(context).pop(true);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceAll('.', ',');

  static String _money(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} ₺';

  // ── Görünüm ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_uploading,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(title: const Text('Toplu Dijital Ürün')),
        body: _buildBody(),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }
    if (_uploading) return _buildProgress();
    if (_providers.isEmpty) return _buildNoProvider();

    final visible = _visible;
    final existing = _existingServiceIds;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList.list(
            children: [
              _buildProviderCard(),
              if (_services.isNotEmpty) _buildPricingCard(),
            ],
          ),
        ),
        if (_loadingServices)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          )
        else if (_servicesError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Servisler alınamadı: $_servicesError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB91C1C)),
              ),
            ),
          )
        else if (_services.isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildListHeader(visible, existing)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) => _buildServiceTile(visible[i], existing),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoProvider() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SellerSectionCard(
          title: 'Önce SMM sağlayıcısı ekle',
          icon: Icons.smart_toy_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dijital ürünler bir SMM sağlayıcısının servislerinden oluşturulur. Mağazana ait aktif '
                'bir sağlayıcı yok; SMM Ayarları\'ndan API anahtarınla ekleyebilirsin.',
                style: TextStyle(color: Colors.black54, height: 1.35),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SmmProviderSettingsScreen()),
                  );
                  if (mounted) _load();
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('SMM Ayarları'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProviderCard() {
    return SellerSectionCard(
      title: 'Sağlayıcı',
      icon: Icons.hub_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _providerId,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'SMM sağlayıcısı'),
            items: [
              for (final p in _providers) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _uploading
                ? null
                : (v) {
                    setState(() => _providerId = v);
                    _loadServices();
                  },
          ),
          if (_services.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_services.length} servis · ${_existingServiceIds.length} tanesi zaten ürün',
              style: const TextStyle(color: Colors.black54, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPricingCard() {
    final ctx = _ctx!;
    final markup = _markup;
    final commission = ctx.digitalCommissionRate;
    const sampleRate = 10.0;
    final sale = markup == null ? null : salePrice(sampleRate, markup);
    final net = sale == null ? null : sale * (1 - commission / 100);
    final loses = net != null && net < sampleRate;

    final categoryItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: _categoryFromProvider, child: Text('Sağlayıcının kategorisi')),
      const DropdownMenuItem(value: _categoryNone, child: Text('Kategorisiz')),
      for (final c in ctx.categories)
        DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
    ];

    return SellerSectionCard(
      title: 'Fiyat ve ayarlar',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('bulk-digital-markup'),
                  controller: _markupController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: InputDecoration(
                    labelText: 'Kâr oranı',
                    suffixText: '%',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: markup == null ? 'Geçersiz' : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _limitController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Kişi başı sipariş',
                    hintText: 'sınırsız',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (sale != null) ...[
            const SizedBox(height: 8),
            Text(
              'Örnek: sağlayıcı ${_money(sampleRate)} ise satış ${_money(sale)}, '
              '%${_fmtNum(commission)} komisyon sonrası net ${_money(net!)}',
              style: TextStyle(
                fontSize: 12.5,
                color: loses ? const Color(0xFFB91C1C) : Colors.black54,
              ),
            ),
            if (loses)
              const Text(
                'Bu oranla komisyondan sonra sağlayıcıya ödediğinden az kazanırsın.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
              ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Mağaza kategorisi', isDense: true, border: OutlineInputBorder()),
            items: categoryItems,
            onChanged: (v) => setState(() => _category = v ?? _categoryFromProvider),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                child: _cover == null
                    ? Icon(Icons.image_outlined, color: Colors.grey.shade400)
                    : _cover!.url != null
                    ? Image.network(_cover!.url!, fit: BoxFit.cover)
                    : const Icon(Icons.photo_outlined, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _cover == null
                      ? 'Kapak görseli (tüm ürünlere)'
                      : (_cover!.label ?? _cover!.fileName ?? 'Kapak görseli'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
              IconButton(
                tooltip: 'Galeriden',
                onPressed: _pickCoverFromGallery,
                icon: const Icon(Icons.photo_outlined),
              ),
              IconButton(
                tooltip: 'Kütüphaneden',
                onPressed: _pickCoverFromLibrary,
                icon: const Icon(Icons.collections_outlined),
              ),
              if (_cover != null)
                IconButton(
                  tooltip: 'Kaldır',
                  onPressed: () => setState(() => _cover = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_cover == null)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _hideWithoutImage,
              onChanged: (v) => setState(() => _hideWithoutImage = v),
              title: const Text('Görselsiz eklenenleri satışa kapalı tut', style: TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }

  Widget _buildListHeader(List<SmmProviderServiceInfo> visible, Set<String> existing) {
    final categories = _providerCategories;
    final selectable = visible.where((s) => _blockReason(s, existing) == null).toList();
    final allSelected = selectable.isNotEmpty && selectable.every((s) => _selected.contains(s.service));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Servis ara (ör. instagram takipçi)',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          if (categories.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _categoryFilter,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tüm kategoriler')),
                for (final c in categories)
                  DropdownMenuItem<String?>(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _categoryFilter = v),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${visible.length} servis gösteriliyor · ${_selected.length} seçili',
                  style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                ),
              ),
              TextButton(
                onPressed: selectable.isEmpty ? null : () => _toggleAllVisible(visible),
                child: Text(allSelected ? 'Seçimi kaldır' : 'Görünenleri seç'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceTile(SmmProviderServiceInfo s, Set<String> existing) {
    final block = _blockReason(s, existing);
    final markup = _markup;
    final selected = _selected.contains(s.service);
    final renamed = _nameOverrides.containsKey(s.service);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? const Color(0xFF93C5FD) : Colors.black.withValues(alpha: 0.07),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: block != null
            ? null
            : () => setState(() => selected ? _selected.remove(s.service) : _selected.add(s.service)),
        onLongPress: block != null ? null : () => _renameService(s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: block != null
                    ? null
                    : (v) => setState(() => v == true ? _selected.add(s.service) : _selected.remove(s.service)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _productName(s).isEmpty ? 'Servis ${s.service}' : _productName(s),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: block != null ? Colors.black45 : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        '#${s.service}',
                        if ((s.category ?? '').isNotEmpty) s.category!,
                        if (s.min != null && s.max != null) '${s.min}–${s.max} adet',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 3),
                    if (s.rate != null)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'Sağlayıcı ${_money(s.rate!)}', style: const TextStyle(color: Colors.black54)),
                            if (markup != null) ...[
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.black45),
                                ),
                              ),
                              TextSpan(
                                text: 'Satış ${_money(salePrice(s.rate!, markup))}',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                              ),
                            ],
                            const TextSpan(text: ' /1000', style: TextStyle(color: Colors.black45)),
                          ],
                        ),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    if (renamed)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text('Ad değiştirildi', style: TextStyle(fontSize: 11.5, color: Color(0xFF2563EB))),
                      ),
                  ],
                ),
              ),
              if (block != null)
                Container(
                  margin: const EdgeInsets.only(top: 4, left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(block, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54)),
                )
              else
                IconButton(
                  tooltip: 'Ürün adını düzenle',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _renameService(s),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildBottomBar() {
    if (_loading || _uploading || _providers.isEmpty || _services.isEmpty) return null;
    final existing = _existingServiceIds;
    final count = _services.where((s) => _selected.contains(s.service) && _blockReason(s, existing) == null).length;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.07))),
        ),
        child: FilledButton.icon(
          key: const ValueKey('bulk-digital-import'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: count == 0 || _markup == null ? null : _import,
          icon: const Icon(Icons.playlist_add_rounded),
          label: Text(count == 0 ? 'Servis seçin' : '$count servisi ürün olarak ekle'),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SellerSectionCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.playlist_add_check_rounded, size: 44, color: Color(0xFF2563EB)),
                const SizedBox(height: 12),
                Text('$_done / $_total servis', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _total == 0 ? null : _done / _total,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cancelRequested ? null : () => setState(() => _cancelRequested = true),
                  child: Text(_cancelRequested ? 'Bu parçadan sonra duracak…' : 'Durdur'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
