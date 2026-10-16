import 'package:cizreapp/core/models/product_image_preset_model.dart';
import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/core/models/smm_provider_model.dart';
import 'package:cizreapp/core/services/smm_service.dart';
import 'package:cizreapp/features/seller/screens/bulk_digital_import_screen.dart';
import 'package:cizreapp/features/seller/screens/bulk_product_upload_screen.dart';
import 'package:cizreapp/features/seller/services/bulk_product_service.dart';
import 'package:cizreapp/features/seller/utils/spreadsheet_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ağsız sahte servis: gönderilen satırları kaydeder, hepsini "eklendi" sayar.
class _FakeBulkService extends BulkProductService {
  final List<List<Map<String, dynamic>>> calls = [];

  @override
  Future<ProductImagePreset?> findLibraryImage(String name) async => null;

  @override
  Future<BulkUpsertResult> upsert(String shopId, List<Map<String, dynamic>> items) async {
    calls.add(items);
    return BulkUpsertResult(
      created: items.where((i) => i['id'] == null).length,
      updated: items.where((i) => i['id'] != null).length,
      failed: 0,
      addedCategories: const [],
      rows: [
        for (var i = 0; i < items.length; i++)
          BulkRowResult(index: i, ok: true, action: items[i]['id'] == null ? 'created' : 'updated', productId: 'n$i'),
      ],
    );
  }
}

Product _product(String id, String name, {String type = 'normal', String? providerId, String? serviceId}) {
  final now = DateTime(2026, 10, 15);
  return Product(
    id: id,
    shopId: 's1',
    name: name,
    price: 10,
    stockQuantity: 3,
    isAvailable: true,
    createdAt: now,
    updatedAt: now,
    productType: type,
    smmProviderId: providerId,
    smmServiceId: serviceId,
  );
}

BulkShopContext _ctx(List<Product> products) => BulkShopContext(
  shopId: 's1',
  shopName: 'Test Dükkan',
  categories: const ['Market'],
  products: products,
  digitalCommissionRate: 10,
  ownStoragePrefix: 'https://proje.supabase.co/storage/v1/object/public/',
);

/// Ekranı bir düğmeyle iter; kapanınca dönen değeri saklar.
class _Launcher extends StatefulWidget {
  const _Launcher(this.screen);

