import 'dart:typed_data';

import 'package:cizreapp/features/music/models/attached_music.dart';
import 'package:cizreapp/features/music/services/mp3_clipper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sentetik MPEG1 Layer III çerçevesi: 128 kbps, 44100 Hz, dolgusuz.
///
/// Başlık baytları:
///   FF       — senkron
///   FB       — senkron (3 bit) + MPEG1 (11) + Layer III (01) + CRC yok (1)
///   90       — bit hızı indeksi 9 (128 kbps) + örnekleme indeksi 0 (44100)
///   00       — kanal modu vb. (kesme için önemsiz)
///
/// Çerçeve uzunluğu = 144 * 128000 / 44100 = 417 bayt.
/// Çerçeve süresi   = 1152 / 44100 * 1000 = 26.122 ms.
const int _frameLength = 417;
const double _frameMs = 1152 * 1000 / 44100;

Uint8List _frames(int count, {int id3Size = 0}) {
  final bytes = BytesBuilder();

  if (id3Size > 0) {
    // ID3v2 başlığı: "ID3" + sürüm + bayrak + synchsafe boyut.
    bytes.add([0x49, 0x44, 0x33, 0x04, 0x00, 0x00]);
    bytes.add([
      (id3Size >> 21) & 0x7F,
      (id3Size >> 14) & 0x7F,
      (id3Size >> 7) & 0x7F,
      id3Size & 0x7F,
    ]);
    // Etiket gövdesi BİLEREK 0xFF içeriyor: çerçeve senkronuna benzeyen
    // baytların atlanmadığını görmek istiyoruz.
    bytes.add(List<int>.filled(id3Size, 0xFF));
  }

  for (var i = 0; i < count; i++) {
    bytes.add([0xFF, 0xFB, 0x90, 0x00]);
    // Gövdeyi çerçeve numarasıyla doldur: hangi çerçevelerin kesildiğini
    // baytlardan doğrulayabilelim.
    bytes.add(List<int>.filled(_frameLength - 4, i % 256));
  }

  return bytes.toBytes();
}

