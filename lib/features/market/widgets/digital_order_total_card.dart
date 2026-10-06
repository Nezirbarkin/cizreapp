import 'package:flutter/material.dart';

import '../../../core/utils/digital_order_pricing.dart';

/// Dijital siparişte anlık toplam (Görev 3.6).
///
/// Ürün detayındaki "Miktar" alanı her değiştiğinde üst ekran durumu
/// (`_digitalQuantity`) günceller; bu kart o değerle sunucunun formülünü
/// ([DigitalOrderPricing]) çalıştırıp toplamı hemen gösterir. Aralık dışı ya da
/// boş miktarda toplam yerine ne girilmesi gerektiği yazar.
class DigitalOrderTotalCard extends StatelessWidget {
  const DigitalOrderTotalCard({
    super.key,
    required this.pricePer1000,
    required this.quantity,
    this.minQuantity = 0,
    this.maxQuantity = 0,
    this.pointsEligible = false,
    this.maxPointsCoveragePercent = 100,
  });

  final double? pricePer1000;
  final int quantity;
  final int minQuantity;

  /// 0 = üst sınır bilinmiyor.
  final int maxQuantity;
  final bool pointsEligible;
  final int maxPointsCoveragePercent;

  bool get _inRange =>
      quantity > 0 && quantity >= minQuantity && (maxQuantity <= 0 || quantity <= maxQuantity);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final quote = _inRange
        ? DigitalOrderPricing.quote(
            pricePer1000: pricePer1000,
            quantity: quantity,
            pointsEligible: pointsEligible,
            maxPointsCoveragePercent: maxPointsCoveragePercent,
          )
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: quote == null ? Colors.grey.shade100 : primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: quote == null ? Colors.grey.shade300 : primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Toplam',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
              ),
              const Spacer(),
              Text(
                quote == null ? '—' : DigitalOrderPricing.formatTry(quote.totalCents),
                key: const ValueKey('digital-order-total'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: quote == null ? Colors.black38 : primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_detail(quote), style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (quote != null && pointsEligible && quote.maxPointsCents > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Puanın yeterliyse en fazla ${DigitalOrderPricing.formatTry(quote.maxPointsCents)} '
              'puanla, kalanı TL bakiyeden ödenir.',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
            ),
          ],
        ],
      ),
    );
  }

  String _detail(DigitalOrderQuote? quote) {
    if (quote != null) {
      return '$quantity adet × ${DigitalOrderPricing.formatTry(quote.pricePer1000Cents)} / 1000 adet';
    }
    if (pricePer1000 == null) return 'Fiyat bilgisi yok';
    if (quantity <= 0) return 'Miktar girince toplam burada anında hesaplanır';
    if (maxQuantity > 0) return 'Miktar $minQuantity – $maxQuantity arasında olmalı';
    return 'Miktar en az $minQuantity olmalı';
  }
}
