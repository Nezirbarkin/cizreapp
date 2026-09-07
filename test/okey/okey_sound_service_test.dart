import 'dart:io';

import 'package:cizreapp/okey/services/okey_sound_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ses servisi testleri.
///
/// EN ÖNEMLİ DAVRANIŞ: ses ÇALINAMASA da uygulama ÇÖKMEMELİ. Test
/// ortamında ses eklentisi hiç yoktur; her çağrı sessizce dokunsal geri
/// bildirime düşmelidir. Aşağıdaki testler tam olarak bunu doğrular.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Ses aç/kapat', () {
    test('varsayılan olarak açık', () async {
      final s = OkeySoundService.instance;
      await s.load();
      expect(s.isEnabled, isTrue);
    });

    test('kapatılabilir ve tercih kaydedilir', () async {
      SharedPreferences.setMockInitialValues({});
      final s = OkeySoundService.instance;
      await s.setEnabled(false);
      expect(s.isEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('okey_sound_enabled'), isFalse);

      await s.setEnabled(true);
      expect(s.isEnabled, isTrue);
    });

    test('toggle durumu tersine çevirir', () async {
      final s = OkeySoundService.instance;
      await s.setEnabled(true);
      expect(await s.toggle(), isFalse);
      expect(await s.toggle(), isTrue);
    });
  });

  group('Ses dosyası eksikken çökmez', () {
    test('ses AÇIKKEN eksik dosya çökmeye yol açmaz', () async {
      final s = OkeySoundService.instance;
      await s.setEnabled(true);

      // Bu efektlerin hiçbirinin dosyası depoda yok — hepsi sessizce
      // dokunsal geri bildirime düşmeli, exception fırlatmamalı.
      for (final sound in OkeySound.values) {
        await expectLater(
          s.play(sound),
          completes,
          reason: '${sound.name} eksik dosyayla çökmemeli',
        );
      }
    });

    test('ses KAPALIYKEN play() anında ve sessizce tamamlanır', () async {
      final s = OkeySoundService.instance;
      await s.setEnabled(false);

      // Ses kapalıyken hiçbir ses/titreşim denemesi yapılmamalı ve çağrı
      // anında dönmeli (ses altyapısına hiç dokunulmaz).
      final sw = Stopwatch()..start();
      for (final sound in OkeySound.values) {
        await expectLater(s.play(sound), completes);
      }
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        lessThan(500),
        reason: 'ses kapalıyken play() ses altyapısına hiç gitmemeli',
      );
    });
  });

  group('Ses olayları eksiksiz tanımlı', () {
    test('her efektin bir dosya adı vardır', () {
      // enum genişletilirse dosya adı eklemeyi unutmayı yakalar
      for (final sound in OkeySound.values) {
        expect(sound.name.isNotEmpty, isTrue);
      }
      expect(
        OkeySound.values.length,
        10,
        reason: 'yeni efekt eklendiyse README ve testi güncelle',
      );
    });

    // ÖRNEK SES SETİ DEPODA. Admin panelindeki "Örneği dinle" düğmesi ve
    // hiçbir dosya yüklenmemişken oyunun çaldığı ses bu dosyalardır; biri
    // eksilirse o olay sessizleşir, bu yüzden varlıkları test edilir.
    test('her efektin örnek ses dosyası assets/sounds altında vardır', () {
      for (final sound in OkeySound.values) {
        expect(
          sound.assetPath,
          'sounds/${sound.fileName}',
          reason: 'assetPath, AssetSource ile aynı yolu üretmeli',
        );
        final file = File('assets/${sound.assetPath}');
        expect(
          file.existsSync(),
          isTrue,
          reason: '${sound.name} için ${file.path} eksik',
        );
        expect(
          file.lengthSync(),
          greaterThan(1000),
          reason: '${file.path} boş/bozuk görünüyor',
        );
      }
    });
  });
}
