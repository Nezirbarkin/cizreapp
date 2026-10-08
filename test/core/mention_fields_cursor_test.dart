import 'package:cizreapp/core/widgets/mention_autocomplete_field.dart';
import 'package:cizreapp/core/widgets/mention_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Admin > Loglar > Son Hatalar: "RangeError: Invalid value: Not in inclusive
/// range 0..N: -1" (core/widgets/mention_autocomplete_field.dart).
///
/// `controller.text = ...` ve `controller.clear()` seçimi `collapsed(-1)`e
/// düşürür; alan odakta değilken imleç yoktur. İmleç konumunu olduğu gibi
/// `lastIndexOf('@', cursorPos)` / `substring` içine veren dinleyici bu durumda
/// RangeError fırlatıyordu. Dinleyici ChangeNotifier içinden çağrıldığı için
/// hata kullanıcıya görünmez, yalnız "Son Hatalar"a düşerdi.
void main() {
  group('MentionAutocompleteField', () {
    Future<TextEditingController> pumpField(WidgetTester tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MentionAutocompleteField(controller: controller)),
        ),
      );
      return controller;
    }

    testWidgets('imleçsiz metin atamasında (selection = -1) hata vermez', (
      tester,
    ) async {
      final controller = await pumpField(tester);

      controller.text = 'merhaba @ali';
      await tester.pump();

      expect(controller.selection.baseOffset, -1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clear() hata vermez', (tester) async {
      final controller = await pumpField(tester);

      controller.text = 'metin';
      controller.clear();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('imleç en başta iken @ solda değildir, hata vermez', (
      tester,
    ) async {
      final controller = await pumpField(tester);

      controller.value = const TextEditingValue(
        text: '@ali',
        selection: TextSelection.collapsed(offset: 0),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('imleç yeni yazılan @ işaretinin hemen sağında: sorgu boş, '
        'hata yok', (tester) async {
      final controller = await pumpField(tester);

      controller.value = const TextEditingValue(
        text: 'selam @',
        selection: TextSelection.collapsed(offset: 7),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('MentionAutocomplete (mention_text.dart)', () {
    testWidgets('imleçsiz metin atamasında ve imleç 0 iken hata vermez', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MentionAutocomplete(controller: controller)),
        ),
      );

      controller.text = '@al';
      await tester.pump();
      expect(tester.takeException(), isNull);

      controller.value = const TextEditingValue(
        text: '@al',
        selection: TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
