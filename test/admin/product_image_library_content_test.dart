import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cizreapp/core/models/product_image_preset_model.dart';
import 'package:cizreapp/features/admin/widgets/admin_ui.dart';
import 'package:cizreapp/features/admin/widgets/product_image_library_content.dart';
import 'package:cizreapp/features/market/services/product_image_preset_service.dart';
import 'package:cizreapp/features/market/services/product_image_scrape_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Supabase'e dokunmayan sahte servis. Admin sayfa/kimlik RPC'lerini
/// bellekteki listeyle taklit eder (sunucudaki süzgeç, arama, sıralama ve
/// sayaç kuralları); yazımları hem kaydeder hem listeye uygular ki sunucudan
/// tazelenen sayaçlar gerçekçi olsun.
class _FakeService extends ProductImagePresetService {
  _FakeService(
    List<ProductImagePreset> items, {
    this.failName,
    List<ProductImageFolder>? folders,
  }) : items = [...items],
       folders = [...(folders ?? _folders())];

  final List<ProductImagePreset> items;
  final List<ProductImageFolder> folders;
  final String? failName;
  final List<Map<String, dynamic>> added = [];
  final List<(List<String>, String?)> moved = [];
  final List<(List<String>, bool)> activated = [];
  final List<List<String>> deleted = [];
  final List<String> addedFolders = [];
  final List<Map<String, dynamic>> folderUpdates = [];
  final List<List<String>> reordered = [];
  final List<
    ({ProductImageAdminQuery query, int limit, int offset, bool summary})
  >
  pageCalls = [];
  final List<ProductImageAdminQuery> idCalls = [];

  /// Verilirse yazımlar (taşı / durum / sil) bu bitene kadar bekler; hatayla
  /// biterse yazım uygulanmaz.
  Completer<void>? writeGate;

  /// Açılış ve tam yenilemeler (satır + özet isteyen sayfa istekleri).
  int get loads => pageCalls.where((c) => c.summary && c.limit > 0).length;

  static const Map<String, String> _tr = {
    'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g', //
    'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c',
  };

  static String _norm(String s) => [
    for (final r in s.runes)
      _tr[String.fromCharCode(r)] ?? String.fromCharCode(r).toLowerCase(),
  ].join();

