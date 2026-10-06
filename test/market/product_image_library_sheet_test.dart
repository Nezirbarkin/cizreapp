import 'dart:io';
import 'dart:math' as math;

import 'package:cizreapp/core/models/product_image_preset_model.dart';
import 'package:cizreapp/features/market/services/product_image_preset_service.dart';
import 'package:cizreapp/features/market/widgets/product_image_library_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Supabase'e dokunmayan sahte servis: her aramada [total] görsellik bir
/// katalogdan sayfa döner, çağrıları kaydeder.
class _FakeService extends ProductImagePresetService {
  _FakeService({this.total = 3});

  int total;

  /// true: "tüm kelimeler" modunda sonuç yok (yalnız matchAny döner).
  bool emptyAnd = false;
  bool fail = false;
  final List<Map<String, Object?>> calls = [];

  @override
  Future<List<ProductImageFolder>> getFolders() async => const [
    ProductImageFolder(id: 'f1', name: 'Manav', imageCount: 3),
    // Satıcıya görünür görseli olmayan klasör çip olarak çıkmamalı.
    ProductImageFolder(id: 'f2', name: 'Kozmetik', imageCount: 0),
  ];

  @override
  Future<List<ProductImagePreset>> searchPresets(
    String query, {
    String? folderId,
    int limit = ProductImagePresetService.pageSize,
    int offset = 0,
    bool matchAny = false,
  }) async {
    calls.add({
      'q': query,
      'folder': folderId,
      'offset': offset,
      'any': matchAny,
    });
    if (fail) throw Exception('ağ yok');
    if (emptyAnd && !matchAny) return [];
    final n = math.max(0, math.min(limit, total - offset));
    return [for (var i = 0; i < n; i++) _preset(offset + i)];
  }
}

ProductImagePreset _preset(int i) => ProductImagePreset(
  id: 'p$i',
  name: 'Görsel $i',
  imageUrl: 'https://example.invalid/$i.webp',
  createdAt: DateTime(2026, 10, 1),
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

  ProductImagePreset? picked;
  var closed = false;

  Future<void> open(
    WidgetTester t,
    _FakeService svc, {
    String query = '',
    Set<String> added = const {},
  }) async {
    picked = null;
    closed = false;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(420, 860);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                picked = await showProductImageLibrarySheet(
                  ctx,
                  initialQuery: query,
                  addedUrls: added,
                  service: svc,
                );
                closed = true;
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('aç'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
  }

  testWidgets('ürün adıyla açılır; boş klasör çipi gizli; çip ve yazı süzer', (
    t,
  ) async {
    final svc = _FakeService();
    await open(t, svc, query: '  Domates ');

    expect(svc.calls.single, {
      'q': 'Domates',
      'folder': null,
      'offset': 0,
      'any': false,
    });
    expect(find.text('Görsel 2'), findsOneWidget);
    expect(find.text('Tümü'), findsOneWidget);
    expect(find.text('Manav · 3'), findsOneWidget);
    expect(find.textContaining('Kozmetik'), findsNothing);

    await t.tap(find.text('Manav · 3'));
    await t.pump();
    expect(svc.calls.last['folder'], 'f1');
    expect(svc.calls.last['q'], 'Domates');

    // Yazarken beklenir (debounce), sonra aynı klasörde aranır.
    await t.enterText(find.byType(TextField), 'elma');
    await t.pump(const Duration(milliseconds: 100));
    expect(svc.calls.last['q'], 'Domates');
    await t.pump(const Duration(milliseconds: 400));
    expect(svc.calls.last, {
      'q': 'elma',
      'folder': 'f1',
      'offset': 0,
      'any': false,
    });
  });

  testWidgets('tam eşleşme yoksa kelimelerinden biriyle eşleşenler, notla', (
    t,
  ) async {
    final svc = _FakeService()..emptyAnd = true;
    await open(t, svc, query: 'Salkım Domates 1 kg');

    expect(svc.calls.map((c) => c['any']), [false, true]);
    expect(find.textContaining('tam eşleşme yok'), findsOneWidget);
    expect(find.text('Görsel 0'), findsOneWidget);

    // Tek kelimede yedek arama anlamsız: doğrudan "bulunamadı".
    await t.enterText(find.byType(TextField), 'domates');
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    expect(svc.calls.last, {
      'q': 'domates',
      'folder': null,
      'offset': 0,
      'any': false,
    });
    expect(svc.calls.length, 3);
    expect(find.text('"domates" için görsel bulunamadı'), findsOneWidget);
    expect(find.textContaining('tam eşleşme yok'), findsNothing);
  });

  testWidgets('eklenmiş görsel işaretli ve seçilemez; diğeri seçilip döner', (
    t,
  ) async {
    await open(t, _FakeService(), added: {'https://example.invalid/0.webp'});

    expect(find.text('Eklendi'), findsOneWidget);
    await t.tap(find.text('Görsel 0'));
    await t.pump(const Duration(milliseconds: 600));
    expect(closed, isFalse);

    await t.tap(find.text('Görsel 1'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(closed, isTrue);
    expect(picked?.id, 'p1');
  });

  testWidgets('kaydırdıkça sonraki sayfalar yüklenir, sonda durur', (t) async {
    final svc = _FakeService(total: 130);
    await open(t, svc);
    expect(svc.calls.map((c) => c['offset']), [0]);

    for (var i = 0; i < 6; i++) {
      await t.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(svc.calls.map((c) => c['offset']), [0, 60, 120]);
    expect(find.text('Görsel 129'), findsOneWidget);
  });

  testWidgets('hata gösterilir, tekrar dene ile yüklenir', (t) async {
    final svc = _FakeService()..fail = true;
    await open(t, svc);
    expect(find.text('Görseller yüklenemedi'), findsOneWidget);

    svc.fail = false;
    await t.tap(find.text('Tekrar dene'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Görsel 0'), findsOneWidget);
  });
}
