import 'dart:convert';

import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/features/social/screens/story_viewer_screen.dart';
import 'package:cizreapp/features/social/services/story_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 1.4: kendi profilinden (ve "hikayeni beğendi" bildiriminden)
/// açılan hikayede başlıkta gerçek ad yerine "Kullanıcı" yazıyordu; çünkü bu
/// yollar hikayeyi yazarın profili OLMADAN çekiyordu.

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

final List<http.Request> _requests = [];
final Map<String, Object? Function(http.Request req)> _routes = {};

MockClient _client() => MockClient((req) async {
  _requests.add(req);
  final handler = _routes[req.url.pathSegments.last];
  return http.Response(
    jsonEncode(handler != null ? handler(req) : <Object>[]),
    200,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

List<String> _paths() => [for (final r in _requests) r.url.pathSegments.last];

const _me = 'user-me';

Map<String, dynamic> _storyRow(
  String id, {
  String userId = _me,
  Map<String, dynamic>? author,
}) => {
  'id': id,
  'user_id': userId,
  'image_url': null,
  'media_type': 'text',
  'text_content': 'Merhaba $id',
  'background': null,
  'views_count': 0,
  'likes_count': 0,
  'created_at': '2026-09-27T10:00:00+00:00',
  'expires_at': '2099-01-01T00:00:00+00:00',
  'is_pinned': false,
  'admin_pinned': false,
  'profiles': author,
};

const _myProfile = {
  'username': 'nezir',
  'full_name': 'Nezir Barkın',
  'avatar_url': null,
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _client(),
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
    _requests.clear();
    _routes.clear();
  });

  group('Story modeli', () {
    test('iç içe gelen profiles birleştirmesinden yazarı okur', () {
      final story = Story.fromJson(_storyRow('s1', author: _myProfile));

      expect(story.fullName, 'Nezir Barkın');
      expect(story.username, 'nezir');
      expect(story.isMissingAuthor, isFalse);
      expect(story.authorDisplayName, 'Nezir Barkın');
    });

    test('düz alanlar önceliklidir (getStories/liderlik kartı biçimi)', () {
      final story = Story.fromJson({
        ..._storyRow('s1', author: _myProfile),
        'full_name': 'Düz Ad',
        'avatar_url': 'https://cdn.invalid/a.png',
      });

      expect(story.fullName, 'Düz Ad');
      expect(story.avatarUrl, 'https://cdn.invalid/a.png');
      expect(story.username, 'nezir');
    });

    test('yazar yoksa "Kullanıcı"; ad boşsa kullanıcı adı', () {
      final bare = Story.fromJson(_storyRow('s1'));
      expect(bare.isMissingAuthor, isTrue);
      expect(bare.authorDisplayName, 'Kullanıcı');

      final handleOnly = bare.copyWith(fullName: '   ', username: 'nezir');
      expect(handleOnly.isMissingAuthor, isFalse);
      expect(handleOnly.authorDisplayName, 'nezir');
    });
  });

  group('StoryService', () {
    test('getUserStories hikayeyi yazarıyla birlikte TEK istekte çeker', () async {
      _routes['stories'] = (_) => [_storyRow('s1', author: _myProfile)];

      final stories = await StoryService().getUserStories(_me);

      expect(_paths(), ['stories']);
      expect(
        _requests.single.url.queryParameters['select'],
        StoryService.selectWithAuthor.replaceAll(' ', ''),
      );
      expect(_requests.single.url.queryParameters['user_id'], 'eq.$_me');
      expect(stories.single.authorDisplayName, 'Nezir Barkın');
    });

    test('getStoryById yazarıyla döner; yoksa null', () async {
      _routes['stories'] = (_) => [_storyRow('s9', author: _myProfile)];
      final story = await StoryService().getStoryById('s9');

      expect(
        _requests.single.url.queryParameters['select'],
        StoryService.selectWithAuthor.replaceAll(' ', ''),
      );
      expect(_requests.single.url.queryParameters['id'], 'eq.s9');
      expect(story!.fullName, 'Nezir Barkın');

      _routes['stories'] = (_) => <Object>[];
      expect(await StoryService().getStoryById('yok'), isNull);
    });

    test('getAuthorProfiles tekrarsız kimliklerle TEK sorgu; boşsa hiç', () async {
      _routes['profiles'] = (_) => [
        {'id': 'u1', ..._myProfile},
      ];

      expect(await StoryService().getAuthorProfiles(const []), isEmpty);
      expect(_requests, isEmpty);

      final authors = await StoryService().getAuthorProfiles(['u1', 'u1', 'u2']);

      expect(_paths(), ['profiles']);
      expect(_requests.single.url.queryParameters['id'], 'in.("u1","u2")');
      expect(authors.keys, ['u1']);
      expect(authors['u1']!['full_name'], 'Nezir Barkın');
    });

    test('withAuthors yalnız eksik yazarları doldurur', () {
      final missing = Story.fromJson(_storyRow('a', userId: 'u1'));
      final known = Story.fromJson(
        _storyRow('b', userId: 'u1', author: {'full_name': 'Zaten Var'}),
      );
      final unknown = Story.fromJson(_storyRow('c', userId: 'u-yok'));

      final filled = StoryService.withAuthors(
        [missing, known, unknown],
        {
          'u1': {'id': 'u1', ..._myProfile},
        },
      );

      expect(filled.map((s) => s.authorDisplayName).toList(), [
        'Nezir Barkın',
        'Zaten Var',
        'Kullanıcı',
      ]);
      expect(filled.map((s) => s.id).toList(), ['a', 'b', 'c']);
    });
  });

  group('StoryViewerScreen başlığı', () {
    Future<void> pumpViewer(WidgetTester tester, List<Story> stories) async {
      _routes['music_settings'] = (_) => <String, Object>{};
      await tester.pumpWidget(
        MaterialApp(home: StoryViewerScreen(stories: stories)),
      );
      // Arka plandaki istekler (tepki, müzik ayarı, yazar) tamamlansın.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> closeViewer(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('yazarıyla gelen kendi hikayemde gerçek ad; ek sorgu yok', (
      tester,
    ) async {
      await pumpViewer(tester, [
        Story.fromJson(_storyRow('s1', author: _myProfile)),
      ]);

      expect(find.text('Nezir Barkın'), findsOneWidget);
      expect(find.text('Kullanıcı'), findsNothing);
      expect(_paths(), isNot(contains('profiles')));

      await closeViewer(tester);
    });

    testWidgets('yazarsız gelen hikayede ad TEK sorguyla tamamlanır', (
      tester,
    ) async {
      _routes['profiles'] = (_) => [
        {'id': _me, ..._myProfile},
      ];

      await pumpViewer(tester, [
        Story.fromJson(_storyRow('s1')),
        Story.fromJson(_storyRow('s2')),
      ]);

      expect(find.text('Nezir Barkın'), findsOneWidget);
      expect(find.text('Kullanıcı'), findsNothing);
      expect(_paths().where((p) => p == 'profiles'), hasLength(1));

      await closeViewer(tester);
    });

    testWidgets('profil de bulunamazsa çökmeden "Kullanıcı" ve "?"', (
      tester,
    ) async {
      _routes['profiles'] = (_) => <Object>[];

      await pumpViewer(tester, [Story.fromJson(_storyRow('s1'))]);

      expect(find.text('Kullanıcı'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await closeViewer(tester);
    });
  });
}
