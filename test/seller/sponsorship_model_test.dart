import 'dart:math';

import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/core/models/shop_model.dart';
import 'package:cizreapp/core/models/sponsorship_model.dart';
import 'package:cizreapp/core/utils/sponsor_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 3.2 — öne çıkarma modelleri, satırdaki "…_until" sütunlarının
/// okunması ve listelerde sponsorların sırası.

final _now = DateTime.utc(2026, 9, 28, 12);

Shop _shop(String id, {bool pinned = false, DateTime? listUntil, DateTime? categoryUntil, int ageDays = 0}) =>
    Shop.fromJson({
      'id': id,
      'owner_id': 'o-$id',
      'category_id': 'c1',
      'name': 'Mağaza $id',
      'slug': id,
      'is_active': true,
      'is_approved': true,
      'is_pinned': pinned,
      'sponsored_list_until': listUntil?.toIso8601String(),
      'sponsored_category_until': categoryUntil?.toIso8601String(),
      'created_at': _now.subtract(Duration(days: ageDays)).toIso8601String(),
      'updated_at': _now.toIso8601String(),
    });

Product _product(String id, {bool pinned = false, DateTime? categoryUntil, DateTime? discountUntil, double price = 100}) =>
    Product.fromJson({
      'id': id,
      'shop_id': 's1',
      'name': 'Ürün $id',
      'price': price,
      'old_price': 120,
      'stock_quantity': 5,
      'is_available': true,
      'is_pinned': pinned,
      'sponsored_category_until': categoryUntil?.toIso8601String(),
      'sponsored_discount_until': discountUntil?.toIso8601String(),
      'created_at': _now.toIso8601String(),
      'updated_at': _now.toIso8601String(),
    });