  List<ProductImagePreset> _match(ProductImageAdminQuery q) {
    final words = _norm(
      q.search,
    ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final list = items.where((p) {
      if (q.folderId != null && p.folderId != q.folderId) return false;
      if (q.unfiled && p.folderId != null) return false;
      if (q.status == ProductImageAdminStatus.active && !p.isActive) {
        return false;
      }
      if (q.status == ProductImageAdminStatus.passive && p.isActive) {
        return false;
      }
      final text = _norm('${p.name} ${p.description ?? ''}');
      return words.every(text.contains);
    }).toList();
    list.sort(
      (a, b) => q.sort == ProductImageAdminSort.newest
          ? b.createdAt.compareTo(a.createdAt)
          : (a.displayOrder != b.displayOrder
                ? a.displayOrder.compareTo(b.displayOrder)
                : _norm(a.name).compareTo(_norm(b.name))),
    );
    return list;
  }

  ProductImageLibrarySummary _summary() {
    int count(String? folder, {bool activeOnly = false}) => items
        .where((p) => p.folderId == folder && (!activeOnly || p.isActive))
        .length;
    return ProductImageLibrarySummary(
      folders: [
        for (final f in folders)
          f.copyWith(
            imageCount: count(f.id),
            activeImageCount: count(f.id, activeOnly: true),
          ),
      ],
      unfiledCount: count(null),
      unfiledActiveCount: count(null, activeOnly: true),
      maxDisplayOrder: items.fold(0, (m, p) => math.max(m, p.displayOrder)),
    );
  }

  @override
  Future<ProductImageAdminPage> getAdminPage(
    ProductImageAdminQuery query, {
    int limit = ProductImagePresetService.adminPageSize,
    int offset = 0,
    bool withSummary = false,
  }) async {
    pageCalls.add((
      query: query,
      limit: limit,
      offset: offset,
      summary: withSummary,
    ));
    final all = _match(query);
    return ProductImageAdminPage(
      items: all.skip(offset).take(limit).toList(),
      total: all.length,
      summary: withSummary ? _summary() : null,
    );
  }

  @override
  Future<List<String>> getAdminPresetIds(ProductImageAdminQuery query) async {
    idCalls.add(query);
    return [for (final p in _match(query)) p.id];
  }

  Future<void> _write(
    List<String> ids,
    ProductImagePreset? Function(ProductImagePreset p) change,
  ) async {
    await writeGate?.future;
    final set = ids.toSet();
    final next = <ProductImagePreset>[];
    for (final p in items) {
      final changed = set.contains(p.id) ? change(p) : p;
      if (changed != null) next.add(changed);
    }
    items
      ..clear()
      ..addAll(next);
  }

  @override
  Future<void> moveToFolder(List<String> ids, String? folderId) async {
    moved.add((ids, folderId));
    await _write(ids, (p) => p.withFolder(folderId));
  }

  @override
  Future<void> setActive(List<String> ids, bool isActive) async {
    activated.add((ids, isActive));
    await _write(ids, (p) => p.copyWith(isActive: isActive));
  }

  @override
  Future<void> deletePresets(List<String> ids) async {
    deleted.add(ids);
    await _write(ids, (_) => null);
  }

  @override
  Future<ProductImageFolder> addFolder({
    required String name,
    int displayOrder = 0,
  }) async {
    addedFolders.add('$name#$displayOrder');
    final folder = ProductImageFolder(
      id: 'nf${addedFolders.length}',
      name: name,
      displayOrder: displayOrder,
    );
    folders.add(folder);
    return folder;
  }

  @override
  Future<void> updateFolder({
    required String id,
    String? name,
    int? displayOrder,
    bool? isActive,
  }) async {
    folderUpdates.add({'id': id, 'name': name, 'active': isActive});
    final i = folders.indexWhere((f) => f.id == id);
    folders[i] = folders[i].copyWith(name: name, isActive: isActive);
  }

  @override
  Future<void> reorderFolders(List<String> idsInOrder) async {
    reordered.add(idsInOrder);
  }

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String uniqueTag,
  }) async => 'https://example.invalid/$uniqueTag-$fileName';

  @override
  Future<ProductImagePreset> addPreset({
    required String name,
    String? description,
    required String imageUrl,
    int displayOrder = 0,
    bool isActive = true,
    String? folderId,
  }) async {
    if (name == failName) throw Exception('Sunucu reddetti');
    added.add({
      'name': name,
      'description': description,
      'order': displayOrder,
      'active': isActive,
      'folder': folderId,
    });
    final preset = ProductImagePreset(
      id: 'new${added.length}',
      name: name,
      imageUrl: imageUrl,
      displayOrder: displayOrder,
      isActive: isActive,
      createdAt: DateTime.now(),
      folderId: folderId,
    );
    items.add(preset);
    return preset;
  }
}

/// Ağa çıkmayan sahte kazıyıcı: her linke aynı görseli döner.
class _FakeScrape extends ProductImageScrapeService {
  _FakeScrape(this.image);

  final ScrapedProductImage image;
  final List<String> links = [];

  @override
  Future<ScrapedProductImage> fetchFromLink(String link) async {
    links.add(link);
    return image;
  }
}

class _FakePicker extends ImagePickerPlatform {
  _FakePicker(this.files);

  final List<XFile> files;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => files;
}

Future<Uint8List> _png() async {
  final rec = ui.PictureRecorder();
  Canvas(
    rec,
  ).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.teal);
  final img = await rec.endRecording().toImage(8, 8);
  return (await img.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
}

/// Manav açık, Kozmetik kapalı.
List<ProductImageFolder> _folders() => const [
  ProductImageFolder(id: 'f1', name: 'Manav', displayOrder: 1),
  ProductImageFolder(
    id: 'f2',
    name: 'Kozmetik',
    displayOrder: 2,
    isActive: false,
  ),
];

