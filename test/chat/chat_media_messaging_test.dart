import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cizreapp/core/models/message_model.dart';
import 'package:cizreapp/core/services/maps_api_key_service.dart';
import 'package:cizreapp/features/chat/services/chat_location_service.dart';
import 'package:cizreapp/features/chat/services/chat_media_service.dart';
import 'package:cizreapp/features/chat/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 3.1 — sohbette fotoğraf/konum: özel kovaya yükleme, imzalı adreslerin
/// TEK istekte toplanması, gönderim RPC'sine tür/ek verinin gitmesi (metin
/// mesajında HİÇ gitmemesi), konum yardımcıları.

const _me = '11111111-1111-4111-8111-111111111111';
const _peer = '22222222-2222-4222-8222-222222222222';

class _FakeServer {
  final List<http.Request> requests = [];
  bool failUpload = false;
  bool failSign = false;
  bool failRpc = false;
  Set<String> missing = {};

  List<String> get paths => [for (final r in requests) r.url.path];

  http.Response _json(http.Request req, Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    request: req,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  MockClient client() => MockClient((req) async {
    requests.add(req);
    final path = req.url.path;
    if (path.startsWith('/storage/v1/object/sign/')) {
      if (failSign) return _json(req, {'message': 'boom'}, 500);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _json(req, [
        for (final p in (body['paths'] as List).cast<String>())
          missing.contains(p)
              ? {'path': p, 'error': 'Either the object does not exist or you do not have access to it', 'signedURL': null}
              : {'path': p, 'signedURL': '/object/sign/chat_attachments/$p?token=t-$p', 'error': null},
      ]);
    }
    if (path.startsWith('/storage/v1/object/chat_attachments/')) {
      if (failUpload) return _json(req, {'message': 'boom', 'statusCode': '500'}, 500);
      return _json(req, {'Key': 'chat_attachments/${path.substring('/storage/v1/object/chat_attachments/'.length)}'});
    }
    if (path.endsWith('/rpc/send_message_with_recipient')) {
      if (failRpc) return _json(req, {'message': 'boom', 'code': 'XX000'}, 500);
      final p = jsonDecode(req.body) as Map<String, dynamic>;
      return _json(req, [
        {
          'message_id': 'msg-${requests.length}',
          'sender_id': p['p_sender_id'],
          'recipient_id': _peer,
          'recipient_message_id': 'msg-r-${requests.length}',
          'content': p['p_content'],
          'conversation_id': p['p_conversation_id'],
          'created_at': '2026-09-28T10:00:00Z',
          'updated_at': '2026-09-28T10:00:00Z',
          'is_read': false,
          'reply_to_id': p['p_reply_to_id'],
          'reply_to_content': p['p_reply_to_content'],
          'reply_to_sender_name': p['p_reply_to_sender_name'],
          'message_type': p['p_message_type'] ?? 'text',
          'attachment': p['p_attachment'],
        },
      ]);
    }
    if (req.url.pathSegments.last == 'app_about_settings') {
      return _json(req, {'google_maps_api_key': 'test-maps-key'});
    }
    return _json(req, <Object>[]);
  });
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

late _FakeServer _server;

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
        autoRefreshToken: false,
      ),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'token-me',
        'token_type': 'bearer',
        'refresh_token': 'refresh-me',
        'expires_at': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
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
    _server
      ..requests.clear()
      ..failUpload = false
      ..failSign = false
      ..failRpc = false
      ..missing = {};
    ChatMediaService.resetForTesting();
  });

  group('ChatMediaService', () {
    test('yol <gönderen>/<alıcı>/<uuid>.<uzantı> — veritabanı CHECK kalıbına uyar', () {
      final path = ChatMediaService.newImagePath(senderId: _me, recipientId: _peer, extension: 'jpg');
      expect(
        RegExp(r'^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|png|webp|gif)$').hasMatch(path),
        isTrue,
        reason: path,
      );
      expect(path, startsWith('$_me/$_peer/'));
      expect(ChatMediaService.newImagePath(senderId: _me, recipientId: _peer, extension: 'jpg'), isNot(path));
    });

    test('aynı karede istenen adresler TEK istekte imzalanır ve saklanır', () async {
      final media = ChatMediaService.shared;
      _server.missing = {'$_me/$_peer/yok.jpg'};
      final results = await Future.wait([
        media.signedUrl('$_me/$_peer/a.jpg'),
        media.signedUrl('$_me/$_peer/b.jpg'),
        media.signedUrl('$_me/$_peer/a.jpg'),
        media.signedUrl('$_me/$_peer/yok.jpg'),
      ]);

      expect(_server.paths, ['/storage/v1/object/sign/chat_attachments']);
      final body = jsonDecode(_server.requests.single.body) as Map<String, dynamic>;
      expect(body['expiresIn'], 86400);
      expect((body['paths'] as List).toSet(), {'$_me/$_peer/a.jpg', '$_me/$_peer/b.jpg', '$_me/$_peer/yok.jpg'});
      expect(results[0], 'https://test.invalid/storage/v1/object/sign/chat_attachments/$_me/$_peer/a.jpg?token=t-$_me/$_peer/a.jpg');
      expect(results[2], results[0]);
      expect(results[3], isNull, reason: 'dosya yoksa adres yok');

      // Önbellekten: yeni istek yok.
      expect(await media.signedUrl('$_me/$_peer/b.jpg'), results[1]);
      expect(_server.requests, hasLength(1));
    });

    test('imzalama başarısızsa null; sonraki istek yeniden dener', () async {
      final media = ChatMediaService.shared;
      _server.failSign = true;
      expect(await media.signedUrl('$_me/$_peer/a.jpg'), isNull);
      _server.failSign = false;
      expect(await media.signedUrl('$_me/$_peer/a.jpg'), isNotNull);
      expect(_server.requests, hasLength(2));
    });

    test('yükleme: özel kovaya, doğru türle, bir yıllık önbellek, üzerine yazmadan', () async {
      await ChatMediaService.shared.upload(
        '$_me/$_peer/x.jpg',
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2]),
        contentType: 'image/jpeg',
      );
      final req = _server.requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/storage/v1/object/chat_attachments/$_me/$_peer/x.jpg');
      expect(req.headers['x-upsert'], 'false');
      final body = latin1.decode(req.bodyBytes);
      expect(body, contains('content-type: image/jpeg'));
      expect(body, contains('name="cacheControl"'));
      expect(body, contains('31536000'));
    });

    test('hazırlama: sıkıştırılmış JPEG ve ölçü; sıkıştırılamazsa gerçek türüyle orijinal', () async {
      final original = await _png(400, 300);
      final small = await _png(160, 120);

      final compressed = await ChatMediaService.prepareImage(original, compress: (_) async => small);
      expect((compressed.extension, compressed.contentType), ('jpg', 'image/jpeg'));
      expect(compressed.bytes, same(small));
      expect((compressed.width, compressed.height), (160, 120));

      final raw = await ChatMediaService.prepareImage(original, fileName: 'foto.jpg', compress: (_) async => null);
      expect((raw.extension, raw.contentType), ('png', 'image/png'), reason: 'ad .jpg olsa da içerik PNG');
      expect(raw.bytes, same(original));
      expect((raw.width, raw.height), (400, 300));

      final thrown = await ChatMediaService.prepareImage(original, compress: (_) async => throw Exception('web'));
      expect(thrown.bytes, same(original));
    });

    test('yerel baytlar sınırlı sayıda tutulur (en eskiler düşer)', () {
      for (var i = 0; i < 30; i++) {
        ChatMediaService.rememberLocalBytes('p$i', Uint8List.fromList([i]));
      }
      expect(ChatMediaService.localBytes('p0'), isNull);
      expect(ChatMediaService.localBytes('p29'), isNotNull);
    });
  });

  group('ChatService', () {
    test('metin mesajı: RPC isteği eskisiyle BİREBİR aynı (yeni parametre yok)', () async {
      final sent = await ChatService().sendMessage(conversationId: 'conv-1', content: 'selam');
      expect(sent?.messageType, MessageType.text);
      final body = jsonDecode(_server.requests.single.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {
        'p_conversation_id',
        'p_content',
        'p_sender_id',
        'p_reply_to_id',
        'p_reply_to_content',
        'p_reply_to_sender_name',
      });
    });

    test('fotoğraf: önce yükleme, sonra tür + ek ile mesaj', () async {
      const path = '$_me/$_peer/33333333-3333-4333-8333-333333333333.jpg';
      final image = PreparedChatImage(
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 9]),
        width: 1080,
        height: 1440,
        extension: 'jpg',
        contentType: 'image/jpeg',
      );
      final sent = await ChatService().sendImageMessage(
        conversationId: 'conv-1',
        path: path,
        image: image,
        caption: '  Akşam  ',
      );

      expect(_server.paths, [
        '/storage/v1/object/chat_attachments/$path',
        '/rest/v1/rpc/send_message_with_recipient',
      ]);
      final body = jsonDecode(_server.requests.last.body) as Map<String, dynamic>;
      expect(body['p_message_type'], 'image');
      expect(body['p_attachment'], {'path': path, 'w': 1080, 'h': 1440, 'caption': 'Akşam'});
      expect(body['p_content'], '📷 Akşam');
      expect(sent?.isImage, isTrue);
      expect(sent?.imagePath, path);
      expect(sent?.imageCaption, 'Akşam');
    });

    test('fotoğraf yüklenemezse mesaj gönderilmez', () async {
      _server.failUpload = true;
      final sent = await ChatService().sendImageMessage(
        conversationId: 'conv-1',
        path: '$_me/$_peer/x.jpg',
        image: PreparedChatImage(
          bytes: Uint8List.fromList([1]),
          width: 0,
          height: 0,
          extension: 'jpg',
          contentType: 'image/jpeg',
        ),
      );
      expect(sent, isNull);
      expect(_server.paths.where((p) => p.contains('/rpc/')), isEmpty);
    });

    test('açıklamasız fotoğrafın önizlemesi; ölçüsüz fotoğrafta w/h yok', () {
      expect(ChatService.imagePreviewText('   '), '📷 Fotoğraf');
      expect(
        ChatService.imageAttachment(
          path: 'a/b/c.jpg',
          image: PreparedChatImage(bytes: Uint8List(0), width: 0, height: 0, extension: 'jpg', contentType: 'image/jpeg'),
        ),
        {'path': 'a/b/c.jpg'},
      );
    });

    test('konum: önizleme metni adresle, ek veri koordinatla', () async {
      final sent = await ChatService().sendLocationMessage(
        conversationId: 'conv-1',
        location: const ChatLocationPick(latitude: 37.3256, longitude: 42.192, label: 'Ali Bey, Cizre'),
        replyToId: '44444444-4444-4444-8444-444444444444',
        replyToContent: 'neredesin?',
        replyToSenderName: 'Ayşe',
      );
      final body = jsonDecode(_server.requests.single.body) as Map<String, dynamic>;
      expect(body['p_message_type'], 'location');
      expect(body['p_attachment'], {'lat': 37.3256, 'lng': 42.192, 'label': 'Ali Bey, Cizre'});
      expect(body['p_content'], '📍 Konum: Ali Bey, Cizre');
      expect(body['p_reply_to_content'], 'neredesin?');
      expect(sent?.isLocation, isTrue);
      expect(sent?.locationLabel, 'Ali Bey, Cizre');

      _server.requests.clear();
      await ChatService().sendLocationMessage(
        conversationId: 'conv-1',
        location: const ChatLocationPick(latitude: 1, longitude: 2),
      );
      final plain = jsonDecode(_server.requests.single.body) as Map<String, dynamic>;
      expect(plain['p_content'], '📍 Konum');
      expect(plain['p_attachment'], {'lat': 1.0, 'lng': 2.0});
    });
  });

  group('ChatLocationService', () {
    test('kısa adres: ülke ve posta kodu atılır', () {
      expect(
        ChatLocationService.shortAddress('Ali Bey, Temiz Sk. No:4, 73200 Cizre/Şırnak, Türkiye'),
        'Ali Bey, Temiz Sk. No:4, Cizre/Şırnak',
      );
      expect(ChatLocationService.shortAddress('Cizre, Turkey'), 'Cizre');
    });

    test('harita bağlantıları ve koordinat biçimi', () {
      expect(
        ChatLocationService.directionsUri(37.3256, 42.192).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=37.3256%2C42.192',
      );
      expect(
        ChatLocationService.searchUri(37.3256, 42.192).toString(),
        'https://www.google.com/maps/search/?api=1&query=37.3256%2C42.192',
      );
      expect(ChatLocationService.formatCoordinates(37.32561234, 42.192), '37.32561, 42.19200');
    });

    test('ters coğrafi kodlama: anahtar veritabanından, adres kısaltılır; hata → null', () async {
      MapsApiKeyService.clearCache();
      final geocodeRequests = <Uri>[];
      var status = 'OK';
      final service = ChatLocationService(
        httpClient: MockClient((req) async {
          geocodeRequests.add(req.url);
          return http.Response(
            jsonEncode({
              'status': status,
              'results': [
                {'formatted_address': 'Ali Bey, Temiz Sk. No:4, 73200 Cizre/Şırnak, Türkiye'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      expect(await service.reverseGeocode(37.3256, 42.192), 'Ali Bey, Temiz Sk. No:4, Cizre/Şırnak');
      expect(geocodeRequests.single.queryParameters, {
        'latlng': '37.3256,42.192',
        'language': 'tr',
        'key': 'test-maps-key',
      });

      status = 'ZERO_RESULTS';
      expect(await service.reverseGeocode(0, 0), isNull);
      MapsApiKeyService.clearCache();
    });
  });
}