void main() {
  group('Mp3Clipper.durationMs', () {
    test('çerçeveleri sayarak süreyi ölçer', () {
      final ms = Mp3Clipper.durationMs(_frames(100));
      expect(ms, isNotNull);
      expect(ms, closeTo(100 * _frameMs, 1));
    });

    test('ID3v2 etiketi atlanır, etiketteki 0xFF baytları süreye katılmaz', () {
      final ms = Mp3Clipper.durationMs(_frames(100, id3Size: 2048));
      expect(ms, closeTo(100 * _frameMs, 1));
    });

    test('MP3 olmayan veri için null döner', () {
      final junk = Uint8List.fromList(List<int>.filled(4096, 0x41));
      expect(Mp3Clipper.durationMs(junk), isNull);
    });
  });

  group('Mp3Clipper.clip', () {
    test('istenen aralığı çerçeve sınırından keser', () {
      final source = _frames(200);
      final clip = Mp3Clipper.clip(source, startMs: 1000, durationMs: 500);

      expect(clip, isNotNull);

      // Kesit çerçeve sınırında başlamalı: ilk dört bayt bir çerçeve başlığı.
      expect(clip![0], 0xFF);
      expect(clip[1], 0xFB);

      // Uzunluk tam sayıda çerçeve olmalı.
      expect(clip.length % _frameLength, 0);

      // Kesit süresi istenen 500 ms'ye bir çerçeveden fazla sapmamalı.
      final clipMs = Mp3Clipper.durationMs(clip);
      expect(clipMs, isNotNull);
      expect(clipMs!, closeTo(500, _frameMs));
    });

    test('kesit TEK BAŞINA geçerli bir MP3 olarak çözümlenir', () {
      final clip = Mp3Clipper.clip(
        _frames(400),
        startMs: 3000,
        durationMs: AttachedMusic.clipDurationMs,
      );
      expect(clip, isNotNull);

      // Kesitin kendisi yeniden kesilebiliyorsa geçerli bir MP3'tür.
      final again = Mp3Clipper.clip(clip!, startMs: 0, durationMs: 2000);
      expect(again, isNotNull);
      expect(Mp3Clipper.durationMs(again!), closeTo(2000, _frameMs));
    });

    test('doğru çerçevelerden başlar (gövde damgasıyla doğrulanır)', () {
      final clip = Mp3Clipper.clip(
        _frames(200),
        startMs: 1000,
        durationMs: 500,
      );
      // 1000 ms, 39. çerçevenin başında dolar (38 * 26.122 = 992.6).
      final expectedFrame = (1000 / _frameMs).ceil();
      expect(clip![4], expectedFrame % 256);
    });

    test('istenen süre dolmadan dosya biterse eldekini verir', () {
      final source = _frames(100); // ~2612 ms
      final clip = Mp3Clipper.clip(
        source,
        startMs: 2400,
        durationMs: AttachedMusic.clipDurationMs,
      );
      expect(clip, isNotNull);
      // Kalan ~200 ms; 15 saniye istendi ama hiç vermemektense bu iyi.
      expect(Mp3Clipper.durationMs(clip!), lessThan(400));
      expect(clip.length, greaterThan(0));
    });

    test('başlangıç dosyanın sonundan sonraysa null döner', () {
      final clip = Mp3Clipper.clip(
        _frames(20), // ~522 ms
        startMs: 60000,
        durationMs: 15000,
      );
      expect(clip, isNull);
    });

    test('MP3 olmayan veri için null döner — çağıran tam dosyayı yükler', () {
      final m4a = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // ftyp
        ...List<int>.filled(4096, 0x11),
      ]);
      expect(Mp3Clipper.clip(m4a, startMs: 0, durationMs: 15000), isNull);
    });

    test('looksLikeMp3 yalnızca .mp3 uzantısını kabul eder', () {
      expect(Mp3Clipper.looksLikeMp3('sarki.mp3'), isTrue);
      expect(Mp3Clipper.looksLikeMp3('SARKI.MP3'), isTrue);
      expect(Mp3Clipper.looksLikeMp3('sarki.m4a'), isFalse);
      expect(Mp3Clipper.looksLikeMp3('sarki'), isFalse);
    });
  });

  group('AttachedMusic', () {
    test('bozuk kayıtlar gönderiyi çizilemez hâle getirmez', () {
      expect(AttachedMusic.fromJson(null), isNull);
      expect(AttachedMusic.fromJson('metin'), isNull);
      expect(AttachedMusic.fromJson({'title': 'Adresi yok'}), isNull);
      expect(AttachedMusic.fromJson({'url': '   '}), isNull);
    });

    test('eksik alanlar makul varsayılanlara düşer', () {
      final m = AttachedMusic.fromJson({'url': 'https://a.invalid/x.mp3'});
      expect(m, isNotNull);
      expect(m!.title, 'Şarkı');
      expect(m.startMs, 0);
      expect(m.durationMs, AttachedMusic.clipDurationMs);
      expect(m.clipped, isFalse);
    });

    test('toJson/fromJson gidiş dönüşü alanları korur', () {
      const original = AttachedMusic(
        url: 'https://a.invalid/x.mp3',
        title: 'Ez Kurdim',
        artist: 'Ciwan Haco',
        startMs: 48000,
        durationMs: 15000,
        clipped: true,
        catalogId: 'c1',
      );
      final back = AttachedMusic.fromJson(original.toJson())!;
      expect(back.url, original.url);
      expect(back.title, original.title);
      expect(back.artist, original.artist);
      expect(back.startMs, original.startMs);
      expect(back.durationMs, original.durationMs);
      expect(back.clipped, isTrue);
      expect(back.catalogId, 'c1');
      expect(back.label, 'Ez Kurdim · Ciwan Haco');
    });
  });
}
