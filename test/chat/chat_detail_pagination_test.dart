import 'dart:async';
import 'dart:convert';

import 'package:cizreapp/core/models/message_model.dart';
import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/features/chat/screens/chat_detail_screen.dart';
import 'package:cizreapp/features/chat/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Konuşma ekranı (Görev 1.2): ilk sayfa tek istekle gelir, liste TERS
/// (açılışta zaten en altta), önbellekteki sayfa beklemeden çizilir, yukarı
/// kaydırınca önceki sayfa yüklenir ve görünüm kaymaz, yukarıdayken gelen
/// yeni mesaj görünümü kaydırmaz.

const _me = 'me';
const _peer = 'peer';
const _conv = 'conv-1';

final _t0 = DateTime.utc(2026, 9, 27, 8);

/// i. mesaj (0 = en eski). Çift sıradakiler benim.
Message _msg(int i) => Message.fromMap({
  'id': 'm$i',
  'conversation_id': _conv,
  'sender_id': i.isEven ? _me : _peer,
  'content': 'Mesaj $i',
  'is_read': true,
  'created_at': _t0.add(Duration(minutes: i)).toIso8601String(),
  'updated_at': _t0.add(Duration(minutes: i)).toIso8601String(),
});

/// [from, to] aralığı, en yeniden eskiye (RPC'nin döndürdüğü sıra).
List<Message> _newestFirst(int from, int to) => [
  for (var i = to; i >= from; i--) _msg(i),
];

class _FakeChatService extends ChatService {
  _FakeChatService({required this.firstPage, this.olderPage = const []});

  final List<Message> firstPage;
  final List<Message> olderPage;
  Completer<void>? firstPageGate;
  int firstPageCalls = 0;
  final List<DateTime> olderRequests = [];
  void Function(RealtimeMessageEvent event)? emit;

  @override
  Future<List<Message>> getMessagesPage(
    String conversationId, {
    DateTime? before,
    int limit = ChatService.messagePageSize,
  }) async {
    if (before == null) {
      firstPageCalls++;
      final gate = firstPageGate;
      if (gate != null) await gate.future;
      return firstPage;
    }
    olderRequests.add(before);
    return olderPage;
  }

  @override
  RealtimeChannel subscribeToMessagesChannel({
    required String conversationId,
    required String currentUserId,
    required void Function(RealtimeMessageEvent event) onEvent,
  }) {
    emit = onEvent;
    // Katılınmayan kanal: testte gerçek soket açılmaz.
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
    'get_chat_presence_settings' => {
      'last_seen': true,
      'last_seen_in_chat': true,
      'last_seen_in_profile': true,
      'last_seen_max_days': 7,
      'online': true,
      'typing': true,
      'typing_in_groups': true,
    },
    _ => <Object>[],
  };
  return http.Response(
    jsonEncode(body),
    200,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

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
}

/// Balondaki mesaj metni. Balon, saat için satır sonuna görünmez bir yer
/// tutucu (WidgetSpan) ekler (Görev 2.3); eşleştirme onu yok sayar.
Finder _text(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? w.textSpan?.toPlainText(includePlaceholders: false)) == text,
  description: 'mesaj metni "$text"',
);

/// Mesaj listesinin kaydırıcısı (mesaj kutusunun kendi kaydırıcısı değil).
Finder get _listScrollable => find
    .descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable))
    .first;

/// O anda çizilmiş (ekranda ya da önbellek alanında) ilk mesaj metni.
String _firstBuiltMessage(Iterable<int> ids) {
  for (final i in ids) {
    if (_text('Mesaj $i').evaluate().isNotEmpty) return 'Mesaj $i';
  }
  throw StateError('çizilmiş mesaj yok');
}

