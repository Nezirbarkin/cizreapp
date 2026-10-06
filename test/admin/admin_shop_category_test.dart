import 'dart:convert';

import 'package:cizreapp/features/admin/services/admin_shop_category_service.dart';
import 'package:cizreapp/features/admin/widgets/admin_shop_category_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 4.5 — Admin > Dükkanlar > "Ana kategori": servis ve pencere.

class _FakeService extends AdminShopCategoryService {
  final calls = <String>[];
  Object? failSave;

  @override
  Future<List<ShopCategoryOption>> fetchCategories() async => const [
    ShopCategoryOption(id: 'c-food', name: 'Yemek', icon: 'utensils'),
    ShopCategoryOption(id: 'c-market', name: 'Market', icon: 'shopping-bag'),
    ShopCategoryOption(id: 'c-old', name: 'Eski Kategori', icon: null, isActive: false),
  ];

  @override
  Future<ShopCategoryChange> setShopCategory({
    required String shopId,
    required String categoryId,
    required bool lock,
    String? note,
  }) async {
    calls.add('$shopId:$categoryId:$lock:${note?.trim() ?? ''}');
    final error = failSave;
    if (error != null) throw error;
    return ShopCategoryChange(categoryId: categoryId, categoryName: 'Market', locked: lock, changed: true);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('servis', () {
    late List<http.Request> requests;
    late Object? Function(http.Request req) respond;

    AdminShopCategoryService service() => AdminShopCategoryService(
      client: SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((req) async {
          requests.add(req);
          return http.Response(
            jsonEncode(respond(req)),
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

    test('kategoriler sırayla, pasifler dahil okunur', () async {
      respond = (_) => [
        {'id': 'c1', 'name': ' Yemek ', 'icon': 'utensils', 'is_active': true, 'display_order': 1},
        {'id': 'c2', 'name': 'Eski', 'icon': 'bilinmeyen', 'is_active': false, 'display_order': 2},
      ];
      final list = await service().fetchCategories();
      expect(requests.single.url.path, '/rest/v1/categories');
      expect(requests.single.url.queryParameters['order'], 'display_order.asc.nullslast,name.asc.nullslast');
      expect(list.first.name, 'Yemek');
      expect(list.first.emoji, '🍽️');
      expect(list.last.isActive, isFalse);
      expect(list.last.emoji, '📁');
    });

    test('değiştirme tek RPC; boş not null gider', () async {
      respond = (_) => {'category_id': 'c2', 'category_name': 'Market', 'locked': true, 'changed': true};
      final change = await service().setShopCategory(shopId: 's1', categoryId: 'c2', lock: true, note: '   ');
      expect(requests.single.url.path, '/rest/v1/rpc/admin_set_shop_category');
      expect(jsonDecode(requests.single.body), {
        'p_shop_id': 's1',
        'p_category_id': 'c2',
        'p_lock': true,
        'p_note': null,
      });
      expect(change.categoryName, 'Market');
      expect(change.locked, isTrue);
      expect(change.changed, isTrue);
    });

    test('hata metinleri', () {
      expect(
        AdminShopCategoryService.errorMessage(const PostgrestException(message: 'x', hint: 'CATEGORY_INACTIVE')),
        contains('pasif'),
      );
      expect(
        AdminShopCategoryService.errorMessage(const PostgrestException(message: 'x', hint: 'CATEGORY_NOT_FOUND')),
        'Kategori bulunamadı (silinmiş olabilir).',
      );
      expect(
        AdminShopCategoryService.errorMessage(const PostgrestException(message: 'x', code: '42501')),
        'Bu işlem için yönetici yetkisi gerekli.',
      );
    });
  });

  group('pencere', () {
    Future<(_FakeService, List<ShopCategoryChange?>)> open(WidgetTester tester, {bool locked = false}) async {
      final fake = _FakeService();
      final results = <ShopCategoryChange?>[];
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => results.add(
                  await AdminShopCategoryDialog.show(
                    context,
                    shopId: 'shop-1',
                    shopName: 'Çay Evi',
                    currentCategoryId: 'c-food',
                    currentLocked: locked,
                    currentLockNote: locked ? 'Eski not' : null,
                    service: fake,
                  ),
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await _settle(tester);
      return (fake, results);
    }

    testWidgets('mevcut kategori seçili, kilit varsayılan açık; seçip kaydedince sonuç döner', (tester) async {
      final (fake, results) = await open(tester);

      expect(find.text('Şu anki kategori'), findsOneWidget);
      expect(find.text('Pasif — seçilemez'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('shop-category-lock'))).value, isTrue);

      // Pasif kategori seçilemez
      await tester.tap(find.byKey(const ValueKey('shop-category-c-old')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('shop-category-c-market')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('shop-category-note')), ' Yanlış kategori ');
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await _settle(tester);

      expect(fake.calls, ['shop-1:c-market:true:Yanlış kategori']);
      expect(results.single!.categoryName, 'Market');
      expect(find.text('Ana kategori'), findsNothing, reason: 'pencere kapandı');
    });

    testWidgets('kilitliyken açılırsa notu doldurur; kilidi kaldırmak kaydedilir', (tester) async {
      final (fake, _) = await open(tester, locked: true);
      expect(find.text('Eski not'), findsOneWidget);
      expect(find.textContaining('Şu an kilitli'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('shop-category-lock')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await _settle(tester);
      expect(fake.calls.single, startsWith('shop-1:c-food:false:'));
    });

    testWidgets('sunucu hatası pencerede gösterilir, pencere açık kalır', (tester) async {
      final (fake, results) = await open(tester);
      fake.failSave = const PostgrestException(message: 'x', hint: 'CATEGORY_INACTIVE');
      await tester.tap(find.byKey(const ValueKey('shop-category-c-market')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await _settle(tester);

      expect(find.textContaining('Bu kategori pasif'), findsOneWidget);
      expect(results, isEmpty);
    });
  });
}
