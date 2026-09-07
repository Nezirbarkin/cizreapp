import 'dart:typed_data';

import 'package:cizreapp/okey/admin/okey_admin_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADMİN PANELİ — DOSYA TANIMA VE HATA MESAJLARI
///
/// İki ayrı hata sınıfını sabitler:
///
/// 1. DOSYA ADINA GÜVENMEK. Android'de galeriden ya da bir bulut
///    sağlayıcısından seçilen dosya çoğu zaman uzantısız bir adla geliyor
///    (`image:1000000034`, `document`). Yalnızca ada bakan doğrulama bu
///    dosyaları "Desteklenmeyen dosya" diye reddediyor, admin geçerli bir
///    fotoğrafı yükleyemiyordu. Artık ad yetmediğinde İÇERİĞE bakılır.
///
/// 2. HAM VERİTABANI HATASI GÖSTERMEK. Panel her hatayı `Hata: $e` diye
///    basıyordu; ekranda `PostgrestException(message: APP:forbidden, ...)`
///    çıkıyor, admin ne yapacağını anlamıyordu.
void main() {
  Uint8List bytes(List<int> head, {int pad = 32}) =>
      Uint8List.fromList([...head, ...List<int>.filled(pad, 0)]);

  group('Görsel içeriğinden tanınır', () {
    test('JPEG imzası', () {
      expect(
        OkeyAdminService.sniffImageExtension(bytes([0xFF, 0xD8, 0xFF, 0xE0])),
        'jpg',
      );
    });

    test('PNG imzası', () {
      expect(
        OkeyAdminService.sniffImageExtension(
          bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        'png',
      );
    });

    test('WEBP imzası (RIFF....WEBP)', () {
      expect(
        OkeyAdminService.sniffImageExtension(
          bytes([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x00, 0x00, 0x00, 0x00, // uzunluk
            0x57, 0x45, 0x42, 0x50, // WEBP
          ]),
        ),
        'webp',
      );
    });

    test('görsel olmayan içerik tanınmaz', () {
      expect(
        OkeyAdminService.sniffImageExtension(bytes([0x50, 0x4B, 0x03, 0x04])),
        isNull,
        reason: 'ZIP dosyası görsel sayılmamalı',
      );
    });
  });

  group('Ses içeriğinden tanınır', () {
    test('ID3 etiketli MP3', () {
      expect(
        OkeyAdminService.sniffAudioExtension(bytes([0x49, 0x44, 0x33, 0x03])),
        'mp3',
      );
    });

    test('etiketsiz MP3 çerçevesi', () {
      expect(
        OkeyAdminService.sniffAudioExtension(bytes([0xFF, 0xFB, 0x90, 0x00])),
        'mp3',
      );
    });

    test('WAV (RIFF....WAVE)', () {
      expect(
        OkeyAdminService.sniffAudioExtension(
          bytes([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x00, 0x00, 0x00, 0x00,
            0x57, 0x41, 0x56, 0x45, // WAVE
          ]),
        ),
        'wav',
      );
    });

    test('OGG', () {
      expect(
        OkeyAdminService.sniffAudioExtension(bytes([0x4F, 0x67, 0x67, 0x53])),
        'ogg',
      );
    });

    test('M4A/MP4 kabı (ftyp)', () {
      expect(
        OkeyAdminService.sniffAudioExtension(
          bytes([
            0x00, 0x00, 0x00, 0x20, // kutu uzunluğu
            0x66, 0x74, 0x79, 0x70, // ftyp
            0x4D, 0x34, 0x41, 0x20, // M4A␠
          ]),
        ),
        'm4a',
      );
    });

    test('ses olmayan içerik tanınmaz', () {
      expect(
        OkeyAdminService.sniffAudioExtension(bytes([0x25, 0x50, 0x44, 0x46])),
        isNull,
        reason: 'PDF ses sayılmamalı',
      );
    });
  });

  group('Uzantı çözümleme: önce ad, sonra içerik', () {
    final jpeg = bytes([0xFF, 0xD8, 0xFF, 0xE0]);
    final mp3 = bytes([0x49, 0x44, 0x33, 0x03]);

    test('ad yeterliyse içeriğe bakılmaz', () {
      expect(OkeyAdminService.resolveImageExtension('foto.png', jpeg), 'png');
    });

    test('UZANTISIZ ad → içerikten çözülür (asıl hata buydu)', () {
      expect(
        OkeyAdminService.resolveImageExtension('image:1000000034', jpeg),
        'jpg',
        reason: 'Android galerisinden gelen ad uzantısız olabiliyor',
      );
      expect(OkeyAdminService.resolveAudioExtension('document', mp3), 'mp3');
    });

    test('alakasız uzantı ama geçerli içerik → kabul', () {
      expect(OkeyAdminService.resolveImageExtension('dosya.bin', jpeg), 'jpg');
    });

    test('jpeg → jpg olarak normalleştirilir', () {
      expect(OkeyAdminService.resolveImageExtension('foto.jpeg', jpeg), 'jpg');
    });

    test('ne ad ne içerik tutuyorsa null', () {
      expect(
        OkeyAdminService.resolveImageExtension(
          'metin.txt',
          bytes([0x68, 0x65, 0x6C, 0x6F]),
        ),
        isNull,
      );
    });
  });

  group('Hata mesajları adminin anlayacağı dile çevrilir', () {
    test('APP: kodları', () {
      const cases = <String, String>{
        'APP:forbidden': 'admin yetkisi',
        'APP:name_taken': 'zaten kullanılıyor',
        'APP:name_required': 'boş olamaz',
        'APP:not_found': 'bulunamadı',
      };
      cases.forEach((code, fragment) {
        final msg = OkeyAdminService.describeError(
          'PostgrestException(message: $code, code: 42501, details: null)',
        );
        expect(
          msg.toLowerCase(),
          contains(fragment.toLowerCase()),
          reason: '$code için anlaşılır bir karşılık yok',
        );
        expect(
          msg,
          isNot(contains('PostgrestException')),
          reason: 'ham istisna metni ekrana çıkmamalı',
        );
      });
    });

    test('benzersizlik ihlali', () {
      final msg = OkeyAdminService.describeError(
        'duplicate key value violates unique constraint '
        '"uq_okey_bot_profiles_name"',
      );
      expect(msg.toLowerCase(), contains('zaten'));
    });

    test('RLS reddi', () {
      final msg = OkeyAdminService.describeError(
        'new row violates row-level security policy',
      );
      expect(msg.toLowerCase(), contains('yetki'));
    });

    test('depo boyut sınırı', () {
      final msg = OkeyAdminService.describeError(
        'The object exceeded the maximum allowed size',
      );
      expect(msg.toLowerCase(), contains('boyut'));
    });

    test('ağ hatası', () {
      final msg = OkeyAdminService.describeError(
        'SocketException: Failed host lookup',
      );
      expect(msg.toLowerCase(), contains('bağlantı'));
    });

    test('tanınmayan hatada en azından message alanı ayıklanır', () {
      final msg = OkeyAdminService.describeError(
        'PostgrestException(message: beklenmedik bir şey, code: XX000)',
      );
      expect(msg, 'beklenmedik bir şey');
    });
  });
}
