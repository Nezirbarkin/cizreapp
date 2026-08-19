import 'package:cizreapp/kullaniciozellikler/models/profile_feature.dart';
import 'package:cizreapp/kullaniciozellikler/widgets/privileged_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

ProfileFeature _feature(String rendererKey) {
  return ProfileFeature.fromMap({
    'feature_id': 'f-$rendererKey',
    'kind': 'avatar_effect',
    'name': rendererKey,
    'renderer_key': rendererKey,
    'primary_color': '#43A047',
    'secondary_color': '#1B5E20',
    'config': const {'speed': 1.0},
    'priority': 1,
  });
}

void main() {
  group('isPhotoOverlayEffect', () {
    test('photo_ önekli renderer_key overlay olarak tanınır', () {
      expect(isPhotoOverlayEffect(_feature('photo_lightning_strike')), isTrue);
      expect(isPhotoOverlayEffect(_feature('photo_rain_overlay')), isTrue);
      expect(isPhotoOverlayEffect(_feature('photo_old_tv')), isTrue);
    });

    test('çerçeve/yaratık renderer_key overlay olarak tanınmaz', () {
      expect(isPhotoOverlayEffect(_feature('snake_coil')), isFalse);
      expect(isPhotoOverlayEffect(_feature('royal_gold_frame')), isFalse);
      expect(isPhotoOverlayEffect(_feature('avatar_procedural')), isFalse);
    });
  });
}
