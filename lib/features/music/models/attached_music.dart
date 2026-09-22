/// Bir gönderiye ya da hikayeye iliştirilmiş müzik.
///
/// `posts.music` / `stories.music` jsonb kolonunun Dart karşılığı. Kolonun
/// şekli migration 20260920000008'de belgelendi; buradaki alan adları o
/// şekille BİREBİR aynı olmak zorunda.
///
/// ## Neden hem [startMs] hem [clipped] var
///
/// İki farklı yükleme yolu aynı çalma sözleşmesine bağlanıyor:
/// * MP3 dosyaları cihazda gerçekten kesilir ([clipped] true, [startMs] 0) —
///   sunucuya yalnızca ~250 KB'lık klip gider.
/// * Kesilemeyen formatlarda dosyanın tamamı yüklenir ([clipped] false) ve
///   oynatıcı [startMs] noktasına atlayıp [durationMs] kadar çalar.
///
/// Dinleyici tarafında ikisi ayırt edilemez; fark yalnızca depolamadadır.
class AttachedMusic {
  final String url;
  final String title;
  final String? artist;

  /// Çalmaya başlanacak an. Kesilmiş kliplerde daima 0.
  final int startMs;

  /// Çalınacak süre — ürün kararı gereği 15 saniye.
  final int durationMs;

  /// Dosya gerçekten kesildi mi? Yalnızca teşhis ve depolama muhasebesi için;
  /// çalma davranışını [startMs] + [durationMs] belirler.
  final bool clipped;

  /// Parça Cizre Radyo'dan seçildiyse katalog kimliği. Cihazdan yüklenen
  /// kliplerde null olur.
  final String? catalogId;

  const AttachedMusic({
    required this.url,
    required this.title,
    required this.startMs,
    required this.durationMs,
    this.artist,
    this.clipped = false,
    this.catalogId,
  });

  /// Ürün kararı: iliştirilen müzik her zaman 15 saniye.
  static const int clipDurationMs = 15000;

  Duration get start => Duration(milliseconds: startMs);
  Duration get end => Duration(milliseconds: startMs + durationMs);

  /// Rozette görünen metin: "Ez Kurdim · Ciwan Haco".
  String get label {
    final a = artist?.trim();
    if (a == null || a.isEmpty) return title;
    return '$title · $a';
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    if (artist != null && artist!.trim().isNotEmpty) 'artist': artist!.trim(),
    'start_ms': startMs,
    'duration_ms': durationMs,
    'clipped': clipped,
    if (catalogId != null) 'catalog_id': catalogId,
  };

  /// Sunucudan gelen jsonb. ASLA hata fırlatmaz: müzik opsiyonel bir süstür,
  /// bozuk bir kayıt yüzünden gönderinin tamamı çizilememeli. Adres yoksa
  /// (ya da kolon null ise) null döner ve çağıran taraf müziği hiç göstermez.
  static AttachedMusic? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final url = (raw['url'] as String?)?.trim();
    if (url == null || url.isEmpty) return null;

    final title = (raw['title'] as String?)?.trim();
    return AttachedMusic(
      url: url,
      title: (title == null || title.isEmpty) ? 'Şarkı' : title,
      artist: (raw['artist'] as String?)?.trim(),
      startMs: (raw['start_ms'] as num?)?.toInt() ?? 0,
      durationMs: (raw['duration_ms'] as num?)?.toInt() ?? clipDurationMs,
      clipped: raw['clipped'] == true,
      catalogId: raw['catalog_id'] as String?,
    );
  }
}
