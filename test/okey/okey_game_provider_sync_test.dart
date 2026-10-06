import 'dart:async';
import 'dart:convert';

import 'package:cizreapp/okey/engine/okey_sync.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/providers/okey_game_provider.dart';
import 'package:cizreapp/okey/services/okey_game_service.dart';
import 'package:cizreapp/okey/services/okey_realtime_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 1.6 — Okey masasının senkron hataları, gerçek [OkeyGameProvider]
/// üzerinde (sahte oyun servisi + sahte realtime kanalı + sahte saat):
///
/// * katılma/yeniden katılma sonrası masa yeniden okunur (olay boşluğu),
/// * kanal hatasında masa okunur ve kanal gecikmeyle yeniden kurulur,
/// * süre dolunca sunucu "yapacak iş yok" dese de masa yeniden okunur,
/// * izleyici "otomatik oyna" çağırmaz; hata olunca her saniye denenmez,
/// * süresi çoktan geçmiş sıra ekranda kalırsa masa aralıklarla okunur,
/// * sayaç cihaz saatine değil sunucu saatine göre,
/// * reconnect tek uçuş; yükleme sürerken kapanan masa kanal kurmaz.

const _me = 'user-me';
const _roomId = 'room-1';
const _matchId = 'match-1';

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _items.remove(key);
  }
}

/// Masada kimlerin oturduğu (Supabase sahte sunucusu koltukları buradan verir).
List<String> _seatUsers = [_me, 'user-2', 'user-3', 'user-4'];

