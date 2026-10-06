import 'dart:convert';

import 'package:cizreapp/core/models/message_model.dart';
import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/features/chat/screens/chat_detail_screen.dart';
import 'package:cizreapp/features/chat/services/chat_service.dart';
import 'package:cizreapp/features/chat/widgets/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 2.3 — "okundu" bilgisi canlı gelir: karşı taraf mesajımı okuyunca
/// (onun konuşmasındaki kopyası is_read=true olur) mavi çift tik ekran
/// yeniden açılmadan görünür. Ayrıca gün hapları ve öbekleme ekranda.

const _me = 'me';
const _peer = 'peer';
const _conv = 'conv-me';
const _peerConv = 'conv-peer';

Map<String, dynamic> _row({
  required String id,
  required String conv,
  required String sender,
  required String content,
  required DateTime at,
  bool isRead = false,
}) => {
  'id': id,
  'conversation_id': conv,
  'sender_id': sender,
  'content': content,
  'is_read': isRead,
  'created_at': at.toIso8601String(),
  'updated_at': at.toIso8601String(),
};

class _FakeChatService extends ChatService {
  _FakeChatService(this.firstPage);

  final List<Message> firstPage;
  void Function(RealtimeMessageEvent event)? emit;

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
  }) {
    emit = onEvent;
    return Supabase.instance.client.channel('test-$conversationId');
  }

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
    _ => <Object>[],
  };
  return http.Response(
    jsonEncode(body),
    200,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

/// Bugün öğlen (Türkiye saati) — gece yarısı sınırında test kararsız olmasın.
DateTime _todayNoonTr() {
  final tr = DateTime.now().toUtc().add(const Duration(hours: 3));
  return DateTime.utc(tr.year, tr.month, tr.day, 12).subtract(const Duration(hours: 3));
}

Future<void> _open(WidgetTester tester, _FakeChatService service) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        home: ChatDetailScreen(
          conversationId: _conv,
          otherUserId: _peer,
          otherUserName: 'Ayşe',
          chatService: service,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Metni [content] olan balonun durum tiki.
Icon _ticksOf(WidgetTester tester, String content) {
  final bubble = find.ancestor(
    of: find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.textSpan?.toPlainText(includePlaceholders: false) == content,
    ),
    matching: find.byType(ChatBubble),
  );
  return tester.widget<Icon>(
    find.descendant(of: bubble, matching: find.byType(Icon)),
  );
}

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

  setUp(() => ChatService().rememberConversationPage(_conv, const []));

  group('ChatService.readReceiptFrom', () {
    final at = DateTime.utc(2026, 9, 27, 9);

    test('karşı taraftaki kopyam okundu → olay', () {
      final event = ChatService.readReceiptFrom(
        _row(id: 'p1', conv: _peerConv, sender: _me, content: 'Selam', at: at, isRead: true),
        conversationId: _conv,
        currentUserId: _me,
      );
      expect(event, isNotNull);
      expect(event!.partnerCopy.content, 'Selam');
      expect(event.partnerCopy.createdAt, at);
    });

    test('kendi kopyam, okunmamış kopya ya da başkasının mesajı → olay yok', () {
      expect(
        ChatService.readReceiptFrom(
          _row(id: 'm1', conv: _conv, sender: _me, content: 'Selam', at: at, isRead: true),
          conversationId: _conv,
          currentUserId: _me,
        ),
        isNull,
      );
      expect(
        ChatService.readReceiptFrom(
          _row(id: 'p1', conv: _peerConv, sender: _me, content: 'Selam', at: at),
          conversationId: _conv,
          currentUserId: _me,
        ),
        isNull,
      );
      expect(
        ChatService.readReceiptFrom(
          _row(id: 'x1', conv: _peerConv, sender: _peer, content: 'Selam', at: at, isRead: true),
          conversationId: _conv,
          currentUserId: _me,
        ),
        isNull,
      );
    });
  });

  testWidgets('karşı taraf okuyunca tek tik → mavi çift tik (ekran yeniden açılmadan)', (tester) async {
    final sentAt = _todayNoonTr();
    final service = _FakeChatService([
      Message.fromMap(_row(id: 'm2', conv: _conv, sender: _me, content: 'Geliyor musun?', at: sentAt)),
      Message.fromMap(_row(id: 'm1', conv: _conv, sender: _peer, content: 'Selam', at: sentAt.subtract(const Duration(minutes: 1)), isRead: true)),
    ]);
    await _open(tester, service);

    expect(_ticksOf(tester, 'Geliyor musun?').icon, Icons.done);

    // Başka bir mesajın okunması bu balonu değiştirmez.
    service.emit!(PartnerReadEvent(Message.fromMap(
      _row(id: 'p9', conv: _peerConv, sender: _me, content: 'Başka', at: sentAt, isRead: true),
    )));
    await tester.pump();
    expect(_ticksOf(tester, 'Geliyor musun?').icon, Icons.done);

    service.emit!(PartnerReadEvent(Message.fromMap(
      _row(id: 'p2', conv: _peerConv, sender: _me, content: 'Geliyor musun?', at: sentAt, isRead: true),
    )));
    await tester.pump();

    final ticks = _ticksOf(tester, 'Geliyor musun?');
    expect(ticks.icon, Icons.done_all);
    expect(ticks.color, ChatPalette.readTick);
  });

  testWidgets('gün hapları Türkiye gününe göre; art arda mesajlar tek öbek', (tester) async {
    final today = _todayNoonTr();
    final yesterday = today.subtract(const Duration(days: 1));
    final service = _FakeChatService([
      // En yeniden eskiye (RPC sırası).
      Message.fromMap(_row(id: 'm4', conv: _conv, sender: _me, content: 'İkinci', at: today.subtract(const Duration(seconds: 30)), isRead: true)),
      Message.fromMap(_row(id: 'm3', conv: _conv, sender: _me, content: 'Birinci', at: today.subtract(const Duration(minutes: 1)), isRead: true)),
      Message.fromMap(_row(id: 'm2', conv: _conv, sender: _peer, content: 'Dünden', at: yesterday, isRead: true)),
    ]);
    await _open(tester, service);

    expect(find.byType(ChatDayPill), findsNWidgets(2));
    expect(find.text('Dün'), findsOneWidget);
    expect(find.text('Bugün'), findsOneWidget);

    ChatBubble bubble(String content) => tester.widget<ChatBubble>(
      find.byWidgetPredicate((w) => w is ChatBubble && w.text == content),
    );
    expect(bubble('Birinci').joinsBelow, isTrue);
    expect(bubble('İkinci').joinsAbove, isTrue);
    expect(bubble('İkinci').joinsBelow, isFalse, reason: 'öbeğin sonu kuyruk taşır');
    expect(bubble('Dünden').joinsBelow, isFalse, reason: 'gün değişince öbek biter');
  });
}
