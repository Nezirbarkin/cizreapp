import 'dart:io';

import 'package:flutter/services.dart';

/// Testlerde metin ve Material ikonlarının GERÇEK glifleriyle çizilmesi için
/// Flutter SDK'sının gömülü fontlarını yükler. Yüklenmezse `flutter test`
/// her yazıyı dikdörtgen bloklarla (Ahem) çizer ve PNG çıktıları okunmaz.
///
/// `setUpAll(() async => loadTestFonts())` içinde çağırın.
Future<void> loadTestFonts() async {
  final dir = _fontDir();
  if (dir == null) return;

  Future<ByteData> read(String name) async {
    final bytes = File('$dir/$name').readAsBytesSync();
    return ByteData.sublistView(bytes);
  }

  final roboto = FontLoader('Roboto');
  for (final f in const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
    'roboto-light.ttf',
  ]) {
    if (File('$dir/$f').existsSync()) roboto.addFont(read(f));
  }
  await roboto.load();

  if (File('$dir/materialicons-regular.otf').existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(read('materialicons-regular.otf'));
    await icons.load();
  }
}

String? _fontDir() {
  final candidates = <String>[
    'C:/flutter/bin/cache/artifacts/material_fonts',
    if (Platform.environment['FLUTTER_ROOT'] != null)
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts',
  ];
  for (final c in candidates) {
    if (Directory(c).existsSync()) return c;
  }
  return null;
}
