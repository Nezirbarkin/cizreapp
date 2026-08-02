// server_quote_display.dart
// Tarih: 2026-08-02
//
// Checkout / multi-shop / ürün-detay ekranlarındaki ORTAK gösterim
// widget'ı. Tüm finansal değerleri doğrudan CheckoutSession
// (server_*) üzerinden gösterir. Client hesaplama YAPMAZ.

import 'package:flutter/material.dart';
import '../models/checkout_session_model.dart';

class ServerQuoteDisplay extends StatelessWidget {
  final CheckoutSession session;
  final bool showItems;

  const ServerQuoteDisplay({
    super.key,
    required this.session,
    this.showItems = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showItems) ...[
              const Text('Ürünler (sunucu onaylı)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...session.items.map((it) => ListTile(
                    dense: true,
                    leading: it.imageUrl != null
                        ? Image.network(it.imageUrl!,
                            width: 40, height: 40, fit: BoxFit.cover)
                        : const Icon(Icons.image),
                    title: Text(it.productName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${it.quantity} × '
                        '${(it.isFlashSale ? it.flashPrice ?? it.unitPrice : it.unitPrice).toStringAsFixed(2)} TL'),
                    trailing: Text(
                      '${it.lineTotal.toStringAsFixed(2)} TL',
                      style: t.bodyMedium,
                    ),
                  )),
              const Divider(),
            ],
            _row(context, 'Ara Toplam', session.serverSubtotal),
            _row(context, 'Kargo', session.serverDeliveryFee),
            if (session.serverCouponDiscount > 0)
              _row(context, 'Kupon İndirimi',
                  -session.serverCouponDiscount, isDiscount: true),
            const Divider(),
            _row(context, 'Toplam', session.serverTotal,
                isTotal: true, style: t.titleLarge),
            if (session.expectedPaidPrice != null)
              _row(context, 'iyzico beklenen tutar', session.expectedPaidPrice!,
                  style: t.bodySmall),
            if (session.isExpired)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.timer_off, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                        'Bu oturumun süresi dolmuş. Lütfen yeniden hazırlayın.')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, num value,
      {bool isTotal = false,
      bool isDiscount = false,
      TextStyle? style}) {
    final color = isDiscount ? Colors.green : (isTotal ? Colors.black : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style ?? DefaultTextStyle.of(context).style),
          Text(
            '${value.toStringAsFixed(2)} TL',
            style: (style ?? const TextStyle()).copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
