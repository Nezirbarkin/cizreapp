import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/features/market/widgets/product_sort_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product(
  String id, {
  required double price,
  double? discountPrice,
  required DateTime createdAt,
  String type = 'normal',
  double? pricePer1000,
}) {
  return Product(
    id: id,
    shopId: 's1',
    name: id,
    price: price,
    discountPrice: discountPrice,
    stockQuantity: 5,
    isAvailable: true,
    createdAt: createdAt,
    updatedAt: createdAt,
    productType: type,
    pricePer1000: pricePer1000,
  );
}

List<String> _ids(List<Product> list) => [for (final p in list) p.id];

void main() {
  final day = DateTime(2026, 10, 1);
  // Sunucu sırası: sabitlenmiş 'pinned' en üstte, sonra yeniden eskiye.
  final products = [
    _product('pinned', price: 50, createdAt: day),
    _product('c', price: 30, createdAt: day.add(const Duration(days: 3))),
    _product('b', price: 80, discountPrice: 20, createdAt: day.add(
      const Duration(days: 2),
    )),
    _product('a', price: 30, createdAt: day.add(const Duration(days: 1))),
  ];

  group('sortProducts', () {
    test('Önerilen sunucu sırasını korur ve yeni liste döndürür', () {
      final sorted = sortProducts(products, ProductSort.recommended);
      expect(_ids(sorted), ['pinned', 'c', 'b', 'a']);
      expect(identical(sorted, products), isFalse);
    });

    test('Yeni: created_at azalan, sabitleme yok sayılır', () {
      expect(
        _ids(sortProducts(products, ProductSort.newest)),
        ['c', 'b', 'a', 'pinned'],
      );
    });

    test('Fiyat artan indirimli fiyata göre sıralar, eşitlikte sırayı korur',
        () {
      // b: 80 → indirimli 20; c ve a ikisi de 30 → gelen sıra (c, a).
      expect(
        _ids(sortProducts(products, ProductSort.priceAsc)),
        ['b', 'c', 'a', 'pinned'],
      );
    });

    test('Fiyat azalan', () {
      expect(
        _ids(sortProducts(products, ProductSort.priceDesc)),
        ['pinned', 'c', 'a', 'b'],
      );
    });

    test('priceOf verilirse (flaş fiyatı) o kullanılır', () {
      final sorted = sortProducts(
        products,
        ProductSort.priceAsc,
        priceOf: (p) => p.id == 'pinned' ? 5 : p.listingPrice,
      );
      expect(_ids(sorted).first, 'pinned');
    });

    test('SMM dijitalde kartta yazan 1000 adet fiyatı kullanılır', () {
      final digital = _product(
        'smm',
        price: 1,
        pricePer1000: 100,
        type: 'digital',
        createdAt: day,
      );
      expect(
        _ids(sortProducts([digital, ...products], ProductSort.priceDesc)),
        ['smm', 'pinned', 'c', 'a', 'b'],
      );
    });

    test('girdi listesini değiştirmez', () {
      final before = _ids(products);
      sortProducts(products, ProductSort.priceDesc);
      expect(_ids(products), before);
    });
  });

  group('ProductSortBar', () {
    Future<List<ProductSort>> pumpBar(
      WidgetTester tester,
      ProductSort value,
    ) async {
      final changes = <ProductSort>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ProductSortBar(value: value, onChanged: changes.add),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('yalnız seçili düğme seçili olarak işaretlenir',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBar(tester, ProductSort.priceAsc);
      expect(
        tester.getSemantics(find.bySemanticsLabel(ProductSort.priceAsc.label)),
        matchesSemantics(
          label: ProductSort.priceAsc.label,
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(ProductSort.newest.label)),
        matchesSemantics(
          label: ProductSort.newest.label,
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('üç ikon düğmesi, metin yok', (tester) async {
      await pumpBar(tester, ProductSort.recommended);
      expect(find.byType(Text), findsNWidgets(2)); // yalnız iki "₺"
      expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });

    testWidgets('dokunuş seçer, seçiliye dokunuş önerilene döner',
        (tester) async {
      final changes = await pumpBar(tester, ProductSort.newest);
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      expect(changes, [ProductSort.priceDesc, ProductSort.recommended]);
    });

    testWidgets('dar ekranda başlıkla aynı satıra taşmadan sığar',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ürünler (120/120)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ProductSortBar(
                    value: ProductSort.priceDesc,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(ProductSortBar)).height,
        ProductSortBar.buttonSize,
      );
    });
  });
}
