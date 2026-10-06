import 'dart:io';

import 'package:cizreapp/core/widgets/app_version_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.8 — ayarlar/çıkış menüsünde "Çıkış Yap"ın altında "CizreApp vX.X.X".
void main() {
  setUpAll(loadTestFonts);

  testWidgets('verilen sürümü "CizreApp vX.X.X" biçiminde gösterir', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AppVersionLabel(loader: () async => '1.3.2'))),
    );
    await tester.pump();
    expect(find.text('CizreApp v1.3.2'), findsOneWidget);
  });

  testWidgets('varsayılan: sürüm paket bilgisinden (package_info_plus) okunur', (tester) async {
    AppVersionLabel.resetCache();
    addTearDown(AppVersionLabel.resetCache);
    PackageInfo.setMockInitialValues(
      appName: 'CizreApp',
      packageName: 'com.cizreapp.com',
      version: '9.8.7',
      buildNumber: '41',
      buildSignature: '',
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppVersionLabel())));
    await tester.pump();
    await tester.pump();
    expect(find.text('CizreApp v9.8.7'), findsOneWidget, reason: 'derleme numarası (+41) gösterilmez');
  });

  test('sürüm okunamazsa satır boş kalır ama yer tutar; biçim yardımcısı', () {
    expect(AppVersionLabel.format(' 1.3.2 '), 'CizreApp v1.3.2');
  });

  test('iki ayar menüsünde de "Çıkış Yap" düğmesinin hemen altında', () {
    for (final path in ['lib/core/widgets/settings_sidebar.dart', 'lib/core/widgets/settings_dialog.dart']) {
      final src = File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final auth = src.indexOf('_buildAuthButton(\n');
      final label = src.indexOf('const AppVersionLabel()');
      expect(auth, greaterThan(0), reason: path);
      expect(label, greaterThan(auth), reason: '$path: sürüm çıkış düğmesinin altında olmalı');
      final between = src.substring(auth, label);
      expect(between.contains('_buildMenuItem('), isFalse, reason: '$path: arada başka menü öğesi olmamalı');
    }
  });
}
