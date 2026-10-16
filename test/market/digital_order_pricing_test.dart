import 'package:cizreapp/core/utils/digital_order_pricing.dart';
import 'package:cizreapp/features/market/widgets/digital_order_total_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.6 — dijital siparişte anlık toplam. Referans değerler CANLI
/// veritabanında sunucunun formülüyle üretildi (20261016000011):
///   birim = round(ppk/1000, 6); toplam = round(ppk × adet / 1000, 2);
///   puan (%60 kapsama) = floor(toplam_kuruş × 60 / 100)
/// Fonksiyonun kendisi: supabase/tests/manual/digital_order_total_exact_test.sql
/// Satır: (ppk, adet, birim×1000000, toplam kuruş, %60 puan kuruş)
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
  (0.35, 1, 350, 0, 0),
  (0.35, 7, 350, 0, 0),
  (0.35, 10, 350, 0, 0),
  (0.35, 20, 350, 1, 0),
  (0.35, 99, 350, 3, 1),
  (0.35, 100, 350, 4, 2),
  (0.35, 333, 350, 12, 7),
  (0.35, 999, 350, 35, 21),
  (0.35, 1000, 350, 35, 21),
  (0.35, 1234, 350, 43, 25),
  (0.35, 3000, 350, 105, 63),
  (0.35, 50000, 350, 1750, 1050),
  (0.5, 1, 500, 0, 0),
  (0.5, 7, 500, 0, 0),
  (0.5, 10, 500, 1, 0),
  (0.5, 20, 500, 1, 0),
  (0.5, 99, 500, 5, 3),
  (0.5, 100, 500, 5, 3),
  (0.5, 333, 500, 17, 10),
  (0.5, 999, 500, 50, 30),
  (0.5, 1000, 500, 50, 30),
  (0.5, 1234, 500, 62, 37),
  (0.5, 3000, 500, 150, 90),
  (0.5, 50000, 500, 2500, 1500),
  (1.99, 1, 1990, 0, 0),
  (1.99, 7, 1990, 1, 0),
  (1.99, 10, 1990, 2, 1),
  (1.99, 20, 1990, 4, 2),
  (1.99, 99, 1990, 20, 12),
  (1.99, 100, 1990, 20, 12),
  (1.99, 333, 1990, 66, 39),
  (1.99, 999, 1990, 199, 119),
  (1.99, 1000, 1990, 199, 119),
  (1.99, 1234, 1990, 246, 147),
  (1.99, 3000, 1990, 597, 358),
  (1.99, 50000, 1990, 9950, 5970),
  (3, 1, 3000, 0, 0),
  (3, 7, 3000, 2, 1),
  (3, 10, 3000, 3, 1),
  (3, 20, 3000, 6, 3),
  (3, 99, 3000, 30, 18),
  (3, 100, 3000, 30, 18),
  (3, 333, 3000, 100, 60),
  (3, 999, 3000, 300, 180),
  (3, 1000, 3000, 300, 180),
  (3, 1234, 3000, 370, 222),
  (3, 3000, 3000, 900, 540),
  (3, 50000, 3000, 15000, 9000),
  (25, 1, 25000, 3, 1),
  (25, 7, 25000, 18, 10),
  (25, 10, 25000, 25, 15),
  (25, 20, 25000, 50, 30),
  (25, 99, 25000, 248, 148),
  (25, 100, 25000, 250, 150),
  (25, 333, 25000, 833, 499),
  (25, 999, 25000, 2498, 1498),
  (25, 1000, 25000, 2500, 1500),
  (25, 1234, 25000, 3085, 1851),
  (25, 3000, 25000, 7500, 4500),
  (25, 50000, 25000, 125000, 75000),
  (35, 1, 35000, 4, 2),
  (35, 7, 35000, 25, 15),
  (35, 10, 35000, 35, 21),
  (35, 20, 35000, 70, 42),
  (35, 99, 35000, 347, 208),
  (35, 100, 35000, 350, 210),
  (35, 333, 35000, 1166, 699),
  (35, 999, 35000, 3497, 2098),
  (35, 1000, 35000, 3500, 2100),
  (35, 1234, 35000, 4319, 2591),
  (35, 3000, 35000, 10500, 6300),
  (35, 50000, 35000, 175000, 105000),
  (45.55, 1, 45550, 5, 3),
  (45.55, 7, 45550, 32, 19),
  (45.55, 10, 45550, 46, 27),
  (45.55, 20, 45550, 91, 54),
  (45.55, 99, 45550, 451, 270),
  (45.55, 100, 45550, 456, 273),
  (45.55, 333, 45550, 1517, 910),
  (45.55, 999, 45550, 4550, 2730),
  (45.55, 1000, 45550, 4555, 2733),
  (45.55, 1234, 45550, 5621, 3372),
  (45.55, 3000, 45550, 13665, 8199),
  (45.55, 50000, 45550, 227750, 136650),
  (55, 1, 55000, 6, 3),
  (55, 7, 55000, 39, 23),
  (55, 10, 55000, 55, 33),
  (55, 20, 55000, 110, 66),
  (55, 99, 55000, 545, 327),
  (55, 100, 55000, 550, 330),
  (55, 333, 55000, 1832, 1099),
  (55, 999, 55000, 5495, 3297),
  (55, 1000, 55000, 5500, 3300),
  (55, 1234, 55000, 6787, 4072),
  (55, 3000, 55000, 16500, 9900),
  (55, 50000, 55000, 275000, 165000),
  (65, 1, 65000, 7, 4),
  (65, 7, 65000, 46, 27),
  (65, 10, 65000, 65, 39),
  (65, 20, 65000, 130, 78),
  (65, 99, 65000, 644, 386),
  (65, 100, 65000, 650, 390),
  (65, 333, 65000, 2165, 1299),
  (65, 999, 65000, 6494, 3896),
  (65, 1000, 65000, 6500, 3900),
  (65, 1234, 65000, 8021, 4812),
  (65, 3000, 65000, 19500, 11700),
  (65, 50000, 65000, 325000, 195000),
  (150, 1, 150000, 15, 9),
  (150, 7, 150000, 105, 63),
  (150, 10, 150000, 150, 90),
  (150, 20, 150000, 300, 180),
  (150, 99, 150000, 1485, 891),
  (150, 100, 150000, 1500, 900),
  (150, 333, 150000, 4995, 2997),
  (150, 999, 150000, 14985, 8991),
  (150, 1000, 150000, 15000, 9000),
  (150, 1234, 150000, 18510, 11106),
  (150, 3000, 150000, 45000, 27000),
  (150, 50000, 150000, 750000, 450000),
  (333.33, 1, 333330, 33, 19),
  (333.33, 7, 333330, 233, 139),
  (333.33, 10, 333330, 333, 199),
  (333.33, 20, 333330, 667, 400),
  (333.33, 99, 333330, 3300, 1980),
  (333.33, 100, 333330, 3333, 1999),
  (333.33, 333, 333330, 11100, 6660),
  (333.33, 999, 333330, 33300, 19980),
  (333.33, 1000, 333330, 33333, 19999),
  (333.33, 1234, 333330, 41133, 24679),
  (333.33, 3000, 333330, 99999, 59999),
  (333.33, 50000, 333330, 1666650, 999990),
  (500, 1, 500000, 50, 30),
  (500, 7, 500000, 350, 210),
  (500, 10, 500000, 500, 300),
  (500, 20, 500000, 1000, 600),
  (500, 99, 500000, 4950, 2970),
  (500, 100, 500000, 5000, 3000),
  (500, 333, 500000, 16650, 9990),
  (500, 999, 500000, 49950, 29970),
  (500, 1000, 500000, 50000, 30000),
  (500, 1234, 500000, 61700, 37020),
  (500, 3000, 500000, 150000, 90000),
  (500, 50000, 500000, 2500000, 1500000),
  (650, 1, 650000, 65, 39),
  (650, 7, 650000, 455, 273),
  (650, 10, 650000, 650, 390),
  (650, 20, 650000, 1300, 780),
  (650, 99, 650000, 6435, 3861),
  (650, 100, 650000, 6500, 3900),
  (650, 333, 650000, 21645, 12987),
  (650, 999, 650000, 64935, 38961),
  (650, 1000, 650000, 65000, 39000),
  (650, 1234, 650000, 80210, 48126),
  (650, 3000, 650000, 195000, 117000),
  (650, 50000, 650000, 3250000, 1950000),
  (1234.56, 1, 1234560, 123, 73),
  (1234.56, 7, 1234560, 864, 518),
  (1234.56, 10, 1234560, 1235, 741),
  (1234.56, 20, 1234560, 2469, 1481),
  (1234.56, 99, 1234560, 12222, 7333),
  (1234.56, 100, 1234560, 12346, 7407),
  (1234.56, 333, 1234560, 41111, 24666),
  (1234.56, 999, 1234560, 123333, 73999),
  (1234.56, 1000, 1234560, 123456, 74073),
  (1234.56, 1234, 1234560, 152345, 91407),
  (1234.56, 3000, 1234560, 370368, 222220),
  (1234.56, 50000, 1234560, 6172800, 3703680),
];

