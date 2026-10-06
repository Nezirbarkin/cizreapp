import 'dart:convert';

import 'package:cizreapp/core/services/privacy_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Çevrimiçi durumu (heartbeat / ön-arka plan) gereksiz istek atmamalı.
///
/// Eskiden: her heartbeat önce tüm profil satırını (get_my_profile) çekiyordu;
/// ön plana dönüşte aynı satır iki kez okunuyordu; bir arka plan turu
/// (inactive → paused → inactive) çevrimdışı yazımını üç kez tekrarlıyordu.
/// Sunucu (set_my_presence) hayalet modu ve tercihi zaten kendisi uygular.

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

final List<String> _rpcCalls = [];
final List<Map<String, dynamic>> _presenceParams = [];
Map<String, dynamic> _profile = {};

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        Object? body;
        final path = req.url.path;
        if (path.startsWith('/rest/v1/rpc/')) {
          final name = path.substring('/rest/v1/rpc/'.length);
          _rpcCalls.add(name);
          if (name == 'get_my_profile') body = _profile;
          if (name == 'set_my_presence') {
            _presenceParams.add(
              Map<String, dynamic>.from(jsonDecode(req.body) as Map),
            );
          }
        }
        return http.Response(
          jsonEncode(body),
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
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'refresh_token': 'test-refresh-token',
        'user': {
          'id': 'user-1',
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  setUp(() {
    _rpcCalls.clear();
    _presenceParams.clear();
    _profile = {'is_ghost_mode': false, 'is_online_enabled': true};
  });

  testWidgets('heartbeat: her atımda yalnız set_my_presence (profil okunmaz)', (
    tester,
  ) async {
    _profile = {'is_ghost_mode': false, 'is_online_enabled': false};
    final service = PrivacyService();
    service.startHeartbeat();
    await tester.pump(const Duration(minutes: 2, seconds: 1));
    await tester.pump(const Duration(minutes: 2));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    service.stopHeartbeat();

    expect(_rpcCalls, ['set_my_presence', 'set_my_presence']);
    // Tercih kapalı olsa da true gönderilir: sunucu false'a çevirir.
    expect(_presenceParams.map((p) => p['p_is_online']), [true, true]);
  });

  test('ön plana dönüş: profil BİR kez okunur, çevrimiçi yazılır', () async {
    final service = PrivacyService();
    await service.onAppResumed();
    service.stopHeartbeat();

    expect(_rpcCalls, ['get_my_profile', 'set_my_presence']);
    expect(_presenceParams.single['p_is_online'], isTrue);
  });

  test('tercih kapalıyken dönüş: çevrimdışı yazılır', () async {
    _profile = {'is_ghost_mode': false, 'is_online_enabled': false};
    final service = PrivacyService();
    await service.onAppResumed();

    expect(_rpcCalls, ['get_my_profile', 'set_my_presence']);
    expect(_presenceParams.single['p_is_online'], isFalse);
  });

  test('hayalet modda dönüş: hiçbir şey yazılmaz', () async {
    _profile = {'is_ghost_mode': true, 'is_online_enabled': true};
    final service = PrivacyService();
    await service.onAppResumed();

    expect(_rpcCalls, ['get_my_profile']);
  });

  test('arka plan turu: çevrimdışı yazımı bir kez, dönüşten sonra yine çalışır', () async {
    final service = PrivacyService();
    // inactive → paused → (dönüşte) inactive
    await service.onAppPaused();
    await service.onAppPaused();
    await service.onAppPaused();
    expect(_rpcCalls, ['get_my_profile', 'set_my_presence']);
    expect(_presenceParams.single['p_is_online'], isFalse);

    _rpcCalls.clear();
    _presenceParams.clear();
    await service.onAppResumed();
    service.stopHeartbeat();
    await service.onAppPaused();
    expect(_rpcCalls, [
      'get_my_profile', 'set_my_presence', // dönüş
      'get_my_profile', 'set_my_presence', // yeni arka plan
    ]);
    expect(_presenceParams.map((p) => p['p_is_online']), [true, false]);
  });
}
