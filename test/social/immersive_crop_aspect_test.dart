import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cizreapp/features/profile/widgets/immersive_crop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 2.8 — oran seçenekli kırpma editörü (gönderi fotoğrafı) ve sabit
/// çerçeveli editör (profil/kapak): büyük çerçeve, fotoğrafın çerçeveyi
/// kaplaması, yakınlaştırma, döndür / aynala / sıfırla.

const _aspects = [
  ImmersiveCropAspect(label: 'Dikey', ratioLabel: '4:5', ratio: 0.8),
  ImmersiveCropAspect(label: 'Kare', ratioLabel: '1:1', ratio: 1),
  ImmersiveCropAspect(label: 'Yatay', ratioLabel: '4:3', ratio: 4 / 3),
];

/// Düz zeminli PNG; [square] verilirse ortasına o kenarda siyah bir kare
/// çizilir (çıktıda karenin kare kalması = görüntü gerilmedi). [leftHalfDark]
/// sol yarıyı siyah boyar (döndürme/aynalama yönünü okumak için).
Future<Uint8List> _png(int width, int height, {double square = 0, bool leftHalfDark = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  if (square > 0) {
    canvas.drawRect(
      Rect.fromCenter(center: Offset(width / 2, height / 2), width: square, height: square),
      Paint()..color = const Color(0xFF000000),
    );
  }
  if (leftHalfDark) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
      Paint()..color = const Color(0xFF000000),
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<(int, int)> _sizeOf(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final size = (image.width, image.height);
  image.dispose();
  return size;
}

/// Çıktının ortasından geçen satır ve sütundaki koyu piksel sayısı:
/// (genişlik, yükseklik) — ortadaki karenin çıktıdaki boyu.
Future<(int, int)> _darkExtent(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  bool dark(int x, int y) => rgba.getUint8((y * image.width + x) * 4) < 128;
  var w = 0;
  var h = 0;
  for (var x = 0; x < image.width; x++) {
    if (dark(x, image.height ~/ 2)) w++;
  }
  for (var y = 0; y < image.height; y++) {
    if (dark(image.width ~/ 2, y)) h++;
  }
  image.dispose();
  return (w, h);
}

/// Çıktıda (genişliğin [fx], yüksekliğin [fy] oranındaki) piksel koyu mu?
Future<bool> _darkAt(Uint8List bytes, double fx, double fy) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final x = (image.width * fx).floor().clamp(0, image.width - 1);
  final y = (image.height * fy).floor().clamp(0, image.height - 1);
  final dark = rgba.getUint8((y * image.width + x) * 4) < 128;
  image.dispose();
  return dark;
}

/// Gerçek (sahte saat dışı) asenkron işin — görsel çözme/kodlama — bitmesini
/// bekler, sonra kareyi ilerletir.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'asenkron görsel işi bitmedi');
}

