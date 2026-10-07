import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/core/models/category_model.dart';
import 'package:cizreapp/core/models/daily_deal_model.dart';
import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/core/models/shop_model.dart';
import 'package:cizreapp/features/market/services/home_snapshot_cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ana sayfa soğuk açılışta cihazdaki son kopyayı anında gösterir
/// (stale-while-revalidate). Kopya, ekranda doğru görünmesi için gereken
/// alanları (sponsor süreleri dahil) eksiksiz geri vermeli; bayat, bozuk ya da
/// başka kullanıcıya ait kopya gösterilmemeli.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('home_snapshot_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final now = DateTime.utc(2026, 10, 7, 12);
  final sponsorUntil = DateTime.utc(2026, 10, 9, 18);

  Shop shop() => Shop.fromJson({
    'id': 's1',
    'owner_id': 'o1',
    'category_id': 'c1',
    'name': 'Sanal Marketim',
    'slug': 'sanal-marketim',
    'delivery_fee': 15,
    'min_order_amount': 150,
    'is_active': true,
    'is_approved': true,
    'is_accepting_orders': true,
    'rating': 4.5,
    'review_count': 7,
    'sponsored_list_until': sponsorUntil.toIso8601String(),
    'sponsored_category_until': sponsorUntil.toIso8601String(),
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  Product product(String id) => Product.fromJson({
    'id': id,
    'shop_id': 's1',
    'name': 'Ürün $id',
    'price': 23,
    'old_price': 25,
    'discount_price': 23,
    'stock_quantity': 5,
    'is_available': true,
    'image_url': 'https://example.com/$id.jpg',
    'sponsored_discount_until': sponsorUntil.toIso8601String(),
    'sponsored_category_until': sponsorUntil.toIso8601String(),
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  HomeSnapshot snapshot({DateTime? savedAt}) => HomeSnapshot(
    categories: [
      Category.fromJson({
        'id': 'c1',
        'name': 'Market & Manav',
        'slug': 'market',
        'created_at': now.toIso8601String(),
      }),
    ],
    shops: [shop()],
    discountedProducts: [product('p1'), product('p2')],
    categoryShopCounts: const {'c1': 2},
    deals: [
      DailyDeal.fromJson({
        'id': 'd1',
        'title': 'Fırsat',
        'image_url': 'https://example.com/d.jpg',
        'link_type': 'shop',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }),
    ],
    settings: const {'home_shop_limit': 6, 'app_slogan': 'Merhaba'},
    savedAt: savedAt ?? DateTime.now(),
  );

  test('kaydedilen kopya eksiksiz geri okunur (sponsor süreleri dahil)', () async {
    await HomeSnapshotCache.write('u1', snapshot());
    final read = await HomeSnapshotCache.read('u1');

    expect(read, isNotNull);
    expect(read!.categories.single.name, 'Market & Manav');
    expect(read.shops.single.name, 'Sanal Marketim');
    expect(read.shops.single.reviewCount, 7);
    // Shop.toJson sponsor sütunlarını yazmaz; önbellek ayrıca eklemeli,
    // yoksa saklı kopyada sponsorlar en üstte görünmez.
    expect(read.shops.single.sponsoredListUntil, sponsorUntil);
    expect(read.shops.single.sponsoredCategoryUntil, sponsorUntil);
    expect(read.discountedProducts.map((p) => p.id), ['p1', 'p2']);
    expect(read.discountedProducts.first.sponsoredDiscountUntil, sponsorUntil);
    expect(read.discountedProducts.first.oldPrice, 25);
    expect(read.categoryShopCounts, {'c1': 2});
    expect(read.deals.single.title, 'Fırsat');
    expect(read.settings['home_shop_limit'], 6);
  });

  test('başka kullanıcının kopyası okunmaz', () async {
    await HomeSnapshotCache.write('u1', snapshot());
    expect(await HomeSnapshotCache.read('u2'), isNull);
    expect(await HomeSnapshotCache.read(null), isNull);
  });

  test('bayat kopya gösterilmez', () async {
    await HomeSnapshotCache.write(
      'u1',
      snapshot(
        savedAt: DateTime.now().subtract(
          HomeSnapshotCache.maxAge + const Duration(hours: 1),
        ),
      ),
    );
    expect(await HomeSnapshotCache.read('u1'), isNull);
  });

  test('bozuk ya da eski sürüm dosya sessizce yok sayılır', () async {
    final file = File('${dir.path}/home_snapshot_u1.json');
    await file.writeAsString('{yarım');
    expect(await HomeSnapshotCache.read('u1'), isNull);

    await file.writeAsString(jsonEncode({'v': 0, 'saved_at': '2026-10-07'}));
    expect(await HomeSnapshotCache.read('u1'), isNull);
  });
}
