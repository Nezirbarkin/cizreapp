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
  final trimmed = url?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return NetworkImage(trimmed);
}
