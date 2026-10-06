import 'dart:io';
import 'dart:ui' as ui;

import 'package:cizreapp/core/models/product_image_preset_model.dart';
import 'package:cizreapp/features/admin/widgets/product_image_library_content.dart';
import 'package:cizreapp/features/market/services/product_image_preset_service.dart';
import 'package:cizreapp/features/market/services/product_image_scrape_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Supabase'e dokunmayan sahte servis: liste sabit, yazımlar kaydedilir.
class _FakeService extends ProductImagePresetService {
  _FakeService(this.items, {this.failName, List<ProductImageFolder>? folders})
    : folders = folders ?? _folders();

  final List<ProductImagePreset> items;
  final List<ProductImageFolder> folders;
  final String? failName;
  final List<Map<String, dynamic>> added = [];
  final List<(List<String>, String?)> moved = [];
  final List<String> addedFolders = [];
  final List<Map<String, dynamic>> folderUpdates = [];
  final List<List<String>> reordered = [];
  int loads = 0;

  @override
  Future<List<ProductImagePreset>> getAllPresetsForAdmin() async {
    loads++;
    return items;
  }

  @override
  Future<List<ProductImageFolder>> getFolders() async => folders;

  @override
  Future<void> moveToFolder(List<String> ids, String? folderId) async {
    moved.add((ids, folderId));
  }

  @override
  Future<ProductImageFolder> addFolder({
    required String name,
    int displayOrder = 0,
  }) async {
    addedFolders.add('$name#$displayOrder');
    return ProductImageFolder(
      id: 'nf${addedFolders.length}',
      name: name,
      displayOrder: displayOrder,
    );
  }

  @override
  Future<void> updateFolder({
    required String id,
    String? name,
    int? displayOrder,
    bool? isActive,
  }) async {
    folderUpdates.add({'id': id, 'name': name, 'active': isActive});
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
    return ProductImagePreset(
      id: 'new${added.length}',
      name: name,
      imageUrl: imageUrl,
      displayOrder: displayOrder,
      isActive: isActive,
      createdAt: DateTime.now(),
    );
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

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

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
    await t.pump();
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
}
