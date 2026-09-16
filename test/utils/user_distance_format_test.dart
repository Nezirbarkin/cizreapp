// Dükkan kartlarındaki uzaklık etiketinin biçimini kilitler.
//
// Ürün kuralı (kullanıcı talebi): 1 km ALTINDA metre, 1 km ÜSTÜNDE km
// gösterilir. Bu testler eşik davranışını ve Türkçe ondalık ayıracını
// (virgül) korur — biçim değişirse kart okunabilirliği bozulur.

import 'package:flutter_test/flutter_test.dart';

import 'package:cizreapp/core/services/user_distance_service.dart';

void main() {
  group('UserDistanceService.format', () {
    test('1 km altı metre olarak gösterilir', () {
      expect(UserDistanceService.format(0), '0 m');
      expect(UserDistanceService.format(85), '85 m');
      expect(UserDistanceService.format(850), '850 m');
    });

    test('metre değeri yuvarlanır, ondalık gösterilmez', () {
      expect(UserDistanceService.format(123.4), '123 m');
      expect(UserDistanceService.format(123.6), '124 m');
    });

    test('1 km eşiği ve üstü km olarak gösterilir', () {
      expect(UserDistanceService.format(999), '999 m');
      expect(UserDistanceService.format(1000), '1,0 km');
      expect(UserDistanceService.format(1200), '1,2 km');
    });

    test('10 km altında tek ondalık, üstünde tam sayı kullanılır', () {
      expect(UserDistanceService.format(9500), '9,5 km');
      expect(UserDistanceService.format(12000), '12 km');
    });

    test('ondalık ayıracı Türkçe virgüldür', () {
      expect(UserDistanceService.format(2500), contains(','));
      expect(UserDistanceService.format(2500), isNot(contains('.')));
    });
  });
}
