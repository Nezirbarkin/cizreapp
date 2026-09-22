import 'package:cizreapp/features/admin/widgets/admin_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('adminCompact', () {
    test('binlik ayraç kullanır, "B" kısaltması üretmez', () {
      expect(adminCompact(0), '0');
      expect(adminCompact(999), '999');
      expect(adminCompact(1290), '1.290');
      expect(adminCompact(5312), '5.312');
      expect(adminCompact(123456), '123.456');
    });

    test('milyondan sonra "Mn" kullanır', () {
      expect(adminCompact(1200000), '1,2 Mn');
    });
  });

  group('adminDuration', () {
    test('saniye, dakika ve saat biçimleri', () {
      expect(adminDuration(40), '40 sn');
      expect(adminDuration(12 * 60), '12 dk');
      expect(adminDuration(3600), '1 sa');
      expect(adminDuration(3600 + 5 * 60), '1 sa 5 dk');
    });
  });

  group('adminTimeAgo', () {
    test('null tire döner, yakın zaman "şimdi"', () {
      expect(adminTimeAgo(null), '-');
      expect(adminTimeAgo(DateTime.now()), 'şimdi');
    });

    test('dakika ve saat', () {
      expect(
        adminTimeAgo(DateTime.now().subtract(const Duration(minutes: 5))),
        '5 dk önce',
      );
      expect(
        adminTimeAgo(DateTime.now().subtract(const Duration(hours: 3))),
        '3 sa önce',
      );
    });
  });

  group('adminDisplayName', () {
    test('ad-soyad, yoksa kullanıcı adı, yoksa silinmiş', () {
      expect(adminDisplayName({'full_name': 'Ayşe', 'username': 'ayse'}), 'Ayşe');
      expect(adminDisplayName({'full_name': ' ', 'username': 'ayse'}), 'ayse');
      expect(adminDisplayName({}), 'Silinmiş kullanıcı');
    });
  });

  group('adminActionStyle', () {
    test('bilinmeyen eylem ham adıyla gösterilir, balance_* bakiye olur', () {
      expect(adminActionStyle('yeni_bir_eylem').label, 'yeni_bir_eylem');
      expect(adminActionStyle('balance_topup').label, 'Bakiye');
      expect(adminActionStyle('login').label, 'Giriş');
    });
  });
}
