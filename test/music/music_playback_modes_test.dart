import 'package:cizreapp/okey/services/okey_sound_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Karışık / tekrar / sıradaki mantığı.
///
/// Ses eklentisi test ortamında yok; motor bunu yakalayıp sessizce devam
/// ediyor (bkz. okey_sound_service_test.dart). Burada yalnızca SIRA
/// hesabını — hangi şarkının sıradaki olduğunu — doğruluyoruz.
List<({String url, String name, bool isLocal})> _tracks(int n) => [
  for (var i = 0; i < n; i++)
    (url: '/yerel/$i.mp3', name: 'Şarkı $i', isLocal: true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sound = OkeySoundService.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Test ortamında ses eklentisi yok. Bir efekt çalmayı denemek motora bunu
    // öğretir (MissingPluginException → ses kalıcı olarak "yok" sayılır);
    // sonrasında müzik çağrıları oynatıcıyı kurmaya hiç kalkmaz. Aksi hâlde
    // oynatıcı kurulumu hiç gelmeyecek bir platform cevabını bekler.
    await sound.setEnabled(true);
    await sound.play(OkeySound.values.first);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    if (sound.isShuffle) await sound.toggleShuffle();
    await sound.setRepeatMode(MusicRepeatMode.all);
    await sound.playUserPlaylist(_tracks(5), index: 2);
  });

  test('kullanıcı listesi yüklenince çalan parça dokunulan parçadır', () {
    expect(sound.playlistSource, MusicPlaylistSource.library);
    expect(sound.currentTrackIndex, 2);
    expect(sound.currentTrackUrl, '/yerel/2.mp3');
    expect(sound.currentTrackIsLocal, isTrue);
  });

  test('tekrar TÜMÜ: sıradaki liste sonundan başa sarar', () {
    expect(sound.upNextIndices(), [3, 4, 0, 1]);
  });

  test('tekrar KAPALI: sıradaki liste sonunda biter', () async {
    await sound.setRepeatMode(MusicRepeatMode.off);
    expect(sound.upNextIndices(), [3, 4]);
  });

  test('tekrar döngüsü: tümü → tek şarkı → kapalı → tümü', () async {
    expect(await sound.cycleRepeatMode(), MusicRepeatMode.one);
    expect(await sound.cycleRepeatMode(), MusicRepeatMode.off);
    expect(await sound.cycleRepeatMode(), MusicRepeatMode.all);
  });

  test('tekrar tercihi kalıcıdır', () async {
    await sound.setRepeatMode(MusicRepeatMode.one);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('music_repeat_mode'), 'one');
  });

  test(
    'karışık açılınca çalan parça yerinde kalır, kalanların hepsi sırada',
    () async {
      await sound.toggleShuffle();
      expect(sound.isShuffle, isTrue);
      expect(sound.currentTrackIndex, 2, reason: 'çalan şarkı kesilmemeli');

      final next = sound.upNextIndices();
      expect(next.length, 4);
      expect(next.toSet(), {0, 1, 3, 4}, reason: 'her şarkı tam bir kez');
      expect(
        next.contains(2),
        isFalse,
        reason: 'çalan şarkı hemen tekrar etmez',
      );
    },
  );

  test('karışıkta ⏭ gösterilen sıradakine gider', () async {
    await sound.toggleShuffle();
    final expected = sound.upNextIndices().first;
    await sound.nextTrack();
    expect(sound.currentTrackIndex, expected);
  });

  test(
    'karışık kapalıyken ⏭ ve ⏮ liste sırasını izler, uçlarda sarar',
    () async {
      await sound.nextTrack();
      expect(sound.currentTrackIndex, 3);
      await sound.nextTrack();
      await sound.nextTrack();
      expect(sound.currentTrackIndex, 0, reason: 'sondan sonra başa');
      await sound.previousTrack();
      expect(sound.currentTrackIndex, 4, reason: 'baştan önce sona');
    },
  );

  test('karışık kapatılınca liste sırası kaldığı yerden sürer', () async {
    await sound.toggleShuffle();
    await sound.nextTrack();
    final here = sound.currentTrackIndex;
    await sound.toggleShuffle();
    expect(sound.isShuffle, isFalse);
    final next = sound.upNextIndices();
    if (here < 4) expect(next.first, here + 1);
  });

  test('radyo listesi cihaz şarkılarını da içerir (yan menü kartı)', () async {
    final previous = OkeySoundService.localTracksProvider;
    addTearDown(() => OkeySoundService.localTracksProvider = previous);
    OkeySoundService.localTracksProvider = () async => [
      (url: '/cihaz/a.mp3', name: 'Cihaz A'),
      (url: '/cihaz/b.mp3', name: 'Cihaz B'),
    ];

    // Sunucu listesi bu ortamda alınamıyor (Supabase yok) — tam da misafir
    // ya da çevrimdışı durum. Kart yine de cihaz şarkılarını çalabilmeli.
    await sound.useRadioPlaylist();

    expect(sound.playlistSource, MusicPlaylistSource.radio);
    expect(sound.hasMusic, isTrue);
    expect(sound.playlist.map((t) => t.url).toSet(), {
      '/cihaz/a.mp3',
      '/cihaz/b.mp3',
    });
    expect(sound.playlist.every((t) => t.isLocal), isTrue);
  });

  test(
    'kanca bağlı değilse radyo listesi eskisi gibi yalnız sunucudan gelir',
    () async {
      final previous = OkeySoundService.localTracksProvider;
      addTearDown(() => OkeySoundService.localTracksProvider = previous);
      OkeySoundService.localTracksProvider = null;

      await sound.useRadioPlaylist();
      expect(sound.playlist.where((t) => t.isLocal), isEmpty);
    },
  );

  test('listeden seçilen parça çalınır', () async {
    await sound.playTrackAt(4);
    expect(sound.currentTrackIndex, 4);
    await sound.playTrackAt(99); // geçersiz: yok sayılır
    expect(sound.currentTrackIndex, 4);
  });
}
