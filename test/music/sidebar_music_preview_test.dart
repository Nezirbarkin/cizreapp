// YAN MENÜ ÖNİZLEMESİ — "Müziğim" satırı ve cihazdan çalan plak kartı.
//
//   flutter test test/music/sidebar_music_preview_test.dart --update-goldens
//
// Yalnızca üretir, karşılaştırmaz (bkz. music_ui_preview_test.dart).
@Tags(['preview'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/core/widgets/settings_sidebar.dart';
import 'package:cizreapp/features/music/music.dart';
import 'package:cizreapp/okey/services/okey_sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global/events'),
          (_) async => null,
        );
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      // Her isteğe boş liste: misafir oturumu, sunucu şarkısı yok — kartta
      // yalnızca CİHAZ şarkıları çalabilir, tam da doğrulamak istediğimiz şey.
      httpClient: MockClient(
        (req) async => http.Response(
          req.url.path.endsWith('/rpc/music_settings')
              ? jsonEncode({
                  'feature': true,
                  'catalog': true,
                  'device_add': true,
                  'attach': true,
                  'artist_upload': true,
                  'max_upload_mb': 10,
                })
              : '[]',
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    OkeySoundService.localTracksProvider =
        MusicLibraryService.backgroundPlaylistEntries;
  });

  testWidgets('yan menü — Müziğim satırı ve cihazdan çalan kart', (
    tester,
  ) async {
    if (!autoUpdateGoldenFiles) return;

    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('cizre_sidebar');
      final file = File('${dir.path}/t0.mp3');
      await file.writeAsBytes(List<int>.filled(64, 0));
      SharedPreferences.setMockInitialValues({
        'music_library_index_v1': jsonEncode([
          {'id': 't0', 'title': 'Ez Kurdim', 'path': file.path},
          {'id': 't1', 'title': 'Dilan', 'path': file.path},
        ]),
      });
      await MusicLibraryService.instance.load(forceRefresh: true);

      // Ses eklentisi yok: motoru "ses yok" moduna al (bkz. playback testi).
      final sound = OkeySoundService.instance;
      await sound.setEnabled(true);
      await sound.play(OkeySound.values.first);
      // Sunucu listesi boş, cihaz parçaları kancadan gelmeli.
      await sound.refreshPlaylist();
    });

    const size = Size(390, 1900);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: size),
        child: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
            home: const SettingsSidebar(),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      OkeySoundService.instance.hasMusic,
      isTrue,
      reason: 'cihaz şarkıları kartın listesine katılmalı',
    );
    expect(OkeySoundService.instance.currentTrackIsLocal, isTrue);
    expect(find.text('Müziğim'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview_yan_menu.png'),
    );
  });
}
