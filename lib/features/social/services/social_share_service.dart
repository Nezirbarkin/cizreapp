import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/post_model.dart';

/// Gönderi ve profil paylaşımı — linklerin, paylaşım metninin ve paylaşım
/// sayacının TEK yeri.
///
/// Link biçimleri uygulamada (deeplink, `onGenerateRoute`) ve web'de aynı
/// yolları açar:
/// * gönderi: `https://cizreapp.com/post/<id>`
/// * profil : `https://cizreapp.com/u/@<kullanıcıadı>`
/// * dükkân : `https://cizreapp.com/s/<slug>` (dükkân ekranında üretilir)
///
/// Eskiden gönderi paylaşım metninde link YOKTU (alıcı gönderiyi açamıyordu),
/// profil paylaşımı yalnız panoya kopyalıyordu, `shares_count` hiç artmıyordu.
class SocialShareService {
  SocialShareService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  static const String origin = 'https://cizreapp.com';

  static String postLink(String postId) => '$origin/post/$postId';

  /// Kullanıcı adları Türkçe harf, tire, hatta boşluk içerebiliyor
  /// (ör. "bilginbarkın"); linkte yüzde kodlanır.
  static String profileLink(String username) {
    final clean = username.trim().replaceFirst(RegExp(r'^@+'), '');
    return '$origin/u/@${Uri.encodeComponent(clean)}';
  }

  /// Gelen bir linki uygulama içi rota adına çevirir (`/post/<id>`,
  /// `/u/@<ad>`, `/s/<slug>`); bizim linkimiz değilse null. Hem
  /// `https://(www.)cizreapp.com/...` hem `cizreapp://post/<id>` biçimi.
  static String? appRouteFor(Uri uri) {
    String path;
    if (uri.scheme == 'cizreapp') {
      // cizreapp://post/<id> → host=post, path=/<id>
      path = '/${uri.host}${uri.path}';
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        (uri.host == 'cizreapp.com' || uri.host == 'www.cizreapp.com')) {
      path = uri.path;
    } else {
      return null;
    }
    try {
      path = Uri.decodeComponent(path);
    } on ArgumentError {
      return null;
    }
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);

    final post = RegExp(r'^/post/([0-9a-fA-F-]{36})$').firstMatch(path);
    if (post != null) return '/post/${post.group(1)!.toLowerCase()}';

    final profile = RegExp(r'^/u/@?([^/@][^/]{0,59})$').firstMatch(path);
    if (profile != null) {
      final name = profile.group(1)!.trim();
      if (name.isNotEmpty) return '/u/@$name';
    }

    final shop = RegExp(r'^/s/([A-Za-z0-9_-]{1,80})$').firstMatch(path);
    if (shop != null) return '/s/${shop.group(1)}';

    return null;
  }

  /// Dışarı paylaşılan gönderi metni (link dahil).
  static String postShareText(Post post, {required String authorName}) {
    final text = StringBuffer()
      ..writeln("📱 CizreApp'te $authorName paylaştı:")
      ..writeln();
    final content = post.content?.trim() ?? '';
    if (content.isNotEmpty) {
      // Çok uzun metin önizlemeyi boğmasın; tamamı linkte.
      text
        ..writeln(content.length > 280 ? '${content.substring(0, 277)}…' : content)
        ..writeln();
    }
    final location = post.location?.trim() ?? '';
    if (location.isNotEmpty) text.writeln('📍 $location');
    text
      ..writeln('👉 ${postLink(post.id)}')
      ..writeln()
      ..write("CizreApp'i indir ve sen de katıl! 🎉");
    return text.toString();
  }

  static String profileShareText({
    required String username,
    String? fullName,
  }) {
    final name = (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : '@$username';
    return "$name CizreApp'te 👋\n👉 ${profileLink(username)}";
  }

  /// Gönderiyi sistem paylaşım sayfasıyla paylaşır. Kullanıcı bir hedef
  /// seçtiyse (ya da platform sonucu bildiremiyorsa) paylaşım sayılır ve
  /// sunucudaki yeni paylaşım sayısı döner; vazgeçtiyse null.
  Future<int?> sharePost(Post post, {required String authorName}) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: postShareText(post, authorName: authorName),
        subject: "CizreApp'te $authorName",
      ),
    );
    if (result.status == ShareResultStatus.dismissed) return null;
    return recordShare(post.id);
  }

  Future<void> shareProfile({required String username, String? fullName}) async {
    await SharePlus.instance.share(
      ShareParams(
        text: profileShareText(username: username, fullName: fullName),
        subject: "CizreApp'te @$username",
      ),
    );
  }

  /// Paylaşımı kaydeder (kişi başına bir kez sayılır). Yeni sayı ya da
  /// kaydedilemediyse null. Hata kullanıcıya gösterilmez: paylaşımın kendisi
  /// zaten yapıldı, sayaç ikincil.
  Future<int?> recordShare(String postId, {String channel = 'external'}) async {
    if (_client.auth.currentUser == null) return null;
    try {
      final value = await _client.rpc(
        'record_post_share',
        params: {'p_post_id': postId, 'p_channel': channel},
      );
      return value is num ? value.toInt() : null;
    } catch (e) {
      debugPrint('Paylaşım kaydedilemedi: $e');
      return null;
    }
  }
}
