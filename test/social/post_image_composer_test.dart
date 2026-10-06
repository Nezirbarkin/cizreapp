import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cizreapp/features/social/models/post_image_format.dart';
import 'package:cizreapp/features/social/widgets/post_image_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// Görev 2.8 — gönderi oluşturmadaki fotoğraf alanı: önizleme seçili
/// çerçevede (akıştaki görüntüyle aynı), çerçeve seçici, kırpma düğmesi,
/// küçük resim şeridi (seç / kaldır / ekle).

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 40, 30), Paint()..color = color);
  final image = await recorder.endRecording().toImage(40, 30);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _Harness extends StatefulWidget {
  const _Harness({required this.images, required this.log, this.enabled = true});

  final List<PostDraftImage> images;
  final List<String> log;
  final bool enabled;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  PostImageFormat format = PostImageFormat.portrait;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0E1116),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PostImageComposer(
            images: widget.images,
            format: format,
            enabled: widget.enabled,
            onFormatChanged: (f) {
              widget.log.add('format:${f.name}');
              setState(() => format = f);
            },
            onCrop: (i) => widget.log.add('crop:$i'),
            onRemove: (i) {
              widget.log.add('remove:$i');
              setState(() => widget.images.removeAt(i));
            },
            onAdd: () => widget.log.add('add'),
            caption: const TextField(decoration: InputDecoration(hintText: 'Bir açıklama ekle...')),
          ),
        ),
      ),
    );
  }
}

void main() {
  late List<Uint8List> pngs;

  setUpAll(() async {
    pngs = [
      await _png(const Color(0xFFE53935)),
      await _png(const Color(0xFF43A047)),
      await _png(const Color(0xFF1E88E5)),
    ];
  });

  List<PostDraftImage> drafts(int n) => [
    for (var i = 0; i < n; i++)
      PostDraftImage(file: XFile.fromData(pngs[i], name: 'f$i.png'), bytes: pngs[i]),
  ];

  Future<List<String>> pump(WidgetTester tester, List<PostDraftImage> images, {bool enabled = true}) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final log = <String>[];
    await tester.pumpWidget(_Harness(images: images, log: log, enabled: enabled));
    await tester.pumpAndSettle();
    return log;
  }

  Finder previewFrame() => find.ancestor(
    of: find.byKey(const ValueKey('post-image-preview')),
    matching: find.byType(AspectRatio),
  );

  testWidgets('önizleme seçili çerçevede; çerçeve değişince önizleme de değişir', (tester) async {
    final log = await pump(tester, drafts(1));

    expect(tester.widget<AspectRatio>(previewFrame()).aspectRatio, 0.8);
    // 390 − 2×16 kenar − 2×12 kart içi − 2×1 kenarlık = 332 px → 4:5 = 415 px
    expect(tester.getSize(previewFrame()), const Size(332, 415));
    for (final label in ['Dikey', 'Kare', 'Yatay', '4:5', '1:1', '4:3']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Yatay'));
    await tester.pumpAndSettle();
    expect(log, ['format:landscape']);
    expect(tester.getSize(previewFrame()).height, closeTo(332 * 3 / 4, 0.01));

    // Seçili çerçeveye tekrar dokunmak bir şey yapmaz.
    await tester.tap(find.text('Yatay'));
    await tester.pumpAndSettle();
    expect(log, ['format:landscape']);

    // Tek fotoğrafta sayfa göstergesi yok; açıklama alanı kartın içinde.
    expect(find.text('1/1'), findsNothing);
    expect(find.text('Bir açıklama ekle...'), findsOneWidget);
  });

  testWidgets('küçük resme dokununca önizleme o fotoğrafa geçer; Kırp onu ister', (tester) async {
    final images = drafts(3);
    final log = await pump(tester, images);

    expect(find.text('1/3'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(ListView), matching: find.byKey(ObjectKey(images[1]))),
    );
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Fotoğrafı kırp'));
    await tester.pump();
    expect(log, ['crop:1']);
  });

  testWidgets('kaldırınca sıra listenin içinde kalır; + ekler', (tester) async {
    final images = drafts(3);
    final log = await pump(tester, images);

    // Son fotoğrafı göster, sonra onu kaldır: gösterilen sıra 2/2'ye iner.
    await tester.drag(find.byKey(const ValueKey('post-image-preview')), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('post-image-preview')), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);

    await tester.tap(find.byTooltip('Fotoğrafı kaldır').at(2));
    await tester.pumpAndSettle();
    expect(log, ['remove:2']);
    expect(images, hasLength(2));
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Fotoğraf ekle'));
    await tester.pump();
    expect(log, ['remove:2', 'add']);
  });

  testWidgets('elle kırpılan fotoğraf "Kırpıldı"; çerçeve değişince kırpma geçersiz', (tester) async {
    final images = drafts(1)..first.setCrop(pngs[2], 0.8);
    await pump(tester, images);

    expect(find.text('Kırpıldı'), findsOneWidget);
    expect(find.byIcon(Icons.crop), findsOneWidget); // küçük resimdeki rozet

    await tester.tap(find.text('Kare'));
    await tester.pumpAndSettle();
    expect(find.text('Kırpıldı'), findsNothing);
    expect(find.text('Kırp'), findsOneWidget);
    // Önizleme artık orijinali gösteriyor (kırpma 4:5 içindi).
    final preview = tester.widget<Image>(find.byType(Image).first);
    expect(((preview.image as ResizeImage).imageProvider as MemoryImage).bytes, same(pngs[0]));
  });

  testWidgets('paylaşım sürerken düğmeler kapalı', (tester) async {
    final log = await pump(tester, drafts(2), enabled: false);

    await tester.tap(find.bySemanticsLabel('Fotoğrafı kırp'));
    await tester.tap(find.text('Kare'));
    await tester.tap(find.byTooltip('Fotoğrafı kaldır').first);
    await tester.tap(find.bySemanticsLabel('Fotoğraf ekle'));
    await tester.pumpAndSettle();
    expect(log, isEmpty);
  });
}
