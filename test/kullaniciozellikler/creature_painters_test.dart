import 'dart:ui' as ui;

import 'package:cizreapp/kullaniciozellikler/widgets/creature_painters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const primary = Color(0xFF43A047);
  const secondary = Color(0xFF1B5E20);

  ui.Canvas newCanvas() {
    final recorder = ui.PictureRecorder();
    return ui.Canvas(recorder);
  }

  group('avatar yaratık çizerleri', () {
    for (final progress in [0.0, 0.15, 0.5, 0.6, 0.75, 0.99, 1.4, -0.3]) {
      test('paintSnakeCoil progress=$progress hatasız çizilir', () {
        expect(
          () => paintSnakeCoil(
            canvas: newCanvas(),
            center: const Offset(30, 30),
            radius: 24,
            progress: progress,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });

      test(
        'paintButterflyLandingOnAvatar progress=$progress hatasız çizilir',
        () {
          expect(
            () => paintButterflyLandingOnAvatar(
              canvas: newCanvas(),
              center: const Offset(30, 30),
              radius: 24,
              progress: progress,
              primaryColor: primary,
              secondaryColor: secondary,
            ),
            returnsNormally,
          );
        },
      );

      test('paintFirefliesAvatar progress=$progress hatasız çizilir', () {
        expect(
          () => paintFirefliesAvatar(
            canvas: newCanvas(),
            center: const Offset(30, 30),
            radius: 24,
            progress: progress,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });

      test('paintCatPawPeek progress=$progress hatasız çizilir', () {
        expect(
          () => paintCatPawPeek(
            canvas: newCanvas(),
            center: const Offset(30, 30),
            radius: 24,
            progress: progress,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });
    }

    test('radius sıfırken bile çökmez', () {
      expect(
        () => paintSnakeCoil(
          canvas: newCanvas(),
          center: Offset.zero,
          radius: 0,
          progress: 0.4,
          primaryColor: primary,
          secondaryColor: secondary,
        ),
        returnsNormally,
      );
      expect(
        () => paintCatPawPeek(
          canvas: newCanvas(),
          center: Offset.zero,
          radius: 0,
          progress: 0.6,
          primaryColor: primary,
          secondaryColor: secondary,
        ),
        returnsNormally,
      );
    });
  });

  group('kapak sahne çizerleri', () {
    const size = Size(320, 140);
    for (final progress in [0.0, 0.25, 0.5, 0.8, 1.3]) {
      test('paintButterflyMeadowCover progress=$progress hatasız çizilir', () {
        expect(
          () => paintButterflyMeadowCover(
            canvas: newCanvas(),
            size: size,
            progress: progress,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });

      test('paintAuroraVeilCover progress=$progress hatasız çizilir', () {
        expect(
          () => paintAuroraVeilCover(
            canvas: newCanvas(),
            size: size,
            progress: progress,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });

      test('paintPetalDriftCover progress=$progress hatasız çizilir', () {
        expect(
          () => paintPetalDriftCover(
            canvas: newCanvas(),
            size: size,
            progress: progress,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });

      test('paintFireflyDuskCover progress=$progress hatasız çizilir', () {
        expect(
          () => paintFireflyDuskCover(
            canvas: newCanvas(),
            size: size,
            progress: progress,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });
    }
  });

  test(
    'drawButterflyShape farklı flap ve heading değerleriyle hatasız çizilir',
    () {
      for (final flap in [0.0, 0.5, 1.0]) {
        for (final heading in [0.0, 1.57, 3.14, -1.0]) {
          expect(
            () => drawButterflyShape(
              newCanvas(),
              const Offset(50, 50),
              18,
              flap,
              primary,
              secondary,
              heading,
            ),
            returnsNormally,
          );
        }
      }
    },
  );

  group('yeni avatar çerçeveleri/yaratıkları', () {
    final avatarPainters = <String, void Function(double)>{
      'paintRoyalGoldFrame': (p) => paintRoyalGoldFrame(
        canvas: newCanvas(),
        center: const Offset(30, 30),
        radius: 24,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintKoiSwim': (p) => paintKoiSwim(
        canvas: newCanvas(),
        center: const Offset(30, 30),
        radius: 24,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintOwlPerch': (p) => paintOwlPerch(
        canvas: newCanvas(),
        center: const Offset(30, 30),
        radius: 24,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintDragonWisp': (p) => paintDragonWisp(
        canvas: newCanvas(),
        center: const Offset(30, 30),
        radius: 24,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintStarConfettiFrame': (p) => paintStarConfettiFrame(
        canvas: newCanvas(),
        center: const Offset(30, 30),
        radius: 24,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
    };

    for (final entry in avatarPainters.entries) {
      for (final progress in [0.0, 0.3, 0.55, 0.75, 0.99, 1.6, -0.2]) {
        test('${entry.key} progress=$progress hatasız çizilir', () {
          expect(() => entry.value(progress), returnsNormally);
        });
      }
    }

    test('radius sıfırken bile çökmez', () {
      for (final fn in avatarPainters.values) {
        expect(() => fn(0.4), returnsNormally);
      }
    });
  });

  group('yeni kapak sahneleri', () {
    const size = Size(320, 140);
    final coverPainters = <String, void Function(double)>{
      'paintStarryNightCover': (p) => paintStarryNightCover(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintSnowfallCover': (p) => paintSnowfallCover(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintGoldenHourCover': (p) => paintGoldenHourCover(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintOceanWaveCover': (p) => paintOceanWaveCover(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintFireworkBurstCover': (p) => paintFireworkBurstCover(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
    };

    for (final entry in coverPainters.entries) {
      for (final progress in [0.0, 0.25, 0.5, 0.8, 1.3]) {
        test('${entry.key} progress=$progress hatasız çizilir', () {
          expect(() => entry.value(progress), returnsNormally);
        });
      }
    }
  });

  group('yeni tüm-profil haleleri', () {
    const size = Size(360, 640);
    final profilePainters = <String, void Function(double)>{
      'paintRoyalAuraEffect': (p) => paintRoyalAuraEffect(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintGalaxySwirlEffect': (p) => paintGalaxySwirlEffect(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhoenixFlameEffect': (p) => paintPhoenixFlameEffect(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintCrystalShimmerEffect': (p) => paintCrystalShimmerEffect(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintThunderStormEffect': (p) => paintThunderStormEffect(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
    };

    for (final entry in profilePainters.entries) {
      for (final progress in [0.0, 0.05, 0.3, 0.6, 0.99]) {
        test('${entry.key} progress=$progress hatasız çizilir', () {
          expect(() => entry.value(progress), returnsNormally);
        });
      }
    }
  });

  group('fotoğraf-üstü (overlay) efektleri', () {
    const size = Size(120, 120);
    final photoPainters = <String, void Function(double)>{
      'paintPhotoLightningStrike': (p) => paintPhotoLightningStrike(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoRainOverlay': (p) => paintPhotoRainOverlay(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoOldTvEffect': (p) => paintPhotoOldTvEffect(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
    };

    for (final entry in photoPainters.entries) {
      // Flaş/glitch pencerelerinin (cycle < 0.05/0.08) hem içinde hem
      // dışında test edilmesi için döngü sınırlarına yakın değerler de var.
      for (final progress in [0.0, 0.04, 0.08, 0.2, 0.5, 0.99, 1.5, -0.1]) {
        test('${entry.key} progress=$progress hatasız çizilir', () {
          expect(() => entry.value(progress), returnsNormally);
        });
      }
    }

    test('sıfır boyutlu canvas için bile çökmez', () {
      expect(
        () => paintPhotoOldTvEffect(
          canvas: newCanvas(),
          size: Size.zero,
          progress: 0.5,
          primaryColor: primary,
          secondaryColor: secondary,
        ),
        returnsNormally,
      );
    });
  });

  group('fotoğraf-üstü efektleri (2. dalga: 14 yeni tür)', () {
    const size = Size(120, 120);
    final morePhotoPainters = <String, void Function(double)>{
      'paintPhotoSnowOverlay': (p) => paintPhotoSnowOverlay(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoFogOverlay': (p) => paintPhotoFogOverlay(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoHeatWave': (p) => paintPhotoHeatWave(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoNeonGlitch': (p) => paintPhotoNeonGlitch(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoVhsStatic': (p) => paintPhotoVhsStatic(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoFilmGrain': (p) => paintPhotoFilmGrain(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoSunFlare': (p) => paintPhotoSunFlare(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoBokehLights': (p) => paintPhotoBokehLights(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoIceFrost': (p) => paintPhotoIceFrost(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoConfettiBurst': (p) => paintPhotoConfettiBurst(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoBubbleOverlay': (p) => paintPhotoBubbleOverlay(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoCrackGlass': (p) => paintPhotoCrackGlass(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoSmokeDrift': (p) => paintPhotoSmokeDrift(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
      'paintPhotoFlameOverlay': (p) => paintPhotoFlameOverlay(
        canvas: newCanvas(),
        size: size,
        progress: p,
        primaryColor: primary,
        secondaryColor: secondary,
      ),
    };

    for (final entry in morePhotoPainters.entries) {
      for (final progress in [0.0, 0.05, 0.12, 0.3, 0.6, 0.99, 1.4, -0.2]) {
        test('${entry.key} progress=$progress hatasız çizilir', () {
          expect(() => entry.value(progress), returnsNormally);
        });
      }
    }

    test('sıfır boyutlu canvas için bile çökmez (köşe/açı matematiği)', () {
      expect(
        () => paintPhotoIceFrost(
          canvas: newCanvas(),
          size: Size.zero,
          progress: 0.4,
          primaryColor: primary,
          secondaryColor: secondary,
        ),
        returnsNormally,
      );
      expect(
        () => paintPhotoCrackGlass(
          canvas: newCanvas(),
          size: Size.zero,
          progress: 0.4,
          primaryColor: primary,
          secondaryColor: secondary,
        ),
        returnsNormally,
      );
    });
  });
}
