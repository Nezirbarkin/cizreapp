import 'dart:convert';

import 'package:cizreapp/features/profile/screens/edit_profile_screen.dart';
import 'package:cizreapp/features/profile/screens/followers_screen.dart';
import 'package:cizreapp/features/profile/services/profile_service.dart';
import 'package:cizreapp/features/profile/widgets/mutual_followers_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Profil/takip hata turu (2026-10-23):
/// * takipçi listesi satır başına sorgu atmıyor (eskiden N+1), sayfalı,
/// * kendi takipçi listemde "Çıkar" (sessiz takipçi çıkarma),
/// * sayılar tek RPC'den (eskiden tüm takip satırları indiriliyordu),
/// * arama metnindeki virgül/parantez PostgREST filtresini bozmuyor,
/// * web sitesi alanı doğrulanıyor.

const _me = '11111111-1111-4111-8111-111111111111';

final List<http.Request> _requests = [];
Object? Function(http.Request req) _respond = (_) => <Object>[];

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;
}

Map<String, dynamic> _profile(String id) => {
      'id': id,
      'username': 'kisi_$id',
      'full_name': 'Kişi $id',
      'avatar_url': null,
      'bio': null,
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '.',
    );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        _requests.add(req);
        final body = _respond(req);
        return http.Response(
          jsonEncode(body),
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
        autoRefreshToken: false,
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
    _requests.clear();
    _respond = (_) => <Object>[];
  });

  group('FollowListScreen', () {
    // 12 takipçi: u3'ü geri takip ediyorum, u5'e bekleyen isteğim var.
    final followers = [for (var i = 1; i <= 12; i++) 'u$i'];

    Object? listRoutes(http.Request req) {
      final path = req.url.path;
      final q = req.url.queryParameters;
      if (path == '/rest/v1/follow_requests') {
        return [
          {'following_id': 'u5'},
        ];
      }
      if (path == '/rest/v1/follows' && req.method == 'GET') {
        if ((q['select'] ?? '').contains('profiles!follows_follower_id_fkey')) {
          return [
            for (final id in followers)
              {'follower_id': id, 'profiles': _profile(id)},
          ];
        }
        // Benim ilişkilerim (tek toplu sorgu)
        return [
          {'following_id': 'u3'},
        ];
      }
      if (path == '/rest/v1/follows' && req.method == 'DELETE') {
        return [
          {'id': 'f1'},
        ];
      }
      return <Object>[];
    }

    Future<void> pumpList(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _respond = listRoutes;
      await tester.pumpWidget(
        const MaterialApp(
          home: FollowListScreen(
            userId: _me,
            listType: FollowListType.followers,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('kişi sayısından bağımsız sabit istek; ilişki doğru çizilir', (
      tester,
    ) async {
      await pumpList(tester);

      expect(find.text('Kişi u1'), findsOneWidget);
      expect(find.text('Kişi u12'), findsOneWidget);
      // 1 liste + 1 bekleyen istekler + 1 toplu ilişki = 3 (eskiden 1 + 12).
      expect(_requests, hasLength(3));
      final relationReq = _requests.lastWhere(
        (r) => r.url.path == '/rest/v1/follows' &&
            r.url.queryParameters['follower_id'] == 'eq.$_me',
      );
      expect(relationReq.url.queryParameters['following_id'], startsWith('in.('));
      // Sayfalama: ilk sayfa 0-29.
      final listReq = _requests.firstWhere(
        (r) => (r.url.queryParameters['select'] ?? '')
            .contains('follows_follower_id_fkey'),
      );
      expect(listReq.url.queryParameters['offset'], '0');
      expect(listReq.url.queryParameters['limit'], '${FollowListScreen.pageSize}');

      // Kendi takipçi listem: her satırda "Çıkar"; geri takip etmediklerimde
      // adın yanında "· Takip Et" (u3'ü takip ediyorum, u5'e isteğim
      // bekliyor → ikisinde yok).
      expect(find.text('Çıkar'), findsNWidgets(12));
      expect(find.text('· Takip Et'), findsNWidgets(10));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('takipçi çıkarma: onay → tek DELETE, satır kalkar', (
      tester,
    ) async {
      await pumpList(tester);
      _requests.clear();

      await tester.tap(find.text('Çıkar').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('takipçilerinden çıkarılsın mı'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Çıkar'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final deletes = _requests.where((r) => r.method == 'DELETE').toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.url.queryParameters['follower_id'], 'eq.u1');
      expect(deletes.single.url.queryParameters['following_id'], 'eq.$_me');
      expect(find.text('Kişi u1'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('ProfileService', () {
    test('getFollowCounts: tek RPC', () async {
      _respond = (_) => {'followers': 1200, 'following': 3, 'friends': 2, 'posts': 9};
      final counts = await ProfileService().getFollowCounts('u9');

      expect(_requests.single.url.path, '/rest/v1/rpc/get_follow_counts');
      expect(jsonDecode(_requests.single.body), {'p_user_id': 'u9'});
      expect(counts.followers, 1200);
      expect(counts.posts, 9);
    });

    test('searchUsers: değer tırnaklı, virgül filtreyi bozmaz', () async {
      await ProfileService().searchUsers('ali, (veli)');

      final or = _requests.single.url.queryParameters['or'];
      expect(
        or,
        '(username.ilike."%ali, (veli)%",full_name.ilike."%ali, (veli)%")',
      );
    });

    test('block: idempotent upsert ve olay yayını', () async {
      final events = <String>[];
      final sub = ProfileService.onUserBlocked.listen(events.add);

      await ProfileService().block('u7');
      await Future<void>.delayed(Duration.zero);

      final req = _requests.single;
      expect(req.url.path, '/rest/v1/blocked_users');
      expect(req.headers['Prefer'], contains('resolution=ignore-duplicates'));
      expect(events, ['u7']);
      await sub.cancel();
    });
  });

  test('web sitesi doğrulama', () {
    expect(EditProfileScreen.normalizeWebsite(''), '');
    expect(EditProfileScreen.normalizeWebsite('ornek.com'), 'https://ornek.com');
    expect(
      EditProfileScreen.normalizeWebsite('http://ornek.com/a'),
      'http://ornek.com/a',
    );
    expect(EditProfileScreen.normalizeWebsite('merhaba dünya'), isNull);
    expect(EditProfileScreen.normalizeWebsite('localhost'), isNull);
  });

  group('Ortak takipçiler', () {
    Map<String, dynamic> u(String name) => {'id': 'id_$name', 'username': name};

    test('özet metni', () {
      expect(const MutualFollowers().summary, '');
      expect(MutualFollowers(count: 1, users: [u('ali')]).summary, 'ali takip ediyor');
      expect(
        MutualFollowers(count: 2, users: [u('ali'), u('veli')]).summary,
        'ali ve veli takip ediyor',
      );
      expect(
        MutualFollowers(count: 5, users: [u('ali'), u('veli'), u('ayse')]).summary,
        'ali, veli ve 3 kişi daha takip ediyor',
      );
    });

    testWidgets('satır tek RPC ile dolar; ortak yoksa boş', (tester) async {
      _respond = (req) => {
            'count': 4,
            'users': [u('ali'), u('veli'), u('ayse')],
          };
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MutualFollowersLine(userId: 'u9'))),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));

      final rpc = _requests.single;
      expect(rpc.url.path, '/rest/v1/rpc/get_mutual_followers');
      expect(jsonDecode(rpc.body), {'p_target': 'u9', 'p_limit': 3});
      expect(find.text('ali, veli ve 2 kişi daha takip ediyor'), findsOneWidget);

      _requests.clear();
      _respond = (_) => {'count': 0, 'users': <Object>[]};
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MutualFollowersLine(userId: 'u8'))),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.textContaining('takip ediyor'), findsNothing);
    });
  });
}
