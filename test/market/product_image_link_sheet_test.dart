import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cizreapp/features/market/services/product_image_scrape_service.dart';
import 'package:cizreapp/features/market/widgets/product_image_link_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScrape extends ProductImageScrapeService {
  _FakeScrape(this.onFetch);

  final Future<ScrapedProductImage> Function(String link) onFetch;
  final List<String> links = [];

  @override
  Future<ScrapedProductImage> fetchFromLink(String link) {
    links.add(link);
    return onFetch(link);
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Sayfayı bir düğmeyle açar; kapanınca dönen değeri [result]'a yazar.
  Future<void> openSheet(
    WidgetTester t,
    _FakeScrape service,
    List<ScrapedProductImage?> result,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 1400);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result.add(
                  await showProductImageLinkSheet(context, service: service),
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('aç'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
  }

  testWidgets('link getirilir, önizlenir ve onaylanınca görsel döner', (
    t,
  ) async {
    final png = (await t.runAsync(_png))!;
    final service = _FakeScrape(
      (_) async => ScrapedProductImage(
        bytes: png,
        mimeType: 'image/png',
        extension: 'png',
        imageUrl: 'https://cdn.example.com/a.png',
        title: 'Kırmızı domates',
      ),
    );
    final result = <ScrapedProductImage?>[];
    await openSheet(t, service, result);

    await t.enterText(find.byType(TextField), 'https://shop.example.com/u');
    await t.tap(find.text('Görseli Getir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(service.links, ['https://shop.example.com/u']);
    expect(find.text('Kırmızı domates'), findsOneWidget);
    expect(find.text('Bu görseli kullan'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await t.tap(find.text('Bu görseli kullan'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    expect(result.single?.imageUrl, 'https://cdn.example.com/a.png');
    expect(result.single?.fileName, 'linkten.png');
  });

  testWidgets('hata satır içinde gösterilir ve düzeltince tekrar denenebilir', (
    t,
  ) async {
    var attempts = 0;
    final png = (await t.runAsync(_png))!;
    final service = _FakeScrape((_) async {
      attempts++;
      if (attempts == 1) {
        throw const ProductImageScrapeException(
          'Site otomatik erişimi engelledi (403); görseli galeriden yükleyin',
        );
      }
      return ScrapedProductImage(
        bytes: png,
        mimeType: 'image/png',
        extension: 'png',
        imageUrl: 'https://cdn.example.com/b.png',
      );
    });
    final result = <ScrapedProductImage?>[];
    await openSheet(t, service, result);

    await t.enterText(find.byType(TextField), 'https://engelli.example.com');
    await t.tap(find.text('Görseli Getir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('otomatik erişimi engelledi'), findsOneWidget);
    expect(find.text('Bu görseli kullan'), findsNothing);

    // Yazmaya başlayınca hata temizlenir; ikinci deneme başarılı olur.
    await t.enterText(find.byType(TextField), 'https://ok.example.com');
    await t.pump();
    expect(find.textContaining('otomatik erişimi engelledi'), findsNothing);

    await t.tap(find.text('Görseli Getir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Bu görseli kullan'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('kapatılırsa null döner', (t) async {
    final service = _FakeScrape((_) async => throw StateError('çağrılmamalı'));
    final result = <ScrapedProductImage?>[];
    await openSheet(t, service, result);

    await t.tap(find.byTooltip('Kapat'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));

    expect(result, [null]);
    expect(service.links, isEmpty);
  });
}
