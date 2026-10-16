import 'dart:io';
import 'dart:ui' as ui;

import 'package:cizreapp/core/models/order_model.dart';
import 'package:cizreapp/features/market/widgets/return_request_sheet.dart';
import 'package:cizreapp/features/shop/services/return_request_service.dart';
import 'package:cizreapp/features/shop/widgets/return_request_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// 2 × 20 (A) + 1 × 30 (B) = 70; teslimat 5, indirim 7 → toplam 68.
/// Mal için ödenen 63 → oran 0,9 (DB testindeki fikstürle aynı).
Order _order() => Order.fromJson({
      'id': 'order-1',
      'user_id': 'u1',
      'shop_id': 's1',
      'status': 'delivered',
      'payment_method': 'balance',
      'payment_status': 'paid',
      'subtotal': 70,
      'delivery_fee': 5,
      'discount': 7,
      'total': 68,
      'delivered_at': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'order_items': [
        {
          'id': 'item-a',
          'order_id': 'order-1',
          'product_id': 'p1',
          'product_name': 'Domates (1 kg)',
          'price': 20,
          'quantity': 2,
        },
        {
          'id': 'item-b',
          'order_id': 'order-1',
          'product_id': 'p2',
          'product_name': 'Zeytinyağı 1 L',
          'price': 30,
          'quantity': 1,
        },
      ],
    });

ReturnRequest _request({
  required ReturnRequestStatus status,
  required List<(String, int, double)> items,
  double refund = 0,
  double sellerDebit = 0,
  String scope = 'partial',
  String? adminResponse,
}) {
  return ReturnRequest.fromJson({
    'id': 'r-${status.name}',
    'order_id': 'order-1',
    'user_id': 'u1',
    'shop_id': 's1',
    'reason': 'Ürün hasarlı geldi',
    'status': status.name,
    'return_scope': scope,
    'refund_amount': refund,
    'seller_debit_amount': sellerDebit,
    'admin_response': adminResponse,
    'created_at': '2026-10-16T09:30:00Z',
    'order_number': '1042',
    'shop_name': 'Cizre Manav',
    'customer_name': 'Ayşe Yılmaz',
    'items': [
      for (final (id, qty, line) in items)
        {
          'id': 'ri-$id',
          'order_item_id': id,
          'product_name': id == 'item-a' ? 'Domates (1 kg)' : 'Zeytinyağı 1 L',
          'quantity': qty,
          'unit_price': line / qty,
          'line_total': line,
        },
    ],
  });
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final dir = Directory('build/test_screens')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!);
}

