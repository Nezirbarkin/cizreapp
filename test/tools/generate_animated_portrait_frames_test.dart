// Hareketli PORTRE avatarlarının karelerini üretir (test DEĞİL, bir üretim aracı).
//
//   $env:GEN_ANIMATED_PORTRAITS='1'; flutter test test/tools/generate_animated_portrait_frames_test.dart
//   python scripts/generate_animated_portraits.py
//
// Her portre için `build/anim_frames/pNN/fMM.png` (şeffaf arka planlı, 384 px)
// yazar: hafif sallanma, nefes alma ve döngünün sonunda göz kırpma. Python
// betiği bunları hareketli bir arka planın üstüne oturtup GIF'e çevirir.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cizreapp/features/profile/models/character_avatar_recipes.dart';
import 'package:cizreapp/features/profile/widgets/face_avatar_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hareketlendirilecek karakterlerin tarif numaraları (1'den başlar).
/// Sıra = çıktı sırası; BU LİSTEYE YALNIZCA SONA EKLENİR.
const List<int> kPortraitRecipes = [
  51, 52, 53, 56, 75, 80, 81, 85, 86, 91, 92, 95,
];

const int kFrames = 20;

void main() {
  testWidgets('hareketli portre karelerini üret', (tester) async {
    if (Platform.environment['GEN_ANIMATED_PORTRAITS'] != '1') return;
    final root = Directory(Platform.environment['ANIM_FRAMES_DIR'] ?? 'build/anim_frames')
      ..createSync(recursive: true);
    await tester.runAsync(() async {
      for (var p = 0; p < kPortraitRecipes.length; p++) {
        final cfg = kCharacterRecipes[kPortraitRecipes[p] - 1].config;
        final dir = Directory('${root.path}/p${(p + 1).toString().padLeft(2, '0')}')
          ..createSync(recursive: true);
        for (var f = 0; f < kFrames; f++) {
          final t = f / kFrames;
          final blink = switch (f) { 14 => 0.55, 15 => 1.0, 16 => 0.5, _ => 0.0 };
          final rec = ui.PictureRecorder();
          FaceAvatarPainter(
            cfg,
            transparent: true,
            blink: blink,
            sway: 0.028 * math.sin(2 * math.pi * t),
            bob: 1.3 * math.sin(2 * math.pi * t + 1.2),
          ).paint(ui.Canvas(rec), const ui.Size(384, 384));
          final img = await rec.endRecording().toImage(384, 384);
          final bd = await img.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/f${f.toString().padLeft(2, '0')}.png')
              .writeAsBytesSync(bd!.buffer.asUint8List());
        }
      }
    });
  });
}
