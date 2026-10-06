import 'dart:convert';

import 'package:cizreapp/features/social/models/follow_suggestion.dart';
import 'package:cizreapp/features/social/services/follow_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 3.5 — takip RPC'si ve önerilen kişiler: istek biçimi, yanıt eşleme,
/// gerekçe metinleri, hata ipuçları.

final List<http.Request> _requests = [];

void main() {
  late Object? Function(http.Request req) respond;
  int status = 200;

  SupabaseClient client() => SupabaseClient(
    'https://test.invalid',
    'test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((req) async {
      _requests.add(req);
      return http.Response(jsonEncode(respond(req)), status, request: req, headers: {'content-type': 'application/json'});
    }),
  );

  setUp(() {
    _requests.clear();
    status = 200;
  });

  Map<String, dynamic> suggestionJson({
    String id = 'u1',
    String reason = 'mutual',
    int mutual = 3,
    List<String> names = const ['ayse', 'mehmet'],
    bool private = false,
    bool followsYou = false,
  }) => {
    'id': id,
    'username': 'ali_$id',
    'full_name': 'Ali $id',
    'avatar_url': null,
    'is_verified': true,
    'is_private': private,
    'followers_count': 42,
    'mutual_count': mutual,
    'follows_you': followsYou,
    'mutual_names': names,
    'reason': reason,
  };

  group('FollowSuggestion', () {
    test('ayrıştırma ve gerekçe metinleri', () {
      final mutual = FollowSuggestion.fromJson(suggestionJson());
      expect(mutual.displayName, 'Ali u1');
      expect(mutual.reasonText, 'ayse ve 2 kişi daha takip ediyor');
      expect(FollowSuggestion.fromJson(suggestionJson(mutual: 1, names: ['ayse'])).reasonText, 'ayse takip ediyor');
      expect(FollowSuggestion.fromJson(suggestionJson(names: [])).reasonText, '3 ortak takip');
      expect(FollowSuggestion.fromJson(suggestionJson(reason: 'follows_you', followsYou: true)).reasonText, 'Seni takip ediyor');
      expect(FollowSuggestion.fromJson(suggestionJson(reason: 'popular')).reasonText, '42 takipçi');
      expect(FollowSuggestion.fromJson(suggestionJson(reason: 'new')).reasonText, 'Yeni üye');
      expect(FollowSuggestion.fromJson(suggestionJson(reason: 'x')).reasonText, 'Senin için önerildi');
    });

    test('düğme etiketi: açık / geri takip / gizli hesap', () {
      expect(FollowSuggestion.fromJson(suggestionJson()).followLabel, 'Takip Et');
      expect(FollowSuggestion.fromJson(suggestionJson(followsYou: true)).followLabel, 'Geri Takip Et');
      expect(FollowSuggestion.fromJson(suggestionJson(private: true, followsYou: true)).followLabel, 'İstek Gönder');
      final noName = FollowSuggestion.fromJson({...suggestionJson(), 'full_name': '  '});
      expect(noName.displayName, 'ali_u1');
    });
  });

  group('FollowService', () {
    test('takip: tek RPC, durum ve takipçi sayısı', () async {
      respond = (_) => {'status': 'requested', 'followers_count': 7};
      final result = await FollowService(client: client()).follow('u9');
      expect(_requests.single.url.path, '/rest/v1/rpc/social_follow');
      expect(jsonDecode(_requests.single.body), {'p_user_id': 'u9', 'p_follow': true});
      expect((result.status, result.followersCount), (FollowStatus.requested, 7));

      respond = (_) => {'status': 'none', 'followers_count': 6};
      final undone = await FollowService(client: client()).unfollow('u9');
      expect(jsonDecode(_requests.last.body), {'p_user_id': 'u9', 'p_follow': false});
      expect(undone.status, FollowStatus.none);
    });

    test('engelli hesap ipucu Türkçe mesaja çevrilir', () async {
      status = 400;
      respond = (_) => {'code': 'P0001', 'message': 'x', 'hint': 'FOLLOW_BLOCKED', 'details': null};
      await expectLater(
        FollowService(client: client()).follow('u9'),
        throwsA(isA<FollowException>().having((e) => e.message, 'message', 'Bu kullanıcıyı takip edemezsin.')),
      );
    });

    test('misafirde öneri istenmez; kaldırma RPC\'si', () async {
      respond = (_) => [suggestionJson()];
      expect(await FollowService(client: client()).suggestions(), isEmpty);
      expect(_requests, isEmpty, reason: 'oturum yokken sunucuya gidilmez');

      respond = (_) => null;
      await FollowService(client: client()).dismissSuggestion('u3');
      expect(_requests.single.url.path, '/rest/v1/rpc/dismiss_follow_suggestion');
      expect(jsonDecode(_requests.single.body), {'p_user_id': 'u3'});
    });
  });

  test('followStatusFromCode', () {
    expect(followStatusFromCode('following'), FollowStatus.following);
    expect(followStatusFromCode('requested'), FollowStatus.requested);
    expect(followStatusFromCode(null), FollowStatus.none);
  });
}
