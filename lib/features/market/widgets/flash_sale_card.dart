// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/flash_sale_model.dart';
import '../../../shared/widgets/flash_discount_badge.dart';

/// Flash sale ürün kartı - büyük indirim rozeti + canlı stok progress bar.
class FlashSaleCard extends StatelessWidget {
  final FlashSale sale;
  final VoidCallback onTap;
  final VoidCallback? onAddToCart;

  const FlashSaleCard({
    super.key,
    required this.sale,
    required this.onTap,
    this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final isSoldOut = sale.isSoldOut || sale.hasEnded;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Görsel
                AspectRatio(
                  aspectRatio: 1.1,
                  child: sale.productImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: sale.productImageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image, size: 36),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image, size: 36),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ürün adı
                      Text(
                        sale.productName ?? 'Ürün',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      // Fiyat satırı
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${sale.flashPrice.toStringAsFixed(2)} ₺',
                            style: const TextStyle(
                              color: Color(0xFFE53935),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${sale.originalPrice.toStringAsFixed(2)} ₺',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              decoration: TextDecoration.lineThrough,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Stok progress bar
                      _StockProgress(sale: sale),
                    ],
                  ),
                ),
              ],
            ),
            // İndirim rozeti
            Positioned(
              top: 6,
              left: 6,
              child: FlashDiscountBadge(
                percentage: sale.discountPercent.round(),
                compact: true,
              ),
            ),
            // Tükendi / süre doldu overlay
            if (isSoldOut)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.45),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sale.isSoldOut ? 'TÜKENDİ' : 'SÜRE DOLDU',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StockProgress extends StatelessWidget {
  final FlashSale sale;
  const _StockProgress({required this.sale});

  @override
  Widget build(BuildContext context) {
    final percent = sale.soldPercent;
    final remaining = sale.remainingStock;
    final isCritical = remaining <= 5 && remaining > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(
              isCritical ? const Color(0xFFFF5252) : const Color(0xFF1B5E20),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isCritical ? 'Son $remaining ürün!' : 'Satılıyor',
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCritical ? FontWeight.bold : FontWeight.normal,
                color: isCritical ? const Color(0xFFE53935) : Colors.grey.shade700,
              ),
            ),
            Text(
              '%${percent.toStringAsFixed(0)} satıldı',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}