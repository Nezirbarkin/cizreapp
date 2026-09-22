import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/music_track.dart';

/// Yerel sanatçı başvurusunun durumu.
enum SubmissionStatus { pending, approved, rejected }

class MusicSubmission {
  final String id;
  final String title;
  final String artist;
  final String? genre;
  final SubmissionStatus status;
  final String? rejectReason;
  final DateTime createdAt;

  const MusicSubmission({
    required this.id,
    required this.title,
    required this.artist,
    required this.status,
    required this.createdAt,
    this.genre,
    this.rejectReason,
  });

  factory MusicSubmission.fromRow(Map<String, dynamic> row) => MusicSubmission(
    id: row['id'] as String? ?? '',
    title: row['title'] as String? ?? '',
    artist: row['artist'] as String? ?? '',
    genre: row['genre'] as String?,
    status: switch (row['status'] as String?) {
      'approved' => SubmissionStatus.approved,
      'rejected' => SubmissionStatus.rejected,
      _ => SubmissionStatus.pending,
    },
    rejectReason: row['reject_reason'] as String?,
    createdAt:
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
  );

  String get statusLabel => switch (status) {
    SubmissionStatus.approved => 'yayında',
    SubmissionStatus.rejected => 'reddedildi',
    SubmissionStatus.pending => 'beklemede',
  };
}

/// Sunucuya bir şey yazarken kullanıcıya gösterilecek somut hata.
///
/// RPC'ler `APP:<kod>` biçiminde hata fırlatıyor; burada o kodlar Türkçe
/// cümlelere çevriliyor. Ham PostgREST metnini kullanıcıya göstermek hem
/// anlaşılmaz hem de şema hakkında gereksiz bilgi sızdırır.
class MusicCatalogException implements Exception {
  final String message;
  const MusicCatalogException(this.message);
  @override
  String toString() => message;
}

/// "Cizre Radyo" kataloğu ve yerel sanatçı başvuruları.
class MusicCatalogService {
  MusicCatalogService._();

  static final MusicCatalogService instance = MusicCatalogService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Katalogda arama.
  ///
  /// Sunucu tarafı kapı `music_search_catalog` içinde: özellik ya da katalog
  /// anahtarı kapalıysa RPC boş döner, yani burada ayrıca bayrak kontrol
  /// etmemize gerek yok.
  ///
  /// ASLA hata fırlatmaz — arama kutusuna yazarken ağ koparsa liste boşalır,
  /// ekran çökmez.
  Future<List<MusicTrack>> search({
    String? query,
    String? genre,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc(
        'music_search_catalog',
        params: {
          'p_query': (query ?? '').trim().isEmpty ? null : query!.trim(),
          'p_genre': (genre ?? '').trim().isEmpty ? null : genre!.trim(),
          'p_limit': limit,
          'p_offset': offset,
        },
      );

      return ((rows as List?) ?? const [])
          .whereType<Map>()
          .map((r) => MusicTrack.fromCatalogRow(Map<String, dynamic>.from(r)))
          .where((t) => (t.url ?? '').isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('⚠️ Müzik kataloğu aranamadı: $e');
      return const [];
    }
  }

  /// Süzgeç çipleri için katalogda gerçekten bulunan türler.
  Future<List<String>> genres() async {
    try {
      final rows = await _client.rpc('music_catalog_genres');
      return ((rows as List?) ?? const [])
          .whereType<Map>()
          .map((r) => (r['genre'] as String?)?.trim() ?? '')
          .where((g) => g.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('⚠️ Müzik türleri okunamadı: $e');
      return const [];
    }
  }

  Future<List<MusicSubmission>> mySubmissions() async {
    try {
      final rows = await _client.rpc('music_my_submissions');
      return ((rows as List?) ?? const [])
          .whereType<Map>()
          .map((r) => MusicSubmission.fromRow(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Başvurular okunamadı: $e');
      return const [];
    }
  }

  /// Sanatçı başvurusu gönderir. Hata DURUMUNDA fırlatır — kullanıcı
  /// dosyasını yükledi, sessizce başarısız olmak kabul edilemez.
  Future<void> submitTrack({
    required String title,
    required String artist,
    String? genre,
    required String storagePath,
    required String publicUrl,
    int? durationMs,
    required int sizeBytes,
    required bool rightsConfirmed,
  }) async {
    try {
      await _client.rpc(
        'music_submit_track',
        params: {
          'p_title': title.trim(),
          'p_artist': artist.trim(),
          'p_genre': (genre ?? '').trim().isEmpty ? null : genre!.trim(),
          'p_storage_path': storagePath,
          'p_public_url': publicUrl,
          'p_duration_ms': durationMs,
          'p_size_bytes': sizeBytes,
          'p_rights_confirmed': rightsConfirmed,
        },
      );
    } catch (e) {
      throw MusicCatalogException(describeRpcError(e));
    }
  }

  /// `APP:<kod>` hatalarını kullanıcı cümlesine çevirir.
  static String describeRpcError(Object error) {
    final text = error is PostgrestException
        ? '${error.message} ${error.details ?? ''}'
        : error.toString();

    if (text.contains('music_uploads_closed')) {
      return 'Şarkı yükleme şu anda kapalı.';
    }
    if (text.contains('rights_not_confirmed')) {
      return 'Hak beyanını onaylaman gerekiyor.';
    }
    if (text.contains('file_too_large')) {
      return 'Dosya izin verilen boyuttan büyük.';
    }
    if (text.contains('too_many_pending')) {
      return 'Bekleyen başvuru sınırına ulaştın. Önce mevcutlar sonuçlansın.';
    }
    if (text.contains('already_reviewed')) {
      return 'Bu başvuru zaten sonuçlandırılmış.';
    }
    if (text.contains('invalid_value')) {
      return 'Eksik ya da geçersiz bilgi var.';
    }
    if (text.contains('forbidden') || text.contains('unauthenticated')) {
      return 'Bu işlem için yetkin yok.';
    }
    return 'İşlem tamamlanamadı. Daha sonra dene.';
  }
}
