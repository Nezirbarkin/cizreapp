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

/// Supabase'e dokunmayan sahte servis: liste sabit, eklemeler kaydedilir.
class _FakeService extends ProductImagePresetService {
  _FakeService(this.items, {this.failName});

  final List<ProductImagePreset> items;
  final String? failName;
  final List<Map<String, dynamic>> added = [];

  @override
  Future<List<ProductImagePreset>> getAllPresetsForAdmin({
    int limit = 1000,
  }) async => items;

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
  }) async {
    if (name == failName) throw Exception('Sunucu reddetti');
    added.add({
      'name': name,
      'description': description,
      'order': displayOrder,
      'active': isActive,
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

List<ProductImagePreset> _sample() => [
  for (final (i, n) in const [
    ('Kırmızı domates', 'sebze, salata'),
    ('Çiğ köfte', 'yemek'),
    ('Simit', null),
  ].indexed)
    ProductImagePreset(
      id: 'id$i',
      name: n.$1,
      description: n.$2,
      imageUrl: 'https://example.invalid/$i.jpg',
      isActive: i != 2,
      displayOrder: i + 1,
      createdAt: DateTime(2026, 9, 1 + i),
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
}
