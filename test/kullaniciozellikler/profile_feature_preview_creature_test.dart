import 'package:cizreapp/kullaniciozellikler/models/profile_feature.dart';
import 'package:cizreapp/kullaniciozellikler/widgets/profile_feature_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProfileFeature _feature({required String kind, required String rendererKey}) {
  return ProfileFeature.fromMap({
    'feature_id': 'f-$rendererKey',
    'kind': kind,
    'name': rendererKey,
    'description': 'test',
    'renderer_key': rendererKey,
    'primary_color': '#43A047',
    'secondary_color': '#1B5E20',
    'config': const {'speed': 1.0},
    'priority': 1,
  });
}

void main() {
  final avatarRenderers = [
    'snake_coil',
    'butterfly_land',
    'firefly_dance',
    'cat_paw_peek',
    'royal_gold_frame',
    'koi_swim',
    'owl_perch',
    'dragon_wisp',
    'star_confetti_frame',
    'photo_lightning_strike',
    'photo_rain_overlay',
    'photo_old_tv',
    'photo_snow_overlay',
    'photo_fog_overlay',
    'photo_heat_wave',
    'photo_neon_glitch',
    'photo_vhs_static',
    'photo_film_grain',
    'photo_sun_flare',
    'photo_bokeh_lights',
    'photo_ice_frost',
    'photo_confetti_burst',
    'photo_bubble_overlay',
    'photo_crack_glass',
    'photo_smoke_drift',
    'photo_flame_overlay',
  ];
  final coverRenderers = [
    'butterfly_meadow_cover',
    'aurora_veil_cover',
    'petal_drift_cover',
    'firefly_dusk_cover',
    'starry_night_cover',
    'snowfall_cover',
    'golden_hour_cover',
    'ocean_wave_cover',
    'firework_burst_cover',
  ];
  final profileWideRenderers = [
    'royal_aura',
    'galaxy_swirl',
    'phoenix_flame',
    'crystal_shimmer',
    'thunder_storm',
  ];

  for (final renderer in avatarRenderers) {
    testWidgets(
      'ProfileFeaturePreview avatar_effect/$renderer hatasız build olur',
      (tester) async {
        final feature = _feature(kind: 'avatar_effect', rendererKey: renderer);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: ProfileFeaturePreview(feature: feature)),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(seconds: 3));

        expect(find.byType(ProfileFeaturePreview), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final renderer in coverRenderers) {
    testWidgets(
      'ProfileFeaturePreview cover_effect/$renderer hatasız build olur',
      (tester) async {
        final feature = _feature(kind: 'cover_effect', rendererKey: renderer);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 120,
                  child: ProfileFeaturePreview(feature: feature, size: 120),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(seconds: 3));

        expect(find.byType(ProfileFeaturePreview), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final renderer in profileWideRenderers) {
    testWidgets('ProfileFeaturePreview effect/$renderer hatasız build olur', (
      tester,
    ) async {
      final feature = _feature(kind: 'effect', rendererKey: renderer);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: ProfileFeaturePreview(feature: feature, size: 200),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(ProfileFeaturePreview), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
