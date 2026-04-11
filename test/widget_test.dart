// CizreApp Widget Testleri
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/main.dart';

void main() {
  testWidgets('SplashScreen yükleniyor', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const CizreApp(supabaseInitialized: true));

    // Verify that splash screen elements are present
    expect(find.text('CizreApp'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.store), findsOneWidget);
  });

  testWidgets('Uygulama tema doğru', (WidgetTester tester) async {
    await tester.pumpWidget(const CizreApp(supabaseInitialized: true));

    // Verify theme is green
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.theme?.primaryColor, const Color(0xFF00C853));
  });
}
