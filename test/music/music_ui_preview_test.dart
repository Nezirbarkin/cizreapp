// EKRAN ÖNİZLEMELERİ — müzik özelliğinin PNG'sini üretir.
//
//   flutter test test/music/music_ui_preview_test.dart --update-goldens
//
// KARŞILAŞTIRMA YAPMAZ, YALNIZCA ÜRETİR (okey_ui_preview_test.dart ile aynı
// gerekçe): golden karşılaştırması yazı tipi/GPU farklarına duyarlıdır ve
// başka bir makinede kırmızı yanar.
@Tags(['preview'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/features/admin/widgets/music_management_content.dart';
import 'package:cizreapp/features/music/music.dart';
import 'package:cizreapp/okey/services/okey_sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ahem kutucukları yerine gerçek harfler çizilsin diye yazı tiplerini yükler.
Future<void> _loadFonts() async {
  const base = 'C:/flutter/bin/cache/artifacts/material_fonts';

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$base/$f');
      if (!file.existsSync()) continue;
      loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

/// Sunucuyu taklit eden istemci. Yol `/rpc/<ad>` ise o RPC'nin cevabını döner.
///
/// `request:` vermek ŞART — null olursa postgrest "Null check operator used on
/// a null value" fırlatır.
MockClient _mockClient() {
  return MockClient((req) async {
    final path = req.url.path;

    Map<String, dynamic>? single;
    List<Map<String, dynamic>>? list;

    if (path.endsWith('/rpc/music_settings')) {
      single = {
        'feature': true,
        'catalog': true,
        'device_add': true,
        'attach': true,
        'artist_upload': true,
        'max_upload_mb': 10,
      };
    } else if (path.endsWith('/rpc/music_search_catalog')) {
      list = [
        {
          'id': 'c1',
          'title': 'Ez Kurdim',
          'artist': 'Ciwan Haco',
          'genre': 'Kürtçe',
          'public_url': 'https://example.invalid/1.mp3',
          'duration_ms': 238000,
          'source': 'admin',
          'created_at': '2026-09-01T10:00:00Z',
        },
        {
          'id': 'c2',
          'title': 'Çîrok',
          'artist': 'Ciwan Haco',
          'genre': 'Kürtçe',
          'public_url': 'https://example.invalid/2.mp3',
          'duration_ms': 261000,
          'source': 'admin',
          'created_at': '2026-09-01T10:00:00Z',
        },
        {
          'id': 'c3',
          'title': 'Dara Bêdeng',
          'artist': 'Mehmet Aslan',
          'genre': 'Türkü',
          'public_url': 'https://example.invalid/3.mp3',
          'duration_ms': 192000,
          'source': 'artist',
          'created_at': '2026-09-18T10:00:00Z',
        },
      ];
    } else if (path.endsWith('/rpc/music_catalog_genres')) {
      list = [
        {'genre': 'Kürtçe', 'track_count': 8},
        {'genre': 'Türkü', 'track_count': 5},
        {'genre': 'Arabesk', 'track_count': 2},
      ];
    } else if (path.endsWith('/rpc/music_my_submissions')) {
      list = [
        {
          'id': 's1',
          'title': 'Şevrêş',
          'artist': 'Mehmet Aslan',
          'genre': 'Kürtçe',
          'status': 'approved',
          'reject_reason': null,
          'created_at': '2026-09-10T10:00:00Z',
        },
        {
          'id': 's2',
          'title': 'Berîvan',
          'artist': 'Mehmet Aslan',
          'genre': 'Türkü',
          'status': 'pending',
          'reject_reason': null,
          'created_at': '2026-09-19T10:00:00Z',
        },
        {
          'id': 's3',
          'title': 'Deng',
          'artist': 'Mehmet Aslan',
          'genre': null,
          'status': 'rejected',
          'reject_reason': 'Ses kaydı telifli bir albümden alınmış.',
          'created_at': '2026-09-15T10:00:00Z',
        },
      ];
    } else if (path.endsWith('/rpc/admin_music_list_submissions')) {
      list = [
        {
          'id': 'p1',
          'user_id': 'u1',
          'username': 'mehmeta',
          'title': 'Dara Bêdeng',
          'artist': 'Mehmet Aslan',
          'genre': 'Kürtçe',
          'public_url': 'https://example.invalid/3.mp3',
          'duration_ms': 192000,
          'size_bytes': 4300000,
          'status': 'pending',
          'reject_reason': null,
          'created_at': '2026-09-20T08:00:00Z',
        },
        {
          'id': 'p2',
          'user_id': 'u2',
          'username': 'rojdak',
          'title': 'Berîvan',
          'artist': 'Rojda K.',
          'genre': 'Türkü',
          'public_url': 'https://example.invalid/4.mp3',
          'duration_ms': 168000,
          'size_bytes': 3570000,
          'status': 'pending',
          'reject_reason': null,
          'created_at': '2026-09-19T08:00:00Z',
        },
      ];
    } else if (path.endsWith('/rpc/admin_music_list_catalog')) {
      list = [
        {
          'id': 'c1',
          'title': 'Ez Kurdim',
          'artist': 'Ciwan Haco',
          'genre': 'Kürtçe',
          'public_url': 'https://example.invalid/1.mp3',
          'storage_path': 'music/1.mp3',
          'duration_ms': 238000,
          'source': 'admin',
          'is_active': true,
          'created_at': '2026-09-01T10:00:00Z',
        },
        {
          'id': 'c3',
          'title': 'Dara Bêdeng',
          'artist': 'Mehmet Aslan',
          'genre': 'Türkü',
          'public_url': 'https://example.invalid/3.mp3',
          'storage_path': 'u1/3.mp3',
          'duration_ms': 192000,
          'source': 'artist',
          'is_active': false,
          'created_at': '2026-09-18T10:00:00Z',
        },
      ];
    }

    final body = single != null ? jsonEncode(single) : jsonEncode(list ?? []);
    return http.Response(
      body,
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

/// Kitaplık indeksini GERÇEK dosyalarla kurar.
///
/// [MusicLibraryService] olmayan dosyaları listeden ayıklıyor (kasıtlı), bu
/// yüzden sahte yollar vermek boş bir liste üretirdi.
Future<void> _seedLibrary() async {
  final dir = await Directory.systemTemp.createTemp('cizre_music_test');
  final entries = <Map<String, dynamic>>[];

  const tracks = [
    ('Ez Kurdim', 'Ciwan Haco', 238000),
    ('Dilan', 'Aynur Doğan', 252000),
    ('Yaz kaydı 2026', null, 127000),
  ];

  for (var i = 0; i < tracks.length; i++) {
    final file = File('${dir.path}/t$i.mp3');
    await file.writeAsBytes(List<int>.filled(64, 0));
    entries.add({
      'id': 't$i',
      'title': tracks[i].$1,
      if (tracks[i].$2 != null) 'artist': tracks[i].$2,
      'path': file.path,
      'duration_ms': tracks[i].$3,
    });
  }

  SharedPreferences.setMockInitialValues({
    'music_library_index_v1': jsonEncode(entries),
  });
}

/// Sahte sunucudan gelen cevabin ekrana yansimasi icin birkac kare bekler.
///
/// `pumpAndSettle` KULLANILAMAZ: ekolayzir/yukleme gostergeleri surekli
/// donuyor ve settle hic tamamlanmaz.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shoot(
  WidgetTester tester,
  Widget screen,
  String file, {
  Size size = const Size(390, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD91A73)),
        ),
        home: screen,
      ),
    ),
  );
  // İKİ pump: ilkinde başlayan yükleme/animasyon o karede %0'dadır.
  await tester.pump();
  await _settle(tester);

  await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    // Supabase.initialize oturumu SharedPreferences'ta saklıyor; sahte
    // değerler ONDAN ÖNCE kurulmazsa MissingPluginException fırlatır.
    SharedPreferences.setMockInitialValues({});
    // Ses eklentisinin genel olay kanalı test ortamında yok; ilk ses
    // denemesinde çerçeve bunu yakalanmamış hata olarak raporluyor. Kanalı
    // boş cevaplı taklit ediyoruz — motor yine "ses yok" moduna geçer.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global/events'),
          (_) async => null,
        );
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _mockClient(),
    );
  });

  setUp(() async {
    MusicSettingsService.invalidate();
    await _seedLibrary();
    await MusicLibraryService.instance.load(forceRefresh: true);
  });

  testWidgets('müziğim — kitaplık', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await _shoot(tester, const MyMusicScreen(), 'preview_muzigim_kitaplik.png');
  });

  testWidgets('müziğim — cizre radyo', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 780)),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
          home: const MyMusicScreen(),
        ),
      ),
    );
    await tester.pump();
    await _settle(tester);

    await tester.tap(find.textContaining('Cizre Radyo'));
    await tester.pump();
    await _settle(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview_muzigim_radyo.png'),
    );
  });

  testWidgets('müzik seçici — kırpma açık', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await MusicSettingsService.fetch();

    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 780)),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
          home: const Scaffold(body: MusicPickerSheet()),
        ),
      ),
    );
    await tester.pump();
    await _settle(tester);

    // Bir şarkı seç: alttaki kırpma paneli ancak seçimden sonra açılır.
    await tester.tap(find.text('Dilan'));
    await tester.pump();
    await _settle(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview_muzik_secici.png'),
    );
  });

  testWidgets('şarkını yükle', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await MusicSettingsService.fetch();
    await _shoot(
      tester,
      const ArtistUploadScreen(),
      'preview_sarkini_yukle.png',
    );
  });

  testWidgets('admin — müzik yönetimi', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await MusicSettingsService.fetch();

    tester.view.physicalSize = const Size(430, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(430, 820)),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
          home: const Scaffold(body: MusicManagementContent()),
        ),
      ),
    );
    await tester.pump();
    await _settle(tester);

    await tester.tap(find.text('Başvurular'));
    await tester.pump();
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview_admin_basvurular.png'),
    );

    await tester.tap(find.text('Ayarlar'));
    await tester.pump();
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview_admin_ayarlar.png'),
    );
  });

  // ------------------------------------------------ çalan müzikle ekranlar

  /// Motoru "ses yok" moduna alıp kitaplıktan bir liste yükler.
  ///
  /// Test ortamında ses eklentisi yok; bir efekt denemesi motora bunu
  /// öğretir ve sonrasında müzik çağrıları oynatıcı kurmaya kalkmaz (aksi
  /// hâlde hiç gelmeyecek bir platform cevabını beklerdi). Liste yüklenir,
  /// oynatıcı "duraklatılmış" görünür — kartın tüm parçaları çizilir.
  Future<void> loadPlaylist(WidgetTester tester) async {
    await tester.runAsync(() async {
      final sound = OkeySoundService.instance;
      await sound.setEnabled(true);
      await sound.play(OkeySound.values.first);
      final tracks = await MusicLibraryService.instance.load();
      await sound.playUserPlaylist([
        for (final t in tracks)
          (url: t.localPath!, name: t.title, isLocal: true),
      ], index: 0);
    });
  }

  testWidgets('müziğim — oynatıcı yüklü', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await loadPlaylist(tester);
    await _shoot(
      tester,
      const MyMusicScreen(),
      'preview_muzigim_oynatici.png',
      size: const Size(390, 844),
    );
  });

  testWidgets('tam ekran oynatıcı', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    await loadPlaylist(tester);
    final tracks = await tester.runAsync(
      () => MusicLibraryService.instance.load(),
    );
    await _shoot(
      tester,
      MusicPlayerScreen(
        lookup: (url) {
          for (final t in tracks ?? const <MusicTrack>[]) {
            if (t.localPath == url) return t;
          }
          return null;
        },
      ),
      'preview_tam_ekran_oynatici.png',
      size: const Size(390, 844),
    );
  });
}
