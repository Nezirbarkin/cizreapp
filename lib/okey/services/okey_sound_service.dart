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

  /// ÇİP KAZANILDI — saatlik bonus ya da reklam ödülü cüzdana düştü
  /// (kullanıcı isteği, 2026-09-07: "bonus al tıkladığında çip (para sesi)
  /// vs çıksın").
  coin,

  /// ISTAKADA (takozda) taş oynatıldı — seçildi ya da başka slota taşındı.
  ///
  /// [discardTile]'dan AYRI bir ses: ıstaka oyuncunun önündedir, masaya
  /// atma değildir. Aynı sesi kullansaydık ıstakada taş kaydırmak "taş
  /// attım" gibi duyulurdu.
  rackTile,

  /// ARAYÜZ DÜĞMESİ tıklandı (AT, SERİ AÇ, ÇİFT DİZ, HUD ikonları...).
  ///
  /// Bilinçli olarak taş sesine benzemez: düğmeye basmak hamlenin
  /// kendisi değil, isteğidir.
  buttonTap,

  /// BEKLEME ODASINA BİR OYUNCU OTURDU (kullanıcı isteği, 2026-09-08:
  /// "oyuncu katılırken ses çıkartın").
  ///
  /// Bekleme odası sessizce yoklanır: koltuklar üç saniyede bir tazelenir ve
  /// masa, oyuncu ekrana bakmıyorken dolar. Ses, oyuncunun ekranı izlemeden
  /// masanın dolduğunu anlamasını sağlayan tek işaret.
  ///
  /// BOT OTURDUĞUNDA DA ÇALAR. Yalnız insanlar için çalsaydı sessizlik "bu
  /// gelen bir bottu" demenin en açık yolu olurdu — masadaki her şeyin botu
  /// gizlemesi ilkesiyle çelişirdi (bkz. OkeyRoomSeat.displayLabel,
  /// OkeyCornerPileWidget.isThinking).
  playerJoin,
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
      case OkeySound.coin:
        return 'coin.wav';
      case OkeySound.rackTile:
        return 'rack.wav';
      case OkeySound.buttonTap:
        return 'click.wav';
      case OkeySound.playerJoin:
        return 'join.wav';
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
      case OkeySound.coin:
        // Çip kazanmak KÜÇÜK ama iyi bir haber: hafif ama iki katmanlı
        // (tek bir tık, ödülü bir hamleyle aynı ağırlıkta gösterirdi).
        await HapticFeedback.mediumImpact();
        break;
      case OkeySound.rackTile:
      case OkeySound.buttonTap:
        // Saniyede birkaç kez tetiklenebilir: en hafif geri bildirim.
        await HapticFeedback.selectionClick();
        break;
      case OkeySound.playerJoin:
        // Masaya biri oturdu: bir hamle değil, bir HABER. Bildirim
        // seslerindeki orta şiddet.
        await HapticFeedback.mediumImpact();
        break;
    }
  }
}

