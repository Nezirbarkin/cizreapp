import 'dart:convert';

import 'package:cizreapp/features/chat/services/group_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Grup sohbeti istek bütçesi (2026-10-23 performans turu):
/// * mesajlar son N ile sınırlı RPC aşırı yüklemesinden (20261023000004),
/// * grup listesi üç bağımsız sorguyu aynı anda atar,
/// * profiller kimlik listesiyle toplu (ekranlar kişi başına sorgu atmaz).

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

final _requests = <http.Request>[];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        _requests.add(req);
        return http.Response(
          jsonEncode(<Object>[]),
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
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

  setUp(_requests.clear);

  test('mesajlar sınırlı RPC ile', () async {
    await GroupChatService().getGroupMessages('g1');

    final rpc = _requests.single;
    expect(rpc.url.path, '/rest/v1/rpc/get_group_messages_with_read_count');
    expect(jsonDecode(rpc.body), {
      'p_group_id': 'g1',
      'p_limit': GroupChatService.messagesPageSize,
    });
  });

  test('grup listesi: üç sorgu aynı anda, gruplar sınırlı', () async {
    await GroupChatService().getAllGroups();

    final paths = _requests.map((r) => r.url.path).toSet();
    expect(paths, {
      '/rest/v1/group_members',
      '/rest/v1/group_join_requests',
      '/rest/v1/groups',
    });
    final groups = _requests.firstWhere((r) => r.url.path == '/rest/v1/groups');
    expect(groups.url.queryParameters['limit'], '300');
  });

  test('profilesById: tek istek, tekrarsız kimlikler', () async {
    await GroupChatService().profilesById(['a', 'b', 'a']);

    expect(_requests, hasLength(1));
    expect(_requests.single.url.queryParameters['id'], 'in.("a","b")');
  });
}
