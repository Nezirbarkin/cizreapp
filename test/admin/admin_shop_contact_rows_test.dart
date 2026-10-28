import 'dart:io';

import 'package:cizreapp/features/admin/widgets/admin_shop_contact_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// admin_shops_page satırı biçiminde örnek (profiles iç içe).
Map<String, dynamic> _pageRow({
  String? phone = '0532 111 22 33',
  String? ownerPhone,
  Object? lat = 37.3270123,
  Object? lng = 42.1901234,
}) =>
    {
      'id': 's1',
      'name': 'Cizre Market',
      'phone': phone,
      'email': 'dukkan@ornek.com',
      'address': 'Nuh Mah. Yafes Cad. No 5',
      'latitude': lat,
      'longitude': lng,
      'iban': 'TR120006400000112345678901',
      'bank_name': 'Ziraat',
      'account_holder_name': 'Ahmet Yılmaz',
      'profiles': {
        'full_name': 'Ahmet Yılmaz',
        'username': 'ahmet',
        'email': 'ahmet@ornek.com',
        'phone': ownerPhone,
      },
    };

void main() {
  group('AdminShopContact.fromShop', () {
    test('dükkan telefonu sahibin profil telefonundan önce gelir', () {
      final c = AdminShopContact.fromShop(_pageRow(ownerPhone: '0500 000 00 00'));
      expect(c.phone, '0532 111 22 33');
      expect(c.phoneFromProfile, isFalse);
      expect(c.dialablePhone, '05321112233');
      expect(c.ownerName, 'Ahmet Yılmaz');
      expect(c.ownerEmail, 'ahmet@ornek.com');
    });

    test('dükkan telefonu boşsa profil telefonuna düşer ve bunu işaretler', () {
      final c = AdminShopContact.fromShop(_pageRow(phone: '  ', ownerPhone: '+90 (532) 999 88 77'));
      expect(c.phone, '+90 (532) 999 88 77');
      expect(c.phoneFromProfile, isTrue);
      expect(c.dialablePhone, '+905329998877');
    });

    test('hiç telefon yoksa null', () {
      final c = AdminShopContact.fromShop(_pageRow(phone: null));
      expect(c.phone, isNull);
      expect(c.dialablePhone, isNull);
      expect(c.phoneFromProfile, isFalse);
    });

    test('ayrı owner haritası (admin_get_owner_profile) profiles yerine kullanılır', () {
      final shop = _pageRow(phone: null)..remove('profiles');
      final c = AdminShopContact.fromShop(
        shop,
        owner: {'full_name': 'Ayşe', 'email': 'ayse@ornek.com', 'phone': '05551234567'},
      );
      expect(c.ownerName, 'Ayşe');
      expect(c.phone, '05551234567');
      expect(c.phoneFromProfile, isTrue);
    });

    test('konum sayı ya da metin olarak gelebilir; harita adresi üretilir', () {
      final c = AdminShopContact.fromShop(_pageRow(lat: '37.5', lng: '42.25'));
      expect(c.hasLocation, isTrue);
      expect(c.locationLabel, '37.50000, 42.25000');
      expect(c.mapsUri.toString(), contains('query=37.5,42.25'));
      expect(AdminShopContact.fromShop(_pageRow(lat: null)).hasLocation, isFalse);
    });

    test('hesap sahibi eski account_holder sütununa düşer', () {
      final shop = _pageRow()
        ..['account_holder_name'] = ''
        ..['account_holder'] = 'Eski Ad';
      expect(AdminShopContact.fromShop(shop).accountHolder, 'Eski Ad');
    });

    test('dükkan e-postası sahibinkiyle aynıysa ayrıca gösterilmez', () {
      final same = _pageRow()..['email'] = 'AHMET@ornek.com';
      expect(AdminShopContact.fromShop(same).showShopEmail, isFalse);
      expect(AdminShopContact.fromShop(_pageRow()).showShopEmail, isTrue);
    });

    test('IBAN 4\'erli gruplanır', () {
      expect(
        AdminShopContact.formatIban('tr12 0006400000112345678901'),
        'TR12 0006 4000 0011 2345 6789 01',
      );
    });
  });

  group('AdminShopContactRows', () {
    Future<void> pumpRows(WidgetTester tester, AdminShopContactRows rows) {
      return tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: rows))),
      );
    }

    testWidgets('telefon, adres, konum ve IBAN görünür; ara/kopyala düğmeleri var', (tester) async {
      await pumpRows(
        tester,
        AdminShopContactRows(contact: AdminShopContact.fromShop(_pageRow())),
      );
      expect(find.text('0532 111 22 33'), findsOneWidget);
      expect(find.text('Nuh Mah. Yafes Cad. No 5'), findsOneWidget);
      expect(find.text('37.32701, 42.19012'), findsOneWidget);
      expect(find.text('TR12 0006 4000 0011 2345 6789 01'), findsOneWidget);
      expect(find.text('Ziraat'), findsOneWidget);
      expect(find.text('dukkan@ornek.com'), findsOneWidget);
      expect(find.byTooltip('Ara'), findsOneWidget);
      expect(find.byTooltip('Haritada aç'), findsOneWidget);
      expect(find.byTooltip('Telefon kopyala'), findsOneWidget);
      expect(find.byTooltip('IBAN kopyala'), findsOneWidget);
      expect(find.text('Sahibin profilinden'), findsNothing);
    });

    testWidgets('profil telefonuna düşünce kaynak notu yazar', (tester) async {
      await pumpRows(
        tester,
        AdminShopContactRows(
          contact: AdminShopContact.fromShop(_pageRow(phone: null, ownerPhone: '05551234567')),
        ),
      );
      expect(find.text('05551234567'), findsOneWidget);
      expect(find.text('Sahibin profilinden'), findsOneWidget);
    });

    testWidgets('eksik alanlar "Girilmemiş" yazar, düğme çıkmaz', (tester) async {
      final empty = _pageRow(phone: null, lat: null)
        ..['address'] = null
        ..['iban'] = null
        ..['bank_name'] = null
        ..['account_holder_name'] = null;
      await pumpRows(
        tester,
        AdminShopContactRows(contact: AdminShopContact.fromShop(empty)),
      );
      // Telefon, adres, konum, IBAN
      expect(find.text('Girilmemiş'), findsNWidgets(4));
      expect(find.byTooltip('Ara'), findsNothing);
      expect(find.byTooltip('Haritada aç'), findsNothing);
      expect(find.text('Banka'), findsNothing);
    });

    testWidgets('bölümler ayrı ayrı kapatılabilir', (tester) async {
      await pumpRows(
        tester,
        AdminShopContactRows(
          contact: AdminShopContact.fromShop(_pageRow()),
          showOwner: false,
          showContact: false,
        ),
      );
      expect(find.text('Telefon'), findsNothing);
      expect(find.text('Sahibi'), findsNothing);
      expect(find.text('IBAN'), findsOneWidget);
    });
  });

  group('kaynak sözleşmesi', () {
    test('admin dükkan detayı satıcı telefonunu yalnız profilden okumaz', () {
      final src = File('lib/features/admin/screens/shop_detail_admin_screen.dart').readAsStringSync();
      expect(src.contains("_shopOwner?['phone']"), isFalse);
      // shops'ta "category" sütunu yok; eskiden hep "-" yazıyordu.
      expect(src.contains("_shop!['category']"), isFalse);
      expect(src.contains('AdminShopContactRows('), isTrue);
    });

    test('admin dükkan kartı ve penceresi ortak iletişim satırlarını kullanır', () {
      final src = File('lib/features/admin/screens/admin_dashboard_parts/_part_shops.dart').readAsStringSync();
      expect(src.contains('AdminShopContact.fromShop(shop).phone'), isTrue);
      expect(src.contains('AdminShopContactRows('), isTrue);
    });
  });
}
