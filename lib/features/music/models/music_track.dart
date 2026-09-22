/// Müzik parçasının nereden geldiği.
///
/// İkisi arayüzde AYNI satır gibi görünür ama teknik olarak tamamen farklıdır:
/// [device] parçasının yalnızca yerel bir dosya yolu vardır ve sunucuda hiç
/// bulunmaz; [catalog] parçasının ise yalnızca bir adresi vardır. Tek bir
/// modelde birleştirmek yerine ayrı alanlar tutup bu bayrakla ayırmak,
/// "yanlışlıkla yerel yolu sunucuya yazmak" gibi hataları derleme zamanında
/// değil ama okurken görünür kılıyor.
enum MusicSourceKind { device, catalog }

/// Çalınabilir bir parça — hem cihaz kitaplığı hem Cizre Radyo için ortak.
class MusicTrack {
  /// Cihaz parçalarında yerel olarak üretilmiş kimlik, katalog parçalarında
  /// sunucudaki `music_catalog.id`.
  final String id;

  final String title;
  final String? artist;
  final String? genre;

  /// Yalnızca [MusicSourceKind.device]: dosyanın uygulama klasöründeki yolu.
  final String? localPath;

  /// Yalnızca [MusicSourceKind.catalog]: herkese açık adres.
  final String? url;

  final int? durationMs;
  final MusicSourceKind kind;

  /// Katalog parçası bir yerel sanatçı başvurusundan mı geldi? (rozet için)
  final bool byLocalArtist;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.kind,
    this.artist,
    this.genre,
    this.localPath,
    this.url,
    this.durationMs,
    this.byLocalArtist = false,
  });

  bool get isDevice => kind == MusicSourceKind.device;

  /// Alt başlık: "Ciwan Haco · 3:58" gibi. Sanatçı yoksa yalnızca süre.
  String get subtitle {
    final parts = <String>[
      if (artist != null && artist!.trim().isNotEmpty) artist!.trim(),
      if (durationMs != null && durationMs! > 0) formatDuration(durationMs!),
    ];
    return parts.join(' · ');
  }

  /// Cihaz kitaplığı için JSON — SharedPreferences'taki indekste saklanır.
  Map<String, dynamic> toLibraryJson() => {
    'id': id,
    'title': title,
    if (artist != null) 'artist': artist,
    if (localPath != null) 'path': localPath,
    if (durationMs != null) 'duration_ms': durationMs,
  };

  factory MusicTrack.fromLibraryJson(Map<String, dynamic> json) => MusicTrack(
    id: json['id'] as String? ?? '',
    title: (json['title'] as String?)?.trim().isNotEmpty == true
        ? json['title'] as String
        : 'Şarkı',
    artist: json['artist'] as String?,
    localPath: json['path'] as String?,
    durationMs: (json['duration_ms'] as num?)?.toInt(),
    kind: MusicSourceKind.device,
  );

  /// `music_search_catalog` RPC satırı.
  factory MusicTrack.fromCatalogRow(Map<String, dynamic> row) => MusicTrack(
    id: row['id'] as String? ?? '',
    title: (row['title'] as String?)?.trim().isNotEmpty == true
        ? row['title'] as String
        : 'Şarkı',
    artist: row['artist'] as String?,
    genre: row['genre'] as String?,
    url: row['public_url'] as String?,
    durationMs: (row['duration_ms'] as num?)?.toInt(),
    kind: MusicSourceKind.catalog,
    byLocalArtist: (row['source'] as String?) == 'artist',
  );

  MusicTrack copyWith({String? title, String? artist, int? durationMs}) =>
      MusicTrack(
        id: id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        genre: genre,
        localPath: localPath,
        url: url,
        durationMs: durationMs ?? this.durationMs,
        kind: kind,
        byLocalArtist: byLocalArtist,
      );
}

/// "3:58" biçimi. Bir saati aşan kayıtlar için "1:04:12".
String formatDuration(int ms) {
  final total = (ms / 1000).round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
