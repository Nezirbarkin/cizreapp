// "Kız & Erkek" hazır avatar PNG'lerini üretir (test DEĞİL, bir üretim aracı).
//
//   $env:GEN_CHARACTER_AVATARS='1'; flutter test test/tools/generate_character_avatars_test.dart
//   python scripts/finalize_character_avatars.py
//
// Çıktı `build/avatar_raw/char_NN.png` (512 px). `finalize_character_avatars.py`
// bunları küçültüp renk sayısını düşürerek `assets/avatars_characters/` altına
// yazar. Ortam değişkeni yoksa hiçbir şey yapmadan geçer, böylece normal test
// çalıştırmalarında dosya üretmez.
import 'dart:io';

import 'package:cizreapp/features/profile/models/character_avatar_recipes.dart';
import 'package:cizreapp/features/profile/widgets/face_avatar_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tarif sayısı ve cinsiyet dağılımı', () {
    expect(kCharacterRecipes.length, 100);
    expect(kCharacterRecipes.where((r) => r.female).length, 50);
  });

  testWidgets('karakter avatarlarını üret', (tester) async {
    if (Platform.environment['GEN_CHARACTER_AVATARS'] != '1') return;
    final dir = Directory(Platform.environment['AVATAR_RAW_DIR'] ?? 'build/avatar_raw')
      ..createSync(recursive: true);
    await tester.runAsync(() async {
      for (var i = 0; i < kCharacterRecipes.length; i++) {
        final bytes = await renderFaceAvatarToPng(kCharacterRecipes[i].config, size: 512);
        File('${dir.path}/char_${(i + 1).toString().padLeft(2, '0')}.png').writeAsBytesSync(bytes);
      }
    });
  });
}
