import 'dart:convert';

import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/core/utils/hashtags.dart';
import 'package:cizreapp/core/widgets/social_rich_text.dart';
import 'package:cizreapp/features/social/services/post_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// #etiket ayrıştırma (sunucuyla aynı kurallar), dokunulabilir metin ve
/// yorum beğenisi / düzenleme / etiket akışı istekleri.

const _me = '11111111-1111-4111-8111-111111111111';
final List<http.Request> _requests = [];
Object _nextBody = <Object>[];

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;
}

void main() {
  group('hashtags', () {
    test('Türkçe harfler, büyük/küçük katlama, tekrar yok', () {
      expect(
        extractHashtags('Akşam #Cizre yürüyüşü #IĞDIR_gezisi #cizre #İzmir'),
        ['cizre', 'iğdir_gezisi', 'izmir'],
      );
    });

    test('URL parçası, kelime içi ve tek harf etiket sayılmaz', () {
      expect(extractHashtags('https://x.com/a#cizre abc#def #c #ok!'), ['ok']);
      expect(extractHashtags(null), isEmpty);
    });

    test('foldHashtag / isValidHashtag', () {
      expect(foldHashtag('#IŞIK'), 'işik');
      expect(foldHashtag('İstanbul'), 'istanbul');
      expect(isValidHashtag('cizre'), isTrue);
      expect(isValidHashtag('a'), isFalse);
      expect(isValidHashtag('a.*'), isFalse);
    });

    testWidgets('SocialRichText: etiket yoksa düz Text, varsa dokunulabilir', (t) async {
      final tapped = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SocialRichText('düz metin'),
                SocialRichText('Bugün #Cizre çok güzel @ali', boldMentions: true, onHashtagTap: tapped.add),
              ],
            ),
          ),
        ),
      );
      expect(find.text('düz metin'), findsOneWidget);
      expect(find.text('Bugün #Cizre çok güzel @ali'), findsOneWidget);

      final rich = t.widget<Text>(find.text('Bugün #Cizre çok güzel @ali'));
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      final tag = spans.firstWhere((s) => s.text == '#Cizre');
      expect(tag.recognizer, isNotNull);
      (tag.recognizer! as dynamic).onTap();
      expect(tapped, ['cizre']);
      expect(spans.firstWhere((s) => s.text == '@ali').style!.fontWeight, FontWeight.bold);
    });
  });

  group('istekler', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://test.invalid',
        publishableKey: 'test-publishable-key',
        httpClient: MockClient((req) async {
          _requests.add(req);
          return http.Response(
            jsonEncode(_nextBody),
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
      _nextBody = <Object>[];
    });

    test('yorum beğen: tek idempotent upsert; geri al: tek delete', () async {
      final s = PostService();
      await s.likeComment('c1', _me);
      expect(_requests, hasLength(1));
      final like = _requests.single;
      expect(like.method, 'POST');
      expect(like.url.path, '/rest/v1/post_comment_likes');
      expect(like.url.queryParameters['on_conflict'], 'comment_id,user_id');
      expect(like.headers['Prefer'], contains('resolution=ignore-duplicates'));

      _requests.clear();
      await s.unlikeComment('c1', _me);
      expect(_requests.single.method, 'DELETE');
      expect(_requests.single.url.queryParameters['comment_id'], 'eq.c1');
      expect(_requests.single.url.queryParameters['user_id'], 'eq.$_me');
    });

    test('beğenilen yorumlar tek istekte', () async {
      _nextBody = [
        {'comment_id': 'c2'},
      ];
      final ids = await PostService().getLikedCommentIds(_me, ['c1', 'c2']);
      expect(ids, {'c2'});
      expect(_requests, hasLength(1));
      expect(_requests.single.url.queryParameters['comment_id'], 'in.("c1","c2")');
    });

    test('etiket akışı RPC gövdesi; bozuk satır atlanır', () async {
      _nextBody = [
        {'id': 'p1', 'user_id': 'u1', 'content': '#cizre', 'created_at': '2026-10-24T10:00:00Z', 'views_count': 4},
        {'bozuk': true},
      ];
      final posts = await PostService().getPostsByHashtag('cizre', limit: 20, offset: 40);
      expect(posts.single.viewsCount, 4);
      final req = _requests.single;
      expect(req.url.path, '/rest/v1/rpc/posts_by_hashtag');
      expect(jsonDecode(req.body), {'p_tag': 'cizre', 'p_limit': 20, 'p_offset': 40});
    });

    test('düzenleme: yalnız content PATCH, dönen edited_at birleştirilir', () async {
      _nextBody = {'id': 'p1', 'content': 'yeni #metin', 'edited_at': '2026-10-24T11:00:00Z', 'updated_at': '2026-10-24T11:00:00Z'};
      final post = Post(
        id: 'p1',
        userId: _me,
        content: 'eski',
        likesCount: 7,
        createdAt: DateTime.utc(2026, 10, 24),
        updatedAt: DateTime.utc(2026, 10, 24),
      );
      final updated = await PostService().updatePostContent(post, '  yeni #metin  ');
      final req = _requests.single;
      expect(req.method, 'PATCH');
      expect(req.url.queryParameters['id'], 'eq.p1');
      expect(jsonDecode(req.body), {'content': 'yeni #metin'});
      expect(updated.content, 'yeni #metin');
      expect(updated.editedAt, DateTime.utc(2026, 10, 24, 11));
      expect(updated.likesCount, 7);
    });
  });
}