/// Ekranın orta bölgesinde görünen ilk mesaj metni.
String _visibleMessage(WidgetTester tester, Iterable<int> ids) {
  for (final i in ids) {
    final f = _text('Mesaj $i');
    if (f.evaluate().isEmpty) continue;
    final dy = tester.getTopLeft(f).dy;
    if (dy > 150 && dy < 650) return 'Mesaj $i';
  }
  throw StateError('ekranda mesaj yok');
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(_listScrollable).position;

double _dy(WidgetTester tester, String text) =>
    tester.getTopLeft(_text(text)).dy;

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

  // Ekran kapanırken son sayfayı önbelleğe yazar; testler birbirini etkilemesin.
  setUp(() => ChatService().rememberConversationPage(_conv, const []));

  testWidgets('açılış: tek sayfa isteği, liste ters ve en yeni mesaj en altta', (tester) async {
    final service = _FakeChatService(firstPage: _newestFirst(60, 99));
    await _open(tester, service);
    await tester.pumpAndSettle();

    expect(service.firstPageCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final position = _position(tester);
    expect(position.pixels, position.minScrollExtent, reason: 'açılışta en altta');
    expect(_text('Mesaj 99'), findsOneWidget);
    expect(_text('Mesaj 98'), findsOneWidget);
    expect(_dy(tester, 'Mesaj 99'), greaterThan(_dy(tester, 'Mesaj 98')),
        reason: 'en yeni mesaj en altta');
    expect(_text('Mesaj 60'), findsNothing, reason: 'eski mesajlar ekran dışında');
  });

  testWidgets('önbellekteki sayfa sunucuyu beklemeden çizilir', (tester) async {
    ChatService().rememberConversationPage(_conv, _newestFirst(90, 99));
    final service = _FakeChatService(firstPage: _newestFirst(60, 99))
      ..firstPageGate = Completer<void>();
    await _open(tester, service);
    await tester.pump();

    expect(_text('Mesaj 99'), findsOneWidget, reason: 'istek bitmeden görünmeli');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    service.firstPageGate!.complete();
    await tester.pumpAndSettle();
    expect(_text('Mesaj 99'), findsOneWidget);
  });

  testWidgets('ilk sayfa önbellekteki silinmiş mesajı kaldırır, canlı geleni korur', (tester) async {
    // Önbellekte 'Mesaj 95' var ama sunucudaki ilk sayfada yok (silinmiş).
    ChatService().rememberConversationPage(_conv, _newestFirst(90, 99));
    final page = _newestFirst(60, 99).where((m) => m.id != 'm95').toList();
    final service = _FakeChatService(firstPage: page)..firstPageGate = Completer<void>();
    await _open(tester, service);
    await tester.pump();
    expect(_text('Mesaj 95'), findsOneWidget);

    // Sayfa gelmeden canlı bir mesaj geldi.
    service.emit!(InsertMessageEvent(_msg(100)));
    await tester.pump();
    service.firstPageGate!.complete();
    await tester.pumpAndSettle();

    expect(_text('Mesaj 95'), findsNothing);
    expect(_text('Mesaj 100'), findsOneWidget);
  });

  testWidgets('yukarı kaydırınca önceki sayfa yüklenir, görünüm kaymaz', (tester) async {
    final service = _FakeChatService(
      firstPage: _newestFirst(60, 99),
      olderPage: _newestFirst(20, 59),
    );
    await _open(tester, service);
    await tester.pumpAndSettle();

    // En üste kadar kaydır (ters listede aşağı sürüklemek).
    while (service.olderRequests.isEmpty) {
      await tester.drag(_listScrollable, const Offset(0, 600));
      await tester.pump();
    }
    expect(service.olderRequests.single, _msg(60).createdAt,
        reason: 'en eski yüklü mesajdan öncesi istenir');
    final anchor = _firstBuiltMessage([for (var i = 60; i < 100; i++) i]);
    final before = _dy(tester, anchor);
    await tester.pumpAndSettle();

    expect(_dy(tester, anchor), before, reason: 'eski sayfa eklenince görünüm kaymamalı');
    await tester.drag(_listScrollable, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(_text('Mesaj 59'), findsOneWidget);
  });

  testWidgets('yukarıdayken gelen yeni mesaj görünümü kaydırmaz', (tester) async {
    final service = _FakeChatService(firstPage: _newestFirst(60, 99));
    await _open(tester, service);
    await tester.pumpAndSettle();

    await tester.drag(_listScrollable, const Offset(0, 900));
    await tester.pumpAndSettle();
    // Çapa: ekranın ortasında görünen bir mesaj (balon boyu tasarıma bağlı).
    final anchor = _text(_visibleMessage(tester, [for (var i = 99; i >= 60; i--) i]));
    expect(anchor, findsOneWidget);
    final before = tester.getTopLeft(anchor).dy;

    service.emit!(InsertMessageEvent(_msg(100)));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(anchor).dy, before);
    expect(_text('Mesaj 100'), findsNothing, reason: 'kullanıcı eski mesajları okuyor');

    // En alta dönünce yeni mesaj orada.
    await tester.drag(_listScrollable, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(_text('Mesaj 100'), findsOneWidget);
  });

  testWidgets('alttayken gelen yeni mesaj en altta görünür', (tester) async {
    final service = _FakeChatService(firstPage: _newestFirst(60, 99));
    await _open(tester, service);
    await tester.pumpAndSettle();

    service.emit!(InsertMessageEvent(_msg(100)));
    await tester.pumpAndSettle();

    expect(_text('Mesaj 100'), findsOneWidget);
    expect(_dy(tester, 'Mesaj 100'), greaterThan(_dy(tester, 'Mesaj 99')));
  });

  testWidgets('yüklenmemiş eski mesajın güncelleme olayı listeye eklenmez', (tester) async {
    final service = _FakeChatService(firstPage: _newestFirst(60, 99));
    await _open(tester, service);
    await tester.pumpAndSettle();

    // Konuşma açılınca okundu işaretlenen eski (sayfa dışı) bir mesaj.
    service.emit!(UpdateMessageEvent(_msg(5)));
    await tester.pumpAndSettle();

    expect(_text('Mesaj 5'), findsNothing);
    expect(_dy(tester, 'Mesaj 99'), greaterThan(_dy(tester, 'Mesaj 98')),
        reason: 'en altta hâlâ en yeni mesaj');
  });
}
