import 'dart:convert';

import 'package:cizreapp/core/models/group_model.dart';
import 'package:cizreapp/core/models/message_model.dart';
import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/features/chat/screens/chat_detail_screen.dart';
import 'package:cizreapp/features/chat/screens/group_chat_screen.dart';
import 'package:cizreapp/features/chat/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sohbette kopyala/yapıştır: mesaja uzun basınca Kopyala / Metni seç /
/// Yanıtla menüsü (birebir ve grup sohbeti), yazı kutusunda Yapıştır.

const _me = 'me';
const _peer = 'peer';
const _conv = 'conv-copy';
const _group = 'group-copy';

final _t0 = DateTime.utc(2026, 10, 5, 8);

Message _msg(int i, String content) => Message.fromMap({
  'id': 'm$i',
  'conversation_id': _conv,
  'sender_id': i.isEven ? _me : _peer,
  'content': content,
  'is_read': true,
  'created_at': _t0.add(Duration(minutes: i)).toIso8601String(),
  'updated_at': _t0.add(Duration(minutes: i)).toIso8601String(),
});

class _FakeChatService extends ChatService {
  _FakeChatService(this.firstPage);

  final List<Message> firstPage;

  @override
  Future<List<Message>> getMessagesPage(
    String conversationId, {
    DateTime? before,
    int limit = ChatService.messagePageSize,
  }) async => before == null ? firstPage : const [];

  @override
  RealtimeChannel subscribeToMessagesChannel({
    required String conversationId,
    required String currentUserId,
    required void Function(RealtimeMessageEvent event) onEvent,
  }) => Supabase.instance.client.channel('test-$conversationId');

  @override
  Future<void> markMessagesAsRead(String conversationId) async {}
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

MockClient _mock() => MockClient((req) async {
  final Object body = switch (req.url.pathSegments.last) {
    'get_typing_channel' => {'topic': null, 'send': false},
    'get_chat_presence_settings' => {
      'last_seen': true,
      'last_seen_in_chat': true,
      'last_seen_in_profile': true,
      'last_seen_max_days': 7,
      'online': true,
      'typing': true,
      'typing_in_groups': true,
    },
    'get_group_messages_with_read_count' => [
      {
        'id': 'g1',
        'group_id': _group,
        'sender_id': _peer,
        'content': 'Grup adresi: Nur Mah. 12',
        'created_at': _t0.toIso8601String(),
        'updated_at': _t0.toIso8601String(),
        'sender': {'full_name': 'Ayşe', 'avatar_url': null},
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

/// Platform panosunun test kopyası.
String? _clipboard;

Future<Object?> _platformHandler(MethodCall call) async {
  switch (call.method) {
    case 'Clipboard.setData':
      _clipboard = (call.arguments as Map)['text'] as String?;
    case 'Clipboard.getData':
      return _clipboard == null ? null : {'text': _clipboard};
    case 'Clipboard.hasStrings':
      return {'value': _clipboard?.isNotEmpty ?? false};
  }
  return null;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _openDirect(WidgetTester tester, List<Message> page) async {
  _phone(tester);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        home: ChatDetailScreen(
          conversationId: _conv,
          otherUserId: _peer,
          otherUserName: 'Ayşe',
          chatService: _FakeChatService(page),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Balondaki mesaj metni (saat yer tutucusu WidgetSpan yok sayılır).
Finder _bubbleText(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? w.textSpan?.toPlainText(includePlaceholders: false)) == text,
  description: 'mesaj metni "$text"',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _mock(),
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
    _clipboard = null;
    ChatService().rememberConversationPage(_conv, const []);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, _platformHandler);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final page = [
    _msg(1, 'IBAN: TR12 0006 4000 0011 2345 6789 01'),
    _msg(0, 'Merhaba'),
  ];

  group('birebir sohbet', () {
    testWidgets('uzun bas → Kopyala: mesaj panoya gider', (tester) async {
      await _openDirect(tester, page);

      await tester.longPress(_bubbleText('IBAN: TR12 0006 4000 0011 2345 6789 01'));
      await tester.pumpAndSettle();
      expect(find.text('Kopyala'), findsOneWidget);
      expect(find.text('Metni seç'), findsOneWidget);
      expect(find.text('Yanıtla'), findsOneWidget);

      await tester.tap(find.text('Kopyala'));
      await tester.pumpAndSettle();
      expect(_clipboard, 'IBAN: TR12 0006 4000 0011 2345 6789 01');
      expect(find.text('Mesaj kopyalandı'), findsOneWidget);
    });

    testWidgets('kendi mesajım da kopyalanır', (tester) async {
      await _openDirect(tester, page);

      await tester.longPress(_bubbleText('Merhaba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kopyala'));
      await tester.pumpAndSettle();
      expect(_clipboard, 'Merhaba');
    });

    testWidgets('Metni seç: seçilebilir pencere, Tümünü kopyala', (tester) async {
      await _openDirect(tester, page);

      await tester.longPress(_bubbleText('IBAN: TR12 0006 4000 0011 2345 6789 01'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Metni seç'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(SelectableText, 'IBAN: TR12 0006 4000 0011 2345 6789 01'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tümünü kopyala'));
      await tester.pumpAndSettle();
      expect(_clipboard, 'IBAN: TR12 0006 4000 0011 2345 6789 01');
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('Yanıtla: yanıt çubuğu açılır', (tester) async {
      await _openDirect(tester, page);

      await tester.longPress(_bubbleText('Merhaba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yanıtla'));
      await tester.pumpAndSettle();
      expect(find.text('Kendinize yanıt'), findsOneWidget);
      expect(_clipboard, isNull);
    });

    testWidgets('yazı kutusuna yapıştır', (tester) async {
      _clipboard = 'panodaki yazı';
      await _openDirect(tester, page);

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.longPress(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'panodaki yazı');
    });
  });

  group('grup sohbeti', () {
    testWidgets('uzun bas → Kopyala ve Yanıtla', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(
            group: ChatGroup(
              id: _group,
              name: 'Komşular',
              createdBy: _peer,
              memberCount: 2,
              createdAt: _t0,
              updatedAt: _t0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Grup adresi: Nur Mah. 12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kopyala'));
      await tester.pumpAndSettle();
      expect(_clipboard, 'Grup adresi: Nur Mah. 12');

      await tester.longPress(find.text('Grup adresi: Nur Mah. 12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yanıtla'));
      await tester.pumpAndSettle();
      // Yanıt çubuğu gönderenin adını ve mesajı gösterir.
      expect(find.text('Grup adresi: Nur Mah. 12'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
