import 'dart:math';

import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../models/sponsorship_model.dart';

/// Listelerde sponsorlu öğelerin sırası ve etiketi (Görev 3.2).
///
/// Üç kat:
///  1. admin sabitlemesi ([Shop.isPinned] / [Product.isPinned]) — gelen sıra
///     korunur;
///  2. bu vitrinde ÜCRETLİ öne çıkarılanlar — her yüklemede karıştırılır ki
///     aynı anda birden çok sponsor en üstü adil paylaşsın;
///  3. geri kalanlar — gelen sıra (ya da [restOrder]) korunur.
abstract final class SponsorOrdering {
  static List<Shop> shops(
    List<Shop> shops,
    SponsorPlacement placement, {
    DateTime? now,
    Random? random,
    Comparator<Shop>? restOrder,
  }) => _order(
    shops,
    pinned: (s) => s.isPinned,
    paid: (s) => s.isSponsoredIn(placement, now: now),
    random: random,
    restOrder: restOrder,
  );

  static List<Product> products(
    List<Product> products,
    SponsorPlacement placement, {
    DateTime? now,
    Random? random,
    Comparator<Product>? restOrder,
  }) => _order(
    products,
    pinned: (p) => p.isPinned,
    paid: (p) => p.isSponsoredIn(placement, now: now),
    random: random,
    restOrder: restOrder,
  );

  /// Kartta "Sponsor" etiketi: admin sabitlemesi ya da bu vitrinde ücretli.
  static bool shopBadge(Shop shop, SponsorPlacement placement, {DateTime? now}) =>
      shop.isPinned || shop.isSponsoredIn(placement, now: now);

  static bool productBadge(Product product, SponsorPlacement placement, {DateTime? now}) =>
      product.isPinned || product.isSponsoredIn(placement, now: now);

  static List<T> _order<T>(
    List<T> items, {
    required bool Function(T item) pinned,
    required bool Function(T item) paid,
    Random? random,
    Comparator<T>? restOrder,
  }) {
    final pinnedItems = <T>[];
    final paidItems = <T>[];
    final rest = <T>[];
    for (final item in items) {
      if (pinned(item)) {
        pinnedItems.add(item);
      } else if (paid(item)) {
        paidItems.add(item);
      } else {
        rest.add(item);
      }
    }
    paidItems.shuffle(random);
    if (restOrder != null) rest.sort(restOrder);
    return [...pinnedItems, ...paidItems, ...rest];
  }
}
