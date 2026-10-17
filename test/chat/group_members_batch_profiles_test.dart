import 'dart:convert';

import 'package:cizreapp/features/chat/services/group_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Grup üyeleri ve katılma istekleri profilleri TEK istekte çeker; eskiden
/// her satır için ayrı ardışık istek gidiyordu (100 üye = 100 istek).

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

final _requests = <Uri>[];
final _routes = <String, Object? Function(http.Request)>{};

http.Response _json(Object? body, http.Request req) => http.Response(
      jsonEncode(body),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        _requests.add(req.url);
        final handler = _routes[req.url.pathSegments.last];
        return _json(handler != null ? handler(req) : <Object>[], req);
      }),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': 'token',
      'token_type': 'bearer',
      'refresh_token': 'refresh',
      'user': {
        'id': 'me',
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
      },
    }));
  });

  setUp(() {
    _requests.clear();
    _routes.clear();
  });

  int profileRequests() =>
      _requests.where((u) => u.path.endsWith('/rest/v1/profiles')).length;

  test('getGroupMembers profilleri tek istekte eşler', () async {
    _routes['group_members'] = (_) => [
          for (var i = 1; i <= 5; i++)
            {
              'id': 'm$i',
              'group_id': 'g1',
              'user_id': 'u$i',
              'role': i == 1 ? 'admin' : 'member',
              'joined_at': '2026-10-0${i}T10:00:00+00:00',
            },
        ];
    _routes['profiles'] = (req) {
      // in.(u1,u2,...) filtresiyle tek istek bekleniyor.
      expect(req.url.queryParameters['id'], startsWith('in.('));
      return [
        for (var i = 1; i <= 5; i++)
          {'id': 'u$i', 'full_name': 'Üye $i', 'username': 'uye$i', 'avatar_url': null},
      ];
    };

    final members = await GroupChatService().getGroupMembers('g1');

    expect(members, hasLength(5));
    expect(profileRequests(), 1);
    expect(
      {for (final m in members) m.userId: m.fullName},
      {for (var i = 1; i <= 5; i++) 'u$i': 'Üye $i'},
    );
  });

  test('getJoinRequests profilleri tek istekte eşler', () async {
    _routes['group_join_requests'] = (_) => [
          for (var i = 1; i <= 3; i++)
            {
              'id': 'r$i',
              'group_id': 'g1',
              'user_id': 'u$i',
              'status': 'pending',
              'created_at': '2026-10-0${i}T10:00:00+00:00',
              'updated_at': '2026-10-0${i}T10:00:00+00:00',
            },
        ];
    _routes['profiles'] = (_) => [
          for (var i = 1; i <= 3; i++)
            {'id': 'u$i', 'full_name': 'Aday $i', 'avatar_url': null},
        ];

    final requests = await GroupChatService().getJoinRequests('g1');

    expect(requests, hasLength(3));
    expect(profileRequests(), 1);
    expect(requests.map((r) => r.userName), ['Aday 1', 'Aday 2', 'Aday 3']);
  });
}
