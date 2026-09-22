import 'package:flutter/material.dart';

import '../../../../core/widgets/product_extras_widgets.dart';

/// Ürün satırlarında 👁 görüntülenme + ❤ beğeni (+ varsa ★ puan) sayısını
/// gösteren çip grubu. Yeni bir görsel icat etmez, mevcut paylaşılan
/// [ProductMiniChip] bileşenini (alıcı tarafında da kullanılan) kompoze eder.
class SellerProductStatsChips extends StatelessWidget {
  const SellerProductStatsChips({
    super.key,
    required this.viewCount,
    required this.favoriteCount,
    this.rating = 0,
    this.totalReviews = 0,
  });

  final int viewCount;
  final int favoriteCount;
  final double rating;
  final int totalReviews;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ProductMiniChip(
          icon: Icons.visibility_outlined,
          label: '$viewCount',
          color: Colors.blueGrey.shade600,
        ),
        ProductMiniChip(
          icon: Icons.favorite_rounded,
          label: '$favoriteCount',
          color: Colors.pink.shade600,
        ),
        if (rating > 0)
          ProductMiniChip(
            icon: Icons.star_rounded,
            label: totalReviews > 0
                ? '${rating.toStringAsFixed(1)} ($totalReviews)'
                : rating.toStringAsFixed(1),
            color: Colors.amber.shade800,
          ),
      ],
    );
  }
}
