import 'dart:convert';

import 'package:cizreapp/okey/providers/okey_points_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Okey hediye geri sayımı (2026-10-23 performans turu): sayaç her saniye
/// `notifyListeners` çağırıyordu ve sağlayıcıyı izleyen ~2500 satırlık lobi
/// saniyede bir baştan kuruluyordu. Artık saniyelik değişim yalnız
/// `giftCountdownListenable`'dan yayınlanır; sağlayıcı yalnız hediye "hazır"
/// olunca haber verir.

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        final Object body = req.url.path == '/rest/v1/rpc/okey_get_wallet'
            ? [
                {
                  'points': 500,
                  'can_claim_hourly': false,
                  'seconds_until_next_gift': 3,
                  'hourly_gift_points': 100,
                  'ad_reward_points': 250,
                },
              ]
            : <Object>[];
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
        autoRefreshToken: false,
      ),
    );
  });

  testWidgets('saniyelik sayaç dinleyicileri uyandırmaz; hazır olunca bir kez', (
    tester,
  ) async {
    final provider = OkeyPointsProvider();

    // Cüzdan yüklensin (gerçek asenkron HTTP).
    for (var i = 0; i < 20 && provider.secondsUntilGift == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(provider.secondsUntilGift, 3);
    expect(provider.giftCountdownListenable.value, '00:03');

    var notifications = 0;
    provider.addListener(() => notifications++);
    final labels = <String>[];
    provider.giftCountdownListenable.addListener(
      () => labels.add(provider.giftCountdownListenable.value),
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(labels, ['00:02', '00:01']);
    expect(notifications, 0, reason: 'geri sayım sırasında lobi uyanmamalı');

    // Son saniye: hediye hazır → düğme durumu değişti, bir kez haber verilir.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(provider.canClaimGift, isTrue);
    expect(labels.last, 'Hazır');
    expect(notifications, 1);

    // Saniyelik zamanlayıcı test gövdesinde kapanmalı (bekleyen zamanlayıcı kalmasın).
    provider.dispose();
  });
}
