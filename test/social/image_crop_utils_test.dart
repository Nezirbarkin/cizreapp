import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cizreapp/core/utils/image_crop_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 2.8 — kırpma yardımcıları. Hesaplar saf; çizim/çözme gerçek
/// piksellerle doğrulanır (dart:ui test motorunda çalışır).

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _blue = Color(0xFF0000FF);

/// [width]×[height] PNG: kenarlarda 50 px kırmızı/mavi şerit, ortası yeşil.
/// Yatay görselde şeritler solda/sağda, dikeyde üstte/altta.
Future<Uint8List> _stripedPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final w = width.toDouble();
  final h = height.toDouble();
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = _green);
  if (width >= height) {
    canvas.drawRect(Rect.fromLTWH(0, 0, 50, h), Paint()..color = _red);
    canvas.drawRect(Rect.fromLTWH(w - 50, 0, 50, h), Paint()..color = _blue);
  } else {
    canvas.drawRect(Rect.fromLTWH(0, 0, w, 50), Paint()..color = _red);
    canvas.drawRect(Rect.fromLTWH(0, h - 50, w, 50), Paint()..color = _blue);
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _Decoded {
  _Decoded(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final ByteData rgba;

  Color pixel(int x, int y) {
    final o = (y * width + x) * 4;
    return Color.fromARGB(rgba.getUint8(o + 3), rgba.getUint8(o), rgba.getUint8(o + 1), rgba.getUint8(o + 2));
  }
}

Future<_Decoded> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final decoded = _Decoded(image.width, image.height, rgba!);
  image.dispose();
  return decoded;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('centerCropRect', () {
    test('geniş görsel iki yandan, uzun görsel üst/alttan kesilir', () {
      expect(centerCropRect(const Size(400, 300), 1), const Rect.fromLTWH(50, 0, 300, 300));
      expect(centerCropRect(const Size(300, 400), 1), const Rect.fromLTWH(0, 50, 300, 300));
      // 9:16 ekran görüntüsü → 4:5
      expect(centerCropRect(const Size(1080, 1920), 0.8), const Rect.fromLTWH(0, 285, 1080, 1350));
      // kare → 4:3
      expect(centerCropRect(const Size(1000, 1000), 4 / 3), const Rect.fromLTWH(0, 125, 1000, 750));
    });

    test('geçersiz girdi boş bölge', () {
      expect(centerCropRect(Size.zero, 1), Rect.zero);
      expect(centerCropRect(const Size(100, 100), 0), Rect.zero);
    });
  });

  group('cropOutputSize', () {
    test('genişlik 1080\'i ve kaynağın kendi çözünürlüğünü aşmaz; oran korunur', () {
      expect(cropOutputSize(const Rect.fromLTWH(0, 0, 2000, 2500), 0.8, maxWidth: 1080), (1080, 1350));
      expect(cropOutputSize(const Rect.fromLTWH(0, 0, 500, 625), 0.8, maxWidth: 1080), (500, 625));
      expect(cropOutputSize(const Rect.fromLTWH(0, 0, 1200, 900), 4 / 3, maxWidth: 1080), (1080, 810));
      expect(cropOutputSize(const Rect.fromLTWH(0, 0, 0.2, 0.2), 1, maxWidth: 1080), (1, 1));
    });
  });

  group('centerCropToAspect (gerçek pikseller)', () {
    test('yatay görselden kare: kenar şeritleri atılır, orta kalır', () async {
      final out = await _decode((await centerCropToAspect(await _stripedPng(400, 300), 1))!);
      expect((out.width, out.height), (300, 300));
      for (final (x, y) in [(0, 0), (0, 150), (299, 150), (150, 150), (299, 299)]) {
        expect(out.pixel(x, y), _green, reason: '($x,$y)');
      }
    });

    test('dikey görselden 4:3: üst/alt şeritler atılır', () async {
      final out = await _decode((await centerCropToAspect(await _stripedPng(300, 400), 4 / 3))!);
      expect((out.width, out.height), (300, 225));
      expect(out.pixel(150, 0), _green);
      expect(out.pixel(150, 224), _green);
    });

    test('büyük görsel 1080 genişliğe küçültülür', () async {
      final out = await _decode((await centerCropToAspect(await _stripedPng(1600, 2400), 0.8))!);
      expect((out.width, out.height), (1080, 1350));
    });

    test('görsel zaten bu orandaysa null (yeniden kodlanmaz)', () async {
      expect(await centerCropToAspect(await _stripedPng(400, 400), 1), isNull);
      expect(await centerCropToAspect(await _stripedPng(400, 300), 4 / 3), isNull);
    });

    test('çözülemeyen bayt istisna fırlatır (çağıran orijinale düşer)', () async {
      await expectLater(centerCropToAspect(Uint8List.fromList([1, 2, 3, 4]), 1), throwsA(anything));
    });
  });

  group('readImageAspectRatio', () {
    test('oranı okur; çözülemezse null', () async {
      expect(await readImageAspectRatio(await _stripedPng(400, 300)), closeTo(4 / 3, 0.01));
      expect(await readImageAspectRatio(await _stripedPng(300, 400)), closeTo(0.75, 0.01));
      expect(await readImageAspectRatio(Uint8List.fromList([0, 1, 2])), isNull);
    });
  });

  test('renderImageRegionPng: saydam alan beyaz zemine oturur', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint()..color = _blue);
    final source = await recorder.endRecording().toImage(20, 20); // sağ/alt yarısı saydam
    final out = await _decode(
      await renderImageRegionPng(source, const Rect.fromLTWH(0, 0, 20, 20), 20, 20),
    );
    source.dispose();
    expect(out.pixel(2, 2), _blue);
    expect(out.pixel(15, 15), const Color(0xFFFFFFFF));
  });
}
