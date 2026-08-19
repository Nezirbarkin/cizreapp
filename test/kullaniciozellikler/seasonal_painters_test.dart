import 'dart:ui' as ui;

import 'package:cizreapp/kullaniciozellikler/widgets/renderer_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-19'da eklenen dekorasyonlar (dolu, karınca, kiraz çiçeği, meteor,
/// yeni çerçeveler...) yalnız çalışma anında çizildiği için derleme bunları
/// doğrulamaz. Bu test her kayıtlı çizeri uç değerlerde gerçek bir canvas'a
/// çizerek shader/bölme hatalarını yakalar.
void main() {
  const primary = Color(0xFF4FC3F7);
  const secondary = Color(0xFF0277BD);

  // Uç durumlar: sıfır/negatif ilerleme, tam tur, tur aşımı ve dejenere boyut.
  const progresses = [0.0, 0.01, 0.33, 0.5, 0.82, 0.99, 1.0, 1.7, -0.4];

  ui.Canvas newCanvas() => ui.Canvas(ui.PictureRecorder());

  group('yüzey çizerleri (registry)', () {
    for (final entry in kSurfaceRenderers.entries) {
      for (final progress in progresses) {
        test('${entry.key} progress=$progress hatasız çizilir', () {
          expect(
            () => entry.value(
              canvas: newCanvas(),
              size: const Size(120, 90),
              progress: progress,
              primaryColor: primary,
              secondaryColor: secondary,
            ),
            returnsNormally,
          );
        });
      }

      test('${entry.key} çok küçük yüzeyde hatasız çizilir', () {
        expect(
          () => entry.value(
            canvas: newCanvas(),
            size: const Size(1, 1),
            progress: 0.5,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });
    }
  });

  group('çerçeve çizerleri (registry)', () {
    for (final entry in kFrameRenderers.entries) {
      for (final progress in progresses) {
        test('${entry.key} progress=$progress hatasız çizilir', () {
          expect(
            () => entry.value(
              canvas: newCanvas(),
              center: const Offset(40, 40),
              radius: 32,
              progress: progress,
              primaryColor: primary,
              secondaryColor: secondary,
            ),
            returnsNormally,
          );
        });
      }

      test('${entry.key} sıfıra yakın yarıçapta hatasız çizilir', () {
        expect(
          () => entry.value(
            canvas: newCanvas(),
            center: Offset.zero,
            radius: 0.01,
            progress: 0.5,
            primaryColor: primary,
            secondaryColor: secondary,
          ),
          returnsNormally,
        );
      });
    }
  });

  group('registry sözleşmesi', () {
    test('yüzey ve çerçeve defterleri çakışmaz', () {
      final overlap = kSurfaceRenderers.keys.toSet().intersection(
        kFrameRenderers.keys.toSet(),
      );
      expect(overlap, isEmpty);
    });

    test('kayıtlı olmayan key için tryPaint* false döner', () {
      expect(
        tryPaintSurface(
          rendererKey: 'boyle_bir_sey_yok',
          canvas: newCanvas(),
          size: const Size(10, 10),
          progress: 0.5,
          primaryColor: primary,
          secondaryColor: secondary,
        ),
        isFalse,
      );
      expect(
        tryPaintFrame(
          rendererKey: 'boyle_bir_sey_yok',
          canvas: newCanvas(),
          center: Offset.zero,
          radius: 10,
          progress: 0.5,
          primaryColor: primary,
          secondaryColor: secondary,
        ),
        isFalse,
      );
    });

    test('avatar yüzey efektleri photo_ önekiyle başlar', () {
      // privileged_avatar.dart yüzey/çerçeve ayrımını rendererKey'in "photo_"
      // ile başlamasına göre yapıyor; yeni yüzey çizerleri bu kurala uymazsa
      // avatar tarafında çerçeve painter'ına düşer ve hiç çizilmez.
      for (final key in kSurfaceRenderers.keys) {
        expect(key.startsWith('photo_'), isTrue, reason: key);
      }
    });
  });
}
