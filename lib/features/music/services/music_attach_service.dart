import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/attached_music.dart';
import '../models/music_track.dart';
import 'mp3_clipper.dart';
import 'music_catalog_service.dart';
import 'music_library_service.dart';

/// Seçilen bir parçayı gönderiye/hikayeye iliştirilebilir hâle getirir.
///
/// ## Üç yol, tek sözleşme
///
/// 1. **Cizre Radyo parçası** — dosya zaten sunucuda ve herkese açık. HİÇBİR
///    ŞEY YÜKLENMEZ; yalnızca adres ve başlangıç anı kaydedilir. En ucuz yol.
/// 2. **Cihazdaki MP3** — [Mp3Clipper] ile 15 saniyelik gerçek bir klip
///    kesilir (~250 KB) ve o yüklenir.
/// 3. **Cihazdaki diğer formatlar** — kesilemez; dosyanın tamamı yüklenir
///    (üst sınır [maxFullUploadBytes]) ve oynatıcı seçilen 15 saniyeyi çalar.
///
/// Üçünün de çıktısı aynı [AttachedMusic] sözleşmesidir; dinleyici aradaki
/// farkı göremez.
class MusicAttachService {
  MusicAttachService._();

  static final MusicAttachService instance = MusicAttachService._();

  static const String bucket = 'post-music';
  static const _uuid = Uuid();

  /// Kesilemeyen formatlarda kabul edilen en büyük dosya.
  ///
  /// Kepçenin kendi sınırı 12 MB; buradaki 8 MB uygulama tarafındaki daha sıkı
  /// kapı. Aradaki boşluk kasıtlı: depo sınırına dayanan bir yükleme kullanıcıya
  /// anlamsız bir sunucu hatası olarak döner, buradaki kapı ise seçim anında
  /// anlaşılır bir cümle gösterebilir.
  static const int maxFullUploadBytes = 8 * 1024 * 1024;

  /// Bu parça iliştirilirken dosyanın TAMAMI mı yüklenecek?
  ///
  /// Arayüz bunu kullanıcıya seçim anında söylüyor — "bu dosya kırpılamıyor,
  /// tamamı yüklenecek". Sürpriz bir 6 MB'lık yükleme kimseyi memnun etmez.
  static bool needsFullUpload(MusicTrack track) {
    if (!track.isDevice) return false;
    final path = track.localPath ?? '';
    return !Mp3Clipper.looksLikeMp3(path);
  }

  /// Parçayı iliştirilebilir hâle getirir.
  ///
  /// [startMs] kullanıcının kırpma çubuğunda seçtiği başlangıç anı.
  /// Hata durumunda [MusicCatalogException] fırlatır: kullanıcı "Ekle"ye
  /// bastıysa sonucu bilmeyi hak ediyor.
  Future<AttachedMusic> prepare(
    MusicTrack track, {
    required int startMs,
  }) async {
    final start = startMs < 0 ? 0 : startMs;

    // 1) Katalog parçası: yükleme yok.
    if (!track.isDevice) {
      final url = track.url;
      if (url == null || url.isEmpty) {
        throw const MusicCatalogException('Bu parçanın adresi bulunamadı.');
      }
      return AttachedMusic(
        url: url,
        title: track.title,
        artist: track.artist,
        startMs: start,
        durationMs: AttachedMusic.clipDurationMs,
        clipped: false,
        catalogId: track.id,
      );
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw const MusicCatalogException('Müzik eklemek için giriş yapmalısın.');
    }

    final bytes = await MusicLibraryService.instance.readBytes(track);
    if (bytes == null) {
      throw const MusicCatalogException('Şarkı dosyası okunamadı.');
    }

    // 2) MP3 ise gerçekten kes.
    Uint8List payload = bytes;
    var clipped = false;
    var effectiveStart = start;
    var extension = p.extension(track.localPath ?? '').toLowerCase();

    if (Mp3Clipper.looksLikeMp3(track.localPath ?? '')) {
      final clip = Mp3Clipper.clip(
        bytes,
        startMs: start,
        durationMs: AttachedMusic.clipDurationMs,
      );
      if (clip != null && clip.isNotEmpty) {
        payload = clip;
        clipped = true;
        // Klip zaten doğru yerden başlıyor; oynatıcı baştan çalmalı.
        effectiveStart = 0;
        extension = '.mp3';
      }
    }

    // 3) Kesilemediyse tam dosya — ama sınırsız değil.
    if (!clipped && payload.lengthInBytes > maxFullUploadBytes) {
      final mb = (payload.lengthInBytes / (1024 * 1024)).toStringAsFixed(1);
      throw MusicCatalogException(
        'Bu dosya kırpılamıyor ve $mb MB — en fazla 8 MB olabilir.',
      );
    }

    final path =
        '$userId/${_uuid.v4()}${extension.isEmpty ? '.mp3' : extension}';

    try {
      await Supabase.instance.client.storage
          .from(bucket)
          .uploadBinary(
            path,
            payload,
            fileOptions: FileOptions(
              upsert: false,
              contentType: contentTypeFor(extension),
            ),
          );
    } catch (e) {
      debugPrint('⚠️ Müzik yüklenemedi: $e');
      throw const MusicCatalogException(
        'Müzik yüklenemedi. Bağlantını kontrol et.',
      );
    }

    final url = Supabase.instance.client.storage
        .from(bucket)
        .getPublicUrl(path);

    return AttachedMusic(
      url: url,
      title: track.title,
      artist: track.artist,
      startMs: effectiveStart,
      durationMs: AttachedMusic.clipDurationMs,
      clipped: clipped,
    );
  }

  /// Uzantıdan MIME türü. Depo kepçesi `allowed_mime_types` ile süzüyor;
  /// yanlış tür göndermek yüklemeyi reddettirir.
  static String contentTypeFor(String extension) {
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return switch (ext.toLowerCase()) {
      '.mp3' => 'audio/mpeg',
      '.m4a' => 'audio/mp4',
      '.mp4' => 'audio/mp4',
      '.aac' => 'audio/aac',
      '.ogg' || '.oga' => 'audio/ogg',
      '.opus' => 'audio/ogg',
      '.wav' => 'audio/wav',
      '.flac' => 'audio/flac',
      '.webm' || '.weba' => 'audio/webm',
      _ => 'audio/mpeg',
    };
  }
}
