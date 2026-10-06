import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Boş ya da HTTP olmayan bir görsel URL'i için `null` döner.
///
/// `NetworkImage('')` çalışma zamanında `Uri.base.resolve('')` yapar; mobilde
/// bu `file:///` demektir ve görsel yüklenirken
/// "Invalid argument(s): No host specified in URI file:///" fırlar.
/// `Image.network` bu hatayı `errorBuilder` ile yutabilir, ama
/// `DecorationImage` ve `CircleAvatar.backgroundImage` yutamaz — hata doğrudan
/// `FlutterError.onError`'a düşer ve admin panelindeki "Son Hatalar" listesini
/// doldurur. Bu yüzden URL'i sağlayan tarafta eliyoruz.
///
/// Kullanım:
/// ```dart
/// final avatar = safeNetworkImage(user.avatarUrl);
/// CircleAvatar(
///   backgroundImage: avatar,
///   child: avatar == null ? const Icon(Icons.person) : null,
/// );
/// ```
ImageProvider? safeNetworkImage(String? url) {
  final trimmed = _validHttpUrl(url);
  if (trimmed == null) return null;
  return NetworkImage(trimmed);
}

/// Küçük yuvarlak avatarlar (liste satırı, yorum, gönderi başlığı) için görsel.
///
/// `NetworkImage(url)` iki yüzden listelerde ağırdı: (1) yüklenen avatarlar
/// 1600 px'e kadar çıkıyor ve 44 px'lik bir daire için tam çözünürlükte
/// (~10 MB bitmap) decode ediliyordu — birkaç satırda görsel önbelleği (100 MB)
/// dolup kaydırırken sürekli yeniden decode ediliyordu; (2) diske önbellek
/// yoktu, her açılışta yeniden indiriliyordu. Bu sağlayıcı diske önbellekler
/// ve bitmap'i [decodeWidth] piksele indirir (en-boy oranı korunur).
///
/// [safeNetworkImage] gibi boş/geçersiz URL'de `null` döner.
ImageProvider? avatarImage(String? url, {int decodeWidth = 256}) {
  final trimmed = _validHttpUrl(url);
  if (trimmed == null) return null;
  return ResizeImage.resizeIfNeeded(
    decodeWidth,
    null,
    CachedNetworkImageProvider(trimmed),
  );
}

String? _validHttpUrl(String? url) {
  final trimmed = url?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return trimmed;
}
