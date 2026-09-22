import 'dart:convert';

import 'package:cizreapp/features/chat/models/chat_presence.dart';
import 'package:cizreapp/features/chat/services/user_presence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sahte sunucu: RPC çağrılarını kaydeder, cevapları test belirler.
class _FakeServer {
  final calls = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic> settingsJson = {
    'last_seen': true,
    'last_seen_in_chat': true,
    'last_seen_in_profile': true,
    'last_seen_max_days': 7,
    'online': true,
    'typing': true,
    'typing_in_groups': true,
  };
  Object profileJson = {
    'show_last_seen': true,
    'last_seen_friends_only': false,
    'show_typing_indicator': true,
  };
  bool failEverything = false;
  Duration settingsDelay = Duration.zero;

  int count(String rpc) => calls[rpc]?.length ?? 0;

  MockClient client() => MockClient((req) async {
    final name = req.url.pathSegments.last;
    Map<String, dynamic> params = {};
    if (req.method == 'POST' && req.body.isNotEmpty) {
      final decoded = jsonDecode(req.body);
      if (decoded is Map) params = Map<String, dynamic>.from(decoded);
    }
    (calls[name] ??= []).add(params);

    if (failEverything) {
      return http.Response(
        jsonEncode({'message': 'boom', 'code': 'XX000'}),
        500,
        request: req,
        headers: {'content-type': 'application/json'},
      );
    }

    Object body = [];
    switch (name) {
      case 'get_chat_presence_settings':
        if (settingsDelay > Duration.zero) await Future<void>.delayed(settingsDelay);
        body = settingsJson;
      case 'get_my_profile':
        body = profileJson;
      case 'get_user_presence':
        final ids = (params['p_user_ids'] as List).cast<String>();
        body = [
          for (final id in ids)
            {
              'user_id': id,
              'can_see_online': true,
              'online': id == 'online-user',
              'last_seen': id == 'online-user' ? null : '2026-09-20T18:10:00+00:00',
            },
        ];
      case 'update_my_chat_privacy':
        body = <String, dynamic>{};
    }
    return http.Response(
      jsonEncode(body),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

late _FakeServer _server;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    _server = _FakeServer();
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _server.client(),
    );
  });

  setUp(() {
    _server
      ..calls.clear()
      ..failEverything = false
      ..settingsDelay = Duration.zero
      ..settingsJson = {
        'last_seen': true,
        'last_seen_in_chat': true,
        'last_seen_in_profile': true,
        'last_seen_max_days': 7,
        'online': true,
        'typing': true,
        'typing_in_groups': true,
      };
    UserPresenceService.instance.reset();
  });

  final service = UserPresenceService.instance;

  group('ayarlar', () {
    test('ilk okumadan sonra önbellekten döner (tek sunucu çağrısı)', () async {
      _server.settingsJson = {..._server.settingsJson, 'last_seen_max_days': 14};
      final a = await service.loadSettings();
      final b = await service.loadSettings();
      expect(a.lastSeenMaxDays, 14);
      expect(b, a);
      expect(_server.count('get_chat_presence_settings'), 1);
      expect(service.hasLoadedSettings, isTrue);
      expect(service.cachedSettings.lastSeenMaxDays, 14);
    });

    test('force önbelleği atlar; invalidate bir sonraki okumayı zorlar', () async {
      await service.loadSettings();
      _server.settingsJson = {..._server.settingsJson, 'typing': false};
      expect((await service.loadSettings()).typing, isTrue, reason: 'önbellekte hâlâ eski');
      expect((await service.loadSettings(force: true)).typing, isFalse);
      expect(_server.count('get_chat_presence_settings'), 2);

      _server.settingsJson = {..._server.settingsJson, 'typing': true};
      service.invalidate();
      expect((await service.loadSettings()).typing, isTrue);
      expect(_server.count('get_chat_presence_settings'), 3);
    });

    test('eşzamanlı çağrılar TEK isteği paylaşır', () async {
      _server.settingsDelay = const Duration(milliseconds: 50);
      final results = await Future.wait([
        service.loadSettings(),
        service.loadSettings(),
        service.loadSettings(),
      ]);
      expect(_server.count('get_chat_presence_settings'), 1);
      expect(results.toSet().length, 1);
    });

    test('okunamazsa varsayılanlar döner, hata fırlatmaz ve önbellek "yüklendi" sayılmaz', () async {
      _server.failEverything = true;
      final s = await service.loadSettings();
      expect(s, const ChatPresenceSettings());
      expect(service.hasLoadedSettings, isFalse);

      // Sunucu düzelince bir sonraki çağrı yeniden dener.
      _server.failEverything = false;
      _server.settingsJson = {..._server.settingsJson, 'online': false};
      expect((await service.loadSettings()).online, isFalse);
    });

    test('bir hata sonrası son BİLİNEN ayar korunur', () async {
      _server.settingsJson = {..._server.settingsJson, 'last_seen': false};
      await service.loadSettings();
      _server.failEverything = true;
      final s = await service.loadSettings(force: true);
      expect(s.lastSeen, isFalse, reason: 'ağ hatası admin kararını açığa çevirmemeli');
    });

    test('reset hesap değişince ayarları varsayılana döndürür', () async {
      _server.settingsJson = {..._server.settingsJson, 'typing': false};
      await service.loadSettings();
      service.reset();
      expect(service.cachedSettings, const ChatPresenceSettings());
      expect(service.hasLoadedSettings, isFalse);
    });
  });

