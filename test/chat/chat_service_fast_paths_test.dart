import 'dart:async';
import 'dart:convert';

import 'package:cizreapp/features/chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sohbet hızlı yolları (Görev 1.2): liste ve konuşma TEK istekle açılır,
/// son görülen veri kullanıcıya bağlı bellekte tutulur, profilden sohbet
/// açma yolu paralel çalışır.

class _Request {
  _Request(this.path, this.body);
  final String path;
  final String body;
}

/// Yola göre yanıt veren sahte Supabase. [gate] verilirse yanıtlar onun
/// tamamlanmasını bekler (eşzamanlılığı görmek için).
class _FakeServer {
  final List<_Request> requests = [];
  final Map<String, Object? Function(http.Request req)> routes = {};
  final Set<String> failing = {};
  Completer<void>? gate;

  List<String> get paths => [for (final r in requests) r.path];

  MockClient client() => MockClient((req) async {
    requests.add(_Request(req.url.path, req.body));
    final g = gate;
    if (g != null) await g.future;
    final name = req.url.pathSegments.last;
    if (failing.contains(name)) {
      return http.Response(
        jsonEncode({'message': 'boom', 'code': 'XX000'}),
        500,
        request: req,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    final handler = routes[name];
    final Object? body = handler != null ? handler(req) : <Object>[];
    return http.Response(
      jsonEncode(body),
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

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

late _FakeServer _server;
var _userSeq = 0;

/// Her test farklı bir kullanıcıyla başlar: önbellek kullanıcıya bağlı
/// olduğundan testler birbirini etkilemez.
Future<String> _signInAsNewUser() async {
  final id = 'user-${++_userSeq}';
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode({
      'access_token': 'token-$id',
      'token_type': 'bearer',
      'refresh_token': 'refresh-$id',
      'user': {
        'id': id,
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
      },
    }),
  );
  return id;
}

Map<String, dynamic> _conversationRow(String me, String partner, int n) => {
  'id': 'conv-$me-$partner',
  'user_id': me,
  'other_user_id': partner,
  'last_message': 'mesaj $n',
  'last_message_time': '2026-09-27T10:0$n:00.123456+00:00',
  'unread_count': n,
  'created_at': '2026-09-01T10:00:00+00:00',
  'updated_at': '2026-09-27T10:0$n:00+00:00',
  'other_user': {
    'id': partner,
    'full_name': 'Kişi $n',
    'username': 'kisi$n',
    'avatar_url': null,
    'is_online': false,
    'last_seen': null,
  },
  'last_message_by_me': n.isEven,
  'last_message_read': n.isOdd,
};

Map<String, dynamic> _messageJson(String id, String conv, String sender, String at) => {
  'id': id,
  'conversation_id': conv,
  'sender_id': sender,
  'content': 'içerik $id',
  'is_read': true,
  'created_at': at,
  'updated_at': at,
  'reply_to_id': null,
  'reply_to_content': null,
  'reply_to_sender_name': null,
  'deleted_for_user_id': null,
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    _server = _FakeServer();
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _server.client(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
  });

  setUp(() {
    _server.requests.clear();
    _server.routes.clear();
    _server.failing.clear();
    _server.gate = null;
  });

  group('getConversations', () {
    test('tek istek atar (get_my_conversations) ve satırları eşler', () async {
      final me = await _signInAsNewUser();
      _server.routes['get_my_conversations'] = (_) => [
        _conversationRow(me, 'p1', 1),
        _conversationRow(me, 'p2', 2),
      ];

      final list = await ChatService().getConversations();

      expect(_server.paths, ['/rest/v1/rpc/get_my_conversations']);
      expect(list, hasLength(2));
      expect(list.first.id, 'conv-$me-p1');
      expect(list.first.userId, me);
      expect(list.first.otherUserId, 'p1');
      expect(list.first.otherUser?['full_name'], 'Kişi 1');
      expect(list.first.unreadCount, 1);
      expect(list.first.lastMessageByMe, isFalse);
      expect(list.first.lastMessageRead, isTrue);
      expect(list.last.lastMessageByMe, isTrue);
      expect(list.last.lastMessageRead, isFalse);
      expect(ChatService().cachedConversations, same(list));
    });

    test('aynı anda gelen çağrılar tek isteği paylaşır', () async {
      final me = await _signInAsNewUser();
      _server.routes['get_my_conversations'] = (_) => [_conversationRow(me, 'p1', 1)];
      _server.gate = Completer<void>();

      final first = ChatService().getConversations();
      final second = ChatService().getConversations();
      await Future<void>.delayed(Duration.zero);
      _server.gate!.complete();
      final results = await Future.wait([first, second]);

      expect(_server.paths, ['/rest/v1/rpc/get_my_conversations']);
      expect(results[0], same(results[1]));

      await ChatService().getConversations();
      expect(_server.paths, hasLength(2), reason: 'bittikten sonra yeni çağrı yeni istek atar');
    });

    test('RPC hata verirse eski çoklu-sorgu yoluna düşer', () async {
      await _signInAsNewUser();
      _server.failing.add('get_my_conversations');

      final list = await ChatService().getConversations();

      expect(list, isEmpty);
      expect(_server.paths.first, '/rest/v1/rpc/get_my_conversations');
      expect(_server.paths, contains('/rest/v1/conversations'),
          reason: 'eski yol konuşmaları doğrudan sorgular');
    });

    test('başka kullanıcı giriş yapınca önceki kullanıcının önbelleği kullanılmaz', () async {
      final me = await _signInAsNewUser();
      _server.routes['get_my_conversations'] = (_) => [_conversationRow(me, 'p1', 1)];
      await ChatService().getConversations();
      ChatService().rememberConversationPage('conv-x', const []);
      expect(ChatService().cachedConversations, isNotNull);

      await _signInAsNewUser();

      expect(ChatService().cachedConversations, isNull);
      expect(ChatService().cachedFirstPage('conv-x'), isNull);
    });

    test('oturum kapanınca (clearCache) önbellek boşalır', () async {
      final me = await _signInAsNewUser();
      _server.routes['get_my_conversations'] = (_) => [_conversationRow(me, 'p1', 1)];
      await ChatService().getConversations();
      ChatService().rememberConversationPage('conv-y', const []);

      ChatService.clearCache();

      expect(ChatService().cachedConversations, isNull);
      expect(ChatService().cachedFirstPage('conv-y'), isNull);
    });
  });

  group('getMessagesPage', () {
    test('tek istek, doğru parametreler, en yeniden eskiye; ilk sayfa önbelleğe girer', () async {
      final me = await _signInAsNewUser();
      _server.routes['get_conversation_messages'] = (_) => [
        _messageJson('m3', 'c1', me, '2026-09-27T10:03:00.654321+00:00'),
        _messageJson('m2', 'c1', 'p1', '2026-09-27T10:02:00+00:00'),
      ];

      final page = await ChatService().getMessagesPage('c1');

      expect(_server.paths, ['/rest/v1/rpc/get_conversation_messages']);
      final body = jsonDecode(_server.requests.single.body) as Map<String, dynamic>;
      expect(body, {'p_conversation_id': 'c1', 'p_before': null, 'p_limit': 40});
      expect([for (final m in page) m.id], ['m3', 'm2']);
      expect([for (final m in ChatService().cachedFirstPage('c1')!) m.id], ['m3', 'm2']);

      // Önceki sayfa: en eski mesajın tam zamanı (mikrosaniye dahil) gönderilir,
      // ilk sayfa önbelleği değişmez.
      _server.requests.clear();
      final older = await ChatService().getMessagesPage('c1', before: page.first.createdAt);
      final olderBody = jsonDecode(_server.requests.single.body) as Map<String, dynamic>;
      expect(olderBody['p_before'], '2026-09-27T10:03:00.654321Z');
      expect(older, hasLength(2));
      expect([for (final m in ChatService().cachedFirstPage('c1')!) m.id], ['m3', 'm2']);
    });

    test('ilk sayfada RPC hatası eski yola düşer; önceki sayfada hata iletilir', () async {
      await _signInAsNewUser();
      _server.failing.add('get_conversation_messages');

      final page = await ChatService().getMessagesPage('c1');
      expect(page, isEmpty);
      expect(_server.paths, contains('/rest/v1/conversations'),
          reason: 'eski yol konuşmayı doğrudan sorgular');

      await expectLater(
        ChatService().getMessagesPage('c1', before: DateTime.utc(2026, 9, 27)),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('getOrCreateConversation', () {
    test('profil ve mevcut konuşma PARALEL istenir, profil tek kez', () async {
      final me = await _signInAsNewUser();
      _server.routes['public_profiles_chat'] = (_) => [
        {
          'id': 'p1',
          'full_name': 'Kişi 1',
          'username': 'kisi1',
          'avatar_url': null,
          'is_online': false,
          'last_seen': null,
          'messages_enabled': true,
        },
      ];
      _server.routes['conversations'] = (_) => [
        {
          'id': 'conv-1',
          'user_id': me,
          'other_user_id': 'p1',
          'last_message': null,
          'last_message_time': null,
          'unread_count': 0,
          'created_at': '2026-09-01T10:00:00+00:00',
          'updated_at': '2026-09-01T10:00:00+00:00',
          'deleted_for_user_id': null,
        },
      ];
      _server.gate = Completer<void>();

      final pending = ChatService().getOrCreateConversation('p1');
      await Future<void>.delayed(Duration.zero);
      expect(
        _server.paths.toSet(),
        {'/rest/v1/public_profiles_chat', '/rest/v1/conversations'},
        reason: 'ikisi de ilk yanıt gelmeden gönderilmiş olmalı',
      );
      _server.gate!.complete();
      final conversation = await pending;

      expect(conversation?.id, 'conv-1');
      expect(conversation?.otherUser?['full_name'], 'Kişi 1');
      expect(conversation?.otherUser?.containsKey('messages_enabled'), isFalse);
      expect(
        _server.paths.where((p) => p.endsWith('public_profiles_chat')),
        hasLength(1),
        reason: 'profil eskiden iki kez sorgulanıyordu',
      );
    });

    test('mesaj izni kapalıysa konuşma açılmaz', () async {
      await _signInAsNewUser();
      _server.routes['public_profiles_chat'] = (_) => [
        {'id': 'p1', 'messages_enabled': false},
      ];

      final conversation = await ChatService().getOrCreateConversation('p1');

      expect(conversation, isNull);
      expect(
        _server.requests.where((r) => r.path.endsWith('/conversations') && r.body.isNotEmpty),
        isEmpty,
        reason: 'yeni konuşma eklenmemeli',
      );
    });
  });
}
