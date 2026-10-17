import 'dart:io';

import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/screens/live_host_screen.dart';
import 'package:cizreapp/features/market/screens/live_viewer_screen.dart';
import 'package:cizreapp/features/market/screens/my_live_streams_screen.dart';
import 'package:cizreapp/features/market/services/live_replay_uploader.dart';
import 'package:cizreapp/features/market/widgets/live_home_card.dart';
import 'package:cizreapp/features/market/widgets/live_replay_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/live_fakes.dart';
import '../helpers/test_fonts.dart';

/// Tekrar izlenen parça (video_player yerine).
class _FakeClip extends ChangeNotifier implements LiveReplayClip {
  _FakeClip(this.url, this.length);

  final Uri url;
  final Duration length;
  final List<String> calls = [];
  bool _initialized = false;
  bool _playing = false;
  bool _completed = false;
  bool disposed = false;
  Duration _position = Duration.zero;
  double volume = 1;

  @override
  Future<void> initialize() async {
    _initialized = true;
    notifyListeners();
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Duration get duration => _initialized ? length : Duration.zero;

  @override
  Duration get position => _position;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isBuffering => false;

  @override
  bool get isCompleted => _completed;

  @override
  bool get hasError => false;

  @override
  Future<void> play() async {
    calls.add('play');
    _playing = true;
    _completed = false;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seek:${position.inSeconds}');
    _position = position;
    _completed = false;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Widget buildView() => ColoredBox(key: ValueKey('fake-clip-${url.pathSegments.last}'), color: Colors.indigo);

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }

  /// Parçanın sonuna gelindi.
  void complete() {
    _position = length;
    _playing = false;
    _completed = true;
    notifyListeners();
  }
}

/// Canlı yayın tekrar izleme ekranları: izleyicide kayıt oynatıcısı (parça
/// zinciri, ilerleme çubuğu, ses), özet ekranındaki kayıt durumu, silme
/// yetkisi; yayıncıda kayıt; Yayınlarım ve ana sayfa kartındaki rozet.
void main() {
  setUpAll(loadTestFonts);

  LiveSession endedSession({Map<String, dynamic>? replay, String id = 'sess-1'}) => LiveSession.fromJson(
    liveSessionJson(
      id: id,
      status: 'ended',
      endedReason: 'host',
      startedAt: kLiveNow.subtract(const Duration(minutes: 4)),
      endedAt: kLiveNow,
      peak: 12,
      durationSeconds: 240,
      messageCount: 5,
      replay: replay,
    ),
  );

  LiveReplayManifest manifest({String state = 'ready', List<int> partsMs = const [180000, 60000]}) =>
      LiveReplayManifest.tryFromJson({
        ...replayJson(state: state, parts: partsMs.length, durationMs: partsMs.fold(0, (a, b) => a + b)),
        'items': [
          for (var i = 0; i < partsMs.length; i++)
            {'part_no': i + 1, 'path': 'sess-1/part-000${i + 1}.mp4', 'duration_ms': partsMs[i]},
        ],
      })!;

  Future<(FakeLiveService, List<_FakeClip>)> openViewer(
    WidgetTester tester, {
    required LiveSession session,
    FakeLiveService? service,
    bool allowDelete = false,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = service ?? (FakeLiveService(userId: 'user-9')..credentials = kViewerCredentials);
    final clips = <_FakeClip>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LiveViewerScreen(
          key: UniqueKey(),
          session: session,
          service: s,
          engineFactory: FakeLiveEngine.new,
          allowReplayDelete: allowDelete,
          replayClipFactory: (url) {
            final ms = url.path.contains('part-0002') ? 60000 : 180000;
            final clip = _FakeClip(url, Duration(milliseconds: ms));
            clips.add(clip);
            return clip;
          },
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    return (s, clips);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('izleyici: kayıt oynatıcısı', () {
    testWidgets('biten yayın açılınca kayıt oynar; parça bitince sıradaki; sonda baştan izle', (tester) async {
      final session = endedSession(replay: replayJson(state: 'ready', parts: 2, durationMs: 240000));
      final service = FakeLiveService(userId: 'user-9')
        ..detail = session
        ..manifest = manifest();
      final (s, clips) = await openViewer(tester, session: session, service: service);

      expect(find.byKey(const ValueKey('live-replay-stage')), findsOneWidget);
      expect(find.text('Yayın sona erdi'), findsNothing, reason: 'siyah özet yerine kayıt');
      expect(find.text('TEKRAR'), findsOneWidget);
      expect(s.calls, containsAll(['detail', 'replay:manifest']));
      expect(clips, hasLength(2), reason: 'sıradaki parça önceden hazırlanır');
      expect(clips[0].isPlaying, isTrue);
      expect(clips[1].isInitialized, isTrue);
      expect(clips[1].isPlaying, isFalse);
      expect(clips[0].url.queryParameters['token'], 't', reason: 'imzalı adres');
      expect(find.byKey(const ValueKey('fake-clip-part-0001.mp4')), findsOneWidget);
      expect(tester.widget<Slider>(find.byKey(const ValueKey('live-replay-slider'))).max, 240000);
      expect(find.text('4:00'), findsOneWidget, reason: 'toplam süre');

      clips[0].complete();
      await settle(tester);
      expect(clips[1].isPlaying, isTrue);
      expect(find.byKey(const ValueKey('fake-clip-part-0002.mp4')), findsOneWidget);

      clips[1].complete();
      await settle(tester);
      expect(find.byTooltip('Baştan izle'), findsOneWidget);

      await tester.tap(find.byTooltip('Baştan izle'));
      await settle(tester);
      final restarted = clips.where((c) => c.url.path.contains('part-0001') && c.isPlaying);
      expect(restarted, isNotEmpty);
    });

    testWidgets('ilerleme çubuğuyla ikinci parçanın içine atlanır; ses kapatılır', (tester) async {
      final session = endedSession(replay: replayJson(state: 'ready', parts: 2, durationMs: 240000));
      final (_, clips) = await openViewer(
        tester,
        session: session,
        service: FakeLiveService(userId: 'user-9')
          ..detail = session
          ..manifest = manifest(),
      );
      final slider = tester.widget<Slider>(find.byKey(const ValueKey('live-replay-slider')));
      slider.onChangeEnd!(200000);
      await settle(tester);
      expect(clips[1].calls, contains('seek:20'), reason: '200 sn = 2. parçanın 20. saniyesi');
      expect(clips[1].isPlaying, isTrue);

      await tester.tap(find.byTooltip('Sesi kapat'));
      await settle(tester);
      expect(clips.where((c) => !c.disposed).every((c) => c.volume == 0), isTrue);
    });

    testWidgets('kayıt artık izlenemiyorsa (sunucu boş döner) özete düşer', (tester) async {
      final session = endedSession(replay: replayJson(state: 'ready'));
      final service = FakeLiveService(userId: 'user-9')
        ..detail = endedSession(replay: replayJson(state: 'deleted', parts: 0))
        ..manifest = null;
      await openViewer(tester, session: session, service: service);
      await settle(tester);
      expect(find.text('Yayın sona erdi'), findsOneWidget);
      expect(find.text('Bu yayının kaydı silindi.'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-replay-open')), findsNothing);
    });

    testWidgets('kaydı olmayan biten yayın: özet, izle düğmesi yok', (tester) async {
      final session = endedSession();
      await openViewer(
        tester,
        session: session,
        service: FakeLiveService(userId: 'user-9')..detail = session,
      );
      expect(find.text('Yayın sona erdi'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-replay-open')), findsNothing);
      expect(find.byKey(const ValueKey('live-replay-note')), findsNothing);
    });

    testWidgets('kayıt hazırlanıyorsa not; satır güncellenince "Kaydı izle" çıkar', (tester) async {
      final session = endedSession(replay: replayJson(state: 'processing', parts: 0, durationMs: 0));
      final service = FakeLiveService(userId: 'user-9')
        ..detail = session
        ..manifest = manifest(state: 'processing', partsMs: const [180000]);
      await openViewer(tester, session: session, service: service);
      expect(find.text('Kayıt hazırlanıyor; hazır olunca buradan izleyebilirsin.'), findsOneWidget);

      service.rows.add({
        'id': 'sess-1',
        'status': 'ended',
        'replay_state': 'recording',
        'replay_parts': 1,
        'replay_duration_ms': 180000,
      });
      await settle(tester);
      expect(find.text('Kaydı izle (3:00)'), findsOneWidget);
      expect(find.text('Yayının son bölümü hâlâ yükleniyor.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('live-replay-open')));
      await settle(tester);
      expect(find.byKey(const ValueKey('live-replay-stage')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-replay-processing')), findsOneWidget);
    });

    testWidgets('izlerken biten yayında önce özet, "Kaydı izle" ile kayda geçilir', (tester) async {
      final live = LiveSession.fromJson(
        liveSessionJson(
          status: 'live',
          isLive: true,
          startedAt: kLiveNow,
          replay: replayJson(state: 'recording', parts: 1, durationMs: 180000),
        ),
      );
      final service = FakeLiveService(userId: 'user-9')
        ..credentials = kViewerCredentials
        ..detail = endedSession(replay: replayJson(state: 'processing', parts: 2, durationMs: 240000))
        ..manifest = manifest(state: 'processing');
      final engine = FakeLiveEngine();
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final clips = <_FakeClip>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LiveViewerScreen(
            session: live,
            service: service,
            engineFactory: () => engine,
            replayClipFactory: (url) => (clips..add(_FakeClip(url, const Duration(minutes: 3)))).last,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      engine.events!.onJoined!();
      await tester.pump();

      service.rows.add({
        'id': 'sess-1',
        'status': 'ended',
        'ended_reason': 'host',
        'replay_state': 'recording',
        'replay_parts': 2,
      });
      await settle(tester);
      expect(engine.calls, contains('leave'));
      expect(find.text('Yayın sona erdi'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-replay-stage')), findsNothing, reason: 'kendiliğinden oynamaz');
      expect(find.text('Kaydı izle (4:00)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('live-replay-open')));
      await settle(tester);
      expect(find.byKey(const ValueKey('live-replay-stage')), findsOneWidget);
      expect(clips.first.isPlaying, isTrue);
    });
  });

  group('izleyici: kaydı silme', () {
    testWidgets('yayıncı kaydı siler; özet "silindi" der', (tester) async {
      final session = endedSession(replay: replayJson(state: 'ready', parts: 2, durationMs: 240000));
      final service = FakeLiveService(userId: 'owner-1')
        ..detail = session
        ..manifest = manifest();
      final (s, _) = await openViewer(tester, session: session, service: service);

      await tester.tap(find.byKey(const ValueKey('live-replay-menu')));
      await settle(tester);
      await tester.tap(find.text('Kaydı sil'));
      await settle(tester);
      expect(find.text('Yayının kaydı herkes için silinecek ve bir daha izlenemeyecek. Emin misin?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
      await settle(tester);
      expect(s.deletedReplays, ['sess-1']);
      expect(find.text('Kayıt silindi'), findsOneWidget);
      expect(find.text('Bu yayının kaydı silindi.'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-replay-delete')), findsNothing);
    });

    testWidgets('izleyici silemez; yönetici ekranından açılınca silebilir', (tester) async {
      final session = endedSession(replay: replayJson(state: 'ready', parts: 2, durationMs: 240000));
      await openViewer(
        tester,
        session: session,
        service: FakeLiveService(userId: 'user-9')
          ..detail = session
          ..manifest = manifest(),
      );
      await tester.tap(find.byKey(const ValueKey('live-replay-menu')));
      await settle(tester);
      expect(find.text('Yayın özeti'), findsOneWidget);
      expect(find.text('Kaydı sil'), findsNothing);
      await tester.tap(find.text('Yayın özeti'));
      await settle(tester);
      expect(find.text('Yayın sona erdi'), findsOneWidget);
      expect(find.text('Kaydı izle (4:00)'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-replay-delete')), findsNothing);

      await openViewer(
        tester,
        session: session,
        allowDelete: true,
        service: FakeLiveService(userId: 'admin-1')
          ..detail = session
          ..manifest = manifest(),
      );
      await tester.tap(find.byKey(const ValueKey('live-replay-menu')));
      await settle(tester);
      expect(find.text('Kaydı sil'), findsOneWidget);
    });
  });

  group('yayıncı: kayıt', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('live_host_replay'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<(FakeLiveService, FakeLiveEngine, LiveReplayUploader)> openHost(
      WidgetTester tester, {
      bool enabled = true,
    }) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Testin sahte zamanında gerçek klasör oluşturma beklenmesin.
      Directory(
        '${tmp.path}${Platform.pathSeparator}live_replays${Platform.pathSeparator}sess-1',
      ).createSync(recursive: true);
      final s = FakeLiveService()..replayStart = LiveReplayStart(enabled: enabled, days: 14);
      final e = FakeLiveEngine();
      final u = LiveReplayUploader(service: s, store: MemoryReplayQueueStore(), baseDirectory: () async => tmp);
      await tester.pumpWidget(
        MaterialApp(
          home: LiveHostScreen(
            shopId: 'shop-1',
            shopName: 'Çay Evi',
            service: s,
            engineFactory: () => e,
            replayUploader: u,
            now: () => kLiveNow.add(const Duration(minutes: 3)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Yayına Başla'));
      await tester.pump();
      e.events!.onJoined!();
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      return (s, e, u);
    }

    Future<void> endStream(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Bitir'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Bitir').last);
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
    }

    testWidgets('canlı olunca kayıt başlar; bitirince parça kanaldan önce kapanır, yüklenir, kayıt hazır', (
      tester,
    ) async {
      final (s, e, _) = await openHost(tester);
      expect(s.calls, containsAllInOrder(['start', 'replay:begin']));
      expect(e.calls, contains('record:start'));
      expect(e.recordings.single, endsWith('part-0001.mp4'));

      e.writeCurrentPart(ms: 95000);
      await endStream(tester);
      expect(e.calls.indexOf('record:stop'), lessThan(e.calls.indexOf('leave')), reason: 'son dakikalar kaybolmasın');
      expect(s.addedParts, ['sess-1#1:95000']);
      expect(s.finishedReplays, ['sess-1']);
      expect(find.text('Yayın sona erdi'), findsOneWidget);
      expect(find.text('Kayıt hazır'), findsOneWidget);
      expect(find.text('İzleyiciler yayını 14 gün boyunca tekrar izleyebilir.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('yükleme ağ beklerken özet bunu söyler', (tester) async {
      final (s, e, _) = await openHost(tester);
      s.uploadErrors.addAll([const SocketException('yok'), const SocketException('yok')]);
      e.writeCurrentPart(ms: 30000);
      await endStream(tester);
      expect(find.text('Kayıt yüklemesi bağlantı bekliyor'), findsOneWidget);
      expect(s.finishedReplays, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('yönetim kaydı kapattıysa kayıt yok, özette kayıt satırı yok', (tester) async {
      final (s, e, _) = await openHost(tester, enabled: false);
      expect(s.calls, contains('replay:begin'));
      expect(e.calls, isNot(contains('record:start')));
      await endStream(tester);
      expect(find.text('Yayın sona erdi'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-host-replay-status')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('listeler', () {
    testWidgets('Yayınlarım: TEKRAR rozeti ve kaydın durumu', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = FakeLiveService()
        ..myHistoryPages.add(
          LiveHistoryPage(
            rows: [
              endedSession(
                id: 'a',
                replay: replayJson(state: 'ready'),
              ),
              endedSession(id: 'b', replay: {'state': 'deleted', 'parts': 0, 'deleted_reason': 'admin'}),
              endedSession(id: 'c'),
            ],
            total: 3,
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: MyLiveStreamsScreen(service: service, now: () => kLiveNow, openSession: (_, _) {}),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('TEKRAR'), findsOneWidget);
      expect(find.text('BİTTİ'), findsNWidgets(2));
      expect(find.text('Kayıt hazır · 30 gün sonra silinir'), findsOneWidget);
      expect(find.text('Kayıt yönetim tarafından silindi'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-history-replay-c')), findsNothing);
    });

    testWidgets('ana sayfa kartı: son yayının kaydı varsa TEKRAR', (tester) async {
      tester.view.physicalSize = const Size(420, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      LiveHomeStoryCard.resetCache();
      final now = DateTime.now().toUtc();
      final service = FakeLiveService()
        ..homeCard = LiveHomeCard(
          enabled: true,
          last: LiveSession.fromJson(
            liveSessionJson(
              id: 'e1',
              status: 'ended',
              startedAt: now.subtract(const Duration(hours: 1)),
              endedAt: now.subtract(const Duration(minutes: 20)),
              replay: replayJson(state: 'ready'),
            ),
          ),
        );
      Widget card(bool compact) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: compact ? 95 : 200,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [LiveHomeStoryCard(service: service, compact: compact, width: 130, onOpen: (_, _) {})],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(card(true));
      await tester.pump();
      await tester.pump();
      expect(find.text('▶ TEKRAR'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Canlı yayın kaydını izle: Çay Evi'),
        findsOneWidget,
      );

      await tester.pumpWidget(card(false));
      await tester.pump();
      await tester.pump();
      expect(find.text('TEKRAR'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
      LiveHomeStoryCard.resetCache();
    });
  });
}
