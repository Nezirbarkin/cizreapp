import 'dart:async';

import 'package:cizreapp/features/leaderboard/leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Future<LeaderboardVisibility> Function() loader,
  required Future<LeaderboardVisibility> Function(bool) saver,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LeaderboardVisibilityTile(loader: loader, saver: saver),
      ),
    ),
  );
  await tester.pump();
}

Finder get _switch =>
    find.byKey(const ValueKey('leaderboard-self-hide-switch'));
Finder get _adminNote =>
    find.byKey(const ValueKey('leaderboard-admin-hidden-note'));

bool _switchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(_switch).value;

void main() {
  testWidgets('kullanıcı kendini gizlediyse anahtar açık gelir', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => const LeaderboardVisibility(selfHidden: true),
      saver: (h) async => LeaderboardVisibility(selfHidden: h),
    );
    expect(_switchValue(tester), isTrue);
    expect(_adminNote, findsNothing);
  });

  testWidgets('yüklenirken anahtar devre dışı', (tester) async {
    final gate = Completer<LeaderboardVisibility>();
    await _pump(
      tester,
      loader: () => gate.future,
      saver: (h) async => LeaderboardVisibility(selfHidden: h),
    );
    expect(tester.widget<SwitchListTile>(_switch).onChanged, isNull);
    gate.complete(const LeaderboardVisibility());
    await tester.pump();
    await tester.pump();
    expect(tester.widget<SwitchListTile>(_switch).onChanged, isNotNull);
  });

  testWidgets('anahtar kaydeder ve sunucunun döndürdüğü durumu gösterir', (
    tester,
  ) async {
    bool? saved;
    await _pump(
      tester,
      loader: () async => const LeaderboardVisibility(),
      saver: (h) async {
        saved = h;
        return LeaderboardVisibility(selfHidden: h);
      },
    );
    expect(_switchValue(tester), isFalse);

    await tester.tap(_switch);
    await tester.pump();
    await tester.pump();

    expect(saved, isTrue);
    expect(_switchValue(tester), isTrue);
    expect(
      find.text('Liderler tablosunda artık görünmüyorsun'),
      findsOneWidget,
    );
  });

  testWidgets('kaydedilemezse eski duruma döner ve uyarır', (tester) async {
    await _pump(
      tester,
      loader: () async => const LeaderboardVisibility(),
      saver: (h) async => throw StateError('ağ yok'),
    );
    await tester.tap(_switch);
    await tester.pump();
    await tester.pump();

    expect(_switchValue(tester), isFalse);
    expect(find.text('Kaydedilemedi, tekrar dene'), findsOneWidget);
  });

  testWidgets('admin gizlediyse uyarı görünür; anahtar yalnız kendi tercihi', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: () async => const LeaderboardVisibility(adminHidden: true),
      saver: (h) async =>
          LeaderboardVisibility(selfHidden: h, adminHidden: true),
    );
    expect(_adminNote, findsOneWidget);
    // Anahtar kendi tercihini gösterir: admin gizlemesi onu açık yapmaz.
    expect(_switchValue(tester), isFalse);

    // Kullanıcı kendini de gizlerse admin bayrağı uyarısı kaybolmaz.
    await tester.tap(_switch);
    await tester.pump();
    await tester.pump();
    expect(_switchValue(tester), isTrue);
    expect(_adminNote, findsOneWidget);
  });
}