MockClient _supabaseHttp() => MockClient((req) async {
  final name = req.url.pathSegments.last;
  final single = (req.headers['accept'] ?? '').contains('vnd.pgrst.object');
  final Object body = switch (name) {
    'okey_rooms' => single ? _roomJson() : [_roomJson()],
    'okey_room_players' => [
      for (var i = 0; i < 4; i++)
        {
          'room_id': _roomId,
          'seat_no': i,
          'user_id': _seatUsers[i],
          'is_ready': true,
          'is_bot': false,
          'is_ai_controlled': false,
          'bot_profile_id': null,
          'profiles': {'username': 'u$i', 'full_name': 'Oyuncu $i', 'avatar_url': null},
          'okey_bot_profiles': null,
        },
    ],
    _ => <Object>[],
  };
  return http.Response(
    jsonEncode(body),
    200,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

Map<String, dynamic> _roomJson() => {
  'id': _roomId,
  'created_by': _me,
  'status': 'in_progress',
  'is_private': false,
  'join_code': null,
  'max_score': 0,
  'turn_seconds': 20,
  'game_mode': 'katlamasiz',
  'team_mode': 'essiz',
  'assist_mode': 'yardimli',
  'entry_fee': 100,
  'total_hands': 3,
  'current_match_id': _matchId,
  'created_at': '2026-09-27T10:00:00Z',
};

/// Sahte sunucu tarafı masa: sıra süresi ve sunucu saati testçe ayarlanır.
class _FakeGame extends OkeyGameService {
  DateTime Function() deadline = () => DateTime.now().add(const Duration(seconds: 20));
  DateTime? Function() serverNow = () => null;
  int turnSeat = 1;
  Duration snapshotDelay = Duration.zero;

  int snapshotCalls = 0;
  int autoAdvanceCalls = 0;
  bool autoAdvanceResult = false;
  Object? autoAdvanceError;

  @override
  Future<OkeyTableSnapshot?> getSnapshot(String matchId, {int? afterMoveId}) async {
    snapshotCalls++;
    if (snapshotDelay > Duration.zero) await Future<void>.delayed(snapshotDelay);
    return (
      match: OkeyMatch.fromMap({
        'id': _matchId,
        'room_id': _roomId,
        'status': 'in_progress',
        'hand_no': 1,
        'dealer_seat': 0,
        'turn_seat': turnSeat,
        'turn_phase': 'draw',
        'turn_token': 'token-1',
        'turn_deadline': deadline().toUtc().toIso8601String(),
        'indicator_tile': {'color': 'red', 'number': 5},
        'okey_tile': {'color': 'red', 'number': 6},
        'deck_remaining': 40,
        'discard_piles': <String, dynamic>{},
        'scores': <String, dynamic>{},
      }),
      hand: const OkeyMyHand.empty(),
      melds: const <OkeyTableMeld>[],
      counts: const <int, int>{},
      moves: const <OkeyMoveRow>[],
      barajs: const <int, String>{},
      requiredOpening: (minPoints: 101, minPairs: 5),
      canUndoSideDraw: false,
      serverNow: serverNow(),
    );
  }

  @override
  Future<bool> autoAdvance(String matchId) async {
    autoAdvanceCalls++;
    final error = autoAdvanceError;
    if (error != null) throw error;
    return autoAdvanceResult;
  }

  @override
  Future<bool> autoPlayAbsent(String matchId) async => false;

  @override
  Future<void> botTakeTurn(String matchId, {String? turnToken}) async {}

  @override
  Future<void> touchPresence(String roomId) async {}

  @override
  Future<void> leaveMatchSeat(String matchId) async {}
}

/// Sahte realtime: kanal kurma/kapama sayılır, katılma ve hata test
/// tarafından tetiklenir.
class _FakeRealtime extends OkeyRealtimeService {
  int subscribeCalls = 0;
  int unsubscribeCalls = 0;
  int _unsubscribing = 0;
  int maxConcurrentUnsubscribes = 0;
  void Function()? onSubscribed;
  void Function(Object? error)? onChannelError;

  @override
  void subscribe({
    required String matchId,
    required void Function() onMatchChanged,
    required void Function() onHandChanged,
    required void Function() onMeldsChanged,
    required void Function() onMovesChanged,
    void Function(Map<String, dynamic> payload)? onQuickPhrase,
    void Function()? onSubscribed,
    void Function(Object? error)? onChannelError,
  }) {
    subscribeCalls++;
    this.onSubscribed = onSubscribed;
    this.onChannelError = onChannelError;
  }

  @override
  void subscribeGifts({
    required String roomId,
    required void Function(Map<String, dynamic> row) onGift,
  }) {}

  @override
  Future<void> sendQuickPhrase({required int seatNo, required String text}) async {}

  @override
  Future<void> unsubscribeMatch() async {}

  @override
  Future<void> unsubscribe() async {
    unsubscribeCalls++;
    _unsubscribing++;
    if (_unsubscribing > maxConcurrentUnsubscribes) {
      maxConcurrentUnsubscribes = _unsubscribing;
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    _unsubscribing--;
  }
}

Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 6)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('koşul gerçekleşmedi', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late _FakeGame game;
  late _FakeRealtime realtime;
  final providers = <OkeyGameProvider>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _supabaseHttp(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'token',
        'token_type': 'bearer',
        'refresh_token': 'refresh',
        'user': {
          'id': _me,
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  setUp(() {
    game = _FakeGame();
    realtime = _FakeRealtime();
    _seatUsers = [_me, 'user-2', 'user-3', 'user-4'];
  });

  tearDown(() {
    for (final p in providers) {
      p.dispose();
    }
    providers.clear();
  });

  Future<OkeyGameProvider> openTable({bool spectator = false, OkeyServerClock? clock}) async {
    final p = OkeyGameProvider(
      _matchId,
      spectator: spectator,
      service: game,
      realtime: realtime,
      clock: clock,
    );
    providers.add(p);
    await _until(() => realtime.subscribeCalls == 1 && p.match != null && p.seats.isNotEmpty);
    return p;
  }

  test('kanal katılınca masa BİR KEZ DAHA okunur (okuma→katılma arası boşluk kapanır)', () async {
    await openTable();
    expect(game.snapshotCalls, 1);

    realtime.onSubscribed!(); // ilk katılma ya da bağlantı dönünce yeniden katılma
    await _until(() => game.snapshotCalls == 2);
  });

  test('kanal hatası: masa hemen okunur, kanal gecikmeyle yeniden kurulur', () async {
    await openTable();

    realtime.onChannelError!(Exception('postgres_changes kurulamadı'));
    await _until(() => game.snapshotCalls == 2);
    await _wait(1200);
    expect(realtime.subscribeCalls, 1, reason: 'hemen değil, bekleyerek');

    await _until(
      () => realtime.subscribeCalls == 2,
      timeout: OkeyTurnSync.resubscribeDelay(0) + const Duration(seconds: 2),
    );
  });

  test('kanal hatasından sonra kendiliğinden yeniden katılırsa kanal yeniden KURULMAZ', () async {
    await openTable();

    realtime.onChannelError!(Exception('geçici'));
    await _wait(100);
    realtime.onSubscribed!(); // realtime_client kendisi yeniden katıldı
    await _wait(OkeyTurnSync.resubscribeDelay(0).inMilliseconds + 600);

    expect(realtime.subscribeCalls, 1);
  });

  test('süre dolunca BİR KEZ otomatik oynat; sunucu "yapacak iş yok" dese de masa okunur', () async {
    final deadline = DateTime.now().subtract(const Duration(seconds: 2));
    game.deadline = () => deadline; // sunucu aynı sırayı gösteriyor
    game.autoAdvanceResult = false; // başkası çoktan ilerletmiş; olay bende kaçmış
    await openTable();
    final before = game.snapshotCalls;

    await _until(() => game.autoAdvanceCalls == 1);
    await _until(() => game.snapshotCalls > before);
    await _wait(2200);
    expect(game.autoAdvanceCalls, 1, reason: 'aynı sıra için tek deneme');
  });

  test('izleyici süre dolunca otomatik oynat ÇAĞIRMAZ', () async {
    _seatUsers = ['user-1', 'user-2', 'user-3', 'user-4']; // ben oturmuyorum
    final deadline = DateTime.now().subtract(const Duration(seconds: 2));
    game.deadline = () => deadline;
    await openTable(spectator: true);

    await _wait(2500);
    expect(game.autoAdvanceCalls, 0);
  });

  test('otomatik oynat hata verirse her saniye değil, beklemeden sonra yeniden denenir', () async {
    var now = DateTime.now();
    final clock = OkeyServerClock(localNow: () => now);
    final deadline = now.subtract(const Duration(seconds: 1));
    game.deadline = () => deadline;
    game.autoAdvanceError = Exception('ağ yok');
    await openTable(clock: clock);

    await _until(() => game.autoAdvanceCalls == 1);
    await _wait(2200); // iki sayaç turu — saat ilerlemedi
    expect(game.autoAdvanceCalls, 1);

    now = now.add(OkeyTurnSync.autoAdvanceRetry + const Duration(seconds: 1));
    await _until(() => game.autoAdvanceCalls == 2);
  });

  test('süresi çoktan geçmiş sıra ekranda kalırsa masa aralıklarla yeniden okunur', () async {
    _seatUsers = ['user-1', 'user-2', 'user-3', 'user-4'];
    var now = DateTime.now();
    final clock = OkeyServerClock(localNow: () => now);
    final deadline = now.subtract(const Duration(seconds: 1));
    game.deadline = () => deadline; // sunucuda sıra hiç ilerlemiyor (olay kaçmış)
    await openTable(spectator: true, clock: clock);
    expect(game.snapshotCalls, 1);

    await _wait(1500);
    expect(game.snapshotCalls, 1, reason: 'süre yeni doldu: henüz bayat sayılmaz');

    now = now.add(const Duration(seconds: 20));
    await _until(() => game.snapshotCalls == 2);
    await _wait(1500);
    expect(game.snapshotCalls, 2, reason: 'her saniye değil');

    now = now.add(OkeyTurnSync.staleInterval);
    await _until(() => game.snapshotCalls == 3);
  });

  test('sayaç SUNUCU saatine göre: cihaz saati 60 sn ilerideyken erken oynatmaz', () async {
    // Sunucu cihazdan 60 sn GERİDE; sıranın 20 sn'si var.
    game.serverNow = () => DateTime.now().subtract(const Duration(seconds: 60));
    final deadline = DateTime.now().subtract(const Duration(seconds: 40));
    game.deadline = () => deadline;
    final p = await openTable();

    expect(p.secondsLeft, inInclusiveRange(17, 20));
    await _wait(2200);
    expect(game.autoAdvanceCalls, 0, reason: 'cihaz saatiyle "süre doldu" sanılıyordu');
    expect(p.secondsLeft, inInclusiveRange(15, 18));
  });

  test('reconnect TEK UÇUŞ: arka arkaya iki çağrı iç içe geçmez', () async {
    final p = await openTable();

    final first = p.reconnect();
    final second = p.reconnect(); // ilki sürerken
    await Future.wait([first, second]);

    expect(realtime.maxConcurrentUnsubscribes, 1);
    expect(realtime.unsubscribeCalls, 2, reason: 'ikinci istek kuyruktan BİR KEZ çalışır');
    expect(realtime.subscribeCalls, 3);
  });

  test('yükleme sürerken masa kapanırsa kanal kurulmaz', () async {
    game.snapshotDelay = const Duration(milliseconds: 400);
    final p = OkeyGameProvider(_matchId, service: game, realtime: realtime);
    await _until(() => game.snapshotCalls == 1);
    p.dispose();

    await _wait(800);
    expect(realtime.subscribeCalls, 0);
  });
}
