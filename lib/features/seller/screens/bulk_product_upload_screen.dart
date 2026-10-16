import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../market/widgets/product_image_library_sheet.dart';
import '../models/bulk_product_draft.dart';
import '../services/bulk_product_service.dart';
import '../utils/spreadsheet_io.dart';
import '../widgets/common/seller_section_card.dart';

/// Excel / CSV dosyasından toplu ürün ekleme ve güncelleme.
///
/// Akış: şablon ya da kendi dosyası → önizleme (hatalı satırlar işaretli,
/// satır düzenlenebilir, görseller eşleştirilir) → parça parça yükleme →
/// özet. Sunucu her satırı ayrı doğrular (`seller_bulk_upsert_products`);
/// hatalı satır diğerlerini durdurmaz. Değişiklik olduysa `true` ile kapanır.
class BulkProductUploadScreen extends StatefulWidget {
  const BulkProductUploadScreen({
    super.key,
    this.service,
    @visibleForTesting this.debugContext,
    @visibleForTesting this.debugTable,
  });

  final BulkProductService? service;

  /// Testte mağaza yüklemesini atlar.
  final BulkShopContext? debugContext;

  /// Testte dosya seçmeden önizlemeyi açar.
  final SpreadsheetTable? debugTable;

  static const Color background = Color(0xFFF6F7FB);

  @override
  State<BulkProductUploadScreen> createState() => _BulkProductUploadScreenState();
}

enum _Phase { loading, start, preview, uploading, done }

enum _Filter { all, create, update, invalid, skipped }

class _UploadSummary {
  int created = 0;
  int updated = 0;
  int cancelled = 0;
  final List<({BulkProductDraft draft, String error})> failures = [];
  final Map<int, List<String>> imageFailures = {};
  final List<String> addedCategories = [];

  bool get changedAnything => created > 0 || updated > 0;
}

class _BulkProductUploadScreenState extends State<BulkProductUploadScreen> {
  late final BulkProductService _service = widget.service ?? BulkProductService();

  _Phase _phase = _Phase.loading;
  String? _loadError;
  BulkShopContext? _ctx;

  BulkImportPlan? _plan;
  SpreadsheetTable? _table;
  String _sourceName = '';
  _Filter _filter = _Filter.all;

  bool _librarySearching = false;
  int _libraryTotal = 0;
  int _libraryDone = 0;
  int _libraryGeneration = 0;

  int _progressDone = 0;
  int _progressTotal = 0;
  String _progressLabel = '';
  bool _cancelRequested = false;
  _UploadSummary? _summary;

  /// Bu ekran açıkken en az bir ürün eklendi/güncellendi mi? ("Başka dosya
  /// yükle" ile özet sıfırlansa da kapanırken Ürünlerim yenilenmeli.)
  bool _changedSinceOpen = false;

  bool _busyExport = false;