void main() {
  setUpAll(() async => loadTestFonts());

  group('iade tutarı (DB kuralıyla aynı)', () {
    test('kalan adetler: reddedilen/geri çekilen talep adet ayırmaz', () {
      final order = _order();
      final remaining = remainingReturnQuantities(order, [
        _request(status: ReturnRequestStatus.completed, items: [('item-a', 1, 20)]),
        _request(status: ReturnRequestStatus.rejected, items: [('item-b', 1, 30)]),
        _request(status: ReturnRequestStatus.cancelled, items: [('item-a', 1, 20)]),
      ]);
      expect(remaining, {'item-a': 1, 'item-b': 1});
    });

    test('kısmi iade indirimi orantılı düşer, son iade kalanın tamamını alır', () {
      final order = _order();
      final all = remainingReturnQuantities(order, const []);
      // A × 1 → 20 × 0,9 = 18
      expect(
        estimateReturnRefund(
          order: order,
          remaining: all,
          selected: {'item-a': 1},
          previouslyRefunded: 0,
        ),
        18.0,
      );
      // Tümü tek talepte → 63 (teslimat ücreti iade edilmez)
      expect(
        estimateReturnRefund(
          order: order,
          remaining: all,
          selected: Map.of(all),
          previouslyRefunded: 0,
        ),
        63.0,
      );
      // 18 iade edildikten sonra kalanlar → 63 − 18 = 45
      final rest = remainingReturnQuantities(order, [
        _request(status: ReturnRequestStatus.approved, items: [('item-a', 1, 20)], refund: 18),
      ]);
      expect(
        estimateReturnRefund(
          order: order,
          remaining: rest,
          selected: Map.of(rest),
          previouslyRefunded: 18,
        ),
        45.0,
      );
    });
  });

  group('iade alt sayfası', () {
    Future<ReturnSheetResult?> pumpSheet(
      WidgetTester tester,
      GlobalKey shotKey,
      Future<void> Function() interact, {
      List<ReturnRequest> existing = const [],
    }) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      ReturnSheetResult? result;
      var popped = false;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
        builder: (context, child) => RepaintBoundary(key: shotKey, child: child),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showReturnRequestSheet(
                    context,
                    order: _order(),
                    existingRequests: existing,
                  );
                  popped = true;
                },
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await interact();
      expect(popped || result == null, isTrue);
      return result;
    }

    testWidgets('tümünü iade et: ürün listesi null döner', (tester) async {
      final key = GlobalKey();
      final result = await pumpSheet(tester, key, () async {
        expect(find.text('₺63.00'), findsOneWidget);
        await _shot(tester, key, 'return_sheet_all');
        await tester.enterText(find.byType(TextField), 'Ürünler bozuk geldi');
        await tester.tap(find.text('Talebi Gönder'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      });
      expect(result, isNotNull);
      expect(result!.items, isNull);
      expect(result.reason, 'Ürünler bozuk geldi');
    });

    testWidgets('ürün seç: seçim + adet, sebepsiz gönderilmez', (tester) async {
      final key = GlobalKey();
      final result = await pumpSheet(tester, key, () async {
        await tester.tap(find.text('Ürün Seç'));
        await tester.pump();
        expect(find.text('₺0.00'), findsOneWidget);

        // Hiçbir şey seçmeden gönder → satır içi hata (alt sayfa açık kalır)
        await tester.tap(find.text('Talebi Gönder'));
        await tester.pump();
        expect(find.text('İade etmek istediğiniz ürünleri seçin'), findsOneWidget);

        // A'yı seç (kalan 2 adetle gelir), bir azalt → 1 adet = 18 ₺
        await tester.tap(find.byType(Checkbox).first);
        await tester.pump();
        await tester.tap(find.byTooltip('Azalt'));
        await tester.pump();
        expect(find.text('₺18.00'), findsOneWidget);

        await tester.tap(find.text('Talebi Gönder'));
        await tester.pump();
        expect(find.text('İade sebebi en az 3 karakter olmalı'), findsOneWidget);

        await tester.tap(find.text('Ürün hasarlı geldi'));
        await tester.pump();
        await _shot(tester, key, 'return_sheet_selected');
        await tester.tap(find.text('Talebi Gönder'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      });
      expect(result, isNotNull);
      expect(result!.items, hasLength(1));
      expect(result.items!.single.orderItemId, 'item-a');
      expect(result.items!.single.quantity, 1);
      expect(result.reason, 'Ürün hasarlı geldi');
    });
  });

  testWidgets('kart: kuryeli satıcının nakit iadesi bakiyeye değil satıcıya yazılır',
      (tester) async {
    final json = {
      'id': 'r-cash',
      'order_id': 'order-1',
      'user_id': 'u1',
      'shop_id': 's1',
      'reason': 'A bozuk geldi',
      'status': 'approved',
      'return_scope': 'partial',
      'refund_method': 'seller_cash',
      'refund_amount': 60,
      'seller_debit_amount': 0,
      'commission_refund_amount': 6,
      'created_at': '2026-10-16T09:30:00Z',
      'items': const [],
    };
    final request = ReturnRequest.fromJson(json);
    expect(request.isSellerCashRefund, isTrue);

    for (final viewer in ReturnCardViewer.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReturnRequestCard(request: request, viewer: viewer),
          ),
        ),
      ));
      expect(find.text('Satıcı nakit iade eder'), findsOneWidget);
      expect(find.textContaining('bakiyenize eklendi'), findsNothing);
      expect(
        find.textContaining('omisyon borcu'),
        viewer == ReturnCardViewer.customer ? findsNothing : findsOneWidget,
      );
    }
  });

  testWidgets('kart: müşteri/satıcı/yönetici görünümleri', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: RepaintBoundary(
          key: key,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ReturnRequestCard(
                request: _request(
                  status: ReturnRequestStatus.pending,
                  items: [('item-a', 1, 20)],
                  refund: 18,
                ),
                viewer: ReturnCardViewer.customer,
                actions: [
                  OutlinedButton(onPressed: () {}, child: const Text('Talebi Geri Çek')),
                ],
              ),
              ReturnRequestCard(
                request: _request(
                  status: ReturnRequestStatus.approved,
                  items: [('item-a', 1, 20), ('item-b', 1, 30)],
                  refund: 45,
                  sellerDebit: 45,
                ),
                viewer: ReturnCardViewer.seller,
                actions: [
                  ElevatedButton(onPressed: () {}, child: const Text('Ürünleri Teslim Aldım')),
                ],
              ),
              ReturnRequestCard(
                request: _request(
                  status: ReturnRequestStatus.rejected,
                  items: [('item-a', 2, 40), ('item-b', 1, 30)],
                  refund: 63,
                  scope: 'full',
                  adminResponse: 'Ürün kullanılmış',
                ),
                viewer: ReturnCardViewer.admin,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('İncelemede'), findsOneWidget);
    expect(find.text('Hesabınızdan düşülen: ₺45.00'), findsOneWidget);
    expect(find.text('Ayşe Yılmaz · Cizre Manav'), findsOneWidget);
    expect(find.text('Tüm sipariş iadesi · 3 ürün'), findsOneWidget);
    // Müşteri kartı satıcı payını göstermez
    expect(find.textContaining('Satıcıdan düşülen'), findsNothing);
    await _shot(tester, key, 'return_cards');
  });
}
