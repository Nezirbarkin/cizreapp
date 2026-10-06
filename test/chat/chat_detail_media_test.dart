// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cizreapp/core/models/message_model.dart';
import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/features/chat/screens/chat_detail_screen.dart';
import 'package:cizreapp/features/chat/services/chat_location_service.dart';
import 'package:cizreapp/features/chat/services/chat_media_service.dart';
import 'package:cizreapp/features/chat/services/chat_service.dart';
import 'package:cizreapp/features/chat/widgets/chat_media_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_google_maps_platform.dart';
import '../helpers/test_fonts.dart';

/// Görev 3.1 — sohbet ekranında fotoğraf/konum: türlerin çizilmesi, "+"
/// menüsü, gönderilen medyanın geçici balonla ANINDA görünüp gerçek mesajla
/// yer değiştirmesi (RPC ya da realtime önce gelse de tek balon), başarısız
/// gönderimde "tekrar dene".

const _me = '11111111-1111-4111-8111-111111111111';
const _peer = '22222222-2222-4222-8222-222222222222';
const _conv = 'conv-media';

Message _msg({
  required String id,
  required String sender,
  required MessageType type,
  required Map<String, dynamic> attachment,
  required String content,
  required DateTime at,
}) => Message.fromMap({
  'id': id,
  'conversation_id': _conv,
  'sender_id': sender,
  'content': content,
  'is_read': false,
  'created_at': at.toIso8601String(),
  'updated_at': at.toIso8601String(),
  'message_type': type.dbValue,
  'attachment': attachment,
});

class _FakeChatService extends ChatService {
  _FakeChatService(this.firstPage);

  final List<Message> firstPage;
  void Function(RealtimeMessageEvent event)? emit;

  final List<ChatLocationPick> locationCalls = [];
  final List<({String path, String? caption, PreparedChatImage image})> imageCalls = [];
  final List<Completer<Message?>> pending = [];

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

  @override
  Future<Message?> sendLocationMessage({
    required String conversationId,
    required ChatLocationPick location,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
  }) {
    locationCalls.add(location);
    final completer = Completer<Message?>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<Message?> sendImageMessage({
    required String conversationId,
    required String path,
    required PreparedChatImage image,
    String? caption,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
    ChatMediaService? media,
  }) {
    imageCalls.add((path: path, caption: caption, image: image));
    final completer = Completer<Message?>();
    pending.add(completer);
    return completer.future;
  }
}

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF26A69A),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Gerçek asenkron işin (dosya okuma, görsel çözme) bitmesini bekler.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: 'beklenen durum oluşmadı');
}

