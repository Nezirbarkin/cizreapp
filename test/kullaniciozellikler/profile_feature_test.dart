import 'package:cizreapp/kullaniciozellikler/models/profile_feature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileFeature', () {
    test('Supabase RPC haritasını doğru modele çevirir', () {
      final feature = ProfileFeature.fromMap({
        'assignment_id': 'assignment-1',
        'feature_id': 'feature-1',
        'code': 'badge_blue_verified',
        'kind': 'badge',
        'name': 'Mavi Tik',
        'description': 'Kimliği doğrulanmış kullanıcı',
        'renderer_key': 'verified',
        'primary_color': '#2196F3',
        'secondary_color': '#64B5F6',
        'config': {'animated': true, 'speed': 1.5},
        'priority': 200,
        'is_enabled': true,
        'starts_at': '2026-08-14T10:00:00Z',
      });

      expect(feature.kind, ProfileFeatureKind.badge);
      expect(feature.primaryColor.toARGB32(), 0xFF2196F3);
      expect(feature.configDouble('speed', 0), 1.5);
      expect(feature.isEnabled, isTrue);
      expect(feature.startsAt, isNotNull);
    });

    test('bilinmeyen türü ikon olarak güvenli biçimde ele alır', () {
      final feature = ProfileFeature.fromMap({
        'id': 'feature-2',
        'kind': 'unexpected',
        'renderer_key': 'fan',
      });

      expect(feature.kind, ProfileFeatureKind.icon);
      expect(feature.name, 'Özellik');
      expect(feature.primaryColor.toARGB32(), 0xFF2196F3);
    });

    test('avatar_effect türünü avatar efekti olarak çözümler', () {
      final feature = ProfileFeature.fromMap({
        'feature_id': 'avatar-feature-1',
        'kind': 'avatar_effect',
        'name': 'Neon Halka',
        'renderer_key': 'neon_ring',
        'config': {'thickness': 2.5},
      });

      expect(feature.kind, ProfileFeatureKind.avatarEffect);
      expect(feature.configDouble('thickness', 0), 2.5);
    });

    test('kullanıcı katalog ve sahiplik alanlarını çözümler', () {
      final feature = ProfileFeature.fromMap({
        'feature_id': 'claimable-1',
        'kind': 'icon',
        'renderer_key': 'school',
        'is_user_claimable': true,
        'is_claimed': true,
        'is_self_claimed': true,
        'is_enabled': true,
      });

      expect(feature.isUserClaimable, isTrue);
      expect(feature.isClaimed, isTrue);
      expect(feature.isSelfClaimed, isTrue);
    });

    test('cover_effect türünü kapak efekti olarak çözümler', () {
      final feature = ProfileFeature.fromMap({
        'feature_id': 'cover-feature-1',
        'kind': 'cover_effect',
        'name': 'Kelebek Çayırı',
        'renderer_key': 'butterfly_meadow_cover',
      });

      expect(feature.kind, ProfileFeatureKind.coverEffect);
    });

    test('satın alma puanı ve plan alanlarını çözümler', () {
      final feature = ProfileFeature.fromMap({
        'feature_id': 'purchasable-1',
        'kind': 'avatar_effect',
        'renderer_key': 'snake_coil',
        'points_price_monthly': 5990,
        'points_price_yearly': 54900,
        'purchase_plan': 'monthly',
        'purchased_points': 5990,
        'is_purchased': true,
      });

      expect(feature.pointsPriceMonthly, 5990);
      expect(feature.pointsPriceYearly, 54900);
      expect(feature.purchasePlan, 'monthly');
      expect(feature.purchasedPoints, 5990);
      expect(feature.isPurchased, isTrue);
    });

    test('puan alanları yoksa null kalır (geriye dönük uyumluluk)', () {
      final feature = ProfileFeature.fromMap({
        'feature_id': 'free-1',
        'kind': 'icon',
        'renderer_key': 'school',
      });

      expect(feature.pointsPriceMonthly, isNull);
      expect(feature.pointsPriceYearly, isNull);
      expect(feature.purchasePlan, isNull);
      expect(feature.purchasedPoints, isNull);
      expect(feature.isPurchased, isFalse);
    });
  });
}
