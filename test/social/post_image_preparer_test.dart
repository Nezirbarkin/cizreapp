import 'dart:typed_data';

import 'package:cizreapp/core/utils/image_type_sniffer.dart';
import 'package:cizreapp/features/social/models/post_image_format.dart';
import 'package:cizreapp/features/social/services/post_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// Görev 2.8 — yüklenen fotoğraf önizlemeyle aynıdır: elle kırpıldıysa o,
/// değilse ortası; ardından JPEG. Hiçbir adım paylaşımı engellemez.

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1]);
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 2]);
final _webp = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
final _compressed = Uint8List.fromList([0xFF, 0xD8, 0xFF, 7, 7]);

PostDraftImage _draft(Uint8List bytes, {String name = 'foto.jpg'}) =>
    PostDraftImage(file: XFile.fromData(bytes, name: name), bytes: bytes);

void main() {
  late List<(Uint8List, double)> cropCalls;
  late List<Uint8List> compressCalls;

  setUp(() {
    cropCalls = [];
    compressCalls = [];
  });

  PostImagePreparer preparer({
    Future<Uint8List?> Function(Uint8List, double)? centerCrop,
    Future<Uint8List?> Function(Uint8List)? compress,
  }) => PostImagePreparer(
    centerCrop: (bytes, aspect) {
      cropCalls.add((bytes, aspect));
      return centerCrop != null ? centerCrop(bytes, aspect) : Future.value(_png);
    },
    compress: (bytes) {
      compressCalls.add(bytes);
      return compress != null ? compress(bytes) : Future.value(_compressed);
    },
  );

  test('bu çerçeveye elle kırpılmış fotoğraf: kırpma kullanılır, ortadan kırpılmaz', () async {
    final cropped = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 5]);
    final draft = _draft(_jpeg)..setCrop(cropped, 0.8);

    final out = await preparer().prepare(draft, 0.8);

    expect(cropCalls, isEmpty);
    expect(compressCalls.single, same(cropped));
    expect((out.bytes, out.extension, out.contentType), (_compressed, 'jpg', 'image/jpeg'));
  });

  test('başka çerçeveye kırpılmışsa geçersiz: orijinalin ortası yeni çerçeveye', () async {
    final draft = _draft(_jpeg)..setCrop(_png, 0.8);

    await preparer().prepare(draft, 1);

    expect(cropCalls.single.$1, same(_jpeg));
    expect(cropCalls.single.$2, 1);
    expect(compressCalls.single, same(_png));
  });

  test('zaten çerçeve oranındaki fotoğraf yeniden kodlanmaz (orijinal sıkıştırılır)', () async {
    await preparer(centerCrop: (_, __) async => null).prepare(_draft(_jpeg), 4 / 3);
    expect(compressCalls.single, same(_jpeg));
  });

  test('çözülemeyen fotoğraf kırpılmadan yüklenir, paylaşım engellenmez', () async {
    final out = await preparer(
      centerCrop: (_, __) async => throw Exception('heic çözülemedi'),
    ).prepare(_draft(_jpeg), 0.8);
    expect(compressCalls.single, same(_jpeg));
    expect(out.extension, 'jpg');
  });

  test('sıkıştırılamazsa (web) olduğu gibi; ad ve tür GERÇEK içeriğe göre', () async {
    // Ortadan kırpılmış çıktı PNG'dir → .png / image/png (adı .jpg olsa bile).
    final png = await preparer(compress: (_) async => null).prepare(_draft(_jpeg), 0.8);
    expect((png.bytes, png.extension, png.contentType), (_png, 'png', 'image/png'));

    final jpg = await preparer(
      centerCrop: (_, __) async => null,
      compress: (_) async => null,
    ).prepare(_draft(_jpeg, name: 'yanlis.png'), 1);
    expect((jpg.extension, jpg.contentType), ('jpg', 'image/jpeg'));
  });

  group('sniffImageType', () {
    test('sihirli baytlar', () {
      expect(sniffImageType(_png), ('png', 'image/png'));
      expect(sniffImageType(_jpeg), ('jpg', 'image/jpeg'));
      expect(sniffImageType(_webp), ('webp', 'image/webp'));
      expect(sniffImageType(Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39])), ('gif', 'image/gif'));
    });

    test('tanınmazsa dosya adı, o da yoksa JPEG', () {
      final unknown = Uint8List.fromList([1, 2, 3]);
      expect(sniffImageType(unknown, fallbackName: 'a.WEBP'), ('webp', 'image/webp'));
      expect(sniffImageType(unknown, fallbackName: 'IMG_1.heic'), ('heic', 'image/heic'));
      expect(sniffImageType(unknown, fallbackName: 'adsiz'), ('jpg', 'image/jpeg'));
      expect(sniffImageType(Uint8List(0)), ('jpg', 'image/jpeg'));
    });
  });
}
