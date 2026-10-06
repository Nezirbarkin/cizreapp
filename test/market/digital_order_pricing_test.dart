import 'package:cizreapp/core/utils/digital_order_pricing.dart';
import 'package:cizreapp/features/market/widgets/digital_order_total_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.6 — dijital siparişte anlık toplam. Referans değerler CANLI
/// veritabanında sunucunun formülüyle üretildi:
///   birim = round(ppk/1000, 4); toplam = round(birim × adet, 2);
///   puan (%60 kapsama) = floor(toplam_kuruş × 60 / 100)
/// Satır: (ppk, adet, birim×10000, toplam kuruş, %60 puan kuruş)
const _serverReference = <(num, int, int, int, int)>[
  (0, 1, 0, 0, 0),
  (0, 7, 0, 0, 0),
  (0, 10, 0, 0, 0),
  (0, 20, 0, 0, 0),
  (0, 99, 0, 0, 0),
  (0, 100, 0, 0, 0),
  (0, 333, 0, 0, 0),
  (0, 999, 0, 0, 0),
  (0, 1000, 0, 0, 0),
  (0, 1234, 0, 0, 0),
  (0, 3000, 0, 0, 0),
  (0, 50000, 0, 0, 0),
  (0.35, 1, 4, 0, 0),
  (0.35, 7, 4, 0, 0),
  (0.35, 10, 4, 0, 0),
  (0.35, 20, 4, 1, 0),
  (0.35, 99, 4, 4, 2),
  (0.35, 100, 4, 4, 2),
  (0.35, 333, 4, 13, 7),
  (0.35, 999, 4, 40, 24),
  (0.35, 1000, 4, 40, 24),
  (0.35, 1234, 4, 49, 29),
  (0.35, 3000, 4, 120, 72),
  (0.35, 50000, 4, 2000, 1200),
  (0.5, 1, 5, 0, 0),
  (0.5, 7, 5, 0, 0),
  (0.5, 10, 5, 1, 0),
  (0.5, 20, 5, 1, 0),
  (0.5, 99, 5, 5, 3),
  (0.5, 100, 5, 5, 3),
  (0.5, 333, 5, 17, 10),
  (0.5, 999, 5, 50, 30),
  (0.5, 1000, 5, 50, 30),
  (0.5, 1234, 5, 62, 37),
  (0.5, 3000, 5, 150, 90),
  (0.5, 50000, 5, 2500, 1500),
  (1.99, 1, 20, 0, 0),
  (1.99, 7, 20, 1, 0),
  (1.99, 10, 20, 2, 1),
  (1.99, 20, 20, 4, 2),
  (1.99, 99, 20, 20, 12),
  (1.99, 100, 20, 20, 12),
  (1.99, 333, 20, 67, 40),
  (1.99, 999, 20, 200, 120),
  (1.99, 1000, 20, 200, 120),
  (1.99, 1234, 20, 247, 148),
  (1.99, 3000, 20, 600, 360),
  (1.99, 50000, 20, 10000, 6000),
  (3, 1, 30, 0, 0),
  (3, 7, 30, 2, 1),
  (3, 10, 30, 3, 1),
  (3, 20, 30, 6, 3),
  (3, 99, 30, 30, 18),
  (3, 100, 30, 30, 18),
  (3, 333, 30, 100, 60),
  (3, 999, 30, 300, 180),
  (3, 1000, 30, 300, 180),
  (3, 1234, 30, 370, 222),
  (3, 3000, 30, 900, 540),
  (3, 50000, 30, 15000, 9000),
  (25, 1, 250, 3, 1),
  (25, 7, 250, 18, 10),
  (25, 10, 250, 25, 15),
  (25, 20, 250, 50, 30),
  (25, 99, 250, 248, 148),
  (25, 100, 250, 250, 150),
  (25, 333, 250, 833, 499),
  (25, 999, 250, 2498, 1498),
  (25, 1000, 250, 2500, 1500),
  (25, 1234, 250, 3085, 1851),
  (25, 3000, 250, 7500, 4500),
  (25, 50000, 250, 125000, 75000),
  (35, 1, 350, 4, 2),
  (35, 7, 350, 25, 15),
  (35, 10, 350, 35, 21),
  (35, 20, 350, 70, 42),
  (35, 99, 350, 347, 208),
  (35, 100, 350, 350, 210),
  (35, 333, 350, 1166, 699),
  (35, 999, 350, 3497, 2098),
  (35, 1000, 350, 3500, 2100),
  (35, 1234, 350, 4319, 2591),
  (35, 3000, 350, 10500, 6300),
  (35, 50000, 350, 175000, 105000),
  (45.55, 1, 456, 5, 3),
  (45.55, 7, 456, 32, 19),
  (45.55, 10, 456, 46, 27),
  (45.55, 20, 456, 91, 54),
  (45.55, 99, 456, 451, 270),
  (45.55, 100, 456, 456, 273),
  (45.55, 333, 456, 1518, 910),
  (45.55, 999, 456, 4555, 2733),
  (45.55, 1000, 456, 4560, 2736),
  (45.55, 1234, 456, 5627, 3376),
  (45.55, 3000, 456, 13680, 8208),
  (45.55, 50000, 456, 228000, 136800),
  (55, 1, 550, 6, 3),
  (55, 7, 550, 39, 23),
  (55, 10, 550, 55, 33),
  (55, 20, 550, 110, 66),
  (55, 99, 550, 545, 327),
  (55, 100, 550, 550, 330),
  (55, 333, 550, 1832, 1099),
  (55, 999, 550, 5495, 3297),
  (55, 1000, 550, 5500, 3300),
  (55, 1234, 550, 6787, 4072),
  (55, 3000, 550, 16500, 9900),
  (55, 50000, 550, 275000, 165000),
  (65, 1, 650, 7, 4),
  (65, 7, 650, 46, 27),
  (65, 10, 650, 65, 39),
  (65, 20, 650, 130, 78),
  (65, 99, 650, 644, 386),
  (65, 100, 650, 650, 390),
  (65, 333, 650, 2165, 1299),
  (65, 999, 650, 6494, 3896),
  (65, 1000, 650, 6500, 3900),
  (65, 1234, 650, 8021, 4812),
  (65, 3000, 650, 19500, 11700),
  (65, 50000, 650, 325000, 195000),
  (150, 1, 1500, 15, 9),
  (150, 7, 1500, 105, 63),
  (150, 10, 1500, 150, 90),
  (150, 20, 1500, 300, 180),
  (150, 99, 1500, 1485, 891),
  (150, 100, 1500, 1500, 900),
  (150, 333, 1500, 4995, 2997),
  (150, 999, 1500, 14985, 8991),
  (150, 1000, 1500, 15000, 9000),
  (150, 1234, 1500, 18510, 11106),
  (150, 3000, 1500, 45000, 27000),
  (150, 50000, 1500, 750000, 450000),
  (333.33, 1, 3333, 33, 19),
  (333.33, 7, 3333, 233, 139),
  (333.33, 10, 3333, 333, 199),
  (333.33, 20, 3333, 667, 400),
  (333.33, 99, 3333, 3300, 1980),
  (333.33, 100, 3333, 3333, 1999),
  (333.33, 333, 3333, 11099, 6659),
  (333.33, 999, 3333, 33297, 19978),
  (333.33, 1000, 3333, 33330, 19998),
  (333.33, 1234, 3333, 41129, 24677),
  (333.33, 3000, 3333, 99990, 59994),
  (333.33, 50000, 3333, 1666500, 999900),
  (500, 1, 5000, 50, 30),
  (500, 7, 5000, 350, 210),
  (500, 10, 5000, 500, 300),
  (500, 20, 5000, 1000, 600),
  (500, 99, 5000, 4950, 2970),
  (500, 100, 5000, 5000, 3000),
  (500, 333, 5000, 16650, 9990),
  (500, 999, 5000, 49950, 29970),
  (500, 1000, 5000, 50000, 30000),
  (500, 1234, 5000, 61700, 37020),
  (500, 3000, 5000, 150000, 90000),
  (500, 50000, 5000, 2500000, 1500000),
  (650, 1, 6500, 65, 39),
  (650, 7, 6500, 455, 273),
  (650, 10, 6500, 650, 390),
  (650, 20, 6500, 1300, 780),
  (650, 99, 6500, 6435, 3861),
  (650, 100, 6500, 6500, 3900),
  (650, 333, 6500, 21645, 12987),
  (650, 999, 6500, 64935, 38961),
  (650, 1000, 6500, 65000, 39000),
  (650, 1234, 6500, 80210, 48126),
  (650, 3000, 6500, 195000, 117000),
  (650, 50000, 6500, 3250000, 1950000),
  (1234.56, 1, 12346, 123, 73),
  (1234.56, 7, 12346, 864, 518),
  (1234.56, 10, 12346, 1235, 741),
  (1234.56, 20, 12346, 2469, 1481),
  (1234.56, 99, 12346, 12223, 7333),
  (1234.56, 100, 12346, 12346, 7407),
  (1234.56, 333, 12346, 41112, 24667),
  (1234.56, 999, 12346, 123337, 74002),
  (1234.56, 1000, 12346, 123460, 74076),
  (1234.56, 1234, 12346, 152350, 91410),
  (1234.56, 3000, 12346, 370380, 222228),
  (1234.56, 50000, 12346, 6173000, 3703800),
];

