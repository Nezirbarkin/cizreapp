import 'dart:convert';

import 'package:cizreapp/core/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Okunmamış sayı isteği TAMAMLANMALI.
///
/// cf40273'te eklenen "aynı anda gelen çağrılar tek isteği paylaşsın" kalıbı
/// `whenComplete(() => map.remove(id))` ile yazılmıştı: `remove` haritadaki
/// future'ın kendisini döndürür, `whenComplete` de dönen future'ı bekler →
/// future kendini bekleyip hiç tamamlanmıyordu. Bildirimler ekranı bu sayıyı
/// beklediği için sonsuza dek dönüyordu.

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

int _countRequests = 0;
int _unread = 3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        if (req.url.path == '/rest/v1/notifications') _countRequests++;
        return http.Response(
          jsonEncode([]),
          200,
          request: req,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'content-range': '*/$_unread',
          },
        );
      }),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
  });

  setUp(() => _countRequests = 0);

  test('getUnreadCount tamamlanır ve sayıyı döndürür', () async {
    final count = await NotificationService()
        .getUnreadCount('user-a')
        .timeout(const Duration(seconds: 5));
    expect(count, 3);
  });

  test('eşzamanlı çağrılar tek isteği paylaşır, ikisi de tamamlanır', () async {
    final service = NotificationService();
    final results = await Future.wait([
      service.getUnreadCount('user-b'),
      service.getUnreadCount('user-b'),
    ]).timeout(const Duration(seconds: 5));
    expect(results, [3, 3]);
    expect(_countRequests, 1);
  });

  test('önbellek süresi dolunca yeni istek de tamamlanır', () async {
    final service = NotificationService();
    await service.getUnreadCount('user-c').timeout(const Duration(seconds: 5));
    await service.markAsRead('x'); // önbelleği temizler
    _unread = 5;
    final count = await service
        .getUnreadCount('user-c')
        .timeout(const Duration(seconds: 5));
    expect(count, 5);
  });
}
