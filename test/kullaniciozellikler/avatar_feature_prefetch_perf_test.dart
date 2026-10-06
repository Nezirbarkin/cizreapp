import 'dart:async';
import 'dart:convert';

import 'package:cizreapp/kullaniciozellikler/services/profile_feature_service.dart';
import 'package:cizreapp/kullaniciozellikler/widgets/privileged_avatar.dart';
import 'package:cizreapp/shared/widgets/flash_discount_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keşfet akışı performans düzeltmeleri (2026-10-05):
///
/// * Akıştaki her kart yazarının özelliklerini ayrı RPC ile istiyordu; artık
///   sayfa başına tek `get_users_profile_features` isteği yeter.
/// * Her avatar, efekti olmasa bile sonsuz bir animasyon (ticker) çalıştırıp
///   kendini her karede yeniden kuruyordu; artık yalnız efekti olan
///   kullanıcıda ticker çalışır.
/// * Flaş indirim rozeti "animasyonları azalt" ayarına uyar.
final List<String> _singleCalls = [];
final List<List<String>> _batchCalls = [];
bool _batchFails = false;
Completer<void>? _batchGate;

Map<String, dynamic> _featureRow(String userId, {required String kind}) => {
  'user_id': userId,
  'assignment_id': 'a-$userId-$kind',
  'feature_id': 'f-$kind',
  'code': kind,
  'kind': kind,
  'name': 'Özellik',
  'description': '',
  'renderer_key': kind == 'avatar_effect' ? 'pulse_glow' : 'star',
  'primary_color': '#FF0000',
  'secondary_color': null,
  'config': <String, dynamic>{},
  'priority': 1,
  'starts_at': '2026-01-01T00:00:00Z',
  'expires_at': null,
};

/// Sunucudaki "özelliği olan" kullanıcılar.
final Map<String, List<Map<String, dynamic>>> _serverFeatures = {
  'effect-user': [_featureRow('effect-user', kind: 'avatar_effect')],
  'batch-badge': [_featureRow('batch-badge', kind: 'badge')],
};

Future<http.Response> _handle(http.Request req) async {
  Object body = const <Object>[];
  final path = req.url.path;
  if (path.endsWith('/rpc/get_users_profile_features')) {
    final ids = (jsonDecode(req.body)['p_user_ids'] as List).cast<String>();
    _batchCalls.add(ids);
    if (_batchGate != null) await _batchGate!.future;
    if (_batchFails) {
      return http.Response(
        jsonEncode({'message': 'boom', 'code': 'XX000'}),
        500,
        request: req,
        headers: {'content-type': 'application/json'},
      );
    }
    body = [for (final id in ids) ...?_serverFeatures[id]];
  } else if (path.endsWith('/rpc/get_user_profile_features')) {
    final id = jsonDecode(req.body)['p_user_id'] as String;
    _singleCalls.add(id);
    body = _serverFeatures[id] ?? const <Object>[];
  }
  return http.Response(
    jsonEncode(body),
    200,
    request: req,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // CachedNetworkImageProvider path_provider kanalını ister.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient(_handle),
    );
  });

  setUp(() {
    _singleCalls.clear();
    _batchCalls.clear();
    _batchFails = false;
    _batchGate = null;
  });

  group('ProfileFeatureService.prefetchUserFeatures', () {
    test('sayfadaki yazarlar tek istekle önbelleğe girer', () async {
      final service = ProfileFeatureService();
      await service.prefetchUserFeatures([
        'batch-badge',
        'batch-empty-1',
        'batch-empty-2',
        'batch-empty-1', // tekrar eden yazar tek kez gönderilir
      ]);

      expect(_batchCalls, hasLength(1));
      expect(_batchCalls.single, hasLength(3));

      final badge = await service.getUserFeatures('batch-badge');
      final empty = await service.getUserFeatures('batch-empty-1');
      expect(badge, hasLength(1));
      expect(empty, isEmpty);
      // Özelliği OLMAYAN kullanıcı da önbellekte: kart tekil RPC atmaz.
      expect(_singleCalls, isEmpty);
      expect(ProfileFeatureService.peekUserFeatures('batch-empty-2'), isEmpty);

      // Zaten önbellekte olanlar için yeni toplu istek atılmaz.
      await service.prefetchUserFeatures(['batch-badge', 'batch-empty-2']);
      expect(_batchCalls, hasLength(1));
    });

    test('ön-yükleme sürerken açılan kart ayrı RPC atmadan bekler', () async {
      _batchGate = Completer<void>();
      final service = ProfileFeatureService();
      final prefetch = service.prefetchUserFeatures(['inflight-user']);
      final cardLoad = service.getUserFeatures('inflight-user');
      await pumpEventQueue();
      expect(_singleCalls, isEmpty);

      _batchGate!.complete();
      await prefetch;
      expect(await cardLoad, isEmpty);
      expect(_singleCalls, isEmpty);
      expect(_batchCalls, hasLength(1));
    });

    test('toplu istek başarısızsa kart tekil isteğe düşer', () async {
      _batchFails = true;
      final service = ProfileFeatureService();
      final prefetch = service.prefetchUserFeatures(['fallback-user']);
      final cardLoad = service.getUserFeatures('fallback-user');
      await prefetch; // hata yutulur
      expect(await cardLoad, isEmpty);
      expect(_singleCalls, ['fallback-user']);
    });
  });

  group('PrivilegedAvatar', () {
    Widget host(String userId) => MaterialApp(
      home: Scaffold(
        body: PrivilegedAvatar(
          userId: userId,
          username: 'ali',
          avatarUrl: null,
        ),
      ),
    );

    testWidgets('efekti olmayan kullanıcıda ticker çalışmaz', (tester) async {
      await tester.pumpWidget(host('plain-user'));
      await tester.pump(); // özellikler yüklendi
      await tester.pump();
      // Eskiden 5 sn'lik sonsuz animasyon her karede yeni kare isterdi.
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('AL'), findsOneWidget); // baş harfler
    });

    testWidgets('efekti olan kullanıcıda animasyon çalışır', (tester) async {
      await tester.pumpWidget(host('effect-user'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);

      // Kullanıcı değişince (efekti yok) ticker durur.
      await tester.pumpWidget(host('plain-user'));
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('FlashDiscountBadge', () {
    testWidgets('animasyonları azalt açıkken sabit durur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Scaffold(body: FlashDiscountBadge(percentage: 20)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('%20 İndirim'), findsOneWidget);
    });

    testWidgets('varsayılan olarak nabız atar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FlashDiscountBadge(percentage: 20, compact: true)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(find.text('%20'), findsOneWidget);

      // Sonsuz değil: 3 nabızdan (~5,4 sn) sonra durur, uygulama boşta kalır.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