void main() {
  setUpAll(loadTestFonts);

  group('DigitalOrderPricing — sunucuyla birebir', () {
    test('${_serverReference.length} referans değer (canlı veritabanında üretildi)', () {
      for (final (ppk, qty, unitE4, cents, points60) in _serverReference) {
        final quote = DigitalOrderPricing.quote(
          pricePer1000: ppk.toDouble(),
          quantity: qty,
          pointsEligible: true,
          maxPointsCoveragePercent: 60,
        )!;
        expect(quote.unitPriceE4, unitE4, reason: 'birim: ppk=$ppk adet=$qty');
        expect(quote.totalCents, cents, reason: 'toplam: ppk=$ppk adet=$qty');
        expect(quote.maxPointsCents, points60, reason: 'puan: ppk=$ppk adet=$qty');
      }
    });

    test('geçersiz girdide hesap yok; puana uygun değilse puan payı 0', () {
      expect(DigitalOrderPricing.quote(pricePer1000: null, quantity: 10), isNull);
      expect(DigitalOrderPricing.quote(pricePer1000: 35, quantity: 0), isNull);
      expect(DigitalOrderPricing.quote(pricePer1000: -1, quantity: 5), isNull);
      expect(DigitalOrderPricing.quote(pricePer1000: 35, quantity: 100)!.maxPointsCents, 0);
      expect(
        DigitalOrderPricing.quote(
          pricePer1000: 35,
          quantity: 100,
          pointsEligible: true,
          maxPointsCoveragePercent: 250,
        )!.maxPointsCents,
        350,
        reason: 'kapsama %100 ile sınırlı',
      );
    });

    test('para biçimi: her zaman 2 hane, binlik ayırıcı', () {
      expect(DigitalOrderPricing.formatTry(4), '₺0,04');
      expect(DigitalOrderPricing.formatTry(70), '₺0,70');
      expect(DigitalOrderPricing.formatTry(123456789), '₺1.234.567,89');
      expect(DigitalOrderPricing.formatTry(100000), '₺1.000,00');
    });
  });

  group('DigitalOrderTotalCard', () {
    Future<void> pump(WidgetTester tester, Widget card) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: card)),
        ),
      );
    }

    String total(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('digital-order-total'))).data!;

    testWidgets('miktar değiştikçe toplam anında güncellenir', (tester) async {
      await pump(
        tester,
        const DigitalOrderTotalCard(pricePer1000: 35, quantity: 20, minQuantity: 20, maxQuantity: 1000),
      );
      expect(total(tester), '₺0,70');
      expect(find.text('20 adet × ₺35,00 / 1000 adet'), findsOneWidget);

      await pump(
        tester,
        const DigitalOrderTotalCard(pricePer1000: 35, quantity: 1000, minQuantity: 20, maxQuantity: 1000),
      );
      expect(total(tester), '₺35,00');
    });

    testWidgets('boş ya da aralık dışı miktarda toplam yok, ne gerektiği yazar', (tester) async {
      await pump(
        tester,
        const DigitalOrderTotalCard(pricePer1000: 650, quantity: 0, minQuantity: 10, maxQuantity: 3000),
      );
      expect(total(tester), '—');
      expect(find.text('Miktar girince toplam burada anında hesaplanır'), findsOneWidget);

      await pump(
        tester,
        const DigitalOrderTotalCard(pricePer1000: 650, quantity: 5, minQuantity: 10, maxQuantity: 3000),
      );
      expect(total(tester), '—');
      expect(find.text('Miktar 10 – 3000 arasında olmalı'), findsOneWidget);

      await pump(
        tester,
        const DigitalOrderTotalCard(pricePer1000: null, quantity: 50, minQuantity: 10, maxQuantity: 3000),
      );
      expect(find.text('Fiyat bilgisi yok'), findsOneWidget);
    });

    testWidgets('puana uygun üründe puanla ödenebilecek en fazla tutar', (tester) async {
      await pump(
        tester,
        const DigitalOrderTotalCard(
          pricePer1000: 650,
          quantity: 100,
          minQuantity: 10,
          maxQuantity: 3000,
          pointsEligible: true,
          maxPointsCoveragePercent: 50,
        ),
      );
      expect(total(tester), '₺65,00');
      expect(find.text('Puanın yeterliyse en fazla ₺32,50 puanla, kalanı TL bakiyeden ödenir.'), findsOneWidget);
    });
  });
}
