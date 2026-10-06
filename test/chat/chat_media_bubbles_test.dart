import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cizreapp/features/chat/services/chat_media_service.dart';
import 'package:cizreapp/features/chat/widgets/chat_media_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.1 — fotoğraf ve konum balonları, ek menüsü.

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  late Uint8List photo;

  setUpAll(() async {
    await loadTestFonts();
    photo = await _png(40, 30);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });

  setUp(ChatMediaService.resetForTesting);

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
    await tester.pump();
  }

  /// CachedNetworkImage'ın önbellek zamanlayıcısı test bitmeden boşalsın.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  group('ChatImageBubble', () {
    testWidgets('bu cihazdan gönderilen fotoğraf yerel baytlardan; saat fotoğrafın üstünde', (tester) async {
      ChatMediaService.rememberLocalBytes('a/b/c.jpg', photo);
      await pump(
        tester,
        const ChatImageBubble(path: 'a/b/c.jpg', aspectRatio: 0.75, time: '14:05', isMine: true, status: 'read'),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect(((image.image as ResizeImage).imageProvider as MemoryImage).bytes, same(photo));
      expect(find.byType(CachedNetworkImage), findsNothing);
      // 400 × 0.68 = 272 genişlik, 3:4 → 362.7 yükseklik
      expect(tester.getSize(find.byType(AspectRatio)), Size(272, 272 / 0.75));
      expect(find.text('14:05'), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      // Balonun etiketi saat ve durumla birleşir (ekran okuyucu tek düğüm okur).
      expect(find.bySemanticsLabel(RegExp(r'^Fotoğraf\n14:05')), findsOneWidget);
    });

    testWidgets('çok uzun fotoğraf 0.6 oranına sıkıştırılır; oran yoksa kare', (tester) async {
      expect(ChatImageBubble.frameAspect(0.3), 0.6);
      expect(ChatImageBubble.frameAspect(3), 1.8);
      expect(ChatImageBubble.frameAspect(null), 1);
      ChatMediaService.rememberLocalBytes('a/b/c.jpg', photo);
      await pump(tester, const ChatImageBubble(path: 'a/b/c.jpg', time: '14:05', isMine: false));
      expect(tester.getSize(find.byType(AspectRatio)), const Size(272, 272));
    });

    testWidgets('açıklama fotoğrafın altında, saat açıklamanın sonunda', (tester) async {
      ChatMediaService.rememberLocalBytes('a/b/c.jpg', photo);
      await pump(
        tester,
        const ChatImageBubble(path: 'a/b/c.jpg', caption: 'Dicle kıyısı', time: '14:05', isMine: false),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText(includePlaceholders: false) == 'Dicle kıyısı',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Fotoğraf: Dicle kıyısı')), findsOneWidget);
      final captionTop = tester.getTopLeft(find.byType(RichText).last).dy;
      final photoBottom = tester.getBottomLeft(find.byType(AspectRatio)).dy;
      expect(captionTop, greaterThanOrEqualTo(photoBottom));
    });

    testWidgets('gönderilirken bekleme halkası, dokunma kapalı; başarısızsa tekrar dene', (tester) async {
      ChatMediaService.rememberLocalBytes('a/b/c.jpg', photo);
      var taps = 0;
      var retries = 0;
      await pump(
        tester,
        ChatImageBubble(
          path: 'a/b/c.jpg',
          time: '14:05',
          isMine: true,
          status: 'sending',
          onTap: () => taps++,
          onRetry: () => retries++,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(ChatImageBubble));
      expect((taps, retries), (0, 0));

      await pump(
        tester,
        ChatImageBubble(
          path: 'a/b/c.jpg',
          time: '14:05',
          isMine: true,
          status: 'failed',
          onTap: () => taps++,
          onRetry: () => retries++,
        ),
      );
      expect(find.text('Gönderilemedi • Tekrar dene'), findsOneWidget);
      await tester.tap(find.byType(ChatImageBubble));
      expect((taps, retries), (0, 1));
    });

    testWidgets('karşıdan gelen fotoğraf imzalı adresle, yola bağlı önbellek anahtarıyla', (tester) async {
      final signRequests = <http.Request>[];
      ChatMediaService.shared = ChatMediaService(
        client: SupabaseClient(
          'https://test.invalid',
          'key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((req) async {
            signRequests.add(req);
            final paths = (jsonDecode(req.body)['paths'] as List).cast<String>();
            return http.Response(
              jsonEncode([
                for (final p in paths) {'path': p, 'signedURL': '/object/sign/chat_attachments/$p?token=t'},
              ]),
              200,
              request: req,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      await pump(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatImageBubble(path: 'x/y/1.jpg', aspectRatio: 1.6, time: '09:00', isMine: false),
            ChatImageBubble(path: 'x/y/2.jpg', aspectRatio: 1.6, time: '09:01', isMine: false),
          ],
        ),
      );
      await tester.pump();

      expect(signRequests, hasLength(1), reason: 'iki balon tek imza isteği');
      final images = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();
      expect(images.map((i) => i.cacheKey), ['chat_attachments/x/y/1.jpg', 'chat_attachments/x/y/2.jpg']);
      expect(images.first.imageUrl, 'https://test.invalid/storage/v1/object/sign/chat_attachments/x/y/1.jpg?token=t');
      await finish(tester);
    });
  });

  group('ChatLocationBubble', () {
    testWidgets('çizilmiş harita, iğne, adres ve koordinat; dokununca açılır', (tester) async {
      var taps = 0;
      await pump(
        tester,
        ChatLocationBubble(
          latitude: 37.3256,
          longitude: 42.192,
          label: 'Ali Bey, Temiz Sk. No:4, Cizre/Şırnak',
          time: '10:30',
          isMine: false,
          onTap: () => taps++,
        ),
      );
      expect(find.byType(ChatMapPreview), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(find.text('Ali Bey, Temiz Sk. No:4, Cizre/Şırnak'), findsOneWidget);
      expect(find.text('37.32560, 42.19200'), findsOneWidget);
      expect(find.text('10:30'), findsOneWidget);
      await tester.tap(find.byType(ChatLocationBubble));
      expect(taps, 1);
    });

    testWidgets('adres yoksa "Konum"; kendi mesajımda tik', (tester) async {
      await pump(
        tester,
        const ChatLocationBubble(latitude: 1, longitude: 2, time: '10:30', isMine: true, status: 'sent'),
      );
      expect(find.text('Konum'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Konum: Konum')), findsOneWidget);
      expect(find.byIcon(Icons.done), findsOneWidget);
    });
  });

  group('Ek menüsü', () {
    Future<ChatAttachmentAction?> open(WidgetTester tester, {required bool camera, required String choose}) async {
      ChatAttachmentAction? picked;
      await pump(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => picked = await showChatAttachmentSheet(context, cameraAvailable: camera),
            child: const Text('aç'),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(find.text('Galeri'), findsOneWidget);
      expect(find.text('Konum'), findsOneWidget);
      expect(find.text('Kamera'), camera ? findsOneWidget : findsNothing);
      await tester.tap(find.text(choose));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('Galeri / Kamera / Konum', (tester) async {
      expect(await open(tester, camera: true, choose: 'Kamera'), ChatAttachmentAction.camera);
      expect(await open(tester, camera: true, choose: 'Konum'), ChatAttachmentAction.location);
    });

    testWidgets('kamera yoksa (web) gösterilmez', (tester) async {
      expect(await open(tester, camera: false, choose: 'Galeri'), ChatAttachmentAction.gallery);
    });
  });
}
