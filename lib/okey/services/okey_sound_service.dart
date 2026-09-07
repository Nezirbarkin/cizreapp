import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show Color, IsolateNameServer;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bildirim düğmesi olaylarının ARKA PLAN izolatından ANA izolata
/// taşındığı portun adı.
///
/// NEDEN GEREKLİ: `showsUserInterface: false` verilmiş bir bildirim düğmesine
/// dokunulduğunda flutter_local_notifications olayı `ActionBroadcastReceiver`
/// üzerinden AYRI bir Flutter motorunda (arka plan izolatı) çalıştırır —
/// uygulama ÖN PLANDA olsa bile. Yani `onDidReceiveNotificationResponse`
/// (ön plan geri çağrısı) bu düğmeler için HİÇ çağrılmaz; düğmelerin
/// çalışmamasının sebebi buydu. Arka plan izolatı ana izolattaki
/// [OkeySoundService] örneğini de göremez (ayrı bellek alanı), bu yüzden
/// yalnızca aksiyon kimliğini bu port üzerinden ana izolata iletir; müziği
/// asıl durduran/başlatan kod ana izolatta çalışır.
const String okeyMusicActionPortName = 'okey_music_action_port';

/// Bildirim düğmelerinin ARKA PLAN işleyicisi.
///
/// Ayrı bir izolatta çalıştığı için burada oynatıcıya erişilemez; tek işi
/// ana izolata haber vermektir. Üst düzey (top-level) ve
/// `@pragma('vm:entry-point')` işaretli OLMAK ZORUNDA — eklenti bu
/// fonksiyonu adres üzerinden çağırır.
@pragma('vm:entry-point')
void okeyMusicNotificationBackgroundHandler(NotificationResponse response) {
  final actionId = response.actionId;
  if (actionId == null) return;
  IsolateNameServer.lookupPortByName(okeyMusicActionPortName)?.send(actionId);
}

/// Oyundaki ses olayları. Her biri `assets/sounds/<dosya>` ile eşleşir.
enum OkeySound {
  /// Desteden veya ıskartadan taş çekildi
  drawTile,

  /// Taş ıskartaya atıldı
  discardTile,

  /// Masaya per/grup açıldı
  layMeld,

  /// Masadaki bir pere taş işlendi
  processTile,

  /// Sıra bana geldi
  yourTurn,

  /// Sıra süresi bitmek üzere (son 5 sn)
  timeWarning,

  /// El bitti — ben kazandım
  win,

  /// El bitti — kaybettim
  lose,

  /// Rakip "işlek" (işlenebilir) bir taş attı — alay/gülme efekti
  laugh,

  /// Geçersiz hamle / hata
  error,
}

/// Bir ses olayının uygulama paketindeki ÖRNEK dosyası.
///
/// Bu dosyalar depoda VARDIR: admin panelinden hiçbir şey yüklenmemişken de
/// oyun sessiz kalmaz, buradaki örnek sesleri çalar. Admin paneli de aynı
/// dosyaları "Örnek" düğmesiyle dinletir.
extension OkeySoundAsset on OkeySound {
  /// `AssetSource` için tam yol (`assets/` öneki olmadan).
  String get assetPath => 'sounds/$fileName';

  /// assets/sounds/ altındaki dosya adı.
  String get fileName {
    switch (this) {
      case OkeySound.drawTile:
        return 'draw.wav';
      case OkeySound.discardTile:
        return 'discard.wav';
      case OkeySound.layMeld:
        return 'meld.wav';
      case OkeySound.processTile:
        return 'process.wav';
      case OkeySound.yourTurn:
        return 'your_turn.wav';
      case OkeySound.timeWarning:
        return 'time_warning.wav';
      case OkeySound.win:
        return 'win.wav';
      case OkeySound.lose:
        return 'lose.wav';
      case OkeySound.laugh:
        return 'laugh.wav';
      case OkeySound.error:
        return 'error.wav';
    }
  }

  /// Ses dosyası yoksa kullanılacak dokunsal geri bildirim.
  Future<void> fallbackHaptic() async {
    switch (this) {
      case OkeySound.win:
      case OkeySound.laugh:
        await HapticFeedback.heavyImpact();
        break;
      case OkeySound.lose:
      case OkeySound.error:
        await HapticFeedback.vibrate();
        break;
      case OkeySound.yourTurn:
      case OkeySound.timeWarning:
        await HapticFeedback.mediumImpact();
        break;
      case OkeySound.drawTile:
      case OkeySound.discardTile:
      case OkeySound.layMeld:
      case OkeySound.processTile:
        await HapticFeedback.selectionClick();
        break;
    }
  }
}

/// Okey masasının ses efektleri.
///
/// SES KAYNAĞI SIRASI:
///  1. Admin panelinden yüklenmiş dosya (uzak URL) — varsa hep bu çalar.
///  2. Uygulama paketindeki ÖRNEK dosya (`assets/sounds/*.wav`).
///  3. İkisi de çalınamazsa dokunsal geri bildirim (titreşim).
///
/// Bu zincir sayesinde ses hiçbir koşulda oyunu bozmaz; admin hiçbir dosya
/// yüklemese bile masa sessiz kalmaz.
class OkeySoundService {
  static const _prefsKey = 'okey_sound_enabled';
  static const _musicPrefsKey = 'okey_music_enabled';
  static const _voicePrefsKey = 'okey_voice_enabled';