/// Domates ve Simit Manav'da, Çiğ köfte klasörsüz; Simit pasif.
List<ProductImagePreset> _sample() => [
  for (final (i, n) in const [
    ('Kırmızı domates', 'sebze, salata', 'f1'),
    ('Çiğ köfte', 'yemek', null),
    ('Simit', null, 'f1'),
  ].indexed)
    ProductImagePreset(
      id: 'id$i',
      name: n.$1,
      description: n.$2,
      imageUrl: 'https://example.invalid/$i.jpg',
      isActive: i != 2,
      displayOrder: i + 1,
      createdAt: DateTime(2026, 9, 1 + i),
      folderId: n.$3,
    ),
];

/// Sayfalı liste için büyük kütüphane: "Görsel 1" … "Görsel n" (sıra no =
/// numara), Manav'da; her üçüncüsü pasif.
List<ProductImagePreset> _many(int n) => [
  for (var i = 1; i <= n; i++)
    ProductImagePreset(
      id: 'g$i',
      name: 'Görsel $i',
      imageUrl: 'https://example.invalid/g$i.jpg',
      isActive: i % 3 != 0,
      displayOrder: i,
      createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
      folderId: 'f1',
    ),
];

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Durum kutusundaki sayı ([label]: Tümü / Yayında / Pasif).
Finder _stat(String label, int value) => find.descendant(
  of: find.widgetWithText(AdminCard, label),
  matching: find.text('$value'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // CachedNetworkImage önbellek dizini için path_provider ister.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  void bigScreen(WidgetTester t) {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(900, 1600);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> open(
    WidgetTester t,
    _FakeService svc, {
    ProductImageScrapeService? scrape,
  }) async {
    bigScreen(t);
    await t.pumpWidget(
      _host(ProductImageLibraryContent(service: svc, scrapeService: scrape)),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('arama Türkçe harfleri sadeleştirir, filtre durumu ayırır', (
    t,
  ) async {
    await open(t, _FakeService(_sample()));
    expect(find.text('Simit'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'cig');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Çiğ köfte'), findsOneWidget);
    expect(find.text('Simit'), findsNothing);

    await t.enterText(find.byType(TextField).first, '');
    await t.tap(find.text('Pasif'));
    await t.pump();
    expect(find.text('Simit'), findsOneWidget);
    expect(find.text('Çiğ köfte'), findsNothing);
  });

  testWidgets('uzun basınca seçim modu açılır', (t) async {
    await open(t, _FakeService(_sample()));
    await t.longPress(find.text('Çiğ köfte'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('1 seçildi'), findsOneWidget);
  });

  testWidgets('çoklu ekleme: adsız satır engellenir, sıra ve durum atanır, '
      'hatalı satır tekrar denenir', (t) async {
    final png = await t.runAsync(_png);
    ImagePickerPlatform.instance = _FakePicker([
      XFile.fromData(
        png!,
        name: 'domates_kirmizi.png',
        path: '/x/domates_kirmizi.png',
      ),
      XFile.fromData(
        png,
        name: 'IMG_2026_0901.png',
        path: '/x/IMG_2026_0901.png',
      ),
      XFile.fromData(png, name: 'zeytin-yagi.png', path: '/x/zeytin-yagi.png'),
    ]);
    final svc = _FakeService(_sample(), failName: 'Zeytin yağı');
    await open(t, svc);

    await t.tap(find.text('Görsel Ekle').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Görselleri seç'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(milliseconds: 300));

    final fields = find.widgetWithText(TextField, 'Görsel adı *');
    expect(fields, findsNWidgets(3));
    // Dosya adından öneri: kamera adı (IMG_...) boş bırakılır.
    expect(
      (t.widget<TextField>(fields.at(0)).controller!.text),
      'Domates kirmizi',
    );
    expect(t.widget<TextField>(fields.at(1)).controller!.text, isEmpty);

    // Boş adla gönderim engellenir; hiçbir şey eklenmez.
    await t.tap(find.text('3 görseli kütüphaneye ekle'));
    await t.pump();
    expect(find.text('Ad gerekli'), findsOneWidget);
    expect(svc.added, isEmpty);

    await t.enterText(fields.at(1), 'Kuru fasulye');
    await t.enterText(fields.at(2), 'Zeytin yağı');
    await t.tap(find.text('3 görseli kütüphaneye ekle'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pump(const Duration(milliseconds: 300));

    // Mevcut en büyük sıra 3 -> yeniler 4 ve 5; biri sunucuda reddedildi.
    expect(svc.added.map((e) => e['order']), [4, 5]);
    expect(svc.added.every((e) => e['active'] == true), isTrue);
    expect(find.text('Kalan 1 görseli tekrar dene'), findsOneWidget);
    expect(find.text('Sunucu reddetti'), findsOneWidget);
  });

  testWidgets('linkten ekle: sayfa başlığı ad önerisi olur, satır kaydedilir', (
    t,
  ) async {
    final png = (await t.runAsync(_png))!;
    final scrape = _FakeScrape(
      ScrapedProductImage(
        bytes: png,
        mimeType: 'image/png',
        extension: 'png',
        imageUrl: 'https://cdn.example.com/domates.png',
        title: 'Kırmızı domates 1 kg',
      ),
    );
    final svc = _FakeService(_sample());
    await open(t, svc, scrape: scrape);

    await t.tap(find.text('Görsel Ekle').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Ürün linkinden ekle'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    await t.enterText(
      find.widgetWithText(TextField, 'Ürün linki'),
      'https://shop.example.com/domates',
    );
    await t.tap(find.text('Görseli Getir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Bu görseli kullan'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    expect(scrape.links, ['https://shop.example.com/domates']);
    final name = find.widgetWithText(TextField, 'Görsel adı *');
    expect(name, findsOneWidget);
    expect(t.widget<TextField>(name).controller!.text, 'Kırmızı domates 1 kg');

    await t.tap(find.text('1 görseli kütüphaneye ekle'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pump(const Duration(milliseconds: 300));

    expect(svc.added.single['name'], 'Kırmızı domates 1 kg');
    expect(svc.added.single['order'], 4);
  });

  testWidgets('klasör çipleri süzer; tüm görünümde kartta klasör adı çıkar', (
    t,
  ) async {
    await open(t, _FakeService(_sample()));

    // Çip şeridi yatay kayar; test fontu geniş olduğu için sondakiler görünür
    // alanın dışında kalabilir (ekran dışı sayılır), dokunmadan önce kaydırılır.
    Finder chip(String label) => find.text(label, skipOffstage: false);
    Future<void> tapChip(String label) async {
      await t.ensureVisible(chip(label));
      await t.pump();
      await t.tap(chip(label));
      await t.pump();
    }

    expect(chip('Tüm klasörler · 3'), findsOneWidget);
    expect(chip('Manav · 2'), findsOneWidget);
    expect(chip('Kozmetik (kapalı) · 0'), findsOneWidget);
    expect(chip('Klasörsüz · 1'), findsOneWidget);
    // Tüm klasörler görünümünde Manav'daki iki kartta klasör etiketi var.
    expect(find.text('Manav'), findsNWidgets(2));

    await tapChip('Manav · 2');
    expect(find.text('Kırmızı domates'), findsOneWidget);
    expect(find.text('Simit'), findsOneWidget);
    expect(find.text('Çiğ köfte'), findsNothing);
    // Tek klasöre bakarken etiket tekrar etmez.
    expect(find.text('Manav'), findsNothing);

    await tapChip('Klasörsüz · 1');
    expect(find.text('Çiğ köfte'), findsOneWidget);
    expect(find.text('Kırmızı domates'), findsNothing);

    // Boş klasör: ekleme çağrısı gösterilir.
    await tapChip('Kozmetik (kapalı) · 0');
    expect(find.text('Bu klasörde henüz görsel yok'), findsOneWidget);
  });

  testWidgets('seçilen görsel klasöre taşınır, sayaçlar anında güncellenir', (
    t,
  ) async {
    final svc = _FakeService(_sample());
    await open(t, svc);

    await t.longPress(find.text('Çiğ köfte'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byTooltip('Klasöre taşı'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    // Çiğ köfte klasörsüz: "Klasörsüz" satırı şu anki diye işaretli.
    expect(find.text('Şu anki'), findsOneWidget);
    await t.tap(find.text('Kozmetik'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    expect(svc.moved.single.$1, ['id1']);
    expect(svc.moved.single.$2, 'f2');
    expect(find.text('Görsel "Kozmetik" klasörüne taşındı'), findsOneWidget);
    expect(
      find.text('Kozmetik (kapalı) · 1', skipOffstage: false),
      findsOneWidget,
    );
    // Klasörsüz görsel kalmadı: çip kaybolur.
    expect(find.textContaining('Klasörsüz', skipOffstage: false), findsNothing);
  });

  testWidgets('klasör süzülürken eklenen görseller o klasöre gider', (t) async {
    final png = await t.runAsync(_png);
    ImagePickerPlatform.instance = _FakePicker([
      XFile.fromData(png!, name: 'zeytin.png', path: '/x/zeytin.png'),
    ]);
    final svc = _FakeService(_sample());
    await open(t, svc);

    await t.tap(find.text('Manav · 2'));
    await t.pump();
    await t.tap(find.text('Görsel Ekle').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Görselleri seç'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(milliseconds: 300));

    // Alt çubuktaki klasör seçimi süzülen klasörle gelir.
    expect(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        matching: find.text('Manav'),
      ),
      findsOneWidget,
    );
    await t.tap(find.text('1 görseli kütüphaneye ekle'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pump(const Duration(milliseconds: 300));

    expect(svc.added.single['name'], 'Zeytin');
    expect(svc.added.single['folder'], 'f1');
  });

  testWidgets('Klasörler sayfası: ekler, kapatır, sürükleyerek sıralar', (
    t,
  ) async {
    final svc = _FakeService(_sample());
    await open(t, svc);
    expect(svc.loads, 1);
    expect(svc.pageCalls, hasLength(1));

    await t.tap(find.text('Klasörler'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('2 görsel · 1 yayında'), findsOneWidget);

    // Boş ad engellenir.
    await t.tap(find.text('Ekle'));
    await t.pump();
    expect(find.text('Klasör adı yaz'), findsOneWidget);
    expect(svc.addedFolders, isEmpty);

    await t.enterText(
      find.widgetWithText(TextField, 'Yeni klasör adı'),
      '  Hırdavat ',
    );
    await t.tap(find.text('Ekle'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // Kırpılmış ad, en büyük sıranın bir fazlası.
    expect(svc.addedFolders, ['Hırdavat#3']);
    expect(find.text('Hırdavat'), findsOneWidget);

    // Manav'ı kapat.
    await t.tap(find.byType(Switch).first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(svc.folderUpdates.single, {
      'id': 'f1',
      'name': null,
      'active': false,
    });
    expect(find.text('2 görsel · kapalı, satıcılar görmez'), findsOneWidget);

    // Manav'ı tutamağından en alta sürükle.
    final g = await t.startGesture(
      t.getCenter(find.byIcon(Icons.drag_indicator_rounded).first),
    );
    await t.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(0, 25));
      await t.pump(const Duration(milliseconds: 50));
    }
    await g.up();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(svc.reordered.single, ['f2', 'nf1', 'f1']);

    // Kapatınca değişiklik olduğu için liste tazelenir.
    await t.tap(find.byTooltip('Kapat'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(svc.loads, 2);
  });

  testWidgets('açılış yalnız bir sayfa + özet indirir; sayaçlar özetten, '
      'kaydırdıkça sonraki sayfalar gelir', (t) async {
    final svc = _FakeService(_many(150));
    await open(t, svc);

    // Tek istek: ilk sayfa ve kütüphane özeti.
    expect(svc.pageCalls, hasLength(1));
    final first = svc.pageCalls.single;
    expect(first.offset, 0);
    expect(first.limit, ProductImagePresetService.adminPageSize);
    expect(first.summary, isTrue);
    expect(first.query, const ProductImageAdminQuery());

    // Yalnız 60 görsel yüklü ama sayaçlar kütüphanenin tamamını gösterir.
    expect(
      find.text('Tüm klasörler · 150', skipOffstage: false),
      findsOneWidget,
    );
    expect(_stat('Tümü', 150), findsOneWidget);
    expect(_stat('Yayında', 100), findsOneWidget);
    expect(_stat('Pasif', 50), findsOneWidget);
    expect(find.text('Görsel 61', skipOffstage: false), findsNothing);

    // Sona yaklaşınca sıradaki sayfa istenir; liste bitince istek durur.
    for (var i = 0; i < 8; i++) {
      await t.drag(find.byType(CustomScrollView), const Offset(0, -1500));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(svc.pageCalls.map((c) => c.offset), [0, 60, 120]);
    expect(svc.pageCalls.skip(1).every((c) => !c.summary), isTrue);
    expect(find.text('Görsel 150'), findsOneWidget);
  });

  testWidgets('arama yazmanın durmasını bekler: tek istek, sunucuda süzülür', (
    t,
  ) async {
    final svc = _FakeService(_sample());
    await open(t, svc);

    for (final q in ['k', 'kö', 'köf']) {
      await t.enterText(find.byType(TextField).first, q);
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(svc.pageCalls, hasLength(1));
    await t.pump(const Duration(milliseconds: 250));
    expect(svc.pageCalls, hasLength(2));
    expect(svc.pageCalls.last.query.search, 'köf');
    expect(svc.pageCalls.last.offset, 0);
    expect(find.text('Çiğ köfte'), findsOneWidget);
    expect(find.text('Simit'), findsNothing);

    // Sıralama değişince ilk sayfa yeni sıralamayla (arama korunur).
    await t.tap(find.byTooltip('Sırala'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('En yeni önce'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(svc.pageCalls.last.query.sort, ProductImageAdminSort.newest);
    expect(svc.pageCalls.last.query.search, 'köf');
  });

  testWidgets('süzgece uyanların tümünü seç: yüklenmemişler de seçilir, '
      'toplu işlem hepsine gider, sayaçlar sunucudan tazelenir', (t) async {
    final svc = _FakeService(_many(150));
    await open(t, svc);

    await t.tap(find.text('Yayında'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(svc.pageCalls.last.query.status, ProductImageAdminStatus.active);

    await t.longPress(find.text('Görsel 1'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('1 seçildi'), findsOneWidget);

    await t.tap(find.byTooltip('Süzgece uyanların tümünü seç'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // Yayındaki 100 görselin hepsi (yalnız 60'ı yüklü) seçildi.
    expect(svc.idCalls.single.status, ProductImageAdminStatus.active);
    expect(find.text('100 seçildi'), findsOneWidget);
    expect(find.text('Süzgece uyan 100 görselin tümü seçildi'), findsOneWidget);

    await t.tap(find.byTooltip('Pasife al'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(svc.activated.single.$1, hasLength(100));
    expect(svc.activated.single.$2, isFalse);
    // "Yayında" süzgecinden hepsi çıktı; sayaçlar sunucudan.
    expect(find.text('Görsel 1'), findsNothing);
    expect(_stat('Yayında', 0), findsOneWidget);
    expect(_stat('Pasif', 150), findsOneWidget);
    expect(svc.pageCalls.last.summary, isTrue);
  });

  testWidgets('silme iyimser: görsel hemen kalkar, hata olursa geri gelir; '
      'başarıda sayaçlar sunucudan', (t) async {
    final svc = _FakeService(_sample());
    await open(t, svc);

    Future<void> deleteFirst() async {
      await t.tap(find.byTooltip('İşlemler').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Sil').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.widgetWithText(FilledButton, 'Sil'));
      await t.pump();
    }

    svc.writeGate = Completer<void>();
    await deleteFirst();
    // Sunucu yanıtı beklenirken kart kalktı.
    expect(find.text('Kırmızı domates'), findsNothing);
    svc.writeGate!.completeError(Exception('Sunucu reddetti'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Kırmızı domates'), findsOneWidget);
    expect(find.text('Sunucu reddetti'), findsOneWidget);
    expect(svc.items, hasLength(3));

    svc.writeGate = null;
    await deleteFirst();
    await t.pump(const Duration(milliseconds: 300));
    expect(svc.deleted.last, ['id0']);
    expect(find.text('Kırmızı domates'), findsNothing);
    expect(find.text('Görsel silindi'), findsOneWidget);
    expect(find.text('Tüm klasörler · 2', skipOffstage: false), findsOneWidget);
    expect(find.text('Manav · 1', skipOffstage: false), findsOneWidget);
  });
}
