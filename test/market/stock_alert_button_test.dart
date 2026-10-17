import 'package:cizreapp/features/market/services/stock_alert_service.dart';
import 'package:cizreapp/features/market/widgets/stock_alert_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStockAlertService extends StockAlertService {
  _FakeStockAlertService({this.signedIn = true, this.initiallySubscribed = false})
      : super();

  final bool signedIn;
  final bool initiallySubscribed;
  final calls = <String>[];
  late bool _subscribed = initiallySubscribed;

  @override
  bool get isSignedIn => signedIn;

  @override
  Future<bool> isSubscribed(String productId) async => _subscribed;

  @override
  Future<void> subscribe(String productId) async {
    calls.add('subscribe:$productId');
    _subscribed = true;
  }

  @override
  Future<void> unsubscribe(String productId) async {
    calls.add('unsubscribe:$productId');
    _subscribed = false;
  }
}

void main() {
  Future<void> pump(WidgetTester tester, StockAlertService service) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StockAlertButton(productId: 'p1', service: service),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('abone değilken düğme abone eder ve şeride döner', (tester) async {
    final service = _FakeStockAlertService();
    await pump(tester, service);

    expect(find.text('Stoğa gelince haber ver'), findsOneWidget);
    await tester.tap(find.text('Stoğa gelince haber ver'));
    await tester.pump();
    await tester.pump();

    expect(service.calls, ['subscribe:p1']);
    expect(find.text('Stoğa gelince bildirim alacaksınız'), findsOneWidget);
    expect(find.text('🔔 Ürün stoğa gelince bildirim alacaksınız'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // SnackBar süresi
  });

  testWidgets('abonelik varsa şerit görünür, kapat iptal eder', (tester) async {
    final service = _FakeStockAlertService(initiallySubscribed: true);
    await pump(tester, service);

    expect(find.text('Stoğa gelince bildirim alacaksınız'), findsOneWidget);
    await tester.tap(find.byTooltip('Stok bildirimini kapat'));
    await tester.pump();
    await tester.pump();

    expect(service.calls, ['unsubscribe:p1']);
    expect(find.text('Stoğa gelince haber ver'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // SnackBar süresi
  });

  testWidgets('giriş yapılmamışsa servis çağrılmaz, uyarı gösterilir',
      (tester) async {
    final service = _FakeStockAlertService(signedIn: false);
    await pump(tester, service);

    await tester.tap(find.text('Stoğa gelince haber ver'));
    await tester.pump();

    expect(service.calls, isEmpty);
    expect(find.text('Stok bildirimi için giriş yapmalısınız'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // SnackBar süresi
  });
}
