import 'package:cizreapp/features/social/widgets/instagram_story_creator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../helpers/test_fonts.dart';

/// Hikaye Oluştur › "Canlı": yalnız yayın izni varken görünür, dokununca
/// canlı yayın başlatılır; 5 seçenek dar telefonda taşmaz.
void main() {
  setUpAll(loadTestFonts);

  Future<void> open(
    WidgetTester tester, {
    VoidCallback? onGoLive,
    Future<bool> Function()? liveAvailable,
    Size size = const Size(360, 780),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: InstagramStoryCreator(
              imagePicker: ImagePicker(),
              onMediaSelected: (_, _, _) {},
              onTextStory: (_, _, _) {},
              onGoLive: onGoLive,
              liveAvailable: liveAvailable,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('izin varsa "Canlı" görünür ve dokununca yayın başlar', (tester) async {
    var started = 0;
    await open(tester, onGoLive: () => started++, liveAvailable: () async => true);
    expect(find.text('Canlı'), findsOneWidget);
    expect(find.text('Metin'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '5 seçenek taşmaz');
    await tester.tap(find.byKey(const ValueKey('story-go-live')));
    expect(started, 1);
  });

  testWidgets('izin yoksa ya da geri çağrı verilmezse "Canlı" yok', (tester) async {
    await open(tester, onGoLive: () {}, liveAvailable: () async => false);
    expect(find.text('Canlı'), findsNothing);
    await open(tester);
    expect(find.text('Canlı'), findsNothing);
  });
}