  final Widget screen;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  Object? result = 'açık';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('sonuç: $result'),
          TextButton(
            onPressed: () async {
              final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => widget.screen));
              setState(() => result = r);
            },
            child: const Text('aç'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(440, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: _Launcher(screen)));
  await tester.tap(find.text('aç'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  testWidgets('Excel önizleme: hatalılar önce, mevcut ad atlanır, yalnız geçerli yeni ürün gider', (tester) async {
    final fake = _FakeBulkService();
    await _open(
      tester,
      BulkProductUploadScreen(
        service: fake,
        debugContext: _ctx([_product('p1', 'Çay 1 kg')]),
        debugTable: SpreadsheetIO.parseText('Ad;Fiyat;Stok;Kategori\nElma;10;3;Manav\nArmut;abc;1;\nçay 1 KG;5;1;\n'),
      ),
    );

    // Hatalı satır olduğu için liste "Hatalı" süzgeciyle açılır.
    expect(find.text('Hatalı (1)'), findsOneWidget);
    expect(find.text('Armut'), findsOneWidget);
    expect(find.text('Fiyat sayı değil: "abc"'), findsOneWidget);
    expect(find.text('Elma'), findsNothing);
    expect(find.text('1 ürün mağazanda aynı adla zaten var'), findsOneWidget);

    await tester.tap(find.text('Tümü (3)'));
    await tester.pump();
    expect(find.text('Elma'), findsOneWidget);
    expect(find.text('Var · atlanacak'), findsOneWidget);
    expect(find.text('"Manav" kategorisi mağazana eklenecek'), findsOneWidget);
    // Elma ve (hatalı) Armut: ikisinin de görseli yok.
    expect(find.text('Görsel yok — satışa kapalı eklenecek'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('bulk-upload')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 yeni ürün eklenecek.\n1 hatalı satır atlanacak.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Yükle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fake.calls, hasLength(1));
    final item = fake.calls.single.single;
    expect(item['name'], 'Elma');
    expect(item['price'], 10);
    expect(item['category'], 'Manav');
    expect(item['is_available'], isFalse, reason: 'görselsiz ürün satışa kapalı eklenir');

    expect(find.text('Yükleme tamamlandı'), findsOneWidget);
    await tester.tap(find.text('Bitti'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('sonuç: true'), findsOneWidget);
  });

  testWidgets('Excel önizleme: "Güncelle" seçilince aynı adlı ürünün fiyatı güncellenir', (tester) async {
    final fake = _FakeBulkService();
    await _open(
      tester,
      BulkProductUploadScreen(
        service: fake,
        debugContext: _ctx([_product('p1', 'Çay 1 kg')]),
        debugTable: SpreadsheetIO.parseText('Ad;Fiyat;Stok\nçay 1 KG;12,5;3\n'),
      ),
    );
    expect(find.text('Var · atlanacak'), findsOneWidget);
    await tester.tap(find.text('Güncelle'));
    await tester.pump();
    expect(find.text('Güncellenecek'), findsOneWidget);
    expect(find.text('Satır 2 · 12,50 ₺ · Stok 3 · Değişecek: fiyat'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk-upload')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Yükle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.calls.single.single, {'id': 'p1', 'price': 12.5});

    // "Bitti" yerine sistem geri tuşu: yine true dönmeli (Ürünlerim yenilensin).
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('sonuç: true'), findsOneWidget);
  });

  testWidgets('Toplu dijital: fiyat kâr oranıyla, ekli/fiyatsız servis seçilemez', (tester) async {
    final fake = _FakeBulkService();
    final now = DateTime(2026, 10, 15);
    await _open(
      tester,
      BulkDigitalImportScreen(
        service: fake,
        smmService: SmmService(),
        debugContext: _ctx([_product('d1', 'Eski', type: 'digital', providerId: 'prov', serviceId: '3')]),
        debugProviders: [
          SmmProvider(
            id: 'prov',
            ownerType: 'seller',
            ownerId: 's1',
            name: 'Sağlayıcım',
            apiUrl: 'https://x',
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
          // Başka mağazanın sağlayıcısı listelenmez.
          SmmProvider(
            id: 'other',
            ownerType: 'seller',
            ownerId: 's2',
            name: 'Yabancı',
            apiUrl: 'https://x',
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        debugServices: [
          SmmProviderServiceInfo(service: '1', name: 'Instagram Takipçi', category: 'Instagram', rate: 10, min: 100, max: 1000),
          SmmProviderServiceInfo(service: '2', name: 'Fiyatsız', category: 'Instagram', min: 1, max: 2),
          SmmProviderServiceInfo(service: '3', name: 'Ekli olan', category: 'TikTok', rate: 5, min: 1, max: 2),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Yabancı'), findsNothing);
    expect(find.text('Fiyat yok'), findsOneWidget);
    expect(find.text('Zaten ekli'), findsOneWidget);
    expect(find.textContaining('Satış 13,00 ₺'), findsOneWidget);

    await tester.tap(find.text('Görünenleri seç'));
    await tester.pump();
    expect(find.text('1 servisi ürün olarak ekle'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk-digital-import')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Ekle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final item = fake.calls.single.single;
    expect(item['product_type'], 'digital');
    expect(item['smm_provider_id'], 'prov');
    expect(item['smm_service_id'], '1');
    expect(item['price_per_1000'], 13.0);
    expect(item['provider_rate'], 10);
    expect(item['min_quantity'], 100);
    expect(item['max_quantity'], 1000);
    expect(item['category'], 'Instagram');
    expect(item['is_available'], isFalse, reason: 'kapak görseli yok');

    expect(find.text('1 ürün eklendi'), findsOneWidget);
    await tester.tap(find.text('Tamam'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('sonuç: true'), findsOneWidget);
  });

  test('satış fiyatı kuruşa yukarı yuvarlanır', () {
    expect(BulkDigitalImportScreen.salePrice(10, 30), 13.0);
    expect(BulkDigitalImportScreen.salePrice(0.333, 0), 0.34);
    expect(BulkDigitalImportScreen.salePrice(1.1, 10), 1.21);
  });
}