  group('fetch', () {
    test('bağlam ve kimlikler sunucuya gider; sonuç kimliğe göre haritalanır', () async {
      final result = await service.fetch(
        ['a', 'online-user'],
        context: PresenceContext.profile,
      );
      final call = _server.calls['get_user_presence']!.single;
      expect(call['p_context'], 'profile');
      expect(call['p_user_ids'], ['a', 'online-user']);
      expect(result['online-user']!.online, isTrue);
      expect(result['a']!.online, isFalse);
      expect(result['a']!.lastSeen, DateTime.utc(2026, 9, 20, 18, 10));
      expect(result['a']!.canSeeOnline, isTrue);
    });

    test('tekrarlar ve boş kimlikler elenir; boş listede sunucuya gidilmez', () async {
      await service.fetch(['a', 'a', '', 'b']);
      expect(_server.calls['get_user_presence']!.single['p_user_ids'], ['a', 'b']);

      _server.calls.clear();
      expect(await service.fetch(const []), isEmpty);
      expect(await service.fetch(['', '']), isEmpty);
      expect(_server.count('get_user_presence'), 0);
    });

    test('500\'ü aşan kimlikler parçalanır', () async {
      final ids = [for (var i = 0; i < 501; i++) 'u$i'];
      final result = await service.fetch(ids);
      final calls = _server.calls['get_user_presence']!;
      expect(calls.length, 2);
      expect((calls[0]['p_user_ids'] as List).length, 500);
      expect((calls[1]['p_user_ids'] as List).length, 1);
      expect(result.length, 501);
    });

    test('varsayılan bağlam sohbettir', () async {
      await service.fetch(['a']);
      expect(_server.calls['get_user_presence']!.single['p_context'], 'chat');
    });

    test('hata olursa boş harita döner (güvenli taraf: kimse için bir şey gösterilmez)', () async {
      _server.failEverything = true;
      expect(await service.fetch(['a', 'b']), isEmpty);
      expect(await service.fetchOne('a'), isNull);
    });

    test('fetchOne tek kimlik sorar', () async {
      final p = await service.fetchOne('online-user');
      expect(p!.online, isTrue);
      expect(_server.calls['get_user_presence']!.single['p_user_ids'], ['online-user']);
    });
  });

  group('kullanıcının kendi tercihleri', () {
    test('profilden okunur', () async {
      _server.profileJson = {
        'show_last_seen': true,
        'last_seen_friends_only': true,
        'show_typing_indicator': false,
      };
      final prefs = await service.loadMyPrivacy();
      expect(prefs.lastSeenAudience, LastSeenAudience.friends);
      expect(prefs.showTypingIndicator, isFalse);
    });

    test('okunamazsa varsayılan (herkes, yazıyor açık)', () async {
      _server.failEverything = true;
      final prefs = await service.loadMyPrivacy();
      expect(prefs.lastSeenAudience, LastSeenAudience.everyone);
      expect(prefs.showTypingIndicator, isTrue);
    });

    test('profil satırı yoksa (boş cevap) varsayılan', () async {
      _server.profileJson = <Object>[];
      final prefs = await service.loadMyPrivacy();
      expect(prefs.lastSeenAudience, LastSeenAudience.everyone);
    });

    test('"herkes" seçimi iki sütunu yazar', () async {
      await service.saveMyPrivacy(lastSeenAudience: LastSeenAudience.everyone);
      expect(_server.calls['update_my_chat_privacy']!.single, {
        'p_show_last_seen': true,
        'p_last_seen_friends_only': false,
      });
    });

    test('"arkadaşlarım" seçimi', () async {
      await service.saveMyPrivacy(lastSeenAudience: LastSeenAudience.friends);
      expect(_server.calls['update_my_chat_privacy']!.single, {
        'p_show_last_seen': true,
        'p_last_seen_friends_only': true,
      });
    });

    test('"hiç kimse" yalnız show_last_seen\'i kapatır; arkadaş bayrağına dokunmaz', () async {
      await service.saveMyPrivacy(lastSeenAudience: LastSeenAudience.nobody);
      final call = _server.calls['update_my_chat_privacy']!.single;
      expect(call, {'p_show_last_seen': false});
      expect(call.containsKey('p_last_seen_friends_only'), isFalse);
    });

    test('yazıyor tercihi tek başına yazılır', () async {
      await service.saveMyPrivacy(showTypingIndicator: false);
      expect(_server.calls['update_my_chat_privacy']!.single, {
        'p_show_typing_indicator': false,
      });
    });

    test('kaydetme hatası çağırana fırlatılır (anahtar geri alınabilsin)', () async {
      _server.failEverything = true;
      expect(
        () => service.saveMyPrivacy(showTypingIndicator: true),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
