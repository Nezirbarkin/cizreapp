import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../../okey/services/okey_sound_service.dart';
import '../models/attached_music.dart';
import '../models/music_track.dart';

/// Gönderi ve hikayelerdeki 15 saniyelik müzik kesitlerini çalar.
///
/// ## Neden TEK bir oynatıcı
///
/// Akışta yüzlerce gönderi olabiliyor. Her kartın kendi [AudioPlayer]'ı olsaydı
/// her biri bir platform kanalı ve bir arabellek tutardı; kaydırma sırasında
/// bellek ve kare süresi hızla bozulurdu. Bunun yerine tek bir oynatıcı var ve
/// hangi kesiti çaldığı [nowPlayingKey] ile yayınlanıyor — kartlar yalnızca
/// "çalan ben miyim" sorusunu soruyor.
///
/// ## Fon müziğiyle çakışma
///
/// Uygulamanın kendi fon müziği ([OkeySoundService]) çalıyorsa kesit
/// başlamadan önce duraklatılır ve kesit bitince kaldığı yerden devam eder.
/// İki müziğin üst üste binmesi, kullanıcının "sesi nereden geliyor"
/// sorusunu sorduğu an özelliğin kaybettiği andır.
///
/// ## Otomatik çalma yok
///
/// Bu sınıf akışta kendiliğinden hiçbir şey başlatmaz; yalnızca kullanıcı
/// rozete dokununca çalar. Hikaye görüntüleyici bunun tek istisnası ve orada
/// çağrıyı ekran kendisi yapar.
class ClipPlayer {
  ClipPlayer._();

  static final ClipPlayer instance = ClipPlayer._();

  AudioPlayer? _player;
  Timer? _stopTimer;
  StreamSubscription<void>? _completeSub;

  /// Fon müziğini biz mi duraklattık? Yalnızca biz duraklattıysak devam
  /// ettiririz — kullanıcı kendi eliyle duraklatmışsa ona dokunmayız.
  bool _pausedBackgroundMusic = false;

  /// Şu an çalan kesitin adresi; hiçbir şey çalmıyorsa null.
  ///
  /// Kartlar bunu dinleyip ▶/⏸ ikonunu değiştiriyor. Adres kullanıyoruz çünkü
  /// aynı şarkı birden çok gönderide olabilir ve o gönderilerin hepsinin aynı
  /// anda "çalıyor" görünmesi doğru davranıştır.
  final ValueNotifier<String?> nowPlayingKey = ValueNotifier<String?>(null);

  bool isPlaying(AttachedMusic music) => nowPlayingKey.value == music.url;

  /// Kesiti çalar. Aynı kesit zaten çalıyorsa durdurur (aç/kapa davranışı).
  ///
  /// ASLA hata fırlatmaz: ses kaynağı çalınamıyorsa (ağ, bozuk dosya, eksik
  /// eklenti) sessizce durur — gönderi yine de okunabilir olmalı.
  Future<void> toggle(AttachedMusic music) async {
    if (isPlaying(music)) {
      await stop();
      return;
    }
    await play(music);
  }

  Future<void> play(AttachedMusic music) async {
    await stop();

    try {
      _pauseBackgroundMusic();

      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(1.0);

      // Kesilmiş kliplerde başlangıç 0; kesilemeyen dosyalarda kullanıcının
      // seçtiği ana atlıyoruz.
      await player.play(UrlSource(music.url));
      if (music.startMs > 0) {
        await player.seek(music.start);
      }

      nowPlayingKey.value = music.url;

      // Dosyanın tamamı yüklenmiş olabilir; 15 saniye dolunca KENDİMİZ
      // durduruyoruz. Zamanlayıcı olmasaydı kesilemeyen formatlarda şarkının
      // tamamı çalardı.
      _stopTimer = Timer(Duration(milliseconds: music.durationMs), stop);

      // Klip kendi kendine bittiyse (kesilmiş dosya) zamanlayıcıyı bekleme.
      _completeSub = player.onPlayerComplete.listen((_) => stop());
    } catch (e) {
      debugPrint('⚠️ Müzik kesiti çalınamadı: $e');
      await stop();
    }
  }

  /// Kırpma çubuğundaki "Önizle" — henüz iliştirilmemiş bir parçanın seçilen
  /// aralığını çalar.
  ///
  /// [play] ile aynı motoru kullanır ama kaynağı parçanın türüne göre seçer:
  /// cihaz parçaları henüz sunucuda olmadığı için dosyadan çalınır.
  Future<void> preview(
    MusicTrack track, {
    required int startMs,
    required int durationMs,
  }) async {
    if (nowPlayingKey.value == track.id) {
      await stop();
      return;
    }
    await stop();

    final source = track.isDevice
        ? (track.localPath == null ? null : DeviceFileSource(track.localPath!))
        : (track.url == null ? null : UrlSource(track.url!));
    if (source == null) return;

    try {
      _pauseBackgroundMusic();

      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(1.0);
      await player.play(source);
      if (startMs > 0) await player.seek(Duration(milliseconds: startMs));

      nowPlayingKey.value = track.id;
      _stopTimer = Timer(Duration(milliseconds: durationMs), stop);
      _completeSub = player.onPlayerComplete.listen((_) => stop());
    } catch (e) {
      debugPrint('⚠️ Önizleme çalınamadı: $e');
      await stop();
    }
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    await _completeSub?.cancel();
    _completeSub = null;

    if (nowPlayingKey.value != null) nowPlayingKey.value = null;

    try {
      await _player?.stop();
    } catch (_) {
      // Durdurulamadıysa da kullanıcı açısından durdu; bir sonraki play()
      // zaten yeni bir kaynak yükleyecek.
    }

    _resumeBackgroundMusic();
  }

  void _pauseBackgroundMusic() {
    try {
      final sound = OkeySoundService.instance;
      if (sound.isMusicPlaying) {
        unawaited(sound.pauseMusic());
        _pausedBackgroundMusic = true;
      }
    } catch (_) {
      // Fon müziği yoksa kesit yine de çalmalı.
    }
  }

  void _resumeBackgroundMusic() {
    if (!_pausedBackgroundMusic) return;
    _pausedBackgroundMusic = false;
    try {
      unawaited(OkeySoundService.instance.resumeMusicPlayback());
    } catch (_) {
      // Devam ettirilemezse kullanıcı yan menüden kendisi başlatabilir.
    }
  }

  /// Uygulama kapanırken ya da testlerde kaynakları bırakır.
  Future<void> dispose() async {
    await stop();
    try {
      await _player?.dispose();
    } catch (_) {
      // Zaten bırakılmış olabilir.
    }
    _player = null;
  }
}
