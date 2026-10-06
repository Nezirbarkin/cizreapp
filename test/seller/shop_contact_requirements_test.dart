import 'package:cizreapp/features/seller/utils/shop_contact_requirements.dart';
import 'package:cizreapp/features/seller/widgets/shop_missing_info_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.7 — satıcı telefon + konum zorunluluğu (istemci kuralı sunucudaki
/// `shop_phone_is_valid` ile aynı) ve paneldeki kalıcı eksik bilgi şeridi.
void main() {
  setUpAll(loadTestFonts);

  group('ShopContactRequirements', () {
    test('telefon biçimi sunucuyla aynı (10–13 rakam)', () {
      for (final ok in ['0532 123 45 67', '+90 (532) 123-4567', '5321234567', '0 488 441 22 33']) {
        expect(ShopContactRequirements.isValidPhone(ok), isTrue, reason: ok);
      }
      for (final bad in ['123456', '', null, '0532 12', '12345678901234']) {
        expect(ShopContactRequirements.isValidPhone(bad), isFalse, reason: '$bad');
      }
      expect(ShopContactRequirements.phoneError(''), 'Telefon gerekli');
      expect(ShopContactRequirements.phoneError('0532'), 'Geçerli bir telefon girin (örn. 0532 123 45 67)');
      expect(ShopContactRequirements.phoneError('0532 123 45 67'), isNull);
    });

    test('eksikler: telefon, konum, ikisi; mağaza satırından', () {
      expect(ShopContactRequirements.missing(phone: '05321234567', latitude: 37.3, longitude: 42.1), isEmpty);
      expect(ShopContactRequirements.missing(phone: '', latitude: 37.3, longitude: 42.1), [ShopMissingInfo.phone]);
      expect(ShopContactRequirements.missing(phone: '05321234567', latitude: null, longitude: 42.1), [
        ShopMissingInfo.location,
      ]);
      expect(ShopContactRequirements.missingFromShop({'phone': null, 'latitude': null, 'longitude': null}), [
        ShopMissingInfo.phone,
        ShopMissingInfo.location,
      ]);
      expect(ShopContactRequirements.missingFromShop(null), isEmpty, reason: 'mağaza yoksa şerit yok');
      expect(
        ShopContactRequirements.bannerText([ShopMissingInfo.phone, ShopMissingInfo.location]),
        'Mağazanın telefon numarası ve haritadan mağaza konumu eksik. Müşterilerin sana ulaşabilmesi '
        've kuryenin mağazanı bulabilmesi için bu bilgiler zorunlu.',
      );
    });
  });

  group('ShopMissingInfoBanner', () {
    testWidgets('eksik varsa görünür, dokununca ayarları açar; tamamsa yer kaplamaz', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopMissingInfoBanner(
              missing: const [ShopMissingInfo.phone, ShopMissingInfo.location],
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(find.text('Eksik mağaza bilgisi'), findsOneWidget);
      expect(find.text('Telefon'), findsOneWidget);
      expect(find.text('Harita konumu'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing, reason: 'kalıcı: kapatılamaz');
      await tester.tap(find.text('Şimdi tamamla ›'));
      expect(taps, 1);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ShopMissingInfoBanner(missing: const [], onTap: () => taps++))),
      );
      expect(find.text('Eksik mağaza bilgisi'), findsNothing);
    });
  });
}