  @override
  void initState() {
    super.initState();
    if (widget.debugContext != null) {
      _ctx = widget.debugContext;
      _phase = _Phase.start;
      if (widget.debugTable != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openTable(() => widget.debugTable!, 'test.xlsx'),
        );
      }
    } else {
      _loadContext();
    }
  }

  @override
  void dispose() {
    _libraryGeneration++;
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() {
      _phase = _Phase.loading;
      _loadError = null;
    });
    try {
      final ctx = await _service.loadShopContext();
      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _phase = _Phase.start;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ── Dosya ───────────────────────────────────────────────────────────────────

  Future<void> _pickSpreadsheet() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv', 'tsv', 'txt', 'xls'],
        withData: true,
      );
    } catch (e) {
      _toast('Dosya seçilemedi: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _toast('Dosya okunamadı');
      return;
    }
    _openTable(() => SpreadsheetIO.readBytes(bytes, fileName: file.name), file.name);
  }

  Future<void> _pasteFromExcel() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    _openTable(() => SpreadsheetIO.parseText(text), 'Yapıştırılan liste');
  }

  void _openTable(SpreadsheetTable Function() read, String sourceName) {
    final ctx = _ctx;
    if (ctx == null) return;
    try {
      final table = read();
      if (table.rows.isEmpty) {
        _showProblem('Dosya boş görünüyor.');
        return;
      }
      final mapping = BulkSheetMapping.detect(table.rows);
      if (mapping == null) {
        _showProblem(
          'Başlık satırı bulunamadı.\n\nİlk satırda en az "Ürün Adı" ile "Fiyat" ya da '
          '"Stok" sütunları olmalı. En kolayı şablonu indirip doldurmak.',
        );
        return;
      }
      if (table.rows.length - mapping.headerRow - 1 > BulkProductService.maxRows) {
        _showProblem(
          'Bir dosyada en fazla ${BulkProductService.maxRows} ürün olabilir. '
          'Dosyayı bölüp parça parça yükleyin.',
        );
        return;
      }
      final plan = BulkImportPlan.fromTable(
        rows: table.rows,
        mapping: mapping,
        numbersCanonical: table.numbersCanonical,
        existingProducts: ctx.products,
        shopCategories: ctx.categories,
      )..ownStoragePrefix = ctx.ownStoragePrefix;
      plan.resolve();
      if (plan.drafts.isEmpty) {
        _showProblem('Başlık satırının altında ürün yok.');
        return;
      }
      setState(() {
        _plan = plan;
        _table = table;
        _sourceName = sourceName;
        _filter = plan.invalidRows.isNotEmpty ? _Filter.invalid : _Filter.all;
        _phase = _Phase.preview;
      });
      unawaited(_runLibrarySearch());
    } on SpreadsheetReadException catch (e) {
      _showProblem(e.message);
    } catch (e) {
      debugPrint('Toplu yükleme dosyası okunamadı: $e');
      _showProblem('Dosya okunamadı. Excel (.xlsx) ya da CSV dosyası seçtiğinizden emin olun.');
    }
  }

  Future<void> _pickImageFiles() async {
    final plan = _plan;
    if (plan == null) return;
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        // Mobilde yol yeterli; baytlar yüklemede okunur. Web'de yol yok.
        withData: kIsWeb,
      );
    } catch (e) {
      _toast('Görseller seçilemedi: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return;
    var added = 0;
    for (final f in result.files) {
      final key = BulkValues.fileKey(f.name);
      if (key.isEmpty) continue;
      final x = f.xFile;
      plan.pickedFiles[key] = BulkImage.file(f.name, x.readAsBytes);
      added++;
    }
    plan.resolve();
    final matched = plan.drafts
        .where((d) => d.images.any((i) => i.kind == BulkImageKind.file))
        .length;
    setState(() {});
    _toast('$added görsel seçildi · $matched ürünle eşleşti');
  }

  // ── Kütüphane eşleştirme ────────────────────────────────────────────────────

  Future<void> _runLibrarySearch() async {
    final plan = _plan;
    if (plan == null || !plan.useLibraryImages) return;
    final targets = plan.needsLibrarySearch.toList();
    if (targets.isEmpty) return;
    final gen = ++_libraryGeneration;
    setState(() {
      _librarySearching = true;
      _libraryTotal = targets.length;
      _libraryDone = 0;
    });

    await _pool(targets.length, 4, (i) async {
      if (gen != _libraryGeneration) return;
      final d = targets[i];
      try {
        final preset = await _service.findLibraryImage(d.name!);
        if (preset != null) d.libraryImage = BulkImage.library(preset.imageUrl, preset.name);
      } catch (e) {
        debugPrint('Kütüphane araması başarısız (${d.name}): $e');
      }
      d.librarySearched = true;
      if (mounted && gen == _libraryGeneration) setState(() => _libraryDone++);
    });

    if (!mounted || gen != _libraryGeneration) return;
    plan.resolve();
    setState(() => _librarySearching = false);
  }

  void _stopLibrarySearch() {
    _libraryGeneration++;
    _plan?.resolve();
    setState(() => _librarySearching = false);
  }

  void _setUseLibrary(bool value) {
    final plan = _plan;
    if (plan == null) return;
    plan.useLibraryImages = value;
    if (!value) _libraryGeneration++;
    plan.resolve();
    setState(() => _librarySearching = false);
    if (value) unawaited(_runLibrarySearch());
  }

  static Future<void> _pool(int count, int width, Future<void> Function(int i) task) async {
    var next = 0;
    Future<void> worker() async {
      while (next < count) {
        final i = next++;
        await task(i);
      }
    }

    await Future.wait([for (var w = 0; w < min(width, count); w++) worker()]);
  }

  // ── Yükleme ─────────────────────────────────────────────────────────────────

  Future<void> _upload() async {
    final plan = _plan;
    final ctx = _ctx;
    if (plan == null || ctx == null) return;
    final rows = plan.sendable.toList();
    if (rows.isEmpty) return;

    final creates = rows.where((d) => d.action == BulkRowAction.create).length;
    final updates = rows.length - creates;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yüklensin mi?'),
        content: Text(
          [
            if (creates > 0) '$creates yeni ürün eklenecek.',
            if (updates > 0) '$updates ürün güncellenecek.',
            if (plan.invalidRows.isNotEmpty) '${plan.invalidRows.length} hatalı satır atlanacak.',
          ].join('\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yükle')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    _libraryGeneration++;
    final summary = _UploadSummary();
    setState(() {
      _phase = _Phase.uploading;
      _progressDone = 0;
      _progressTotal = rows.length;
      _progressLabel = 'Hazırlanıyor…';
      _cancelRequested = false;
      _librarySearching = false;
    });

    for (var start = 0; start < rows.length; start += BulkProductService.rpcChunkSize) {
      if (_cancelRequested) {
        summary.cancelled = rows.length - start;
        break;
      }
      final chunk = rows.sublist(start, min(start + BulkProductService.rpcChunkSize, rows.length));
      final urls = List<List<String>>.filled(chunk.length, const []);

      final withImages = [
        for (var i = 0; i < chunk.length; i++)
          if (chunk[i].action == BulkRowAction.create || chunk[i].imagesChanged) i,
      ];
      if (withImages.any((i) => chunk[i].images.any((img) => img.needsUpload))) {
        _setProgressLabel('Görseller yükleniyor… (${start + 1}–${start + chunk.length})');
      }
      await _pool(withImages.length, 3, (k) async {
        final i = withImages[k];
        final failures = <String>[];
        urls[i] = await _service.prepareImages(ctx.shopId, chunk[i].images, failures: failures);
        if (failures.isNotEmpty) summary.imageFailures[chunk[i].rowNumber] = failures;
      });

      _setProgressLabel('Kaydediliyor… (${start + 1}–${start + chunk.length})');
      final items = [
        for (var i = 0; i < chunk.length; i++)
          chunk[i].toRpcItem(imageUrls: urls[i], hideWithoutImage: plan.hideWithoutImage),
      ];
      try {
        final res = await _service.upsert(ctx.shopId, items);
        summary.created += res.created;
        summary.updated += res.updated;
        for (final c in res.addedCategories) {
          if (!summary.addedCategories.contains(c)) summary.addedCategories.add(c);
        }
        for (final r in res.rows) {
          if (!r.ok && r.index >= 0 && r.index < chunk.length) {
            summary.failures.add((draft: chunk[r.index], error: r.error ?? 'Kaydedilemedi'));
          }
        }
      } catch (e) {
        debugPrint('Toplu yükleme parçası başarısız: $e');
        final msg = _friendlyError(e);
        for (final d in chunk) {
          summary.failures.add((draft: d, error: msg));
        }
      }
      if (!mounted) return;
      setState(() => _progressDone += chunk.length);
    }

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _changedSinceOpen = _changedSinceOpen || summary.changedAnything;
      _phase = _Phase.done;
    });
  }

  void _setProgressLabel(String label) {
    if (mounted) setState(() => _progressLabel = label);
  }

  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
      return 'Bağlantı hatası; internetinizi kontrol edip bu satırları tekrar yükleyin';
    }
    if (s.contains('42501')) return 'Bu mağazaya ürün ekleme yetkiniz yok';
    return 'Sunucu hatası; bu satırları tekrar yükleyin';
  }

  // ── Dışa aktarma / şablon ───────────────────────────────────────────────────

  Future<void> _shareTemplate(BuildContext buttonContext) async {
    await _share(buttonContext, () => _service.buildTemplate(), 'toplu_urun_sablonu.xlsx');
  }

  Future<void> _shareExport(BuildContext buttonContext) async {
    final ctx = _ctx;
    if (ctx == null) return;
    final stamp = DateTime.now();
    final name =
        'urunlerim_${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}.xlsx';
    await _share(buttonContext, () => _service.buildExport(ctx.products), name);
  }

  /// Hatalı / yüklenemeyen satırları özgün hücreleri + "Hata" sütunuyla verir:
  /// satıcı düzeltip aynı dosyayı yeniden yükler.
  Future<void> _shareFailedRows(BuildContext buttonContext) async {
    final table = _table;
    final plan = _plan;
    final summary = _summary;
    if (table == null || plan == null) return;
    final errors = <int, String>{
      for (final d in plan.drafts.where((d) => d.include && !d.isValid)) d.rowNumber: d.errors.join('; '),
      if (summary != null)
        for (final f in summary.failures) f.draft.rowNumber: f.error,
    };
    final header = table.rows[plan.mapping.headerRow];
    final rows = <List<Object?>>[
      [...header, 'Hata'],
      for (final rowNumber in errors.keys.toList()..sort())
        [
          ...List<String>.generate(header.length, (c) {
            final row = table.rows[rowNumber - 1];
            return c < row.length ? row[c] : '';
          }),
          errors[rowNumber],
        ],
    ];
    await _share(
      buttonContext,
      () => SpreadsheetIO.buildXlsx([SpreadsheetSheet(name: 'Hatalı Satırlar', rows: rows)]),
      'hatali_satirlar.xlsx',
    );
  }

  Future<void> _share(BuildContext buttonContext, Uint8List Function() build, String name) async {
    if (_busyExport) return;
    setState(() => _busyExport = true);
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await _service.shareSpreadsheet(build(), name, origin: origin);
    } catch (e) {
      debugPrint('Dosya paylaşılamadı: $e');
      _toast('Dosya paylaşılamadı');
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  // ── Yardımcılar ─────────────────────────────────────────────────────────────

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showProblem(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dosya yüklenemedi'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
        ],
      ),
    );
  }

  Future<void> _editDraft(BulkProductDraft d) async {
    final plan = _plan;
    if (plan == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _DraftEditSheet(draft: d, numbersCanonical: false),
    );
    if (changed == true && mounted) {
      plan.resolve();
      setState(() {});
      unawaited(_runLibrarySearch());
    }
  }

  void _resetToStart() {
    _libraryGeneration++;
    setState(() {
      _plan = null;
      _table = null;
      _summary = null;
      _librarySearching = false;
      _phase = _Phase.start;
    });
  }

  // ── Görünüm ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final changed = _changedSinceOpen;
    return PopScope(
      // Yükleme bittiyse sistem geri tuşu da `true` dönmeli: Ürünlerim yenilensin.
      canPop: _phase != _Phase.uploading && !changed,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_phase == _Phase.uploading) {
          _toast('Yükleme sürüyor; durdurmak için "Durdur"a basın');
        } else {
          Navigator.of(context).pop(changed);
        }
      },
      child: Scaffold(
        backgroundColor: BulkProductUploadScreen.background,
        appBar: AppBar(
          title: const Text('Toplu Ürün Yükle'),
          leading: _phase == _Phase.uploading
              ? const SizedBox.shrink()
              : BackButton(onPressed: () => Navigator.of(context).pop(changed)),
          actions: [
            if (_phase == _Phase.preview)
              IconButton(
                tooltip: 'Başka dosya seç',
                icon: const Icon(Icons.restart_alt),
                onPressed: _resetToStart,
              ),
          ],
        ),
        body: switch (_phase) {
          _Phase.loading => _buildLoading(),
          _Phase.start => _buildStart(),
          _Phase.preview => _buildPreview(),
          _Phase.uploading => _buildUploading(),
          _Phase.done => _buildDone(),
        },
        bottomNavigationBar: _phase == _Phase.preview ? _buildBottomBar() : null,
      ),
    );
  }

  Widget _buildLoading() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadContext,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildStart() {
    final ctx = _ctx!;
    final primary = Theme.of(context).colorScheme.primary;
    final physicalCount = ctx.products.where((p) => !p.isDigital).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SellerSectionCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.table_view_rounded, color: primary),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Excel ile toplu ürün', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text(
                      'Yüzlerce ürünü tek dosyayla ekle ya da fiyat ve stokları toplu güncelle. '
                      'Yüklemeden önce her satırı kontrol edebilirsin.',
                      style: TextStyle(color: Colors.black54, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SellerSectionCard(
          title: '1. Şablonu indir',
          icon: Icons.download_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hazır sütunlu Excel dosyası. Kendi listen varsa bu adımı atlayabilirsin; '
                '"Ürün Adı", "Fiyat", "Stok" gibi başlıklar otomatik tanınır.',
                style: TextStyle(color: Colors.black54, height: 1.35),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (b) => OutlinedButton.icon(
                  onPressed: _busyExport ? null : () => _shareTemplate(b),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Şablonu indir (.xlsx)'),
                ),
              ),
            ],
          ),
        ),
        SellerSectionCard(
          title: '2. Dosyanı yükle',
          icon: Icons.upload_file_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Excel (.xlsx) ya da CSV. En fazla ${BulkProductService.maxRows} satır.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('bulk-pick-file'),
                onPressed: _pickSpreadsheet,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Dosya seç'),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _pasteFromExcel,
                icon: const Icon(Icons.content_paste_rounded, size: 20),
                label: const Text('Excel\'den kopyala-yapıştır'),
              ),
            ],
          ),
        ),
        if (physicalCount > 0)
          SellerSectionCard(
            title: 'Toplu fiyat / stok güncelle',
            icon: Icons.sync_alt_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$physicalCount ürününü Excel\'e aktar, fiyat ve stokları değiştir, aynı dosyayı '
                  'buradan geri yükle. Yalnız değişen ürünler güncellenir.',
                  style: const TextStyle(color: Colors.black54, height: 1.35),
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (b) => OutlinedButton.icon(
                    onPressed: _busyExport ? null : () => _shareExport(b),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Ürünlerimi dışa aktar'),
                  ),
                ),
              ],
            ),
          ),
        SellerSectionCard(
          title: 'Sütunlar',
          icon: Icons.view_column_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in BulkProductService.templateFields)
                    Chip(
                      label: Text(f.templateHeader),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: f.templateHeader.endsWith('*')
                          ? primary.withValues(alpha: 0.12)
                          : Colors.grey.shade100,
                      side: BorderSide.none,
                      labelStyle: const TextStyle(fontSize: 12.5),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                '* zorunlu. Görsel sütununa bağlantı (https://…) ya da dosya adı yazabilirsin; '
                'boş kalanlar için görsel kütüphanesinde ürün adıyla arama yapılır.',
                style: TextStyle(color: Colors.black54, fontSize: 12.5, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<BulkProductDraft> _filtered(BulkImportPlan plan) => switch (_filter) {
    _Filter.all => plan.drafts,
    _Filter.create => plan.toCreate.toList(),
    _Filter.update => plan.toUpdate.toList(),
    _Filter.invalid => plan.invalidRows.toList(),
    _Filter.skipped => plan.drafts
        .where((d) =>
            !d.include ||
            (d.isValid && (d.action == BulkRowAction.skipExisting || d.action == BulkRowAction.unchanged)))
        .toList(),
  };

  Widget _buildPreview() {
    final plan = _plan!;
    final rows = _filtered(plan);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList.list(
            children: [
              _buildSummaryCard(plan),
              _buildOptionsCard(plan),
            ],
          ),
        ),
        SliverToBoxAdapter(child: _buildFilterBar(plan)),
        if (rows.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Bu filtrede satır yok', style: TextStyle(color: Colors.black45))),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) => _DraftTile(
                key: ValueKey('draft-${rows[i].rowNumber}'),
                draft: rows[i],
                onTap: () => _editDraft(rows[i]),
                onIncludeChanged: (v) {
                  rows[i].include = v;
                  plan.resolve();
                  setState(() {});
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryCard(BulkImportPlan plan) {
    final creates = plan.toCreate.length;
    final updates = plan.toUpdate.length;
    final invalid = plan.invalidRows.length;
    final skipped = plan.skippedExisting.length + plan.unchanged.length + plan.excluded.length;
    return SellerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 20, color: Colors.black54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text('${plan.drafts.length} satır', style: const TextStyle(color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatBox(value: creates, label: 'Yeni', color: const Color(0xFF16A34A)),
              const SizedBox(width: 8),
              _StatBox(value: updates, label: 'Güncelleme', color: const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              _StatBox(value: invalid, label: 'Hatalı', color: const Color(0xFFDC2626)),
              const SizedBox(width: 8),
              _StatBox(value: skipped, label: 'Atlanacak', color: const Color(0xFF6B7280)),
            ],
          ),
          if (plan.mapping.unknownHeaders.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Tanınmayan sütunlar yok sayıldı: ${plan.mapping.unknownHeaders.join(', ')}',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ],
          if (invalid > 0) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (b) => TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: _busyExport ? null : () => _shareFailedRows(b),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Hatalı satırları Excel olarak al'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionsCard(BulkImportPlan plan) {
    final fileMatched = plan.drafts.where((d) => d.images.any((i) => i.kind == BulkImageKind.file)).length;
    final libraryMatched = plan.withLibraryImage.length;
    final wantsImages = plan.drafts.any((d) => d.action == BulkRowAction.create);

    return SellerSectionCard(
      title: 'Seçenekler',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (plan.nameMatchCount > 0) ...[
            Text(
              '${plan.nameMatchCount} ürün mağazanda aynı adla zaten var',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<BulkDuplicatePolicy>(
              segments: [
                for (final p in BulkDuplicatePolicy.values)
                  ButtonSegment(value: p, label: Text(p.label, style: const TextStyle(fontSize: 13))),
              ],
              selected: {plan.duplicatePolicy},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                plan.duplicatePolicy = s.first;
                plan.resolve();
                setState(() {});
                unawaited(_runLibrarySearch());
              },
            ),
            const SizedBox(height: 14),
          ],
          const Text('Görseller', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            plan.pickedFiles.isEmpty
                ? 'Görsel sütunundaki dosya adlarını (ya da ürün adıyla adlandırılmış fotoğrafları) '
                    'eşleştirmek için fotoğrafları seç.'
                : '${plan.pickedFiles.length} fotoğraf seçildi · $fileMatched ürünle eşleşti',
            style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickImageFiles,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(plan.pickedFiles.isEmpty ? 'Fotoğrafları seç' : 'Fotoğraf ekle'),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: plan.useLibraryImages,
            onChanged: _setUseLibrary,
            title: const Text('Görseli olmayanlara kütüphaneden bul', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              _librarySearching
                  ? 'Aranıyor… $_libraryDone / $_libraryTotal'
                  : (libraryMatched > 0 ? '$libraryMatched ürüne görsel bulundu' : 'Ürün adıyla hazır görsel aranır'),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          if (_librarySearching)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _libraryTotal == 0 ? null : _libraryDone / _libraryTotal,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  TextButton(onPressed: _stopLibrarySearch, child: const Text('Durdur')),
                ],
              ),
            ),
          if (wantsImages)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: plan.hideWithoutImage,
              onChanged: (v) {
                plan.hideWithoutImage = v;
                plan.resolve();
                setState(() {});
              },
              title: const Text('Görselsiz ürünleri satışa kapalı ekle', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Sonradan görsel ekleyip Ürünlerim\'den satışa açabilirsin',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BulkImportPlan plan) {
    final skipped = plan.skippedExisting.length + plan.unchanged.length + plan.excluded.length;
    final items = <(_Filter, String, int)>[
      (_Filter.all, 'Tümü', plan.drafts.length),
      (_Filter.create, 'Yeni', plan.toCreate.length),
      (_Filter.update, 'Güncelleme', plan.toUpdate.length),
      (_Filter.invalid, 'Hatalı', plan.invalidRows.length),
      (_Filter.skipped, 'Atlanacak', skipped),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (final (f, label, count) in items)
            if (f == _Filter.all || count > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  label: Text('$label ($count)'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final plan = _plan!;
    final count = plan.sendable.length;
    final blocked = _librarySearching;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.07))),
        ),
        child: FilledButton.icon(
          key: const ValueKey('bulk-upload'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: count == 0 || blocked ? null : _upload,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(
            blocked
                ? 'Görseller aranıyor…'
                : count == 0
                ? 'Yüklenecek ürün yok'
                : '$count ürünü yükle',
          ),
        ),
      ),
    );
  }

  Widget _buildUploading() {
    final fraction = _progressTotal == 0 ? null : _progressDone / _progressTotal;
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
                const Icon(Icons.cloud_upload_rounded, size: 44, color: Color(0xFF2563EB)),
                const SizedBox(height: 12),
                Text(
                  '$_progressDone / $_progressTotal ürün',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(_progressLabel, style: const TextStyle(color: Colors.black54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: fraction, minHeight: 8, borderRadius: BorderRadius.circular(8)),
                const SizedBox(height: 16),
                const Text(
                  'Uygulamadan çıkmayın. Yarıda keserseniz yüklenenler kalır.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black45),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
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

  Widget _buildDone() {
    final s = _summary!;
    final plan = _plan!;
    final invalidCount = plan.invalidRows.length;
    final failedTotal = s.failures.length + invalidCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SellerSectionCard(
          child: Column(
            children: [
              Icon(
                s.failures.isEmpty ? Icons.check_circle_rounded : Icons.info_rounded,
                size: 52,
                color: s.failures.isEmpty ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 10),
              Text(
                s.changedAnything ? 'Yükleme tamamlandı' : 'Hiçbir ürün kaydedilmedi',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatBox(value: s.created, label: 'Eklendi', color: const Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  _StatBox(value: s.updated, label: 'Güncellendi', color: const Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  _StatBox(value: failedTotal, label: 'Hatalı', color: const Color(0xFFDC2626)),
                ],
              ),
              if (s.cancelled > 0) ...[
                const SizedBox(height: 12),
                Text('${s.cancelled} ürün durdurulduğu için yüklenmedi.', style: const TextStyle(color: Colors.black54)),
              ],
              if (s.addedCategories.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Mağazana eklenen kategoriler: ${s.addedCategories.join(', ')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
        if (s.failures.isNotEmpty || s.imageFailures.isNotEmpty)
          SellerSectionCard(
            title: 'Sorunlu satırlar',
            icon: Icons.error_outline,
            iconColor: const Color(0xFFDC2626),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in s.failures.take(50))
                  _ProblemLine(row: f.draft.rowNumber, name: f.draft.displayName, message: f.error, error: true),
                for (final e in s.imageFailures.entries.take(50))
                  _ProblemLine(
                    row: e.key,
                    name: 'Görsel',
                    message: e.value.join('; '),
                    error: false,
                  ),
                if (s.failures.length > 50 || s.imageFailures.length > 50)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('…ve diğerleri (hepsi Excel dosyasında)', style: TextStyle(color: Colors.black54)),
                  ),
              ],
            ),
          ),
        if (failedTotal > 0)
          Builder(
            builder: (b) => OutlinedButton.icon(
              onPressed: _busyExport ? null : () => _shareFailedRows(b),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Hatalı satırları Excel olarak al'),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).pop(_changedSinceOpen),
          child: const Text('Bitti'),
        ),
        const SizedBox(height: 4),
        TextButton(onPressed: _resetToStart, child: const Text('Başka dosya yükle')),
      ],
    );
  }
}

// ── Parçalar ──────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label, required this.color});

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: color.withValues(alpha: 0.9)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProblemLine extends StatelessWidget {
  const _ProblemLine({required this.row, required this.name, required this.message, required this.error});

  final int row;
  final String name;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Satır $row · ', style: const TextStyle(color: Colors.black45)),
            TextSpan(text: '$name: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(
              text: message,
              style: TextStyle(color: error ? const Color(0xFFB91C1C) : const Color(0xFFB45309)),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 13, height: 1.35),
      ),
    );
  }
}

String _money(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} ₺';

class _DraftTile extends StatelessWidget {
  const _DraftTile({super.key, required this.draft, required this.onTap, required this.onIncludeChanged});

  final BulkProductDraft draft;
  final VoidCallback onTap;
  final ValueChanged<bool> onIncludeChanged;

  ({String label, Color color}) get _status {
    final d = draft;
    if (!d.include) return (label: 'Çıkarıldı', color: const Color(0xFF6B7280));
    if (!d.isValid) return (label: 'Hatalı', color: const Color(0xFFDC2626));
    return switch (d.action) {
      BulkRowAction.create => (label: 'Yeni', color: const Color(0xFF16A34A)),
      BulkRowAction.update => (label: 'Güncellenecek', color: const Color(0xFF2563EB)),
      BulkRowAction.skipExisting => (label: 'Var · atlanacak', color: const Color(0xFF6B7280)),
      BulkRowAction.unchanged => (label: 'Değişmedi', color: const Color(0xFF6B7280)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final status = _status;
    final details = <String>[
      'Satır ${d.rowNumber}',
      if (d.price != null) _money(d.price!) else if (d.existing != null) _money(d.existing!.price),
      if (d.stock != null) 'Stok ${d.stock}' else if (d.existing != null) 'Stok ${d.existing!.stockLabel}',
      if ((d.category ?? '').isNotEmpty) d.category!,
    ];
    if (d.action == BulkRowAction.update && d.isValid) {
      final diff = d.updateDiff().keys.map(_fieldLabel).toList();
      if (d.imagesChanged) diff.add('görsel');
      if (diff.isNotEmpty) details.add('Değişecek: ${diff.join(', ')}');
    }

    return Opacity(
      opacity: d.include ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: d.include && !d.isValid ? const Color(0xFFFCA5A5) : Colors.black.withValues(alpha: 0.07),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: d.include, onChanged: (v) => onIncludeChanged(v ?? false)),
                _Thumb(images: d.images),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              d.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: status.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.label,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: status.color),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        details.join(' · '),
                        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                      ),
                      for (final e in d.errors)
                        _Note(text: e, color: const Color(0xFFB91C1C), icon: Icons.error_outline),
                      if (d.include)
                        for (final w in d.warnings)
                          _Note(text: w, color: const Color(0xFFB45309), icon: Icons.info_outline),
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

  static String _fieldLabel(String key) => switch (key) {
    'name' => 'ad',
    'description' => 'açıklama',
    'price' => 'fiyat',
    'old_price' => 'eski fiyat',
    'stock' => 'stok',
    'category' => 'kategori',
    'is_available' => 'satış durumu',
    'shipping_fee' => 'kargo ücreti',
    'free_shipping' => 'ücretsiz kargo',
    'min_order_quantity' => 'min. adet',
    'max_order_quantity' => 'maks. adet',
    'badges' => 'rozetler',
    _ => key,
  };
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color, height: 1.3))),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.images});

  final List<BulkImage> images;

  @override
  Widget build(BuildContext context) {
    final first = images.isEmpty ? null : images.first;
    Widget child;
    if (first == null) {
      child = Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: 22);
    } else if (first.hasNetworkPreview) {
      child = CachedNetworkImage(
        imageUrl: first.url!,
        fit: BoxFit.cover,
        memCacheWidth: 120,
        errorWidget: (_, _, _) => Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
      );
    } else {
      child = Icon(
        first.kind == BulkImageKind.file ? Icons.photo_outlined : Icons.link_rounded,
        color: const Color(0xFF2563EB),
        size: 22,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 52,
          height: 52,
          margin: const EdgeInsets.only(top: 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: child),
        ),
        if (first?.kind == BulkImageKind.library)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF7C3AED)),
            ),
          ),
        if (images.length > 1)
          Positioned(
            left: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Text('+${images.length - 1}', style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
      ],
    );
  }
}