void main() {
  setUpAll(loadTestFonts);

  group('DigitalOrderPricing — sunucuyla birebir', () {
    test('${_serverReference.length} referans değer (canlı veritabanında üretildi)', () {
      for (final (ppk, qty, unitE6, cents, points60) in _serverReference) {
        final quote = DigitalOrderPricing.quote(
          pricePer1000: ppk.toDouble(),
          quantity: qty,
          pointsEligible: true,
          maxPointsCoveragePercent: 60,
        )!;
        expect(quote.unitPriceE6, unitE6, reason: 'birim: ppk=$ppk adet=$qty');
        expect(quote.totalCents, cents, reason: 'toplam: ppk=$ppk adet=$qty');
        expect(quote.maxPointsCents, points60, reason: 'puan: ppk=$ppk adet=$qty');
      }
    });

    test('ucuz serviste birim kırpılmaz: 0,24 TL / 1000 adet × 1000 = 0,24 TL', () {
      // Eski formül birimi 0,0002'ye kırpıp 0,20 TL veriyordu.
      expect(DigitalOrderPricing.quote(pricePer1000: 0.24, quantity: 1000)!.totalCents, 24);
      expect(DigitalOrderPricing.quote(pricePer1000: 0.24, quantity: 100000)!.totalCents, 2400);
      expect(DigitalOrderPricing.quote(pricePer1000: 0.67, quantity: 100)!.totalCents, 7);
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