void main() {
  late Uint8List photo;
  late String photoPath;
  late FakeGoogleMapsPlatform maps;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
    photo = await _png(64, 48);
    final dir = await Directory.systemTemp.createTemp('cizre_chat_media');
    photoPath = '${dir.path}${Platform.pathSeparator}foto.png';
    await File(photoPath).writeAsBytes(photo);

    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => call.method == 'pickImage' ? photoPath : null,
    );
    // Konum izni yok (0 = denied): açıklama ekranı gösterilir.
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => switch (call.method) {
        'checkPermission' || 'requestPermission' => 0,
        'isLocationServiceEnabled' => true,
        _ => null,
      },
    );

    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient(
        (req) async => http.Response(
          jsonEncode(<Object>[]),
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
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
    ChatService().rememberConversationPage(_conv, const []);
    ChatMediaService.resetForTesting();
    maps = FakeGoogleMapsPlatform();
    GoogleMapsFlutterPlatform.instance = maps;
  });

  Future<void> open(WidgetTester tester, _FakeChatService service) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
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

  /// "+" → Konum → açıklamada "Vazgeç" (izin yok) → Cizre merkezi gönderilir.
  Future<void> sendLocation(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Fotoğraf veya konum gönder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konum'));
    // Konum aranırken seçicide dönen halka var: pumpAndSettle bitmez.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sohbette konum paylaşmak için izin gerekiyor'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bu Konumu Gönder'));
    // Geçici balonda dönen halka var: pumpAndSettle bitmez, geçişi bekle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Message realLocation({String id = 'real-loc', bool isRead = false}) => _msg(
    id: id,
    sender: _me,
    type: MessageType.location,
    attachment: {'lat': ChatLocationService.defaultLatitude, 'lng': ChatLocationService.defaultLongitude},
    content: '📍 Konum',
    at: DateTime.now().toUtc(),
  );

  testWidgets('fotoğraf ve konum mesajları kendi balonlarıyla çizilir', (tester) async {
    final at = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
    ChatMediaService.rememberLocalBytes('$_peer/$_me/foto.jpg', photo);
    final service = _FakeChatService([
      _msg(
        id: 'm2',
        sender: _me,
        type: MessageType.location,
        attachment: {'lat': 37.3256, 'lng': 42.192, 'label': 'Ali Bey, Cizre'},
        content: '📍 Konum: Ali Bey, Cizre',
        at: at.add(const Duration(minutes: 1)),
      ),
      _msg(
        id: 'm1',
        sender: _peer,
        type: MessageType.image,
        attachment: {'path': '$_peer/$_me/foto.jpg', 'w': 64, 'h': 48, 'caption': 'Dicle'},
        content: '📷 Dicle',
        at: at,
      ),
    ]);
    await open(tester, service);

    expect(find.byType(ChatImageBubble), findsOneWidget);
    expect(find.byType(ChatLocationBubble), findsOneWidget);
    expect(find.text('Ali Bey, Cizre'), findsOneWidget);
    // Önizleme metni balonda metin olarak görünmez.
    expect(find.textContaining('📍 Konum'), findsNothing);
    expect(find.textContaining('📷'), findsNothing);
  });

  testWidgets('"+" menüsü: Galeri, Kamera, Konum', (tester) async {
    await open(tester, _FakeChatService(const []));
    await tester.tap(find.byTooltip('Fotoğraf veya konum gönder'));
    await tester.pumpAndSettle();
    expect(find.text('Galeri'), findsOneWidget);
    expect(find.text('Kamera'), findsOneWidget);
    expect(find.text('Konum'), findsOneWidget);
  });

  testWidgets('konum: geçici balon ANINDA, gerçek mesaj gelince yerini alır', (tester) async {
    final service = _FakeChatService(const []);
    await open(tester, service);
    await sendLocation(tester);

    expect(service.locationCalls.single.latitude, ChatLocationService.defaultLatitude);
    expect(find.byType(ChatLocationBubble), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ChatLocationBubble), matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
      reason: 'gönderiliyor',
    );

    service.pending.single.complete(realLocation());
    await tester.pumpAndSettle();
    expect(find.byType(ChatLocationBubble), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ChatLocationBubble), matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );
    expect(find.byIcon(Icons.done), findsOneWidget, reason: 'gönderildi tiki');
  });

  testWidgets('realtime RPC\'den önce gelirse de tek balon kalır', (tester) async {
    final service = _FakeChatService(const []);
    await open(tester, service);
    await sendLocation(tester);

    service.emit!(InsertMessageEvent(realLocation()));
    await tester.pump();
    expect(find.byType(ChatLocationBubble), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ChatLocationBubble), matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );

    service.pending.single.complete(realLocation());
    await tester.pumpAndSettle();
    expect(find.byType(ChatLocationBubble), findsOneWidget);
  });

  testWidgets('gönderilemezse "tekrar dene"; yeniden gönderince tek balon', (tester) async {
    final service = _FakeChatService(const []);
    await open(tester, service);
    await sendLocation(tester);

    service.pending.single.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Gönderilemedi • Tekrar dene'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // hata bildirimi kapansın
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ChatLocationBubble));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tekrar gönder'));
    // Yeni geçici balonda dönen halka var: pumpAndSettle bitmez.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(service.locationCalls, hasLength(2));
    expect(find.byType(ChatLocationBubble), findsOneWidget);
    service.pending.last.complete(realLocation(id: 'real-2'));
    await tester.pumpAndSettle();
    expect(find.text('Gönderilemedi • Tekrar dene'), findsNothing);
    expect(find.byType(ChatLocationBubble), findsOneWidget);
  });

  testWidgets('başarısız balon silinebilir', (tester) async {
    final service = _FakeChatService(const []);
    await open(tester, service);
    await sendLocation(tester);
    service.pending.single.complete(null);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ChatLocationBubble));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatLocationBubble), findsNothing);
    expect(service.locationCalls, hasLength(1));
  });

  testWidgets('fotoğraf: galeri → önizleme + açıklama → yerel baytlarla geçici balon', (tester) async {
    final service = _FakeChatService(const []);
    await open(tester, service);

    await tester.tap(find.byTooltip('Fotoğraf veya konum gönder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeri'));
    await tester.pump();
    await _settle(tester, () => find.text('Fotoğraf gönder').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Ayşe'), findsWidgets);

    await tester.enterText(find.byType(TextField).last, 'Dicle kıyısı');
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pump();
    await _settle(tester, () => service.imageCalls.isNotEmpty);
    // Geçici balonda dönen halka var: pumpAndSettle bitmez.
    await tester.pump(const Duration(milliseconds: 600));

    final call = service.imageCalls.single;
    expect(call.caption, 'Dicle kıyısı');
    expect(call.path, matches(RegExp('^$_me/$_peer/[0-9a-f-]{36}[.]png\$')),
        reason: 'test ortamında sıkıştırıcı yok → gerçek türüyle PNG');
    expect((call.image.width, call.image.height), (64, 48));

    // Geçici balon yerel baytlarla, "gönderiliyor".
    expect(find.byType(ChatImageBubble), findsOneWidget);
    expect(ChatMediaService.localBytes(call.path), isNotNull);
    expect(
      find.descendant(of: find.byType(ChatImageBubble), matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );

    service.pending.single.complete(
      _msg(
        id: 'real-img',
        sender: _me,
        type: MessageType.image,
        attachment: {'path': call.path, 'w': 64, 'h': 48, 'caption': 'Dicle kıyısı'},
        content: '📷 Dicle kıyısı',
        at: DateTime.now().toUtc(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatImageBubble), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ChatImageBubble), matching: find.byType(CircularProgressIndicator)),
      findsNothing,
    );
  });
}
