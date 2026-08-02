// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/models/flash_sale_model.dart';
import '../../../core/models/product_model.dart';
import '../services/flash_sale_service.dart';
import '../../../shared/widgets/flash_discount_badge.dart';

/// Ürün kartlarında kullanılan, **flaş indirim bilinçli** fiyat satırı.
///
/// - Aktif bir flaş sale varsa: flaş fiyatı (kırmızı, büyük) + üstü çizili
///   orijinal fiyat + flaş indirim rozeti.
/// - Yoksa ürünün kendi `discount_price` / `old_price` mantığına düşer
///   (Product.effectivePrice) + normal indirim rozeti.
/// - Hiç indirim yoksa sadece normal fiyat gösterilir.
///
/// `FutureBuilder` kullanır çünkü aktif flaş sale'i ürün kartı render
/// anında çekmek (veritabanı indeksli sorgu, tek satır, gecikme tolere
/// edilebilir) en sade yoldur; ürün kartları zaten birçok asenkron
/// yükleme (kapak görseli, favori) ile geliyor.
class FlashAwarePriceRow extends StatelessWidget {
  final Product product;
  final TextStyle? priceStyle;
  final TextStyle? oldPriceStyle;
  final Color? oldPriceColor;
  final bool showBadge;
  final double? width;

  const FlashAwarePriceRow({
    super.key,
    required this.product,
    this.priceStyle,
    this.oldPriceStyle,
    this.oldPriceColor,
    this.showBadge = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final service = FlashSaleService();
    return FutureBuilder<FlashSale?>(
      future: service.getActiveFlashSaleForProduct(product.id),
      builder: (context, snap) {
        final flashSale = snap.data;
        if (flashSale != null) {
          return _flashRow(context, flashSale);
        }
        if (product.hasDiscount) {
          return _normalDiscountRow(context);
        }
        return _plainRow(context);
      },
    );
  }

  Widget _flashRow(BuildContext context, FlashSale sale) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '₺${sale.flashPrice.toStringAsFixed(2)}',
            style: priceStyle ??
                const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Color(0xFFE53935),
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '₺${sale.originalPrice.toStringAsFixed(2)}',
            style: oldPriceStyle ??
                TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: oldPriceColor ?? Colors.grey.shade400,
                  fontSize: 9,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showBadge) ...[
          const SizedBox(width: 4),
          FlashDiscountBadge(percentage: sale.discountPercent.round(), compact: true),
        ],
      ],
    );
  }

  Widget _normalDiscountRow(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '₺${product.effectivePrice.toStringAsFixed(2)}',
            style: priceStyle ??
                TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (product.displayOldPrice != null) ...[
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '₺${product.displayOldPrice!.toStringAsFixed(2)}',
              style: oldPriceStyle ??
                  TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: oldPriceColor ?? Colors.grey.shade400,
                    fontSize: 9,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (showBadge && product.discountPercentage != null) ...[
          const SizedBox(width: 4),
          FlashDiscountBadge(
            percentage: product.discountPercentage!,
            compact: true,
          ),
        ],
      ],
    );
  }

  Widget _plainRow(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '₺${product.effectivePrice.toStringAsFixed(2)}',
      style: priceStyle ??
          TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: theme.colorScheme.primary,
          ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Ürün kartı için hangi indirim türünün uygulanacağını döndüren küçük
/// helper. Aynı mantığı `_renderFlashBadge` ile paylaşır.
class FlashAwareDiscountBadge extends StatelessWidget {
  final Product product;
  final bool compact;

  const FlashAwareDiscountBadge({
    super.key,
    required this.product,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final service = FlashSaleService();
    return FutureBuilder<FlashSale?>(
      future: service.getActiveFlashSaleForProduct(product.id),
      builder: (context, snap) {
        final flash = snap.data;
        if (flash != null) {
          return FlashDiscountBadge(
            percentage: flash.discountPercent.round(),
            compact: compact,
          );
        }
        if (product.hasDiscount && product.discountPercentage != null) {
          return FlashDiscountBadge(
            percentage: product.discountPercentage!,
            compact: compact,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
