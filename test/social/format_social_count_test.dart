import 'package:cizreapp/features/social/widgets/social_post_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatSocialCount: Türkçe virgül, aşağı yuvarlama, ",0" yok', () {
    expect(formatSocialCount(0), '0');
    expect(formatSocialCount(999), '999');
    expect(formatSocialCount(1000), '1B');
    expect(formatSocialCount(1050), '1B');
    expect(formatSocialCount(1250), '1,2B');
    expect(formatSocialCount(12345), '12,3B');
    expect(formatSocialCount(125400), '125B');
    expect(formatSocialCount(999999), '999B'); // "1000B" değil
    expect(formatSocialCount(1000000), '1Mn');
    expect(formatSocialCount(2345678), '2,3Mn');
    expect(formatSocialCount(-5), '-5');
  });
}
