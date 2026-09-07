import 'package:cizreapp/okey/admin/okey_admin_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// SES DOSYASI FORMAT DOĞRULAMASI
///
/// GEÇMİŞ: Dosya seçiciye `FileType.custom` + `allowedExtensions` veriliyordu.
/// Android bu durumda uzantıyı MIME türüne çevirip filtreliyor; `.m4a`
/// dosyaları cihaza göre `audio/mp4`, `audio/x-m4a` ya da başka bir tür
/// raporladığı için seçicide SOLUK kalıp seçilemiyordu — kullanıcı şarkıyı
/// hiç seçemiyordu.
///
/// Çözüm: seçici artık tüm dosyaları gösteriyor, doğrulamayı bu saf fonksiyon
/// yapıyor. Bu testler o doğrulamanın .m4a'yı kabul ettiğini ve alakasız
/// dosyaları reddettiğini sabitler.
void main() {
  group('Desteklenen ses formatları', () {
    test('.m4a KABUL EDİLİR', () {
      expect(
        OkeyAdminService.isSupportedAudio('sarki.m4a'),
        isTrue,
        reason: 'kullanıcının şikâyeti tam olarak buydu',
      );
    });

    test('yaygın ses formatlarının hepsi kabul edilir', () {
      for (final ext in OkeyAdminService.supportedAudioExtensions) {
        expect(
          OkeyAdminService.isSupportedAudio('dosya.$ext'),
          isTrue,
          reason: '.$ext reddedildi',
        );
      }
    });

    test('BÜYÜK HARFLİ uzantı da kabul edilir', () {
      expect(OkeyAdminService.isSupportedAudio('Sarki.M4A'), isTrue);
      expect(OkeyAdminService.isSupportedAudio('SES.MP3'), isTrue);
    });

    test('ses olmayan dosyalar reddedilir', () {
      expect(OkeyAdminService.isSupportedAudio('belge.pdf'), isFalse);
      expect(OkeyAdminService.isSupportedAudio('resim.png'), isFalse);
      expect(
        OkeyAdminService.isSupportedAudio('video.mp4'),
        isFalse,
        reason: 'mp4 video kabı; ses için m4a beklenir',
      );
    });

    test('uzantısız dosya reddedilir', () {
      expect(OkeyAdminService.isSupportedAudio('uzantisiz'), isFalse);
      expect(OkeyAdminService.isSupportedAudio('nokta.'), isFalse);
    });

    test('adında birden çok nokta olan dosyada SON uzantı sayılır', () {
      expect(OkeyAdminService.isSupportedAudio('benim.sarkim.v2.m4a'), isTrue);
      expect(
        OkeyAdminService.isSupportedAudio('sarki.m4a.txt'),
        isFalse,
        reason: 'gerçek uzantı .txt — kabul edilmemeli',
      );
    });

    test('extensionOf uzantıyı küçük harfe çevirir', () {
      expect(OkeyAdminService.extensionOf('A.M4A'), 'm4a');
      expect(OkeyAdminService.extensionOf('yok'), '');
    });

    test('kullanıcıya gösterilen liste .m4a içerir', () {
      expect(OkeyAdminService.supportedAudioLabel, contains('m4a'));
    });
  });
}
