import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Satıcı panelindeki liste ekranları için tam-ekran spinner yerine kullanılan
/// iskelet yükleyici. `shop_card.dart`'taki `ShopCardSkeleton` ile aynı
/// paleti (grey.shade200 / grey.shade50) ve kart reçetesini (18px, ince
/// kenarlık) kullanır — içerik geldiğinde liste zıplamaz.
class SellerListSkeleton extends StatelessWidget {
  const SellerListSkeleton({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 96,
    this.padding = const EdgeInsets.all(16),
  });

  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) => Container(
        height: itemHeight,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        ),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: itemHeight - 24,
                  height: itemHeight - 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: double.infinity, height: 14, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 120, height: 12, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 80, height: 12, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
