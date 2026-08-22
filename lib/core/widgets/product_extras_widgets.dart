import 'package:flutter/material.dart';

import '../models/product_model.dart';

/// Ürün rozetleri ve ek özellikleri (kargo / hazırlık süresi / adet limiti) için
/// küçük etiket. Hem satıcı panelinde hem alıcı tarafında aynı görünüm kullanılır.
class ProductMiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  /// Ürün detayı gibi geniş alanlarda biraz daha büyük gösterim.
  final bool large;

  const ProductMiniChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = large ? 12.0 : 10.5;
    final iconSize = large ? 15.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 7,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(large ? 8 : 6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ürünün satıcı tarafından tanımlanmış rozetleri. Rozet yoksa hiç yer kaplamaz.
class ProductBadgesWrap extends StatelessWidget {
  final Product product;
  final bool large;

  const ProductBadgesWrap({
    super.key,
    required this.product,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final badges = product.badgeDetails;
    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final badge in badges)
          ProductMiniChip(
            icon: badge.icon,
            label: badge.label,
            color: badge.color,
            large: large,
          ),
      ],
    );
  }
}

/// Ürün kartlarında (grid/liste) **görselin üzerine** yerleştirilen çok
/// kompakt etiket şeridi: satıcının seçtiği rozetler + ücretsiz kargo.
///
/// Kart yerleşimleri sabit yükseklikli olduğu için metin alanına yeni satır
/// eklemek taşmaya yol açardı; bu yüzden etiketler görselin boş alanında
/// gösterilir. Fotoğraf üzerinde okunabilirlik için saydam değil, dolu renkli
/// zemin kullanılır.
///
/// Satıcı rozet seçmediyse ve ücretsiz kargo yoksa hiç yer kaplamaz.
class ProductCardTagStrip extends StatelessWidget {
  final Product product;

  /// Dar kartlarda en fazla kaç etiket gösterilsin (varsayılan 2).
  final int maxTags;

  const ProductCardTagStrip({
    super.key,
    required this.product,
    this.maxTags = 2,
  });

  @override
  Widget build(BuildContext context) {
    final tags = <_CardTagData>[
      for (final badge in product.badgeDetails)
        _CardTagData(badge.icon, badge.label, badge.color),
      // Ücretsiz kargo rozetlerden sonra gelir: rozet satıcının bilinçli
      // seçimi, kargo ise türetilmiş bir bilgi.
      if (product.freeShipping && !product.isDigital)
        _CardTagData(
          Icons.local_shipping,
          'Kargo Bedava',
          const Color(0xFF2E7D32),
        ),
    ];

    if (tags.isEmpty) return const SizedBox.shrink();

    final visible = tags.take(maxTags).toList();

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final tag in visible)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: tag.color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tag.icon, size: 9, color: Colors.white),
                const SizedBox(width: 2),
                Text(
                  tag.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CardTagData {
  final IconData icon;
  final String label;
  final Color color;

  const _CardTagData(this.icon, this.label, this.color);
}

/// Kargo, hazırlık süresi ve sipariş adedi bilgileri. Satıcı hiçbirini
/// tanımlamadıysa hiç yer kaplamaz — mevcut ürünlerin görünümü değişmez.
class ProductLogisticsWrap extends StatelessWidget {
  final Product product;
  final bool large;

  /// Kargo bilgisini gizlemek için (örn. dijital ürünlerde anlamsız).
  final bool showShipping;

  const ProductLogisticsWrap({
    super.key,
    required this.product,
    this.large = false,
    this.showShipping = true,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (showShipping && product.freeShipping)
        ProductMiniChip(
          icon: Icons.local_shipping_outlined,
          label: 'Ücretsiz kargo',
          color: Colors.green.shade700,
          large: large,
        )
      else if (showShipping && product.shippingFee != null)
        ProductMiniChip(
          icon: Icons.local_shipping_outlined,
          label: 'Kargo ₺${product.shippingFee!.toStringAsFixed(2)}',
          color: Colors.blueGrey.shade700,
          large: large,
        ),
      if (product.prepTimeLabel != null)
        ProductMiniChip(
          icon: Icons.schedule,
          label: product.prepTimeLabel!,
          color: Colors.indigo.shade600,
          large: large,
        ),
      if (product.orderQuantityLabel != null)
        ProductMiniChip(
          icon: Icons.production_quantity_limits,
          label: product.orderQuantityLabel!,
          color: Colors.deepPurple.shade400,
          large: large,
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }
}