void main() {
  group('SponsorPlacement', () {
    test('veritabanı değerleri göçle aynı; tanınmayan null', () {
      expect(SponsorPlacement.values.map((p) => p.dbValue),
          ['shop_list', 'shop_category', 'product_category', 'product_discount']);
      expect(SponsorPlacement.fromDb('product_discount'), SponsorPlacement.productDiscount);
      expect(SponsorPlacement.fromDb('homepage_banner'), isNull);
      expect(SponsorPlacement.values.where((p) => p.isProduct),
          [SponsorPlacement.productCategory, SponsorPlacement.productDiscount]);
    });
  });

  group('satırdaki bitiş sütunları', () {
    test('mağaza: yalnız ilgili vitrinde ve süresi geçmemişse sponsorlu', () {
      final shop = _shop('a', listUntil: _now.add(const Duration(hours: 2)), categoryUntil: _now.subtract(const Duration(minutes: 1)));
      expect(shop.isSponsoredIn(SponsorPlacement.shopList, now: _now), isTrue);
      expect(shop.isSponsoredIn(SponsorPlacement.shopCategory, now: _now), isFalse, reason: 'süresi geçti');
      expect(shop.isSponsoredIn(SponsorPlacement.productDiscount, now: _now), isFalse);
      expect(_shop('b').isSponsoredIn(SponsorPlacement.shopList, now: _now), isFalse);
    });

    test('ürün: kategori ve indirim vitrinleri ayrı', () {
      final product = _product('p', discountUntil: _now.add(const Duration(days: 1)));
      expect(product.isSponsoredIn(SponsorPlacement.productDiscount, now: _now), isTrue);
      expect(product.isSponsoredIn(SponsorPlacement.productCategory, now: _now), isFalse);
      expect(product.copyWith(name: 'x').sponsoredDiscountUntil, product.sponsoredDiscountUntil);
    });

    test('sütunlar yoksa (eski önbellek/satır) sponsorsuz', () {
      final shop = Shop.fromJson({
        'id': 'z', 'owner_id': 'o', 'category_id': 'c', 'name': 'Z', 'slug': 'z',
        'created_at': _now.toIso8601String(), 'updated_at': _now.toIso8601String(),
      });
      expect(shop.sponsoredListUntil, isNull);
      expect(shop.isSponsoredIn(SponsorPlacement.shopList, now: _now), isFalse);
    });
  });

  group('SponsorOrdering', () {
    test('admin sabitlemesi → ücretli (karışık) → kalanlar (en yeni önce)', () {
      final future = _now.add(const Duration(days: 1));
      final shops = [
        _shop('old', ageDays: 9),
        _shop('paid1', listUntil: future, ageDays: 5),
        _shop('pinned', pinned: true, ageDays: 3),
        _shop('new', ageDays: 1),
        _shop('paid2', listUntil: future, ageDays: 2),
        _shop('expired', listUntil: _now.subtract(const Duration(hours: 1)), ageDays: 4),
      ];
      final ordered = SponsorOrdering.shops(
        shops,
        SponsorPlacement.shopList,
        now: _now,
        random: Random(1),
        restOrder: (a, b) => b.createdAt.compareTo(a.createdAt),
      );
      expect(ordered.first.id, 'pinned');
      expect(ordered.sublist(1, 3).map((s) => s.id).toSet(), {'paid1', 'paid2'});
      expect(ordered.sublist(3).map((s) => s.id), ['new', 'expired', 'old']);
    });

    test('vitrine özgü: kategori sponsoru dükkanlar listesinde öne geçmez', () {
      final shops = [_shop('a'), _shop('b', categoryUntil: _now.add(const Duration(days: 1)))];
      expect(SponsorOrdering.shops(shops, SponsorPlacement.shopList, now: _now).map((s) => s.id), ['a', 'b']);
      expect(SponsorOrdering.shops(shops, SponsorPlacement.shopCategory, now: _now).map((s) => s.id), ['b', 'a']);
    });

    test('ücretli sponsorlar yüklemeler arasında adil döner (karıştırılır)', () {
      final future = _now.add(const Duration(days: 1));
      final products = [for (var i = 0; i < 6; i++) _product('p$i', discountUntil: future)];
      final firsts = <String>{
        for (var seed = 0; seed < 20; seed++)
          SponsorOrdering.products(products, SponsorPlacement.productDiscount, now: _now, random: Random(seed)).first.id,
      };
      expect(firsts.length, greaterThan(1));
    });

    test('ürün sıralaması yalnız sponsor olmayanlara uygulanır', () {
      final products = [
        _product('cheap', price: 10),
        _product('sponsor', price: 500, categoryUntil: _now.add(const Duration(days: 1))),
        _product('mid', price: 50),
      ];
      final ordered = SponsorOrdering.products(
        products,
        SponsorPlacement.productCategory,
        now: _now,
        restOrder: (a, b) => b.price.compareTo(a.price),
      );
      expect(ordered.map((p) => p.id), ['sponsor', 'mid', 'cheap']);
    });

    test('etiket: admin sabitlemesi her yerde, ücretli yalnız kendi vitrininde', () {
      expect(SponsorOrdering.shopBadge(_shop('p', pinned: true), SponsorPlacement.shopCategory, now: _now), isTrue);
      final paid = _product('x', discountUntil: _now.add(const Duration(hours: 1)));
      expect(SponsorOrdering.productBadge(paid, SponsorPlacement.productDiscount, now: _now), isTrue);
      expect(SponsorOrdering.productBadge(paid, SponsorPlacement.productCategory, now: _now), isFalse);
    });
  });

  group('ShopSponsorship', () {
    ShopSponsorship row({String status = 'active', DateTime? start, DateTime? end}) =>
        ShopSponsorship.tryFromJson({
          'id': 's1',
          'shop_id': 'shop',
          'product_id': null,
          'placement': 'shop_list',
          'package_name': 'Haftalık',
          'duration_days': 7,
          'price_paid': '150.00',
          'status': status,
          'starts_at': start?.toIso8601String(),
          'ends_at': end?.toIso8601String(),
          'created_at': _now.toIso8601String(),
        })!;

    test('durum etiketi: yayında / sırada / sona erdi / onay bekliyor / reddedildi', () {
      final h = const Duration(hours: 1);
      expect(row(start: _now.subtract(h), end: _now.add(h)).statusLabel(_now), 'Yayında');
      expect(row(start: _now.add(h), end: _now.add(h * 3)).statusLabel(_now), 'Sırada');
      expect(row(start: _now.subtract(h * 3), end: _now.subtract(h)).statusLabel(_now), 'Sona erdi');
      expect(row(status: 'pending').statusLabel(_now), 'Onay bekliyor');
      expect(row(status: 'rejected').statusLabel(_now), 'Reddedildi');
      expect(row(status: 'cancelled').statusLabel(_now), 'İptal edildi');
    });

    test('numeric metin olarak gelen fiyat okunur; tanınmayan vitrin atlanır', () {
      expect(row().pricePaid, 150);
      expect(ShopSponsorship.tryFromJson({'id': 'x', 'shop_id': 's', 'placement': 'yeni_vitrin'}), isNull);
      expect(SponsorshipPackage.tryFromJson({'id': 'p', 'placement': 'yeni_vitrin'}), isNull);
    });

    test('satın alma sonucu', () {
      final result = SponsorshipPurchase.fromJson({
        'id': 'n1',
        'status': 'active',
        'placement': 'product_discount',
        'price': 15,
        'balance_after': 985.5,
        'starts_at': '2026-09-28T12:00:00+00:00',
        'ends_at': '2026-09-29T12:00:00+00:00',
      });
      expect(result.placement, SponsorPlacement.productDiscount);
      expect((result.price, result.balanceAfter), (15.0, 985.5));
      expect(result.endsAt, DateTime.utc(2026, 9, 29, 12));
    });
  });
}