void main() {
  late Uint8List landscape; // 400×300
  late Uint8List squareMarked; // 400×300, ortada 60×60 siyah kare
  late Uint8List cover; // 1600×900
  late Uint8List leftDark; // 300×300, sol yarısı siyah

  setUpAll(() async {
    landscape = await _png(400, 300);
    squareMarked = await _png(400, 300, square: 60);
    cover = await _png(1600, 900);
    leftDark = await _png(300, 300, leftHalfDark: true);
  });

  Future<void> host(WidgetTester tester, Future<void> Function(BuildContext) onOpen, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(onPressed: () => onOpen(context), child: const Text('aç')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sayfa geçişi
    // Fotoğraf çözülene kadar yalnız yükleniyor göstergesi var.
    await _settle(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
  }

  Future<void> confirm(WidgetTester tester, bool Function() done) async {
    await tester.tap(find.byTooltip('Onayla'));
    await tester.pump();
    await _settle(tester, done);
    await tester.pump(const Duration(milliseconds: 400)); // kapanış geçişi
  }

  testWidgets('oran çipleri görünür; seçilen oran ve kırpma birlikte döner', (tester) async {
    ImmersiveCropResult? result;
    var returned = false;
    await host(tester, (context) async {
      result = await showImmersiveAspectCropEditor(
        context,
        imageBytes: landscape,
        title: 'Fotoğrafı Kırp',
        aspects: _aspects,
        initialAspect: 0.8,
        footnote: 'Seçtiğin çerçeve gönderideki tüm fotoğraflara uygulanır',
      );
      returned = true;
    });

    expect(find.text('Fotoğrafı Kırp'), findsOneWidget);
    for (final label in ['Dikey', 'Kare', 'Yatay', '4:5', '1:1', '4:3']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Seçtiğin çerçeve gönderideki tüm fotoğraflara uygulanır'), findsOneWidget);

    // Gösterilen fotoğraf EZİLMEZ: 4:5 çerçeveyi (390×487.5) kaplamak için
    // 650×487.5 çizilir, ekrandan taşar. (Eskiden ekran genişliğine, 390
    // px'e sıkışıyor, kullanıcı çıktıdan farklı bir görüntü görüyordu.)
    expect(tester.getSize(find.byType(RawImage)), const Size(650, 487.5));

    await tester.tap(find.text('Kare'));
    await tester.pump();
    await confirm(tester, () => returned);

    expect(result, isNotNull);
    expect(result!.aspectRatio, 1);
    // 400×300 fotoğraf, kare çerçeve, en uzak yakınlaştırma: tam yükseklik.
    final size = await tester.runAsync(() => _sizeOf(result!.bytes));
    expect(size, (300, 300));
  });

  testWidgets('fotoğraf çerçeveye sığacak kadar küçültülebilir: yatay fotoğrafın tamamı kalır', (tester) async {
    ImmersiveCropResult? result;
    var returned = false;
    await host(tester, (context) async {
      result = await showImmersiveAspectCropEditor(
        context,
        imageBytes: landscape,
        title: 'Fotoğrafı Kırp',
        aspects: _aspects,
        initialAspect: 4 / 3,
      );
      returned = true;
    });

    await confirm(tester, () => returned);

    expect(result!.aspectRatio, closeTo(4 / 3, 1e-9));
    // Eski editörde fotoğraf EKRANI kaplamak zorundaydı; 390 px genişlikteki
    // çerçeveye fotoğrafın ancak üçte biri girerdi.
    final size = await tester.runAsync(() => _sizeOf(result!.bytes));
    expect(size, (400, 300));
  });

  testWidgets('kısa ekranda uzun çerçeve oranını korur (çıktı gerilmez)', (tester) async {
    ImmersiveCropResult? result;
    var returned = false;
    await host(
      tester,
      (context) async {
        result = await showImmersiveAspectCropEditor(
          context,
          imageBytes: squareMarked,
          title: 'Fotoğrafı Kırp',
          aspects: _aspects,
          initialAspect: 0.8,
        );
        returned = true;
      },
      // 4:5 çerçeve ekran genişliğinde 487 px olurdu; sınır 0.6 × 600 = 360.
      size: const Size(390, 600),
    );

    await confirm(tester, () => returned);

    final (w, h) = (await tester.runAsync(() => _sizeOf(result!.bytes)))!;
    expect(w / h, closeTo(0.8, 0.01));
    // Çerçeve oranını kaybetseydi (yalnız yükseklik kısılsaydı) seçilen alan
    // 4:5 çıktıya gerilerek sığdırılırdı: kare dikdörtgene dönerdi.
    final (squareW, squareH) = (await tester.runAsync(() => _darkExtent(result!.bytes)))!;
    expect(squareW, greaterThan(40));
    expect(squareH / squareW, closeTo(1, 0.05));
  });

  testWidgets('vazgeçince null döner', (tester) async {
    ImmersiveCropResult? result = ImmersiveCropResult(bytes: _empty, aspectRatio: 0);
    var returned = false;
    await host(tester, (context) async {
      result = await showImmersiveAspectCropEditor(
        context,
        imageBytes: landscape,
        title: 'Fotoğrafı Kırp',
        aspects: _aspects,
        initialAspect: 1,
      );
      returned = true;
    });

    await tester.tap(find.byTooltip('Vazgeç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(returned, isTrue);
    expect(result, isNull);
  });

  testWidgets('kapak 16:9: çip yok, fotoğraf çerçeveyi kaplar, 1280×720 PNG baytları döner', (tester) async {
    Uint8List? bytes;
    var returned = false;
    await host(tester, (context) async {
      bytes = await showImmersiveCropEditor(
        context,
        imageBytes: cover,
        shape: ImmersiveCropShape.rect,
        rectAspectRatio: 16 / 9,
        title: 'Kapak Fotoğrafı',
      );
      returned = true;
    });

    expect(find.text('Kare'), findsNothing);
    // Fotoğraf EKRANI değil çerçeveyi kaplar (eskiden 1500×844 çiziliyor,
    // 16:9 kapağın ancak dörtte biri çerçeveye giriyordu): çerçeve kenarlarda
    // 20'şer px pay bırakarak ekran genişliğinde, fotoğrafın tamamı içinde.
    final shown = tester.getSize(find.byType(RawImage));
    expect(shown.width, closeTo(390 - 40, 0.01));
    expect(shown.width / shown.height, closeTo(16 / 9, 0.001));
    await confirm(tester, () => returned);

    expect(bytes, isNotNull);
    final size = await tester.runAsync(() => _sizeOf(bytes!));
    expect(size, (1280, 720));
  });

  group('profil fotoğrafı (daire)', () {
    Future<void> openProfile(
      WidgetTester tester,
      Uint8List imageBytes,
      void Function(Uint8List?) onResult,
    ) {
      return host(tester, (context) async {
        onResult(await showImmersiveCropEditor(
          context,
          imageBytes: imageBytes,
          shape: ImmersiveCropShape.circle,
          title: 'Profil Fotoğrafı',
        ));
      });
    }

    RawImage shownImage(WidgetTester tester) => tester.widget<RawImage>(find.byType(RawImage));

    /// Döndür/aynala görseli asenkron yeniden üretir: gösterilen görsel
    /// değişene dek bekler.
    Future<void> tapTool(WidgetTester tester, String label) async {
      final before = shownImage(tester).image;
      await tester.tap(find.text(label));
      await tester.pump();
      await _settle(tester, () => !identical(shownImage(tester).image, before));
    }

    testWidgets('daire kenardan kenara; en uzakta fotoğrafın kısa kenarının tamamı kırpılır', (tester) async {
      Uint8List? bytes;
      var returned = false;
      await openProfile(tester, landscape, (b) {
        bytes = b;
        returned = true;
      });

      // Eskiden daire ekran genişliğinin %68'iydi ve fotoğraf EKRANI kaplamak
      // zorundaydı: 400×300 fotoğrafın ancak ~94 px'lik bir parçası seçilebiliyordu.
      final shown = tester.getSize(find.byType(RawImage));
      expect(shown.height, closeTo(390 - 40, 0.01));
      expect(find.byType(Slider), findsOneWidget);
      for (final label in ['Döndür', 'Aynala', 'Sıfırla']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      await confirm(tester, () => returned);
      // Kare çıktı, kaynaktan büyütülmez (eskiden her zaman 1024'e şişirilirdi).
      expect(await tester.runAsync(() => _sizeOf(bytes!)), (300, 300));
    });

    testWidgets('döndür: saat yönünün tersine döner (sol yarı alta iner)', (tester) async {
      Uint8List? bytes;
      var returned = false;
      await openProfile(tester, leftDark, (b) {
        bytes = b;
        returned = true;
      });

      await tapTool(tester, 'Döndür');
      await confirm(tester, () => returned);

      expect(await tester.runAsync(() => _darkAt(bytes!, 0.5, 0.85)), isTrue);
      expect(await tester.runAsync(() => _darkAt(bytes!, 0.5, 0.15)), isFalse);
    });

    testWidgets('aynala: sol yarı sağa geçer', (tester) async {
      Uint8List? bytes;
      var returned = false;
      await openProfile(tester, leftDark, (b) {
        bytes = b;
        returned = true;
      });

      await tapTool(tester, 'Aynala');
      await confirm(tester, () => returned);

      expect(await tester.runAsync(() => _darkAt(bytes!, 0.85, 0.5)), isTrue);
      expect(await tester.runAsync(() => _darkAt(bytes!, 0.15, 0.5)), isFalse);
    });

    testWidgets('döndürdükten sonra aynala ekrandaki görüntüyü yatayda çevirir', (tester) async {
      Uint8List? bytes;
      var returned = false;
      await openProfile(tester, leftDark, (b) {
        bytes = b;
        returned = true;
      });

      await tapTool(tester, 'Döndür'); // siyah alta indi
      await tapTool(tester, 'Aynala'); // yatay çevirme altı üste taşımaz
      await confirm(tester, () => returned);

      expect(await tester.runAsync(() => _darkAt(bytes!, 0.5, 0.85)), isTrue);
      expect(await tester.runAsync(() => _darkAt(bytes!, 0.5, 0.15)), isFalse);
    });

    testWidgets('sıfırla: döndürme ve yakınlaştırma geri alınır', (tester) async {
      Uint8List? bytes;
      var returned = false;
      await openProfile(tester, leftDark, (b) {
        bytes = b;
        returned = true;
      });

      await tapTool(tester, 'Döndür');
      await tester.tap(find.byTooltip('Yakınlaştır'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Sıfırla'));
      await tester.pump();
      await confirm(tester, () => returned);

      expect(await tester.runAsync(() => _sizeOf(bytes!)), (300, 300));
      expect(await tester.runAsync(() => _darkAt(bytes!, 0.15, 0.5)), isTrue);
      expect(await tester.runAsync(() => _darkAt(bytes!, 0.85, 0.5)), isFalse);
    });

    testWidgets('yakınlaştır düğmesi bir adımda 1.5 kat yaklaşır', (tester) async {
      Uint8List? bytes;
      var returned = false;
      await openProfile(tester, landscape, (b) {
        bytes = b;
        returned = true;
      });

      await tester.tap(find.byTooltip('Yakınlaştır'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // yakınlaştırma geçişi
      await confirm(tester, () => returned);

      expect(await tester.runAsync(() => _sizeOf(bytes!)), (200, 200));
    });

    testWidgets('çift dokunuş dokunulan noktaya 2.5 kat yakınlaştırır', (tester) async {
      Uint8List? bytes;
      var returned = false;
      await openProfile(tester, landscape, (b) {
        bytes = b;
        returned = true;
      });

      final center = tester.getCenter(find.byType(RawImage));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await confirm(tester, () => returned);

      expect(await tester.runAsync(() => _sizeOf(bytes!)), (120, 120));
    });
  });
}

final Uint8List _empty = Uint8List(0);