/// Excel'den kopyalanan hücreleri yapıştırma penceresi.
class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _controller.text = text;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Excel\'den yapıştır'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Excel ya da Google E-Tablolar\'da başlık satırıyla birlikte hücreleri seçip kopyalayın, '
              'buraya yapıştırın.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              minLines: 6,
              maxLines: 10,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'Ürün Adı\tFiyat\tStok\nSalkım Domates\t34,90\t25',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pasteClipboard,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Panodan yapıştır'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Devam')),
      ],
    );
  }
}

/// Önizlemede bir satırı düzeltme sayfası.
class _DraftEditSheet extends StatefulWidget {
  const _DraftEditSheet({required this.draft, required this.numbersCanonical});

  final BulkProductDraft draft;
  final bool numbersCanonical;

  @override
  State<_DraftEditSheet> createState() => _DraftEditSheetState();
}

class _DraftEditSheetState extends State<_DraftEditSheet> {
  static const _fields = [
    BulkField.name,
    BulkField.price,
    BulkField.oldPrice,
    BulkField.stock,
    BulkField.category,
    BulkField.description,
  ];

  late final Map<BulkField, TextEditingController> _controllers = {
    for (final f in _fields) f: TextEditingController(text: widget.draft.rawText(f)),
  };
  late bool _include = widget.draft.include;
  late List<BulkImage>? _manualImages = widget.draft.manualImages;
  bool _imageTouched = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (x == null || !mounted) return;
      setState(() {
        _manualImages = [BulkImage.file(x.name, x.readAsBytes)];
        _imageTouched = true;
      });
    } catch (e) {
      debugPrint('Galeriden seçilemedi: $e');
    }
  }

  Future<void> _pickFromLibrary() async {
    final preset = await showProductImageLibrarySheet(
      context,
      initialQuery: _controllers[BulkField.name]!.text,
    );
    if (preset == null || !mounted) return;
    setState(() {
      _manualImages = [BulkImage.library(preset.imageUrl, preset.name)];
      _imageTouched = true;
    });
  }

  void _save() {
    final d = widget.draft;
    for (final f in _fields) {
      final text = _controllers[f]!.text;
      if (text.trim() != d.rawText(f).trim()) {
        d.setRaw(f, text, numbersCanonical: widget.numbersCanonical);
        if (f == BulkField.name) {
          // Ad değişti: kütüphane eşleşmesi eski ada göreydi, yeniden aranır.
          d
            ..libraryImage = null
            ..librarySearched = false;
        }
      }
    }
    d.include = _include;
    if (_imageTouched) d.manualImages = _manualImages;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final isUpdate = d.action == BulkRowAction.update || d.action == BulkRowAction.unchanged;
    final current = _manualImages ?? d.images;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    InputDecoration deco(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: const OutlineInputBorder(),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Satır ${d.rowNumber}${isUpdate ? ' · mevcut ürünü günceller' : ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (isUpdate)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Boş bıraktığın alan değişmez.',
                  style: TextStyle(color: Colors.black54, fontSize: 12.5),
                ),
              ),
            for (final e in d.errors) _Note(text: e, color: const Color(0xFFB91C1C), icon: Icons.error_outline),
            const SizedBox(height: 14),
            TextField(controller: _controllers[BulkField.name], decoration: deco('Ürün adı')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[BulkField.price],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: deco('Fiyat (₺)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controllers[BulkField.oldPrice],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: deco('Eski fiyat', hint: 'isteğe bağlı'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[BulkField.stock],
                    keyboardType: TextInputType.number,
                    decoration: deco('Stok'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(controller: _controllers[BulkField.category], decoration: deco('Kategori')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controllers[BulkField.description],
              minLines: 2,
              maxLines: 4,
              decoration: deco('Açıklama'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Thumb(images: current),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    current.isEmpty
                        ? 'Görsel yok'
                        : switch (current.first.kind) {
                            BulkImageKind.library => 'Kütüphaneden: ${current.first.label ?? ''}',
                            BulkImageKind.file => 'Dosya: ${current.first.fileName ?? ''}',
                            BulkImageKind.remote => 'Bağlantıdan indirilecek',
                            BulkImageKind.ready => 'Mevcut görsel',
                          },
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_outlined, size: 18),
                  label: const Text('Galeriden'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickFromLibrary,
                  icon: const Icon(Icons.collections_outlined, size: 18),
                  label: const Text('Kütüphaneden'),
                ),
                if (current.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      _manualImages = const [];
                      _imageTouched = true;
                    }),
                    child: const Text('Görseli kaldır'),
                  ),
                if (_manualImages != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _manualImages = null;
                      _imageTouched = true;
                    }),
                    child: const Text('Otomatik'),
                  ),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _include,
              onChanged: (v) => setState(() => _include = v),
              title: const Text('Bu satırı yükle'),
            ),
            const SizedBox(height: 4),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _save,
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}
