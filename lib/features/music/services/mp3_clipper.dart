import 'dart:typed_data';

/// Bir MP3 dosyasından, hiçbir yeni paket kullanmadan, çalınabilir bir kesit
/// çıkarır.
///
/// ## Neden elle yazıldı
///
/// Gerçek bir ses kesme kütüphanesi (ffmpeg_kit_flutter) ~40 MB'lık native
/// bağımlılık getiriyor ve iOS/Android derleme zincirine yeni kırılma noktası
/// ekliyor. Oysa MP3 için kesmek YENİDEN KODLAMA gerektirmez: dosya, her biri
/// kendi başlığını taşıyan bağımsız çerçevelerden (frame) oluşur. Doğru
/// çerçeve sınırından kesilen bayt aralığı, tek başına geçerli bir MP3'tür.
///
/// Bu sınıfın yaptığı tam olarak budur: çerçeveleri yürüyüp süre biriktirir,
/// istenen aralığın baytlarını kopyalar.
///
/// ## Neyi yapmaz
///
/// * MP3 dışındaki formatları (m4a, flac, ogg) kesemez — onların çerçeve
///   yapısı yok, kapsayıcı (container) yeniden yazmak gerekir. [clip] böyle
///   bir dosyada null döner ve çağıran taraf dosyanın tamamını yükler.
/// * VBR dosyalarda süre birikimi çerçeve çerçeve yapıldığı için doğrudur;
///   yalnızca Xing/Info başlığındaki toplam süre bilgisi klibe taşınmaz, bu da
///   oynatmayı etkilemez.
class Mp3Clipper {
  Mp3Clipper._();

  /// MPEG1 Layer III bit hızları (kbps). 0 ve 15 geçersizdir.
  static const List<int> _bitratesV1 = [
    0,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
    0,
  ];

  /// MPEG2 ve MPEG2.5 Layer III bit hızları (kbps).
  static const List<int> _bitratesV2 = [
    0,
    8,
    16,
    24,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    144,
    160,
    0,
  ];

  static const List<int> _ratesV1 = [44100, 48000, 32000];
  static const List<int> _ratesV2 = [22050, 24000, 16000];
  static const List<int> _ratesV25 = [11025, 12000, 8000];

  /// Dosya adına bakarak MP3 olup olmadığını söyler.
  ///
  /// Uzantı yalanabilir; bu yüzden [clip] ayrıca gerçek çerçeve senkronu arar
  /// ve bulamazsa null döner. Bu metot yalnızca arayüzün "bu dosya
  /// kırpılabilir" ipucunu erkenden gösterebilmesi için var.
  static bool looksLikeMp3(String fileName) =>
      fileName.toLowerCase().trim().endsWith('.mp3');

  /// [bytes] içindeki MP3'ten [startMs] anından başlayan [durationMs]
  /// uzunluğunda bir kesit döndürür.
  ///
  /// Dosya MP3 değilse ya da çerçeveler okunamıyorsa **null** döner — bu bir
  /// hata değil, "bu dosya kesilemiyor" cevabıdır.
  static Uint8List? clip(
    Uint8List bytes, {
    required int startMs,
    required int durationMs,
  }) {
    final firstFrame = _skipId3(bytes);
    if (firstFrame >= bytes.length) return null;

    var offset = _findSync(bytes, firstFrame);
    if (offset < 0) return null;

    double elapsedMs = 0;
    int? clipStart;
    var framesSeen = 0;

    while (offset + 4 <= bytes.length) {
      final header = _parseHeader(bytes, offset);
      if (header == null) {
        // Çerçeve bozuk: bir sonraki senkron sözcüğünü ara. Bozuk bayt
        // dizileri (gömülü etiketler, dolgu) MP3'lerde olağandır; tek bir
        // hatada pes etmek çalışan dosyaları reddetmek olurdu.
        final next = _findSync(bytes, offset + 1);
        if (next < 0) break;
        offset = next;
        continue;
      }

      framesSeen++;

      if (clipStart == null && elapsedMs >= startMs) {
        clipStart = offset;
      }

      if (clipStart != null && elapsedMs >= startMs + durationMs) {
        return Uint8List.sublistView(bytes, clipStart, offset);
      }

      elapsedMs += header.durationMs;
      offset += header.frameLength;
    }

    // Hiç geçerli çerçeve yoksa bu dosya MP3 değil.
    if (framesSeen == 0) return null;

    // Başlangıç noktası dosyanın sonundan sonraysa kesit boş olurdu.
    if (clipStart == null) return null;

    // İstenen süre dolmadan dosya bitti: elde kalanı ver. Kullanıcı şarkının
    // son 8 saniyesini seçtiyse 15 yerine 8 saniye almak, hiç alamamaktan iyi.
    return Uint8List.sublistView(bytes, clipStart, bytes.length);
  }