/// Bir düğme geri çağrısını ARAYÜZ TIK SESİYLE sarar.
///
/// Okey'deki düğmelerin hepsi birkaç ortak parçadan geçer ([OkeyButton],
/// [OkeyCard], eylem çubuğundaki `_Control`); tık sesini tek tek her
/// `onPressed`'e eklemek yerine o parçalarda bu sarmalayıcı kullanılır —
/// yeni bir düğme eklendiğinde sesi hatırlamak gerekmez.
///
/// `null` geri çağrı `null` döner: kapalı düğme ses de çıkarmaz.
VoidCallback? withOkeyTapSound(VoidCallback? onTap) {
  if (onTap == null) return null;
  return () {
    unawaited(OkeySoundService.instance.play(OkeySound.buttonTap));
    onTap();
  };
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
  ///
  /// [isLocal] true ise `url` aslında cihazdaki bir DOSYA YOLUDUR ve
  /// [DeviceFileSource] ile çalınır. "Müziğim > Kitaplığım" bu yolu kullanır:
  /// böylece kullanıcının kendi şarkıları da bildirim kontrollerini, ilerleme
  /// çubuğunu ve yan menüdeki plak kartını olduğu gibi kullanır — ikinci bir
  /// ses motoru kurmaya gerek kalmaz.
  List<({String url, String name, bool isLocal})> _playlist = [];
  int _trackIndex = 0;
  StreamSubscription<void>? _trackEndSub;

  /// Çalma listesi nereden geliyor?
  ///
  /// Varsayılan [MusicPlaylistSource.radio]: bugüne kadarki davranışın
  /// birebir aynısı — liste sunucudan gelir, [refreshPlaylist] onu tazeler.
  /// Kullanıcı "Müziğim > Kitaplığım"dan bir şarkı çaldığında kaynak
  /// [MusicPlaylistSource.library] olur ve sunucu tazelemesi DEVRE DIŞI kalır;
  /// aksi hâlde yan menünün her açılışında kullanıcının kendi listesi
  /// sunucununkiyle değiştirilirdi.
  MusicPlaylistSource _source = MusicPlaylistSource.radio;

  /// Tekrar modu. Varsayılan [MusicRepeatMode.all] — bu özellik gelmeden
  /// önceki davranışın aynısı: liste bitince başa dönülür, tek şarkı döngüde.
  MusicRepeatMode _repeatMode = MusicRepeatMode.all;

  /// Karışık çalma. Liste sırası DEĞİŞMEZ; yalnızca "sıradaki" sorusunun
  /// cevabı [_shuffleOrder] üzerinden verilir. Böylece karışığı kapatınca
  /// kullanıcı kendi sırasına kaldığı yerden döner.
  bool _shuffle = false;
  List<int> _shuffleOrder = const [];

  /// Liste bitti ve tekrar kapalı: oynatıcı durdu ama kullanıcı durdurmadı.
  ///
  /// Başka bir ekranın (ör. Okey masası açılışı) [startMusic] çağrısı bu
  /// durumda müziği KENDİLİĞİNDEN yeniden başlatmamalı — kullanıcı listenin
  /// bitmesini bilerek seçti.
  bool _reachedEnd = false;

  static const _repeatPrefsKey = 'music_repeat_mode';
  static const _shufflePrefsKey = 'music_shuffle';

  /// Kullanıcının cihaz kitaplığını fon müziği listesine katan kaynak.
  ///
  /// Okey katmanı müzik özelliğini tanımaz (bağımlılık yönü tersine
  /// dönmesin); main.dart açılışta bu kancayı bağlar. Bağlanmazsa liste
  /// eskisi gibi yalnızca sunucudan gelir.
  static Future<List<({String url, String name})>> Function()?
  localTracksProvider;

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

  /// [startMusic] ÇAĞRI SAYACI — eş zamanlı çağrıların birbirini ezmesini
  /// önler.
  ///
  /// Bu metot bağımsız üç yerden üst üste tetiklenebilir: Okey masası
  /// açılışı, kullanıcının sonraki/önceki dokunuşu ve şarkı doğal olarak
  /// bitince otomatik geçiş. İki çağrı iç içe girdiğinde ikisi de aynı
  /// `_musicPlayer` üzerinde çalışır; DAHA ÖNCE başlayıp DAHA SONRA biten
  /// bir çağrı, kendi (artık eski) parça bilgisini en son yazan taraf
  /// olabiliyordu — ekranda "2. şarkı" yazarken aslında 3. şarkı çalıyordu.
  /// Her çağrı kendi sıra numarasını alır; yalnızca hâlâ EN GÜNCEL çağrı
  /// olan taraf sonucu yazar.
  int _playOp = 0;

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

  // -------------------------------------------------------------------------
  // DİNLEME İSTATİSTİĞİ (Admin > Müzik Çalar)
  //
  // Kim, hangi şarkıyı, ne kadar dinledi: şarkı başlayınca `start`, çalarken
  // her 30 sn'de `heartbeat` (+geçen süre), duraklatınca/kapatınca `pause`/
  // `stop`. Sunucu yalnızca özet tutar (kullanıcı × şarkı × gün); misafir
  // dinlemeleri kaydedilmez. Tamamen fire-and-forget: rapor başarısız olursa
  // müzik etkilenmez.
  // -------------------------------------------------------------------------
  static const _listenBeat = Duration(seconds: 30);
  Timer? _listenTimer;
  DateTime? _lastListenBeatAt;

  /// Son rapordan bu yana geçen saniyeyi verir ve sayacı sıfırlar.
  int _flushListenSeconds() {
    final last = _lastListenBeatAt;
    final now = DateTime.now();
    _lastListenBeatAt = now;
    if (last == null) return 0;
    return now.difference(last).inSeconds.clamp(0, 120);
  }

  void _reportMusic(String event, {int deltaSeconds = 0, String? url}) {
    final trackUrl = url ?? _playingUrl;
    if (trackUrl == null) return;

    // Kullanıcının kendi dosyası sunucuda YOK: yerel bir yolu istatistik
    // tablosuna yazmak hem anlamsız bir "parça" satırı üretir hem de
    // kullanıcının cihazındaki dosya adlarını sunucuya sızdırırdı. Kaynağa
    // değil ADRESE bakıyoruz — kullanıcı kataloğu kendi sırasıyla dinlediğinde
    // o parçalar sunucuda olduğu için raporlanmaya devam etmeli.
    if (!trackUrl.startsWith('http')) return;
    unawaited(() async {
      try {
        final client = Supabase.instance.client;
        if (client.auth.currentUser == null) return;
        await client.rpc(
          'music_report',
          params: {
            'p_track_key': trackUrl,
            'p_track_name': _currentTrackName,
            'p_event': event,
            'p_delta': deltaSeconds,
          },
        );
      } catch (_) {
        // istatistik opsiyonel; müzik etkilenmez
      }
    }());
  }

  void _startListenReporting({required bool isNewTrack}) {
    _lastListenBeatAt = DateTime.now();
    _reportMusic(isNewTrack ? 'start' : 'resume');
    _listenTimer?.cancel();
    _listenTimer = Timer.periodic(_listenBeat, (_) {
      if (!isMusicPlaying) return;
      _reportMusic('heartbeat', deltaSeconds: _flushListenSeconds());
    });
  }

  void _stopListenReporting(String event, {String? url}) {
    _listenTimer?.cancel();
    _listenTimer = null;
    final delta = _flushListenSeconds();
    _lastListenBeatAt = null;
    // Son dilimin süresi heartbeat olarak yazılır; ardından durum olayı.
    if (delta > 0) _reportMusic('heartbeat', deltaSeconds: delta, url: url);
    _reportMusic(event, url: url);
  }

  /// Eksik olduğu anlaşılan sesler — tekrar tekrar denenmez.
  final Set<OkeySound> _missing = {};

  /// Ses altyapısı bu ortamda hiç çalışmıyor (eklenti yok / platform
  /// desteklemiyor). Bir kez tespit edilince bir daha denenmez.
  bool _audioUnavailable = false;

  /// TARAYICI OTOMATİK OYNATMA KİLİDİ.
  ///
  /// Web'de tarayıcı, kullanıcı sayfayla ETKİLEŞMEDEN önce ses çalmayı
  /// reddeder (NotAllowedError). Bu kısıt olmasaydı sorun yoktu; ama
  /// [_tryPlay] o hatayı "dosya yok" sanıp efekti [_missing] listesine
  /// yazıyor, müzik denemesi de sessizce düşüyordu — web'de hiçbir sesin
  /// gelmemesinin sebebi buydu. Bu bayrak, ilk dokunuştan ÖNCEKİ
  /// başarısızlıkların KALICI sayılmasını engeller.
  ///
  /// Mobil/masaüstünde böyle bir kısıt yok: doğrudan açık başlar.
  bool _userGestured = !kIsWeb;

  /// SES EKLENTİSİ BU BUILD'DE HİÇ YOK (MissingPluginException).
  ///
  /// [_audioUnavailable]'dan ayrı tutulur: ilk kullanıcı dokunuşu
  /// ([notifyUserGesture]) otomatik oynatma kilidinden kaynaklanan
  /// başarısızlıkları temizler, ama eksik eklentiyi temizlememelidir —
  /// aksi halde her açılışta bir tur daha MissingPluginException fırlar.
  bool _audioPluginMissing = false;

  void _markAudioPluginMissing() {
    _audioPluginMissing = true;
    _audioUnavailable = true;
  }

  /// Sık tetiklenen arayüz seslerinin (düğme tıkı, ıstakada taş) en az
  /// aralığı. Hızlı art arda dokunuşlar aynı sesi kesip "cırtlak" bir
  /// tekrar üretiyordu.
  static const _uiSoundGap = Duration(milliseconds: 55);

  /// Müzik oynatıcısındaki duraklat/devam et/durdur çağrılarının üst
  /// zaman sınırı.
  ///
  /// ESKİDEN 300 ms'ydi. `audioplayers`'ın native `pause()`/`resume()`
  /// çağrısı — özellikle ses odağı (audio focus) yeniden müzakere
  /// edilirken veya cihaz biraz yoğunken — bu süreyi ARA SIRA aşıyordu.
  /// Süre dolduğunda `catch` bloğu devreye girip [_musicPaused] bayrağını
  /// GÜNCELLEMEDEN çıkıyordu; ama native çağrı arka planda çalışmaya devam
  /// edip birkaç yüz ms sonra GERÇEKTEN duraklatıyor/devam ettiriyordu.
  /// Sonuç: düğmenin ikonu ile sesin gerçek durumu birbirinden kopuyor,
  /// bir sonraki dokunuş "hiçbir şey yapmıyormuş" gibi görünüyordu —
  /// duraklat/devam et düğmesinin "ara sıra bozulması" buydu. 1200 ms,
  /// gerçek bir donmayı (eklenti tamamen yanıt vermiyor) hâlâ yakalar ama
  /// sıradan bir gecikmeyi hataya çevirmez.
  static const _musicControlTimeout = Duration(milliseconds: 1200);
  final Map<OkeySound, DateTime> _lastUiSoundAt = {};

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
  List<({String url, String name, bool isLocal})> get playlist =>
      List.unmodifiable(_playlist);

  /// Çalma listesi şu an nereden geliyor?
  MusicPlaylistSource get playlistSource => _source;

  MusicRepeatMode get repeatMode => _repeatMode;
  bool get isShuffle => _shuffle;

  bool get _hasValidIndex => _trackIndex >= 0 && _trackIndex < _playlist.length;

  /// Çalan (ya da sıradaki) parçanın adresi — cihaz parçalarında dosya yolu.
  String? get currentTrackUrl =>
      _hasValidIndex ? _playlist[_trackIndex].url : null;

  /// Çalan parça kullanıcının cihazından mı?
  bool get currentTrackIsLocal =>
      _hasValidIndex && _playlist[_trackIndex].isLocal;

  /// Sıradaki parçaların liste sırası (en çok [limit] tane).
  ///
  /// Karışık açıksa karışık sırayı, kapalıysa liste sırasını izler; tekrar
  /// "tümü" ise liste sonundan başa sarar. Tam ekran oynatıcıdaki
  /// "Sıradaki" bölümü bunu gösterir.
  List<int> upNextIndices({int limit = 20}) {
    final n = _playlist.length;
    if (n < 2 || !_hasValidIndex) return const [];

    final result = <int>[];
    if (_shuffle) {
      _ensureShuffleOrder();
      final pos = _shuffleOrder.indexOf(_trackIndex);
      for (var i = pos + 1; i < _shuffleOrder.length; i++) {
        result.add(_shuffleOrder[i]);
      }
    } else {
      for (var i = _trackIndex + 1; i < n; i++) {
        result.add(i);
      }
      if (_repeatMode == MusicRepeatMode.all) {
        for (var i = 0; i < _trackIndex; i++) {
          result.add(i);
        }
      }
    }
    return result.take(limit).toList();
  }

  /// Tekrar modunu değiştirir: tümü → tek şarkı → kapalı → tümü.
  Future<MusicRepeatMode> cycleRepeatMode() async {
    final next = switch (_repeatMode) {
      MusicRepeatMode.all => MusicRepeatMode.one,
      MusicRepeatMode.one => MusicRepeatMode.off,
      MusicRepeatMode.off => MusicRepeatMode.all,
    };
    await setRepeatMode(next);
    return next;
  }

  Future<void> setRepeatMode(MusicRepeatMode mode) async {
    _repeatMode = mode;
    // Çalan parçaya HEMEN uygulanır: "tek şarkı"ya geçen kullanıcı, çalan
    // şarkının bitince tekrar etmesini bekler — bir sonrakinin değil.
    await _applyEndBehavior();
    _notifyMusicState();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_repeatPrefsKey, mode.name);
    } catch (_) {
      // tercih kaydedilemezse bu oturum boyunca yine de geçerli
    }
  }

  Future<bool> toggleShuffle() async {
    _shuffle = !_shuffle;
    // Karışık AÇILINCA çalan parça yerinde kalır, kalanlar karılır — çalan
    // şarkı kesilmez ve hemen tekrar gelmez.
    _shuffleOrder = _shuffle ? _newShuffleOrder(first: _trackIndex) : const [];
    _notifyMusicState();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_shufflePrefsKey, _shuffle);
    } catch (_) {
      // tercih kaydedilemezse bu oturum boyunca yine de geçerli
    }
    return _shuffle;
  }

  /// Çalan parçada [position] noktasına atlar (ilerleme çubuğunu sürükleme).
  Future<void> seekMusic(Duration position) async {
    final p = _musicPlayer;
    if (p == null || _playingUrl == null) return;
    final target = position < Duration.zero ? Duration.zero : position;
    try {
      await p.seek(target).timeout(_musicControlTimeout);
      musicProgress.value = (
        position: target,
        total: musicProgress.value.total,
      );
    } catch (_) {
      // atlanamadıysa çalma olduğu yerden sürer
    }
  }

  /// Listedeki [index]'inci parçayı çalar ("Sıradaki" listesinden seçim).
  Future<void> playTrackAt(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _trackIndex = index;
    await _playCurrentTrack();
  }

  /// Karışık sıra: [first] başta, kalanlar karışık.
  List<int> _newShuffleOrder({int? first}) {
    final n = _playlist.length;
    final rest = [
      for (var i = 0; i < n; i++)
        if (i != first) i,
    ]..shuffle();
    if (first != null && first >= 0 && first < n) return [first, ...rest];
    return rest;
  }

  /// Karışık sıra listeyle uyumsuzsa (liste değişti) yeniden kurar.
  void _ensureShuffleOrder() {
    if (_shuffleOrder.length != _playlist.length ||
        !_shuffleOrder.contains(_trackIndex)) {
      _shuffleOrder = _newShuffleOrder(first: _trackIndex);
    }
  }

  /// Sıradaki (ya da önceki) parçanın liste sırası.
  ///
  /// [wrap] false ise liste sonunda null döner — tekrar KAPALIYKEN şarkı
  /// kendi kendine bittiğinde kullanılır. Elle ⏭'e basıldığında hep sarar.
  int? _neighbourIndex({required bool forward, required bool wrap}) {
    final n = _playlist.length;
    if (n == 0) return null;

    if (!_shuffle) {
      final i = _trackIndex + (forward ? 1 : -1);
      if (i >= 0 && i < n) return i;
      if (!wrap) return null;
      return (i + n) % n;
    }

    _ensureShuffleOrder();
    final pos = _shuffleOrder.indexOf(_trackIndex);
    final i = pos + (forward ? 1 : -1);
    if (i >= 0 && i < _shuffleOrder.length) return _shuffleOrder[i];
    if (!wrap) return null;
    if (!forward) return _shuffleOrder.last;

    // Karışık tur bitti: yeni bir tur kur. Az önce çalan şarkı yeni turun
    // ilk şarkısı olmasın — art arda iki kez aynı şarkı "karışık" değildir.
    final fresh = _newShuffleOrder();
    if (fresh.length > 1 && fresh.first == _trackIndex) {
      fresh
        ..removeAt(0)
        ..insert(1, _trackIndex);
    }
    _shuffleOrder = fresh;
    return fresh.first;
  }

  /// Parça bittiğinde ne olacağını oynatıcıya uygular.
  ///
  /// "Tek şarkı" (ya da tek parçalık listede "tümü") → oynatıcı kendi
  /// döngüsünde çalar. Diğer durumlarda parça bitince [_onTrackCompleted]
  /// sıradakine geçer.
  Future<void> _applyEndBehavior() async {
    final p = _musicPlayer;
    if (p == null) return;
    await _trackEndSub?.cancel();
    _trackEndSub = null;

    final loop =
        _repeatMode == MusicRepeatMode.one ||
        (_playlist.length == 1 && _repeatMode == MusicRepeatMode.all);
    try {
      await p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
    } catch (_) {
      // ayarlanamazsa oynatıcının son modu geçerli kalır
    }
    if (!loop) {
      _trackEndSub = p.onPlayerComplete.listen(
        (_) => unawaited(_onTrackCompleted()),
      );
    }
  }

  Future<void> _onTrackCompleted() async {
    final next = _neighbourIndex(
      forward: true,
      wrap: _repeatMode == MusicRepeatMode.all,
    );

    if (next == null) {
      // Liste bitti, tekrar kapalı: DUR. Şarkı imleci başa alınır ki ▶'a
      // basan kullanıcı listeyi baştan dinlesin.
      if (_playingUrl != null) _stopListenReporting('stop');
      _reachedEnd = true;
      _musicPaused = true;
      _playingUrl = null;
      if (_shuffle) {
        _shuffleOrder = _newShuffleOrder();
        _trackIndex = _shuffleOrder.isEmpty ? 0 : _shuffleOrder.first;
      } else {
        _trackIndex = 0;
      }
      if (_hasValidIndex) _currentTrackName = _playlist[_trackIndex].name;
      musicProgress.value = (position: Duration.zero, total: Duration.zero);
      _notifyMusicState();
      unawaited(_showNowPlayingNotification(_currentTrackName));
      return;
    }

    _trackIndex = next;
    await startMusic(restart: true);
  }

  /// [localTracksProvider] üzerinden cihaz parçalarını okur. ASLA hata
  /// fırlatmaz: kitaplık okunamazsa liste yalnızca sunucudan gelir.
  Future<List<({String url, String name, bool isLocal})>>
  _loadLocalTracks() async {
    final provider = localTracksProvider;
    if (provider == null) return const [];
    try {
      final list = await provider();
      return [
        for (final t in list)
          if (t.url.isNotEmpty) (url: t.url, name: t.name, isLocal: true),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Kullanıcının "Müziğim" ekranında SEÇTİĞİ listeyi devreye alır ve
  /// [index]'teki şarkıyı çalmaya başlar.
  ///
  /// Hem cihaz kitaplığı hem de katalogdan kullanıcının kendi sırasıyla
  /// dinlediği liste bu yoldan geçer. Ortak yanları, listenin KULLANICIYA ait
  /// olması: [refreshPlaylist] artık onu ezmez.
  Future<void> playUserPlaylist(
    List<({String url, String name, bool isLocal})> tracks, {
    int index = 0,
  }) async {
    if (tracks.isEmpty) return;
    _source = MusicPlaylistSource.library;
    _playlist = List.of(tracks);
    _trackIndex = index.clamp(0, _playlist.length - 1);
    // Yeni liste: karışık sıra dokunulan şarkıyla başlayarak yeniden kurulur.
    _shuffleOrder = _shuffle ? _newShuffleOrder(first: _trackIndex) : const [];
    _currentTrackName = _playlist[_trackIndex].name;
    _musicPaused = false;
    _notifyMusicState();
    if (!_musicEnabled) {
      await setMusicEnabled(true);
      return;
    }
    await startMusic(restart: true);
  }

  /// Sunucu (Cizre Radyo) listesine geri döner.
  ///
  /// Kullanıcı kitaplığını dinlemeyi bıraktığında çağrılır; liste sunucudan
  /// yeniden okunur ve eski davranış kaldığı yerden sürer.
  Future<void> useRadioPlaylist({bool restart = false}) async {
    if (_source == MusicPlaylistSource.radio) return;
    _source = MusicPlaylistSource.radio;
    _playlist = [];
    _trackIndex = 0;
    await refreshPlaylist();
    if (restart) await startMusic(restart: true);
  }

  /// Çalma listesini sunucudan tazeler.
  ///
  /// ASLA hata fırlatmaz — müzik tamamen opsiyoneldir.
  Future<void> refreshPlaylist() async {
    // Kullanıcı kendi kitaplığını dinliyor: sunucu listesi onu EZMEMELİ.
    // Bu metot yan menü her açıldığında çağrılıyor, yani koruma olmasaydı
    // kullanıcının şarkısı ekran değiştirir değiştirmez kesilirdi.
    if (_source == MusicPlaylistSource.library) return;

    try {
      final tracks = <({String url, String name, bool isLocal})>[];
      var radioOk = false;
      try {
        final rows = await Supabase.instance.client.rpc('okey_list_music');
        for (final r in (rows as List? ?? const [])) {
          final m = r as Map;
          final u = m['public_url'] as String?;
          if (u == null || u.isEmpty) continue;
          final name = (m['display_name'] as String?)?.trim();
          tracks.add((
            url: u,
            name: (name == null || name.isEmpty) ? 'Şarkı' : name,
            isLocal: false,
          ));
        }
        radioOk = true;
      } catch (_) {
        // Sunucu listesi alınamadı (ağ, misafir oturumu). Cihaz parçaları
        // varsa müzik yine de çalabilmeli — aşağıda onlara bakıyoruz.
      }

      // KULLANICININ CİHAZINDAKİ ŞARKILAR da listeye katılır: yan menüdeki
      // plak kartı yalnızca sunucunun değil, kullanıcının kendi müziğini de
      // çalar. Sunucuya hiçbir şey gitmez; dosyalar yerelden çalınır.
      tracks.addAll(await _loadLocalTracks());

      if (!radioOk) {
        if (tracks.isEmpty) return; // Liste alınamazsa müzik çalmaz.
        // Ağ geçici koptu: elimizdeki sunucu parçalarını atmayalım, yoksa
        // çalan liste bir anda yalnızca cihaz şarkılarına düşerdi.
        tracks.insertAll(0, _playlist.where((t) => !t.isLocal));
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
      _shuffleOrder = const [];
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
      _shuffle = prefs.getBool(_shufflePrefsKey) ?? false;
      final repeat = prefs.getString(_repeatPrefsKey);
      _repeatMode = MusicRepeatMode.values.firstWhere(
        (m) => m.name == repeat,
        orElse: () => MusicRepeatMode.all,
      );
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

  /// KULLANICI SAYFAYA İLK KEZ DOKUNDU — web'de ses kilidini açar.
  ///
  /// Uygulamanın kökünden (bkz. `main.dart` > [MaterialApp.builder]) her
  /// işaretçi basışında çağrılır; ilk çağrıdan sonrası bedava döner.
  /// Etkileşim öncesi tarayıcının reddettiği denemeler yüzünden "eksik"
  /// işaretlenmiş efektler temizlenir ve durmuş müzik yeniden başlatılır.
  void notifyUserGesture() {
    if (_userGestured) return;
    _userGestured = true;
    _missing.clear();
    if (!_audioPluginMissing) _audioUnavailable = false;
    if (_musicEnabled && _playingUrl == null) {
      unawaited(startMusic());
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
    // Liste tekrar kapalıyken bitti: yalnızca kullanıcının açık isteği
    // (restart) yeniden başlatır, başka ekranların çağrısı değil.
    if (_reachedEnd && !restart) return;
    _reachedEnd = false;
    if (_playlist.isEmpty) await refreshPlaylist();
    if (_playlist.isEmpty) return;
    if (_trackIndex >= _playlist.length) _trackIndex = 0;

    final track = _playlist[_trackIndex];

    // AYNI ŞARKI ZATEN YÜKLÜ → DOKUNMA (çalıyor ya da duraklatılmış, FARK
    // ETMEZ).
    //
    // Oyun ekranı, yan menü ve müzik açma/kapama hepsi bu metodu çağırıyor.
    // Koşulsuz `play()` çağrısı parçayı her seferinde başa sarıyordu; ekran
    // değiştirdikçe şarkının baştan başlamasının sebebi buydu. ESKİDEN bu
    // kısa devre yalnızca `!_musicPaused` iken işliyordu — yani kullanıcı
    // müziği DURAKLATTIKTAN sonra başka bir ekran (ör. Okey masası açılışı,
    // bkz. OkeyGameProvider._init) bu metodu çağırınca şarkı kullanıcı HİÇBİR
    // ŞEY YAPMADAN baştan başlıyor ve duraklatma sıfırlanıyordu — "şarkı
    // kendiliğinden oynatılıyor" şikâyetinin kaynağı buydu. Duraklatılmışken
    // de aynı parça zaten yüklüyse dokunulmamalı; gerçek bir devam ettirme
    // [resumeMusicPlayback] üzerinden, kullanıcının kendi isteğiyle olmalı.
    if (!restart && _musicPlayer != null && _playingUrl == track.url) {
      _currentTrackName = track.name;
      unawaited(_showNowPlayingNotification(_currentTrackName));
      return;
    }

    final myOp = ++_playOp;
    final completer = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          _musicPlayer ??= AudioPlayer();

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
          // Parça bitince ne olacağı tekrar/karışık tercihine bağlı
          // (bkz. [_applyEndBehavior]). Varsayılan "tümü": tek şarkı
          // döngüde, çok şarkı bitince sıradakine — eskiden olduğu gibi.
          await _applyEndBehavior();

          await _musicPlayer!
              .play(
                // Kitaplık parçalarında `url` bir dosya yoludur; ağ üzerinden
                // çalmaya çalışmak sessizce başarısız olurdu.
                track.isLocal
                    ? DeviceFileSource(track.url)
                    : UrlSource(track.url),
              )
              .timeout(const Duration(seconds: 5));

          // BU ÇAĞRI ARTIK ESKİMİŞ Mİ? Beklerken daha yeni bir startMusic()
          // çağrısı (ör. kullanıcının art arda "sonraki"ye basması) devreye
          // girip kendi sonucunu yazmış olabilir — o zaman burası SESSİZCE
          // çıkar, üzerine yazmaz. Ses zaten en son `play()` neyse onu
          // çalıyor; mesele yalnızca hangi çağrının durumu KAYDETTİĞİ.
          if (myOp != _playOp) return;

          // Bildirim panelinde şarkı adını göster — çalma başarılı olduysa.
          // Önceki şarkının süresini kapat, yenisini başlat.
          if (_playingUrl != null && _playingUrl != track.url) {
            _stopListenReporting('pause', url: _playingUrl);
          }
          _musicPaused = false;
          _playingUrl = track.url;
          _currentTrackName = track.name;
          _notifyMusicState();
          unawaited(_showNowPlayingNotification(_currentTrackName));
          _startListenReporting(isNewTrack: true);
        } on MissingPluginException {
          // Ses eklentisi bu derlemede hic yok (bkz. [_audioPluginMissing]).
          // Efektlerdeki kararin aynisi: bir daha denemek ayni istisnayi
          // firlatir, sessizce ve KALICI olarak kapatilir. Bu, çağrının
          // eski olup olmadığına bakmaz: eklenti cihaz/derleme genelinde
          // eksik, tek bir çağrıya özgü değil.
          _markAudioPluginMissing();
          if (myOp == _playOp) _playingUrl = null;
        } catch (_) {
          // müzik tamamen opsiyonel. AMA bu çağrı eskimişse (daha yeni bir
          // startMusic() zaten başarıyla yazdıysa) o başarıyı SIFIRLAMA —
          // aksi hâlde geç kalan bir zaman aşımı, az önce başlayan yeni
          // şarkıyı ekranda "çalmıyor" gösterirdi.
          if (myOp == _playOp) _playingUrl = null;
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (error, __) {
        if (error is MissingPluginException) _markAudioPluginMissing();
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  /// Sıradaki şarkıya geçer.
  Future<void> nextTrack() async {
    if (_playlist.length < 2) return;
    _trackIndex = _neighbourIndex(forward: true, wrap: true) ?? 0;
    await _playCurrentTrack();
  }

  /// Önceki şarkıya geçer.
  ///
  /// Şarkının ilk birkaç saniyesinden sonra ⏮ önce ŞARKININ BAŞINA sarar;
  /// ikinci basış önceki şarkıya gider. Yaygın oynatıcıların davranışı bu —
  /// kullanıcı "bu şarkıyı baştan dinleyeyim" için ayrı bir düğme aramaz.
  Future<void> previousTrack() async {
    if (_playingUrl != null &&
        !_musicPaused &&
        musicProgress.value.position > const Duration(seconds: 3)) {
      await seekMusic(Duration.zero);
      return;
    }
    if (_playlist.length < 2) return;
    _trackIndex = _neighbourIndex(forward: false, wrap: true) ?? 0;
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
      await p.pause().timeout(_musicControlTimeout);
      _musicPaused = true;
      _notifyMusicState();
      unawaited(_showNowPlayingNotification(_currentTrackName));
      _stopListenReporting('pause');
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
      await p.resume().timeout(_musicControlTimeout);
      _musicPaused = false;
      _notifyMusicState();
      unawaited(_showNowPlayingNotification(_currentTrackName));
      _startListenReporting(isNewTrack: false);
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
    // Dinleme istatistiği: durdurulmadan ÖNCE (çalan şarkının URL'si silinmeden).
    if (_playingUrl != null && !_musicPaused) {
      _stopListenReporting('stop');
    } else if (_playingUrl != null) {
      _reportMusic('stop');
    }
    _musicPaused = false;
    _playingUrl = null;
    _notifyMusicState();
    unawaited(_hideNowPlayingNotification());
    final p = _musicPlayer;
    if (p == null) return;
    try {
      await p.stop().timeout(_musicControlTimeout);
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
    if (sound == OkeySound.buttonTap || sound == OkeySound.rackTile) {
      final last = _lastUiSoundAt[sound];
      final now = DateTime.now();
      if (last != null && now.difference(last) < _uiSoundGap) return;
      _lastUiSoundAt[sound] = now;
    }
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
        } on MissingPluginException {
          // EKLENTİ KAYITLI DEĞİL (örn. web build'i eski bir plugin
          // registrant ile üretilmişse audioplayers_web bundle'a girmez).
          // Bu, tek bir dosyanın eksikliği değil ALTYAPININ yokluğudur ve
          // yeniden denemekle düzelmez: her efekt için tekrar tekrar
          // MissingPluginException fırlatıp merkezi hata kaydını doldururdu.
          _markAudioPluginMissing();
          finish(false);
        } catch (_) {
          // Dosya yok / oynatılamadı → bu efekti bir daha deneme.
          // AMA web'de kullanıcı henüz sayfaya dokunmadıysa hata "dosya
          // yok" değil, tarayıcının otomatik oynatma kilididir; kalıcı
          // işaretlenirse ilk dokunuştan sonra da sessiz kalırdı.
          if (_userGestured) _missing.add(sound);
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
        // Eklenti yok / platform desteklemiyor → sesi tamamen devre dışı bırak.
        // Web'de beklenen hata otomatik oynatma kilididir (kullanıcı sayfaya
        // dokunmadan ses çalınamaz) ve GEÇİCİDİR; o yüzden web'de yalnızca bu
        // deneme başarısız sayılır. Tek istisna MissingPluginException:
        // audioplayers'ın web tarafı bundle'a hiç girmemiş demektir, bir
        // sonraki denemede de girmeyecektir.
        if (error is MissingPluginException) _markAudioPluginMissing();
        if (!kIsWeb) _audioUnavailable = true;
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

/// Fon müziğinin çalma listesi nereden besleniyor?
///
/// [radio] uygulamanın bugüne kadarki tek davranışıdır ve varsayılan olarak
/// kalır: liste sunucudan (`okey_list_music`) gelir. [library] ise kullanıcının
/// "Müziğim" ekranından çaldığı kendi dosyalarıdır — sunucuya hiç uğramaz.
///
/// Ayrımın tek amacı listenin KİMİN olduğunu bilmek: kullanıcının listesi
/// sunucu tazelemesiyle ezilmemeli ve dinleme istatistiğine yazılmamalı.
enum MusicPlaylistSource { radio, library }

/// Liste bitince / şarkı bitince ne olacağı.
///
/// [all]: liste sonunda başa dön (varsayılan, eski davranış).
/// [one]: çalan şarkıyı döngüde çal.
/// [off]: liste bitince dur.
enum MusicRepeatMode { off, all, one }
