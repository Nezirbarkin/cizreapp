import 'dart:typed_data';

/// Baytların gerçek görsel türü (sihirli baytlardan): (uzantı, MIME).
///
/// Yüklenen dosyanın adı ve içerik türü İÇERİKLE uyumlu olsun diye kullanılır
/// (ör. sıkıştırılamayan bir PNG'nin `.jpg` adıyla yüklenmemesi). Tanınmazsa
/// [fallbackName]'in uzantısı, o da yoksa JPEG kabul edilir.
(String, String) sniffImageType(Uint8List bytes, {String fallbackName = ''}) {
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return ('png', 'image/png');
  if (startsWith(const [0xFF, 0xD8, 0xFF])) return ('jpg', 'image/jpeg');
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return ('gif', 'image/gif');
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) && startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return ('webp', 'image/webp');
  }

  final dot = fallbackName.lastIndexOf('.');
  final ext = dot >= 0 ? fallbackName.substring(dot + 1).toLowerCase() : '';
  return switch (ext) {
    'png' => ('png', 'image/png'),
    'webp' => ('webp', 'image/webp'),
    'gif' => ('gif', 'image/gif'),
    'heic' || 'heif' => (ext, 'image/$ext'),
    _ => ('jpg', 'image/jpeg'),
  };
}