  /// Dosyanın toplam süresini çerçeveleri sayarak ölçer.
  ///
  /// MP3 değilse null döner. Kırpma çubuğunun "hangi 15 saniye" sorusunu
  /// sorabilmesi için şarkının uzunluğunu bilmek gerekiyor ve cihazdaki bir
  /// dosyanın süresini öğrenmenin paketsiz başka yolu yok.
  static int? durationMs(Uint8List bytes) {
    final firstFrame = _skipId3(bytes);
    if (firstFrame >= bytes.length) return null;

    var offset = _findSync(bytes, firstFrame);
    if (offset < 0) return null;

    double total = 0;
    var framesSeen = 0;

    while (offset + 4 <= bytes.length) {
      final header = _parseHeader(bytes, offset);
      if (header == null) {
        final next = _findSync(bytes, offset + 1);
        if (next < 0) break;
        offset = next;
        continue;
      }
      framesSeen++;
      total += header.durationMs;
      offset += header.frameLength;
    }

    if (framesSeen == 0) return null;
    return total.round();
  }

  /// ID3v2 etiketini atlar — etiket ses verisi değildir ve çerçeve senkronuna
  /// benzeyen baytlar içerebilir.
  static int _skipId3(Uint8List b) {
    if (b.length < 10) return 0;
    if (b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) return 0; // "ID3"
    // Boyut 4 bayt, her birinin yalnızca alt 7 biti kullanılır (synchsafe).
    final size =
        (b[6] & 0x7F) << 21 |
        (b[7] & 0x7F) << 14 |
        (b[8] & 0x7F) << 7 |
        (b[9] & 0x7F);
    return 10 + size;
  }

  /// [from] konumundan itibaren ilk çerçeve senkronunu (11 bit 1) bulur.
  static int _findSync(Uint8List b, int from) {
    for (var i = from; i + 1 < b.length; i++) {
      if (b[i] == 0xFF && (b[i + 1] & 0xE0) == 0xE0) return i;
    }
    return -1;
  }

  static _FrameHeader? _parseHeader(Uint8List b, int i) {
    if (i + 4 > b.length) return null;
    if (b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) return null;

    final versionBits = (b[i + 1] >> 3) & 0x03; // 0=2.5, 2=2, 3=1
    final layerBits = (b[i + 1] >> 1) & 0x03; // 1 = Layer III
    if (versionBits == 1 || layerBits != 1) return null;

    final bitrateIndex = (b[i + 2] >> 4) & 0x0F;
    final rateIndex = (b[i + 2] >> 2) & 0x03;
    final padding = (b[i + 2] >> 1) & 0x01;
    if (bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) return null;

    final isV1 = versionBits == 3;
    final bitrate =
        (isV1 ? _bitratesV1[bitrateIndex] : _bitratesV2[bitrateIndex]) * 1000;
    final sampleRate = switch (versionBits) {
      3 => _ratesV1[rateIndex],
      2 => _ratesV2[rateIndex],
      _ => _ratesV25[rateIndex],
    };
    if (bitrate == 0 || sampleRate == 0) return null;

    // Layer III çerçeve uzunluğu. MPEG1'de 1152, MPEG2/2.5'te 576 örnek.
    final samples = isV1 ? 1152 : 576;
    final frameLength = (samples ~/ 8) * bitrate ~/ sampleRate + padding;
    if (frameLength <= 4) return null;

    return _FrameHeader(
      frameLength: frameLength,
      durationMs: samples * 1000 / sampleRate,
    );
  }
}

class _FrameHeader {
  final int frameLength;
  final double durationMs;
  const _FrameHeader({required this.frameLength, required this.durationMs});
}
