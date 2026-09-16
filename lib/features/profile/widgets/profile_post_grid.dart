import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/post_model.dart';
import '../../../core/widgets/text_background.dart';

/// Profil ekranlarındaki ("kendi profilim" ve "başkasının profili") gönderi
/// ızgarası.
///
/// Eskiden iki ekranda da kopyalanmış, keskin köşeli, gri zeminli 2px aralıklı
/// bir ızgara vardı; metin gönderileri gri üstüne gri küçük punto olarak
/// okunmuyordu. Bu widget o düzeni tek yerde toplar ve yeniden tasarlar:
///
///   * yuvarlatılmış kartlar, nefes alan aralık,
///   * görselin üstünde yalnızca alt kenarda yumuşak bir karartma — sayaçlar
///     her zeminde okunur,
///   * sabitlenmiş gönderiler için rozet.
///
/// METİN GÖNDERİLERİ (2026-09-09): Kare artık gönderinin KENDİ arka planını
/// çizer. Kullanıcı paylaşırken bir zemin seçtiyse (post.background) ızgarada
/// da o zemin görünür; SEÇMEDİYSE kare SADE çizilir — düz kağıt zemin, koyu
/// yazı, süs yok. Eskiden gönderi kimliğinden türetilen rastgele bir renk
/// geçişi basılıyordu: kullanıcı hiç seçmediği renkleri kendi profilinde
/// görüyor ve sade paylaşımlar olduğundan daha "gürültülü" duruyordu.
///
/// KONUM: Bu widget gönderi konumunu (post.location / latitude / longitude)
/// ne okur ne gösterir — konum davranışı bilinçli olarak dokunulmadan bırakıldı.
class ProfilePostGrid extends StatelessWidget {
  final List<Post> posts;

  /// Beğenilen gönderi kimlikleri; kalp ikonunun dolu/boş çizilmesi için.
  final Set<String> likedPostIds;

  final void Function(Post post) onTap;

  /// Çift dokunuşla beğeni (yalnız `user_profile_screen` kullanıyor).
  final void Function(Post post)? onDoubleTap;

  const ProfilePostGrid({
    super.key,
    required this.posts,
    required this.likedPostIds,
    required this.onTap,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _tile(context, posts[index]),
          childCount: posts.length,
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Post post) {
    final firstImage = post.images.isNotEmpty ? post.images.first : null;
    final background = firstImage == null
        ? textBackgroundById(post.background)
        : null;

    // Sade metin karesi: koyu yazı açık zeminde. Sayaçları siyah gradyanla
    // basmak burada okunmazlığa yol açardı; ince bir ayraç + koyu ikon yeter.
    final isPlainText = firstImage == null && background == null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final plainInk = isDark ? Colors.white : const Color(0xFF15202B);

    return GestureDetector(
      onTap: () => onTap(post),
      onDoubleTap: onDoubleTap == null ? null : () => onDoubleTap!(post),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: isPlainText
              ? BoxDecoration(
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE3E8EE),
                  ),
                  borderRadius: BorderRadius.circular(16),
                )
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (firstImage != null)
                _imageLayer(firstImage)
              else if (background != null)
                TextBackgroundCanvas(
                  background: background,
                  text: _tileText(post),
                  // 5 satir, karenin yuksekligine sigan azami satir sayisi:
                  // 6'da metin kutusu kareyi asiyor ve alt satir ellipsis
                  // yerine ortadan kirpiliyordu.
                  maxLines: 5,
                  fontScale: 0.9,
                  padding: const EdgeInsets.fromLTRB(9, 10, 9, 22),
                )
              else
                _plainTextLayer(post, isDark: isDark, ink: plainInk),

              // Sayaç şeridi. Zeminli/görselli karede alt karartma gerekir;
              // sade karede zemin zaten açık, karartma yerine düz durur.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 7),
                  decoration: isPlainText
                      ? null
                      : BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.black.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                  child: Row(
                    children: [
                      _counter(
                        likedPostIds.contains(post.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        post.likesCount,
                        color: isPlainText
                            ? plainInk.withValues(alpha: 0.65)
                            : Colors.white,
                      ),
                      const SizedBox(width: 10),
                      _counter(
                        Icons.mode_comment_outlined,
                        post.commentsCount,
                        color: isPlainText
                            ? plainInk.withValues(alpha: 0.65)
                            : Colors.white,
                      ),
                    ],
                  ),
                ),
              ),

              // Çoklu görsel göstergesi
              if (post.images.length > 1)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _badge(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.collections,
                            size: 11, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(
                          '${post.images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Sabitlenmiş gönderi rozeti
              if (post.isPinned || post.adminPinned)
                Positioned(
                  top: 6,
                  left: 6,
                  child: _badge(
                    color: Colors.amber.shade700.withValues(alpha: 0.9),
                    child: const Icon(Icons.push_pin,
                        size: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _tileText(Post post) {
    final text = (post.content ?? '').trim();
    return text.isEmpty ? 'Gönderi' : text;
  }

  Widget _imageLayer(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, _) => Container(color: const Color(0xFFECEFF3)),
      errorWidget: (context, _, __) => Container(
        color: const Color(0xFFECEFF3),
        child: Icon(Icons.broken_image_outlined,
            color: Colors.grey.shade400, size: 22),
      ),
    );
  }

  /// Arka plan seçilmemiş metin gönderisi: süssüz, düz zemin, okunur yazı.
  Widget _plainTextLayer(Post post, {required bool isDark, required Color ink}) {
    return Container(
      color: isDark ? const Color(0xFF161B22) : const Color(0xFFF7F9FB),
      padding: const EdgeInsets.fromLTRB(10, 11, 10, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          _tileText(post),
          // Bkz. zeminli kare: 6 satir kareyi asip kirpiliyor.
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ink,
            fontSize: 11.5,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _counter(IconData icon, int value, {required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _badge({required Widget child, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
