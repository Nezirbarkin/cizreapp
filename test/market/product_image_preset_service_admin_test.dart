import 'dart:convert';

import 'package:cizreapp/core/models/product_image_preset_model.dart';
import 'package:cizreapp/features/market/services/product_image_preset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin görsel kütüphanesi veri katmanı: sayfa/kimlik RPC'lerinin
/// parametreleri ve yanıt okuma; toplu yazımların parçalanması.
void main() {
  late List<http.Request> requests;
  late Object? Function(http.Request req) respond;

  ProductImagePresetService service() => ProductImagePresetService(
    client: SupabaseClient(
      'https://test.invalid',
      'test-key',
      httpClient: MockClient((req) async {
        requests.add(req);
        final body = respond(req);
        if (body == null) return http.Response('', 204, request: req);
        return http.Response(
          jsonEncode(body),
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ),
  );

  setUp(() {
    requests = [];
    respond = (_) => null;
  });

  Map<String, dynamic> row(String id, {bool active = true}) => {
    'id': id,
    'name': 'Görsel $id',
    'description': null,
    'image_url': 'https://example.invalid/$id.webp',
    'is_active': active,
    'display_order': 3,
    'created_at': '2026-10-16T09:00:00+00:00',
    'folder_id': 'f1',
  };

  /// `id=in.("a","b",…)` süzgecindeki kimlikler.
  List<String> idsOf(http.Request req) {
    final f = req.url.queryParameters['id']!;
    expect(f, startsWith('in.('));
    return [
      for (final id in f.substring(4, f.length - 1).split(','))
        id.replaceAll('"', ''),
    ];
  }

  test(
    'sayfa: süzgeç, sıralama, sayfa ve özet parametreleri; yanıt okunur',
    () async {
      respond = (_) => {
        'items': [row('a'), row('b', active: false)],
        'total': 1234,
        'summary': {
          'folders': [
            {
              'id': 'f1',
              'name': 'Manav',
              'display_order': 1,
              'is_active': true,
              'image_count': 1200,
              'active_image_count': 900,
            },
          ],
          'unfiled_count': 34,
          'unfiled_active_count': 30,
          'max_display_order': 8123,
        },
      };
      final page = await service().getAdminPage(
        const ProductImageAdminQuery(
          folderId: 'f1',
          status: ProductImageAdminStatus.passive,
          search: 'çiğ köfte',
          sort: ProductImageAdminSort.newest,
        ),
        offset: 120,
        withSummary: true,
      );

      expect(
        requests.single.url.path,
        '/rest/v1/rpc/admin_product_image_presets_page',
      );
      expect(jsonDecode(requests.single.body), {
        'p_folder_id': 'f1',
        'p_unfiled': false,
        'p_status': 'passive',
        'p_query': 'çiğ köfte',
        'p_sort': 'newest',
        'p_limit': ProductImagePresetService.adminPageSize,
        'p_offset': 120,
        'p_with_summary': true,
      });
      expect(page.total, 1234);
      expect(page.items.map((p) => p.id), ['a', 'b']);
      expect(page.items.last.isActive, isFalse);
      final s = page.summary!;
      expect(s.folders.single.imageCount, 1200);
      expect(s.totalCount, 1234);
      expect(s.activeCount, 930);
      expect(s.unfiledCount, 34);
      expect(s.maxDisplayOrder, 8123);
    },
  );

  test('özetsiz sayfa: summary null; klasörsüz süzgeci', () async {
    respond = (_) => {'items': <Object>[], 'total': 0};
    final page = await service().getAdminPage(
      const ProductImageAdminQuery(unfiled: true),
      limit: 0,
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_folder_id'], isNull);
    expect(body['p_unfiled'], isTrue);
    expect(body['p_status'], 'all');
    expect(body['p_sort'], 'order');
    expect(body['p_limit'], 0);
    expect(body['p_with_summary'], isFalse);
    expect(page.summary, isNull);
    expect(page.items, isEmpty);
  });

  test('süzgece uyan tüm kimlikler: sıralama/sayfa gönderilmez', () async {
    respond = (_) => ['a', 'b', 'c'];
    final ids = await service().getAdminPresetIds(
      const ProductImageAdminQuery(
        status: ProductImageAdminStatus.active,
        search: 'domates',
        sort: ProductImageAdminSort.newest,
      ),
    );
    expect(
      requests.single.url.path,
      '/rest/v1/rpc/admin_product_image_preset_ids',
    );
    expect(jsonDecode(requests.single.body), {
      'p_folder_id': null,
      'p_unfiled': false,
      'p_status': 'active',
      'p_query': 'domates',
    });
    expect(ids, ['a', 'b', 'c']);
  });

  test(
    'toplu yazımlar adres sınırına takılmasın diye parça parça gider',
    () async {
      final ids = [for (var i = 0; i < 320; i++) 'id$i'];
      final svc = service();

      await svc.setActive(ids, false);
      expect(requests, hasLength(3));
      expect(requests.every((r) => r.method == 'PATCH'), isTrue);
      expect(
        requests.map((r) => idsOf(r).length),
        everyElement(lessThanOrEqualTo(ProductImagePresetService.idBatchSize)),
      );
      expect(requests.expand(idsOf).toSet(), ids.toSet());
      expect(jsonDecode(requests.first.body), {'is_active': false});

      requests.clear();
      await svc.moveToFolder(ids, null);
      expect(requests, hasLength(3));
      expect(jsonDecode(requests.first.body), {'folder_id': null});
      expect(requests.expand(idsOf).toSet(), ids.toSet());

      requests.clear();
      await svc.deletePresets(ids.take(150).toList());
      expect(requests.single.method, 'DELETE');
      expect(idsOf(requests.single), hasLength(150));
    },
  );
}