  /// Eski TEK şarkının anahtarı. Çalma listesi geldikten sonra da geçerli
  /// kalır (geriye dönük uyumluluk).
  static const musicKey = 'background_music';
  static final OkeySoundService instance = OkeySoundService._();

  OkeySoundService._();

  bool _enabled = true;
  bool _musicEnabled = true;
  bool _voiceEnabled = true;
  bool _loaded = false;

  /// Arka plan müziği ayrı bir oynatıcıda çalar. Efekt havuzundan bilerek
  /// ayrıdır: efektler müziği kesmemeli.
  AudioPlayer? _musicPlayer;

  /// ÇALMA LİSTESİ — admin birden çok şarkı yükleyebilir.
  /// Şarkı bitince sıradakine geçilir; liste bitince başa dönülür.
  List<({String url, String name})> _playlist = [];
  int _trackIndex = 0;
  StreamSubscription<void>? _trackEndSub;

  /// Şu an çalan şarkının görünen adı (bildirim panelinde gösterilir).
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  static const int _nowPlayingNotificationId = 9024001;
  static const _nowPlayingChannel = AndroidNotificationChannel(
    'okey_now_playing',
    'Okey — Şimdi Çalıyor',
    description: 'Okey masasında arka plan müziği çalarken gösterilir.',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  /// Bildirim panelindeki aksiyon düğmelerinin ID'leri.
  static const _actionPause = 'okey_music_pause';
  static const _actionResume = 'okey_music_resume';
  static const _actionPrev = 'okey_music_prev';
  static const _actionNext = 'okey_music_next';
  static const _actionClose = 'okey_music_close';

  // Bildirim düğmelerinin ikonları — android/app/src/main/res/drawable
  // altındaki vektör çizimler. Sistem çizimleri (@android:drawable/...)
  // KULLANILAMAZ: eklenti ismi UYGULAMANIN paketinde arar
  // (resources.getIdentifier(name, "drawable", packageName)), android
  // paketinde değil; sistem adı verilirse ikon sessizce hiç görünmez.
  static const _iconPlay = DrawableResourceAndroidBitmap('ic_notif_play');
  static const _iconPause = DrawableResourceAndroidBitmap('ic_notif_pause');
  static const _iconPrev = DrawableResourceAndroidBitmap('ic_notif_prev');
  static const _iconNext = DrawableResourceAndroidBitmap('ic_notif_next');
  static const _iconClose = DrawableResourceAndroidBitmap('ic_notif_close');

  /// Bildirimdeki ALBÜM KAPAĞI (largeIcon).
  ///
  /// `drawable-nodpi/ic_music_art.png` — vektör DEĞİL, gerçek raster: eklenti
  /// largeIcon'u `BitmapFactory.decodeResource` ile okur ve vektör çizimlerde
  /// `null` döner (kapak sessizce hiç görünmez). Kaynağı
  /// `scripts/generate_music_art.py` üretir.
  static const _artwork = DrawableResourceAndroidBitmap('ic_music_art');

  /// Bildirim kartının vurgu rengi (Android başlık/ikon tonlaması).
  static const _brandColor = Color(0xFFD91A73);

  /// Duraklat/Devam Et düğmesinin doğru etiketle gösterilebilmesi için.
  bool _musicPaused = false;
  bool get isMusicPaused => _musicPaused;

  /// Bildirim yeniden çizilirken (Duraklat/Devam Et sonrası) hangi şarkı adı
  /// gösterilecek — her seferinde playlist index hesabını tekrarlamamak için.
  String _currentTrackName = 'Şarkı';

  /// Oynatıcıya ŞU AN yüklenmiş şarkının URL'si.
  ///
  /// `startMusic()` ekran/menü açılışlarında tekrar tekrar çağrılıyor;
  /// bu alan olmadan her çağrı çalan parçayı BAŞA sarıyordu.
  String? _playingUrl;

  /// Çalan şarkının KONUMU ve UZUNLUĞU — "şimdi çalıyor" panelindeki
  /// ilerleme çubuğu ve süre yazısı için.
  ///
  /// [musicState]'ten AYRI bir bildirici: konum saniyede ~5 kez değişiyor;
  /// aynı bildiriciyi kullansaydık müzik durumunu dinleyen HER ekran
  /// (yan menü, oyun masası) saniyede beş kez yeniden çizilirdi. Bunu
  /// yalnızca ilerleme çubuğu dinler.
  final ValueNotifier<({Duration position, Duration total})> musicProgress =
      ValueNotifier((position: Duration.zero, total: Duration.zero));
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  /// Müzik durumu (çalıyor/duraklatıldı/şarkı değişti) her değiştiğinde artan
  /// sayaç. Bildirim panelinden veya başka bir ekrandan yapılan değişikliğin
  /// açık olan arayüze yansıması için dinlenir.
  final ValueNotifier<int> musicState = ValueNotifier<int>(0);

  /// Arka plan izolatından gelen bildirim düğmesi olaylarının portu.
  ReceivePort? _actionPort;

  void _notifyMusicState() => musicState.value++;

  /// Eksik olduğu anlaşılan sesler — tekrar tekrar denenmez.
  final Set<OkeySound> _missing = {};

  /// Ses altyapısı bu ortamda hiç çalışmıyor (eklenti yok / platform
  /// desteklemiyor). Bir kez tespit edilince bir daha denenmez.
  bool _audioUnavailable = false;

  /// Admin panelinden yüklenmiş ses dosyalarının URL'leri (sound_key -> url).
  /// Varsa paketteki assets/sounds/ dosyasının YERİNE bunlar çalınır.
  Map<String, String> _remoteUrls = {};

  /// Kısa efektler üst üste binebilsin diye küçük bir oynatıcı havuzu.
  final List<AudioPlayer> _pool = [];
  int _poolIndex = 0;
  static const _poolSize = 3;

  bool get isEnabled => _enabled;
  bool get isMusicEnabled => _musicEnabled;

  /// SESLİ ANONS ("Seri açıldı", "Çift açıldı", "Son üç taş") açık mı?
  ///
  /// Efektlerden ve müzikten AYRI bir tercih: konuşma, efektlerin aksine
  /// masadaki diğer seslerin üstüne biner ve kalabalık bir yerde rahatsız
  /// edici olabilir. Kullanıcı efektleri açık tutup yalnızca anonsu
  /// susturabilsin.
  bool get isVoiceEnabled => _voiceEnabled;

  /// Müzik GERÇEKTEN çalıyor mu? (`isMusicEnabled` sadece tercihi söyler;
  /// duraklatılmış ya da hiç başlamamış olabilir.)
  bool get isMusicPlaying =>
      _musicEnabled && !_musicPaused && _playingUrl != null;

  /// Çalınabilecek en az bir şarkı var mı?
  bool get hasMusic => _playlist.isNotEmpty;

  /// Çalma listesindeki şarkı sayısı.
  int get musicTrackCount => _playlist.length;

  /// Şu an çalan (veya son çalınan) şarkının görünen adı.
  String get currentTrackName => _currentTrackName;

  /// Çalma listesindeki şu anki şarkının sırası.
  int get currentTrackIndex => _trackIndex;

  /// Çalma listesi — sadece isim göstermek için (dışarıya salt okunur).
  List<({String url, String name})> get playlist =>
      List.unmodifiable(_playlist);

  /// Çalma listesini sunucudan tazeler.
  ///
  /// ASLA hata fırlatmaz — müzik tamamen opsiyoneldir.
  Future<void> refreshPlaylist() async {
    try {
      final rows = await Supabase.instance.client.rpc('okey_list_music');
      final tracks = <({String url, String name})>[];
      for (final r in (rows as List? ?? const [])) {
        final m = r as Map;
        final u = m['public_url'] as String?;
        if (u == null || u.isEmpty) continue;
        final name = (m['display_name'] as String?)?.trim();
        tracks.add((
          url: u,
          name: (name == null || name.isEmpty) ? 'Şarkı' : name,
        ));
      }
      // AYNI ŞARKI KÜMESİ → SIRAYI OLDUĞU GİBİ KORU.
      //
      // Bu metot yalnızca oyun açılışında değil, yan menü her açıldığında —
      // yani pratikte HER EKRANDA — çağrılıyor. Eskiden her çağrıda liste
      // yeniden karılıyor, `_trackIndex` aynı kaldığı hâlde altındaki şarkı
      // değişiyordu. Kullanıcının gördüğü sonuç: "şarkılar her ekranda
      // farklı çalıyor". Karma artık yalnızca liste GERÇEKTEN değiştiğinde
      // (admin şarkı ekledi/sildi) yapılır.
      final sameSet =
          tracks.length == _playlist.length &&
          tracks
              .map((t) => t.url)
              .toSet()
              .containsAll(_playlist.map((t) => t.url));
      if (sameSet && _playlist.isNotEmpty) return;

      tracks.shuffle(); // her oturumda farklı sırayla çalsın

      // Çalan şarkı yeni listede de varsa imleci ONA taşı — liste değişti
      // diye çalan parçanın kesilmesi için bir sebep yok.
      final playing = _playingUrl;
      final keepIndex = playing == null
          ? -1
          : tracks.indexWhere((t) => t.url == playing);
      _playlist = tracks;
      _trackIndex = keepIndex >= 0 ? keepIndex : 0;
      if (_trackIndex >= _playlist.length) _trackIndex = 0;
      if (_playlist.isNotEmpty && _playingUrl == null) {
        _currentTrackName = _playlist[_trackIndex].name;
      }
      _notifyMusicState();
    } catch (_) {
      // Liste alınamazsa müzik çalmaz; oyun etkilenmez.
    }
  }

  /// Kayıtlı ses tercihini ve admin'in yüklediği ses dosyalarını yükler.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
      _musicEnabled = prefs.getBool(_musicPrefsKey) ?? true;
      _voiceEnabled = prefs.getBool(_voicePrefsKey) ?? true;
    } catch (_) {
      _enabled = true;
      _musicEnabled = true;
      _voiceEnabled = true;
    }
    await refreshRemoteSounds();
  }

  /// Admin panelinden yüklenmiş ses dosyalarının listesini tazeler.
  Future<void> refreshRemoteSounds() async {
    try {
      final rows = await Supabase.instance.client
          .from('okey_sound_assets')
          .select('sound_key, public_url');
      final map = <String, String>{};
      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;
        final key = m['sound_key'] as String?;
        final url = m['public_url'] as String?;
        if (key != null && url != null && url.isNotEmpty) map[key] = url;
      }
      _remoteUrls = map;
      // Yeni dosya yüklenmiş olabilir — "eksik" işaretlerini sıfırla
      _missing.clear();
    } catch (_) {
      // Ses tamamen opsiyonel; liste alınamazsa paketteki dosyalar kullanılır.
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value && !_audioUnavailable) {
      for (final p in _pool) {
        try {
          // ÖNEMLİ: ses eklentisi yoksa stop() hiç tamamlanmayabilir —
          // zaman aşımı olmadan burası kilitleniyordu.
          await p.stop().timeout(const Duration(milliseconds: 300));
        } catch (_) {
          // durdurulamadıysa da ses kapalı sayılır
        }
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // tercih kaydedilemezse de ses açık/kapalı çalışmaya devam eder
    }
  }

  Future<bool> toggle() async {
    await setEnabled(!_enabled);
    return _enabled;
  }

  // -------------------------------------------------------------------------
  // ARKA PLAN MÜZİĞİ
  //
  // Efektlerden BAĞIMSIZ açılıp kapanır: kullanıcı efektleri açık tutup
  // yalnızca müziği susturabilir. Müzik yalnızca admin panelinden bir dosya
  // yüklendiyse çalar; yüklenmemişse sessizce hiçbir şey yapmaz.
  // -------------------------------------------------------------------------

  Future<void> setMusicEnabled(bool value) async {
    _musicEnabled = value;
    if (value) {
      await startMusic();
    } else {
      await stopMusic();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_musicPrefsKey, value);
    } catch (_) {
      // tercih kaydedilemezse de müzik açık/kapalı çalışmaya devam eder
    }
  }

  Future<bool> toggleMusic() async {
    await setMusicEnabled(!_musicEnabled);
    return _musicEnabled;
  }

  /// Çalma listesini başlatır. ASLA hata fırlatmaz.
  ///
  /// Tek şarkı varsa döngüye alınır; birden çok şarkı varsa biri bitince
  /// sıradakine geçilir ve liste bittiğinde başa dönülür.
  Future<void> startMusic({bool restart = false}) async {
    if (!_musicEnabled || _audioUnavailable) return;
    if (_playlist.isEmpty) await refreshPlaylist();
    if (_playlist.isEmpty) return;
    if (_trackIndex >= _playlist.length) _trackIndex = 0;

    final track = _playlist[_trackIndex];

    // AYNI ŞARKI ZATEN ÇALIYOR → DOKUNMA.
    //
    // Oyun ekranı, yan menü ve müzik açma/kapama hepsi bu metodu çağırıyor.
    // Koşulsuz `play()` çağrısı parçayı her seferinde başa sarıyordu; ekran
    // değiştirdikçe şarkının baştan başlamasının sebebi buydu.
    if (!restart &&
        !_musicPaused &&
        _musicPlayer != null &&
        _playingUrl == track.url) {
      _currentTrackName = track.name;
      unawaited(_showNowPlayingNotification(_currentTrackName));
      return;
    }

    final completer = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          _musicPlayer ??= AudioPlayer();

          // Tek şarkı: döngü. Birden çok: bitince sıradakine geç.
          await _musicPlayer!.setReleaseMode(
            _playlist.length == 1 ? ReleaseMode.loop : ReleaseMode.stop,
          );
          await _musicPlayer!.setVolume(0.35); // efektlerin önüne geçmesin

          await _trackEndSub?.cancel();
          // Konum/uzunluk akışları HER parçada yeniden kurulur (oynatıcı
          // aynı kalsa da eski abonelik önceki parçanın son değerini
          // taşıyordu).
          await _positionSub?.cancel();
          await _durationSub?.cancel();
          musicProgress.value = (position: Duration.zero, total: Duration.zero);
          _positionSub = _musicPlayer!.onPositionChanged.listen(
            (pos) => musicProgress.value = (
              position: pos,
              total: musicProgress.value.total,
            ),
            onError: (_) {},
          );
          _durationSub = _musicPlayer!.onDurationChanged.listen(
            (total) => musicProgress.value = (
              position: musicProgress.value.position,
              total: total,
            ),
            onError: (_) {},
          );
          if (_playlist.length > 1) {
            _trackEndSub = _musicPlayer!.onPlayerComplete.listen((_) {
              _trackIndex = (_trackIndex + 1) % _playlist.length;
              unawaited(startMusic(restart: true));
            });
          }

          await _musicPlayer!
              .play(UrlSource(track.url))
              .timeout(const Duration(seconds: 5));

          // Bildirim panelinde şarkı adını göster — çalma başarılı olduysa.
          _musicPaused = false;
          _playingUrl = track.url;
          _currentTrackName = track.name;
          _notifyMusicState();
          unawaited(_showNowPlayingNotification(_currentTrackName));
        } catch (_) {
          // müzik tamamen opsiyonel
          _playingUrl = null;
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (_, __) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  /// Sıradaki şarkıya geçer.
  Future<void> nextTrack() async {
    if (_playlist.length < 2) return;
    _trackIndex = (_trackIndex + 1) % _playlist.length;
    await _playCurrentTrack();
  }

  /// Önceki şarkıya geçer.
  Future<void> previousTrack() async {
    if (_playlist.length < 2) return;
    _trackIndex = (_trackIndex - 1 + _playlist.length) % _playlist.length;
    await _playCurrentTrack();
  }

  /// İmlecin gösterdiği şarkıyı BAŞTAN çalar.
  ///
  /// Müzik duraklatılmışsa ya da tercih kapalıysa önce açar: kullanıcı
  /// "sonraki"ye bastığında beklediği şey sıradaki şarkının ÇALMASIDIR,
  /// sessizce imlecin kaymasi değil.
  Future<void> _playCurrentTrack() async {
    _musicPaused = false;
    if (!_musicEnabled) {
      // setMusicEnabled(true) zaten startMusic()'i çağırır.
      await setMusicEnabled(true);
      return;
    }
    await startMusic(restart: true);
  }

  /// Yan menüdeki ▶/⏸ düğmesi için: müziği KAPATMADAN duraklatır ya da
  /// kaldığı yerden devam ettirir.
  ///
  /// `toggleMusic()`ten farkı, tercihi (ve dolayısıyla bir sonraki
  /// açılıştaki davranışı) değiştirmemesi ve çalma konumunu koruması —
  /// eskiden ▶'a her basışta şarkı baştan başlıyordu.
  Future<void> togglePlayPause() async {
    if (!_musicEnabled) {
      await setMusicEnabled(true);
      return;
    }
    if (_musicPaused || _playingUrl == null) {
      await resumeMusicPlayback();
    } else {
      await pauseMusic();
    }
  }

  /// Müziği DURAKLATIR (durdurmaz) — bildirim panelindeki "Duraklat"
  /// düğmesi ve/veya uygulama içi kontroller için. `stopMusic()`'ten farkı:
  /// çalma pozisyonunu korur, [resumeMusicPlayback] ile kaldığı yerden
  /// devam eder.
  Future<void> pauseMusic() async {
    final p = _musicPlayer;
    if (p == null || _musicPaused) return;
    try {
      await p.pause().timeout(const Duration(milliseconds: 300));
      _musicPaused = true;
      _notifyMusicState();
      unawaited(_showNowPlayingNotification(_currentTrackName));
    } catch (_) {
      // duraklatılamadıysa müzik çalmaya devam eder
    }
  }

  /// [pauseMusic] ile duraklatılmış müziği kaldığı yerden devam ettirir.
  /// Oynatıcı hiç başlamadıysa (ör. servis yeniden kurulduysa) baştan başlar.
  Future<void> resumeMusicPlayback() async {
    if (!_musicEnabled) {
      // Bildirimden "Devam Et"e basan kullanıcı müziği açmak istiyor.
      await setMusicEnabled(true);
      return;
    }
    final p = _musicPlayer;
    if (p == null || _playingUrl == null) {
      _musicPaused = false;
      await startMusic(restart: true);
      return;
    }
    try {
      await p.resume().timeout(const Duration(milliseconds: 300));
      _musicPaused = false;
      _notifyMusicState();
      unawaited(_showNowPlayingNotification(_currentTrackName));
    } catch (_) {
      // devam ettirilemediyse sessizce yut
    }
  }

  Future<void> stopMusic() async {
    await _trackEndSub?.cancel();
    _trackEndSub = null;
    await _positionSub?.cancel();
    _positionSub = null;
    await _durationSub?.cancel();
    _durationSub = null;
    musicProgress.value = (position: Duration.zero, total: Duration.zero);
    _musicPaused = false;
    _playingUrl = null;
    _notifyMusicState();
    unawaited(_hideNowPlayingNotification());
    final p = _musicPlayer;
    if (p == null) return;
    try {
      await p.stop().timeout(const Duration(milliseconds: 300));
    } catch (_) {
      // durdurulamadıysa da müzik kapalı sayılır
    }
  }

  // ---------------------------------------------------------------------
  // BİLDİRİM PANELİ — "şimdi çalıyor" + aktarım düğmeleri
  //
  // Müzik çalarken bildirim panelinde kalıcı (ongoing) bir bildirim
  // gösterir; Duraklat/Devam Et, Sonraki ve Kapat düğmeleri içerir.
  //
  // SINIR: bu, kilit ekranı/Bluetooth/Android Auto ile tümleşik gerçek bir
  // MediaStyle medya oturumu DEĞİL (o `audio_service` + arka plan servisi
  // gerektirir) — sadece bildirimdeki düğmelere DOKUNULDUĞUNDA çalışır ve
  // uygulama süreci hayattayken güvenilirdir. Düğmeler uygulamayı ÖNE
  // GETİRMEZ (showsUserInterface: false) — getirseydi Android yeni bir
  // intent ile MainActivity'yi başlatıp kullanıcıyı o an bulunduğu
  // ekrandan (ör. Okey masası) atardı. ASLA hata fırlatmaz: bildirim de
  // müzik gibi tamamen opsiyoneldir.
  // ---------------------------------------------------------------------

  Future<void> _ensureNotificationsReady() async {
    if (_notificationsReady) return;
    _notificationsReady =
        true; // tek seferlik deneme — başarısız olsa da tekrar denenmez
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      // Düğme olayları ARKA PLAN izolatından gelecek (bkz.
      // [okeyMusicActionPortName]); önce onları karşılayacak portu aç.
      _registerActionPort();
      await _notifications.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
        // Bildirimin GÖVDESİNE dokunma (düğmeye değil) buraya düşer.
        onDidReceiveNotificationResponse: _onNotificationAction,
        // `showsUserInterface: false` verilmiş DÜĞMELER yalnızca buraya
        // düşer — bu parametre olmadan eklenti çağrı adresini hiç
        // kaydetmediği için düğmeler HİÇBİR ŞEY YAPMIYORDU.
        onDidReceiveBackgroundNotificationResponse:
            okeyMusicNotificationBackgroundHandler,
      );
      if (!kIsWeb && Platform.isAndroid) {
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_nowPlayingChannel);
      }
    } catch (_) {
      // Bildirim altyapısı kurulamazsa müzik yine de çalmaya devam eder.
    }
  }

  /// Arka plan izolatının göndereceği aksiyonları karşılayan portu açar.
  void _registerActionPort() {
    if (_actionPort != null) return;
    try {
      final port = ReceivePort();
      // Aynı isimde eski bir kayıt kalmışsa (sıcak yeniden başlatma)
      // registerPortWithName false döner ve olaylar kaybolurdu.
      IsolateNameServer.removePortNameMapping(okeyMusicActionPortName);
      IsolateNameServer.registerPortWithName(
        port.sendPort,
        okeyMusicActionPortName,
      );
      port.listen((message) {
        if (message is String) _handleMusicAction(message);
      });
      _actionPort = port;
    } catch (_) {
      // Port açılamazsa bildirim düğmeleri çalışmaz; müzik etkilenmez.
    }
  }

  /// Bildirimin GÖVDESİNE dokunulunca (düğmelerine değil).
  void _onNotificationAction(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId != null) _handleMusicAction(actionId);
  }

  /// Bildirimdeki bir düğmeye (Önceki/Duraklat/Devam Et/Sonraki/Kapat)
  /// dokunulunca — hangi izolattan geldiği fark etmez, iş burada yapılır.
  void _handleMusicAction(String actionId) {
    switch (actionId) {
      case _actionPause:
        unawaited(pauseMusic());
        break;
      case _actionResume:
        unawaited(resumeMusicPlayback());
        break;
      case _actionPrev:
        unawaited(previousTrack());
        break;
      case _actionNext:
        unawaited(nextTrack());
        break;
      case _actionClose:
        unawaited(setMusicEnabled(false));
        break;
    }
  }

  Future<void> _showNowPlayingNotification(String songName) async {
    if (kIsWeb) return; // masaüstü/web'de bildirim paneli kavramı farklı
    try {
      await _ensureNotificationsReady();
      // showsUserInterface: false — bu düğmeler sadece arka planda ses
      // durumunu değiştirir, UI göstermesi GEREKMEZ. true bırakılınca
      // Android uygulamayı yeni bir intent ile öne getiriyor, bu da
      // kullanıcının o an bulunduğu ekrandan (ör. Okey masası) atılmasına
      // yol açıyordu.
      // DÜĞME SIRASI = medya oynatıcı sırası: ⏮ ⏯ ⏭ ✕
      //
      // Android bildirim panelinde en fazla 3 düğme KOMPAKT görünümde
      // gösterilir; kalanlar bildirim genişletilince çıkar. Bu yüzden en
      // sık kullanılanlar (önceki/duraklat/sonraki) başa, "Kapat" sona
      // konur. Tek şarkılık listede önceki/sonraki hiç eklenmez — üç
      // düğmenin ikisi işlevsiz olurdu.
      final multi = _playlist.length > 1;
      final actions = <AndroidNotificationAction>[
        // cancelNotification: false — ÖNEMLİ. Bu alanın varsayılanı `true`
        // olduğu için Önceki/Duraklat/Sonraki'ye basıldığında Android
        // bildirimi KAPATIYORDU: kullanıcı hangi düğmeye basarsa bassın
        // "şimdi çalıyor" kartı ekrandan kayboluyordu. Yalnızca "Kapat"
        // bildirimi kaldırmalı.
        if (multi)
          const AndroidNotificationAction(
            _actionPrev,
            'Önceki',
            icon: _iconPrev,
            showsUserInterface: false,
            cancelNotification: false,
          ),
        _musicPaused
            ? const AndroidNotificationAction(
                _actionResume,
                'Devam Et',
                icon: _iconPlay,
                showsUserInterface: false,
                cancelNotification: false,
              )
            : const AndroidNotificationAction(
                _actionPause,
                'Duraklat',
                icon: _iconPause,
                showsUserInterface: false,
                cancelNotification: false,
              ),
        if (multi)
          const AndroidNotificationAction(
            _actionNext,
            'Sonraki',
            icon: _iconNext,
            showsUserInterface: false,
            cancelNotification: false,
          ),
        const AndroidNotificationAction(
          _actionClose,
          'Kapat',
          icon: _iconClose,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];

      // BAŞLIK = ŞARKI ADI, ikinci satır = yalnızca DURUM.
      //
      // Eskiden başlık "Şimdi çalıyor", gövde şarkı adıydı: kartın en
      // büyük/kalın satırını sabit bir etiket kaplıyor, asıl bilgi altta
      // küçülüyordu. Uygulama adı da ikinci satırda tekrar ediyordu —
      // bildirimin kendi başlığında zaten yazdığı için gereksizdi. Çalarken
      // ikinci satır boş bırakılır; çaldığını kronometre söylüyor.
      final subtitle = _musicPaused ? 'Duraklatıldı' : '';

      // GEÇEN SÜRE — bildirimin kendi kronometresi.
      //
      // Panelde HAREKETLİ tek şey budur ve bedava gelir: `when` anına göre
      // sayacı Android'in kendisi ilerletir, biz saniyede bir bildirimi
      // yeniden yayınlamayız (bu hem pil hem de titreşim/ses açısından
      // pahalı olurdu). Duraklatınca kronometre kapatılır — donmuş bir
      // sayaç bozuk görünür.
      final startedAt =
          DateTime.now().millisecondsSinceEpoch -
          musicProgress.value.position.inMilliseconds;

      await _notifications.show(
        _nowPlayingNotificationId,
        songName,
        subtitle,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _nowPlayingChannel.id,
            _nowPlayingChannel.name,
            channelDescription: _nowPlayingChannel.description,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: !_musicPaused, // duraklatınca kaydırarak kapatılabilir
            autoCancel: false,
            onlyAlertOnce: true, // şarkı değişince yeniden titretmez/uyarmaz
            playSound: false,
            enableVibration: false,
            icon: '@mipmap/ic_launcher',
            // Kapak: plak görseli. Bildirim kartındaki tek "görsel" bu.
            largeIcon: _artwork,
            color: _brandColor,
            ticker: songName,
            // Kilit ekranında da görünsün: müzik gizli bir bilgi değil.
            visibility: NotificationVisibility.public,
            showWhen: !_musicPaused,
            when: _musicPaused ? null : startedAt,
            usesChronometer: !_musicPaused,
            category: AndroidNotificationCategory.transport,
            actions: actions,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (_) {
      // Bildirim gösterilemezse müzik yine de çalmaya devam eder.
    }
  }

  Future<void> _hideNowPlayingNotification() async {
    if (kIsWeb) return;
    try {
      await _notifications.cancel(_nowPlayingNotificationId);
    } catch (_) {
      // yoksayılabilir
    }
  }

  AudioPlayer _nextPlayer() {
    if (_pool.length < _poolSize) {
      final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      // EFEKTLER SES ODAĞINI (audio focus) İSTEMESİN.
      //
      // audioplayers'ın varsayılanı AUDIOFOCUS_GAIN'dir: 300 ms'lik bir taş
      // sesi bile odağı isteyince Android arka plan müziğine
      // AUDIOFOCUS_LOSS gönderir ve eklenti müzik oynatıcıyı DURAKLATIR.
      // Kullanıcının gördüğü sonuç: "herhangi bir butona tıklayınca şarkı
      // kayboluyor". `mixWithOthers` odak isteğini tamamen kapatır, efekt
      // müziğin ÜSTÜNE karışarak çalar.
      unawaited(
        p
            .setAudioContext(
              AudioContextConfig(
                focus: AudioContextConfigFocus.mixWithOthers,
              ).build(),
            )
            .catchError((_) {
              // bazı platformlarda desteklenmez — efekt yine de çalar
            }),
      );
      _pool.add(p);
      return p;
    }
    _poolIndex = (_poolIndex + 1) % _pool.length;
    return _pool[_poolIndex];
  }

  // -------------------------------------------------------------------------
  // SESLİ ANONS (TTS)
  //
  // "Seri açıldı" / "Çift açıldı" / "Ahmet, son üç taş" gibi cümleler cihazın
  // kendi konuşma motoruyla okunur.
  //
  // ## Neden TTS, neden hazır ses dosyası değil
  //
  // Anonsların biri DEĞİŞKEN metin taşıyor: son üç taşı kalan oyuncunun ADI.
  // Hazır .wav dosyalarıyla bu cümle ya isimsiz kalırdı ("son üç taş" — kimin?)
  // ya da masadaki her ad için ayrı dosya gerekirdi. Kullanıcının isteği tam
  // olarak "herkes bilsin BU KULLANICININ son 3 taşı kalmış" olduğu için ad
  // cümlenin ayrılmaz parçası.
  //
  // ## Asla oyunu bozmaz
  //
  // Efektlerdeki zincirin aynısı: motor yoksa, dil yüklü değilse ya da eklenti
  // bu platformda derlenmemişse (ör. Linux masaüstü) anons SESSİZCE atlanır.
  // Ekrandaki yazılı bant (bkz. OkeyGameProvider.announcement) her koşulda
  // görünür, yani bilgi kaybolmaz.
  // -------------------------------------------------------------------------

  FlutterTts? _tts;
  bool _ttsUnavailable = false;

  /// Aynı cümlenin üst üste iki kez okunmasını engeller (tazeleme yarışları).
  String? _lastSpoken;
  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> setVoiceEnabled(bool value) async {
    _voiceEnabled = value;
    if (!value) {
      try {
        await _tts?.stop().timeout(const Duration(milliseconds: 300));
      } catch (_) {
        // durdurulamadıysa da anons kapalı sayılır
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_voicePrefsKey, value);
    } catch (_) {
      // tercih kaydedilemezse de anons açık/kapalı çalışmaya devam eder
    }
  }

  Future<bool> toggleVoice() async {
    await setVoiceEnabled(!_voiceEnabled);
    return _voiceEnabled;
  }

  /// Bir cümleyi Türkçe seslendirir. ASLA hata fırlatmaz.
  Future<void> speak(String text) async {
    if (!_voiceEnabled || _ttsUnavailable) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Aynı cümle 3 saniye içinde tekrar istenirse yut: tek bir hamle birden
    // çok realtime olayı doğuruyor ve tazelemeler üst üste binebiliyor.
    final now = DateTime.now();
    if (trimmed == _lastSpoken &&
        now.difference(_lastSpokenAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastSpoken = trimmed;
    _lastSpokenAt = now;

    // audioplayers gibi flutter_tts de eklenti yokken hatayı asenkron
    // fırlatabilir; korumalı zone olmadan bu hata zone'a kaçardı.
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    runZonedGuarded(
      () async {
        try {
          final tts = await _ensureTts();
          if (tts == null) {
            finish();
            return;
          }
          // Önceki anons hâlâ okunuyorsa kesilir: masada olan bitenin EN SON
          // hali duyulmalı, sıraya girmiş eski cümleler değil.
          await tts.stop();
          await tts.speak(trimmed);
        } catch (_) {
          // Motor yok / dil yüklü değil → bir daha denenmez.
          _ttsUnavailable = true;
          if (kDebugMode) {
            debugPrint('OkeySoundService: TTS kullanılamıyor, anons atlanıyor.');
          }
        }
        finish();
      },
      (error, stack) {
        _ttsUnavailable = true;
        if (kDebugMode) {
          debugPrint('OkeySoundService: TTS altyapısı yok ($error).');
        }
        finish();
      },
    );

    return completer.future;
  }

  Future<FlutterTts?> _ensureTts() async {
    if (_ttsUnavailable) return null;
    final existing = _tts;
    if (existing != null) return existing;

    final tts = FlutterTts();
    // iOS: masada arka plan müziği çalıyor. Varsayılan kategori müziği
    // KESERDİ; ambient + mixWithOthers ile anons müziğin ÜSTÜNE biner.
    if (!kIsWeb && Platform.isIOS) {
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.ambient,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
    await tts.setLanguage('tr-TR');
    await tts.setSpeechRate(0.5); // Android varsayılanı fazla hızlı okuyor
    await tts.setPitch(1.0);
    await tts.setVolume(1.0);
    // Anons bittiğini BEKLEMEYİZ: konuşma oyun akışını asla geciktirmemeli.
    await tts.awaitSpeakCompletion(false);
    _tts = tts;
    return tts;
  }

  /// Bir efekti çalar. Ses kapalıysa hiçbir şey yapmaz; dosya yoksa veya ses
  /// altyapısı bu ortamda çalışmıyorsa dokunsal geri bildirime düşer.
  ///
  /// ASLA hata fırlatmaz — ses tamamen opsiyoneldir ve hiçbir koşulda oyunu
  /// etkilememelidir.
  Future<void> play(OkeySound sound) async {
    if (!_enabled) return;
    if (_audioUnavailable || _missing.contains(sound)) {
      await _safeHaptic(sound);
      return;
    }
    final played = await _tryPlay(sound);
    if (!played) await _safeHaptic(sound);
  }

  /// audioplayers, eklenti bulunamadığında hatayı `AudioPlayer` yapıcısının
  /// içinden ASENKRON olarak fırlatır; bu hata normal try/catch ile
  /// yakalanamaz, doğrudan zone'a kaçar (test ortamında ve eklentinin
  /// bulunmadığı platformlarda görülür). Bu yüzden çağrı korumalı bir zone
  /// içinde yapılır.
  Future<bool> _tryPlay(OkeySound sound) {
    final completer = Completer<bool>();

    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    runZonedGuarded(
      () async {
        try {
          final player = _nextPlayer();
          await player.stop();
          // Öncelik: admin panelinden yüklenmiş dosya (uzak URL).
          // Yoksa uygulama paketindeki assets/sounds/ dosyası denenir.
          final remote = _remoteUrls[sound.name];
          if (remote != null && remote.isNotEmpty) {
            await player.play(UrlSource(remote));
          } else {
            await player.play(AssetSource(sound.assetPath));
          }
          finish(true);
        } catch (_) {
          // Dosya yok / oynatılamadı → bu efekti bir daha deneme
          _missing.add(sound);
          if (kDebugMode) {
            debugPrint(
              'OkeySoundService: assets/sounds/${sound.fileName} '
              'bulunamadı, titreşime düşülüyor.',
            );
          }
          finish(false);
        }
      },
      (error, stack) {
        // Eklenti yok / platform desteklemiyor → sesi tamamen devre dışı bırak
        _audioUnavailable = true;
        if (kDebugMode) {
          debugPrint(
            'OkeySoundService: ses altyapısı kullanılamıyor '
            '($error) — dokunsal geri bildirime geçiliyor.',
          );
        }
        finish(false);
      },
    );

    return completer.future;
  }

  Future<void> _safeHaptic(OkeySound sound) async {
    try {
      await sound.fallbackHaptic();
    } catch (_) {
      // bazı platformlarda titreşim yok — sessizce yut
    }
  }

  Future<void> dispose() async {
    try {
      await _tts?.stop().timeout(const Duration(milliseconds: 300));
    } catch (_) {
      // konuşma durdurulamadıysa da kapanış sürmeli
    }
    _actionPort?.close();
    _actionPort = null;
    IsolateNameServer.removePortNameMapping(okeyMusicActionPortName);
    for (final p in _pool) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _pool.clear();
  }
}
