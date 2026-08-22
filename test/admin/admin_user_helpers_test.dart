// =============================================================================
// AdminUserHelpers birim testi
// Kullanım: flutter test test/admin/admin_user_helpers_test.dart
//
// Kart widget'ı admin_dashboard_screen.dart kütüphanesinin bir `part`'ı
// olduğu için doğrudan test edilemiyor; saf mantık AdminUserHelpers'a
// çıkarıldı ve burada kapsanır.
// =============================================================================

import 'package:cizreapp/features/admin/utils/admin_user_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminUserHelpers.isValidAvatarUrl', () {
    test('tam https storage URL true döner', () {
      expect(
        AdminUserHelpers.isValidAvatarUrl(
          'https://x.supabase.co/storage/v1/object/public/avatars/a.jpg',
        ),
        isTrue,
      );
    });

    test('http URL true döner', () {
      expect(
        AdminUserHelpers.isValidAvatarUrl('http://example.com/a.png'),
        isTrue,
      );
    });

    test('null / boş / boşluk / göreli yol false döner', () {
      expect(AdminUserHelpers.isValidAvatarUrl(null), isFalse);
      expect(AdminUserHelpers.isValidAvatarUrl(''), isFalse);
      expect(AdminUserHelpers.isValidAvatarUrl('   '), isFalse);
      expect(AdminUserHelpers.isValidAvatarUrl('avatars/a.jpg'), isFalse);
      expect(AdminUserHelpers.isValidAvatarUrl('/storage/v1/a.jpg'), isFalse);
    });

    test('baştaki/sondaki boşluk düzeltilir', () {
      expect(
        AdminUserHelpers.isValidAvatarUrl('  https://x.co/a.jpg  '),
        isTrue,
      );
    });
  });

  group('AdminUserHelpers.formatStatCount', () {
    test('1000 altı düz sayı', () {
      expect(AdminUserHelpers.formatStatCount(0), '0');
      expect(AdminUserHelpers.formatStatCount(1), '1');
      expect(AdminUserHelpers.formatStatCount(999), '999');
    });

    test('binler B ile (gereksiz .0 yok)', () {
      expect(AdminUserHelpers.formatStatCount(1000), '1B');
      expect(AdminUserHelpers.formatStatCount(1500), '1.5B');
      expect(AdminUserHelpers.formatStatCount(10000), '10B');
      expect(AdminUserHelpers.formatStatCount(12500), '12.5B');
      expect(AdminUserHelpers.formatStatCount(999999), '1000B');
    });

    test('milyonlar Mn ile', () {
      expect(AdminUserHelpers.formatStatCount(1000000), '1Mn');
      expect(AdminUserHelpers.formatStatCount(1500000), '1.5Mn');
    });

    test('num (double) girdisi int\'e iner', () {
      expect(AdminUserHelpers.formatStatCount(1500.0), '1.5B');
      expect(AdminUserHelpers.formatStatCount(42.9), '42');
    });
  });

  group('AdminUserHelpers.formatLastSeen', () {
    final now = DateTime(2026, 8, 10, 12, 0);

    test('null -> "-"', () {
      expect(AdminUserHelpers.formatLastSeen(null, now: now), '-');
    });

    test('negatif fark (saat sapması) -> "az önce"', () {
      expect(
        AdminUserHelpers.formatLastSeen(
          now.add(const Duration(minutes: 5)),
          now: now,
        ),
        'az önce',
      );
    });

    test('dakika / saat / gün etiketleri', () {
      expect(
        AdminUserHelpers.formatLastSeen(
          now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        '5 dk önce',
      );
      expect(
        AdminUserHelpers.formatLastSeen(
          now.subtract(const Duration(hours: 3)),
          now: now,
        ),
        '3 sa önce',
      );
      expect(
        AdminUserHelpers.formatLastSeen(
          now.subtract(const Duration(days: 2)),
          now: now,
        ),
        '2 gün önce',
      );
    });

    test('30+ gün -> gg.aa.yyyy', () {
      final old = DateTime(2026, 1, 5, 9, 30);
      expect(AdminUserHelpers.formatLastSeen(old, now: now), '05.01.2026');
    });
  });

  group('AdminUserHelpers.isNewMember', () {
    final now = DateTime(2026, 8, 10, 12, 0);

    test('null -> false', () {
      expect(AdminUserHelpers.isNewMember(null, now: now), isFalse);
    });

    test('6 gün önce -> true', () {
      expect(
        AdminUserHelpers.isNewMember(
          now.subtract(const Duration(days: 6)),
          now: now,
        ),
        isTrue,
      );
    });

    test('7 gün önce -> false', () {
      expect(
        AdminUserHelpers.isNewMember(
          now.subtract(const Duration(days: 7)),
          now: now,
        ),
        isFalse,
      );
    });

    test('gelecek tarih (saat sapması) -> true', () {
      expect(
        AdminUserHelpers.isNewMember(
          now.add(const Duration(minutes: 1)),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('AdminUserHelpers.initialOf', () {
    test('username tercih edilir', () {
      expect(AdminUserHelpers.initialOf('ahmet', 'Ahmet Yılmaz'), 'A');
    });

    test('username boşsa full_name kullanılır', () {
      expect(AdminUserHelpers.initialOf('  ', 'Zeynep'), 'Z');
    });

    test('ikisi de boş -> ?', () {
      expect(AdminUserHelpers.initialOf(null, null), '?');
      expect(AdminUserHelpers.initialOf('', ''), '?');
    });

    test('harf büyütülür', () {
      expect(AdminUserHelpers.initialOf('mehmet', null), 'M');
    });
  });
}
