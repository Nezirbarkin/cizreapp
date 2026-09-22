import 'package:flutter/material.dart';

import '../../../core/models/post_model.dart';
import '../../../core/widgets/text_background.dart';
import '../../../kullaniciozellikler/widgets/privileged_avatar.dart';
import '../../../kullaniciozellikler/widgets/profile_privileges.dart';
import 'heart_animation_overlay.dart';
import 'post_image_carousel.dart';
import '../../music/music.dart';

/// Yazar rolüne göre rozet rengi. Tüm gönderi kartlarında ortak kullanılır.
Color authorRoleColor(AuthorRole role) {
  switch (role) {
    case AuthorRole.seller:
      return const Color(0xFFE91E63); // Pembe (Satıcı)
    case AuthorRole.courier:
      return const Color(0xFF4CAF50); // Yeşil (Kurye)
    case AuthorRole.driver:
      return const Color(0xFF2196F3); // Mavi (Sürücü)
    case AuthorRole.admin:
      return const Color(0xFF9C27B0); // Mor (Admin)
    default:
      return Colors.grey;
  }
}

/// 1.2B / 3,4K gibi kısa sayaç biçimi (dört haneli sayılar kartı taşırıyordu).
String formatSocialCount(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}B';
  }
  return '$count';
}

/// Gönderi kartlarındaki tarih biçimi: Bugün/Dün/gün ay/tam tarih + saat.
String formatSocialPostDate(DateTime utcDate) {
  final date = utcDate.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final dateOnly = DateTime(date.year, date.month, date.day);

  String dateStr;
  if (dateOnly == today) {
    dateStr = 'Bugün';
  } else if (dateOnly == yesterday) {
    dateStr = 'Dün';
  } else if (date.year == now.year) {
    const aylar = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    dateStr = '${date.day} ${aylar[date.month - 1]}';
  } else {
    dateStr =
        '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$dateStr $hour:$minute';
}

/// Uygulama genelindeki TÜM gönderi listelerinde (Keşfet, Favoriler, Profil)
/// kullanılan ortak gönderi kartı: yumuşak gölgeli, köşeleri yuvarlak beyaz
/// kart + hap biçimli aksiyon butonları. Tasarım burada değişirse her ekran
/// otomatik güncellenir; kopyalanmış kart kodu ekranlar arasında sürüklenmez.
class SocialPostCard extends StatelessWidget {
  final Post post;
  final String fullName;
  final String username;
  final String? avatarUrl;
  final AuthorRole authorRole;
  final bool isVerified;
  final bool showPrivilegeBadges;
  final bool isLiked;
  final bool isSaved;
  // Sahibinin kendi profilinde sabitlediği gönderi (post.isPinned) için amber
  // çerçeve + "Sabitlendi" rozeti. Admin'in feed'de sabitlediği gönderi
  // (post.adminPinned) her yerde "Sabit" ibaresiyle ayrıca gösterilir.
  final bool showOwnPinBadge;
  final VoidCallback onTap;
  final VoidCallback onAuthorTap;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSend;
  final VoidCallback onSave;
  final Widget? trailing;

  const SocialPostCard({
    super.key,
    required this.post,
    required this.fullName,
    required this.username,
    required this.avatarUrl,
    required this.authorRole,
    required this.isVerified,
    required this.onTap,
    required this.onAuthorTap,
    required this.onLike,
    required this.onComment,
    required this.onSend,
    required this.onSave,
    this.showPrivilegeBadges = true,
    this.isLiked = false,
    this.isSaved = false,
    this.showOwnPinBadge = false,
    this.trailing,
  });

  /// Instagram tarzı animasyonlu kalp efekti (çift dokunuşla beğeni).
  void _showLikeAnimation(BuildContext context) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final entry = OverlayEntry(
      builder: (context) =>
          HeartAnimationOverlay(key: UniqueKey(), parentSize: size),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1500), () {
      entry.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    final postBackground = textBackgroundById(post.background);
    final isPinnedByOwner = showOwnPinBadge && post.isPinned;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: () {
        _showLikeAnimation(context);
        if (!isLiked) onLike();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPinnedByOwner
                ? Colors.amber.shade400
                : const Color(0xFFE9EDF1),
            width: isPinnedByOwner ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---------------------------------------------- başlık satırı
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PrivilegedAvatar(
                        userId: post.userId,
                        username: username,
                        avatarUrl: avatarUrl,
                        radius: 22,
                        // Kullanıcı ikon/tikleri avatarın altında tekrar
                        // edilmez; başlıkta ismin yanında tek kez gösterilir.
                        showSocialPrivileges: false,
                        onTap: onAuthorTap,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: onAuthorTap,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: Color(0xFF11181C),
                                    ),
                                    softWrap: true,
                                  ),
                                  if (showPrivilegeBadges)
                                    ProfilePrivilegeBadges(
                                      userId: post.userId,
                                      maximum: 3,
                                    ),
                                  if (isVerified)
                                    const Icon(
                                      Icons.verified,
                                      size: 15,
                                      color: Color(0xFF1DA1F2),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                runSpacing: 3,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '@$username',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    '· ${formatSocialPostDate(post.createdAt)}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  if (authorRole.isStaff)
                                    _PostChip(
                                      label: authorRole.displayLabel,
                                      color: authorRoleColor(authorRole),
                                    ),
                                  if (post.adminPinned)
                                    _PostChip(
                                      label: 'Sabit',
                                      color: Colors.amber.shade700,
                                      icon: Icons.push_pin,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),

                  // -------------------------------------------------- içerik
                  // Arka plan seçilmiş metin gönderisi paylaşıldığı
                  // kompozisyonla çizilir; seçilmemişse SADE metin.
                  if (post.content != null &&
                      post.content!.isNotEmpty &&
                      postBackground != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 10, 8, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: TextBackgroundCanvas(
                            background: postBackground,
                            text: post.content!,
                            maxLines: 10,
                            padding: const EdgeInsets.all(22),
                          ),
                        ),
                      ),
                    )
                  else if (post.content != null && post.content!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 6, 8, 0),
                      child: Text(
                        post.content!,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1F2933),
                          height: 1.42,
                        ),
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // -------------------------------------------------- müzik
                  // OTOMATİK ÇALMAZ. Akış kaydırılırken kendiliğinden ses
                  // çıkaran bir kart hem veri harcar hem de kullanıcının
                  // sessiz sandığı ortamda sesi açar; rozet yalnızca
                  // dokunulunca çalar ve tüm kartlar tek oynatıcıyı paylaşır.
                  if (post.music != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 10, 8, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FeedMusicPill(music: post.music!),
                      ),
                    ),

                  // ------------------------------------------------- görsel
                  if (post.images.isNotEmpty && post.images.first.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, right: 6),
                      // PostImageCarousel kendi ClipRRect'ini uyguluyor.
                      child: PostImageCarousel(
                        imageUrls: post.images,
                        onTap: onTap,
                      ),
                    ),

                  // ------------------------------------------------- konum
                  if (post.location != null && post.location!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, left: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: 15,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              post.location!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 6),
                  Divider(height: 14, color: Colors.grey.shade200),

                  // ------------------------------------------ aksiyon satırı
                  Row(
                    children: [
                      _ActionButton(
                        icon: isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        count: post.likesCount,
                        onTap: onLike,
                        color: const Color(0xFFE0245E),
                        isActive: isLiked,
                      ),
                      const SizedBox(width: 4),
                      _ActionButton(
                        icon: Icons.mode_comment_outlined,
                        count: post.commentsCount,
                        onTap: onComment,
                        color: const Color(0xFF1D9BF0),
                      ),
                      const SizedBox(width: 4),
                      _ActionButton(
                        icon: Icons.send_outlined,
                        count: null,
                        onTap: onSend,
                        color: const Color(0xFF17BF63),
                      ),
                      const Spacer(),
                      _ActionButton(
                        icon: isSaved
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        count: null,
                        onTap: onSave,
                        color: const Color(0xFFF59E0B),
                        isActive: isSaved,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isPinnedByOwner)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.push_pin, size: 10, color: Colors.white),
                      SizedBox(width: 2),
                      Text(
                        'Sabitlendi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Başlık satırındaki küçük rozet (rol / sabit).
class _PostChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _PostChip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kart altındaki hap biçimli aksiyon butonu.
/// Aktifken (beğenildi / kaydedildi) rengin açık tonu zemin olarak yanar.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int? count;
  final VoidCallback onTap;
  final Color color;
  final bool isActive;

  const _ActionButton({
    required this.icon,
    required this.count,
    required this.onTap,
    required this.color,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = isActive ? color : Colors.grey.shade600;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: count != null ? 10 : 8,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 19),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  formatSocialCount(count!),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
