// ignore_for_file: deprecated_member_use

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/models/analytics_model.dart';
import '../../../kullaniciozellikler/widgets/privileged_avatar.dart';

/// Profil ekranları (ProfileScreen + UserProfileScreen) arasında tekrar eden
/// yardımcı widget ve fonksiyonlar. İki ekran birebir aynı mantığı taşıdığı
/// için burada tek kaynakta toplanır.

/// Tek istatistik kutusu (Gönderi / Takipçi / Takip / Arkadaş).
/// Tıklanabilir alanın boşluklarda bile tepki vermesi için opaque davranış
/// kullanılır (user_profile_screen.dart ile uyumlu).
Widget buildStatItem(
  String count,
  String label,
  VoidCallback? onTap, {
  bool showDivider = false,
}) {
  return GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: EdgeInsets.only(left: showDivider ? 8 : 2, right: 2),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0xFFD8DCE2), width: 1),
              ),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: const TextStyle(
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: const TextStyle(
              fontSize: 8,
              color: Color(0xFF30343B),
              fontWeight: FontWeight.w600,
              letterSpacing: -0.15,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Profil sayaçlarını ekrana sığan sosyal medya biçiminde gösterir.
/// Örnekler: 999, 1,2K, 12K, 1,5M.
String formatProfileCount(int value) {
  if (value < 1000) return value.toString();

  String compact(double number, String suffix) {
    final rounded = number >= 10
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(1);
    return '${rounded.replaceFirst('.0', '').replaceFirst('.', ',')}$suffix';
  }

  if (value < 1000000) return compact(value / 1000, 'K');
  return compact(value / 1000000, 'M');
}

/// Referans tasarımdaki kapağın üzerine binen avatar ve sayaç paneli.
class ProfileIdentityHeader extends StatelessWidget {
  final String userId;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final bool hasStories;
  final int postsCount;
  final int followersCount;
  final int followingCount;
  final int friendsCount;
  final VoidCallback onAvatarTap;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;
  final VoidCallback onFriendsTap;
  final Widget? website;
  final Widget? statusBadge;
  final bool showHero;

  const ProfileIdentityHeader({
    super.key,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.bio,
    required this.hasStories,
    required this.postsCount,
    required this.followersCount,
    required this.followingCount,
    required this.friendsCount,
    required this.onAvatarTap,
    required this.onFollowersTap,
    required this.onFollowingTap,
    required this.onFriendsTap,
    this.website,
    this.statusBadge,
    this.showHero = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHero)
            SizedBox(
              height: 94,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 35,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(color: Colors.white),
                  ),
                  Positioned(
                    top: -56,
                    left: 0,
                    right: 0,
                    height: 150,
                    child: PhysicalShape(
                      clipper: const _ProfileHeaderCurveClipper(),
                      color: Colors.white,
                      shadowColor: const Color(0x26000000),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(122, 63, 10, 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: buildStatItem(
                                formatProfileCount(postsCount),
                                'Gönderiler',
                                null,
                              ),
                            ),
                            Expanded(
                              child: buildStatItem(
                                formatProfileCount(followersCount),
                                'Takipçiler',
                                onFollowersTap,
                                showDivider: true,
                              ),
                            ),
                            Expanded(
                              child: buildStatItem(
                                formatProfileCount(followingCount),
                                'Takip',
                                onFollowingTap,
                                showDivider: true,
                              ),
                            ),
                            Expanded(
                              child: buildStatItem(
                                formatProfileCount(friendsCount),
                                'Arkadaşlar',
                                onFriendsTap,
                                showDivider: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: -62,
                    child: GestureDetector(
                      onTap: onAvatarTap,
                      child: AvatarEffectFrame(
                        userId: userId,
                        child: Container(
                          width: 106,
                          height: 106,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: hasStories
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF833AB4),
                                      Color(0xFFE1306C),
                                      Color(0xFFF77737),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFFF9FAFB),
                                      Color(0xFFD1D5DB),
                                    ],
                                  ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 16,
                                offset: Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              backgroundColor: const Color(0xFFF3F4F6),
                              backgroundImage:
                                  avatarUrl != null && avatarUrl!.isNotEmpty
                                  ? NetworkImage(avatarUrl!)
                                  : null,
                              child: avatarUrl == null || avatarUrl!.isEmpty
                                  ? Text(
                                      username.isNotEmpty
                                          ? username
                                                .substring(0, 1)
                                                .toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF4B5563),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        fullName,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    if (statusBadge != null) ...[
                      const SizedBox(width: 10),
                      statusBadge!,
                    ],
                  ],
                ),
                if (bio != null && bio!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    bio!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
                if (website != null) ...[const SizedBox(height: 8), website!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kapak görseliyle aynı Stack içinde çizilen kıvrımlı profil kahraman alanı.
/// Böylece avatar ve eğri sliver sınırında kırpılmaz.
class ProfileHeroHeader extends StatelessWidget {
  final String userId;
  final String username;
  final String? avatarUrl;
  final bool hasStories;
  final int postsCount;
  final int followersCount;
  final int followingCount;
  final int friendsCount;
  final VoidCallback onAvatarTap;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;
  final VoidCallback onFriendsTap;

  const ProfileHeroHeader({
    super.key,
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.hasStories,
    required this.postsCount,
    required this.followersCount,
    required this.followingCount,
    required this.friendsCount,
    required this.onAvatarTap,
    required this.onFollowersTap,
    required this.onFollowingTap,
    required this.onFriendsTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 122,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: PhysicalShape(
              clipper: const _ProfileHeaderCurveClipper(),
              color: Colors.white,
              shadowColor: const Color(0x28000000),
              elevation: 7,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(122, 25, 8, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: buildStatItem(
                        formatProfileCount(postsCount),
                        'Gönderiler',
                        null,
                      ),
                    ),
                    Expanded(
                      child: buildStatItem(
                        formatProfileCount(followersCount),
                        'Takipçiler',
                        onFollowersTap,
                        showDivider: true,
                      ),
                    ),
                    Expanded(
                      child: buildStatItem(
                        formatProfileCount(followingCount),
                        'Takip',
                        onFollowingTap,
                        showDivider: true,
                      ),
                    ),
                    Expanded(
                      child: buildStatItem(
                        formatProfileCount(friendsCount),
                        'Arkadaşlar',
                        onFriendsTap,
                        showDivider: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            bottom: 5,
            child: GestureDetector(
              onTap: onAvatarTap,
              child: AvatarEffectFrame(
                userId: userId,
                child: Container(
                  width: 104,
                  height: 104,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasStories
                        ? const LinearGradient(
                            colors: [
                              Color(0xFF833AB4),
                              Color(0xFFE1306C),
                              Color(0xFFF77737),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [Color(0xFFF9FAFB), Color(0xFFD1D5DB)],
                          ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x35000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      backgroundColor: const Color(0xFFF3F4F6),
                      backgroundImage:
                          avatarUrl != null && avatarUrl!.isNotEmpty
                          ? NetworkImage(avatarUrl!)
                          : null,
                      child: avatarUrl == null || avatarUrl!.isEmpty
                          ? Text(
                              username.isNotEmpty
                                  ? username.substring(0, 1).toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4B5563),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderCurveClipper extends CustomClipper<Path> {
  const _ProfileHeaderCurveClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 58)
      ..lineTo(size.width * 0.13, 58)
      ..cubicTo(
        size.width * 0.22,
        58,
        size.width * 0.23,
        3,
        size.width * 0.39,
        3,
      )
      ..lineTo(size.width, 3)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Profil ekranlarındaki geniş takip, mesaj ve düzenleme eylemi.
class ProfileActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final List<Color>? gradientColors;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final Color shadowColor;

  const ProfileActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.gradientColors,
    this.backgroundColor = const Color(0xFF68717B),
    this.foregroundColor = Colors.white,
    this.borderColor,
    this.shadowColor = const Color(0x30000000),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: gradientColors == null ? backgroundColor : null,
        gradient: gradientColors != null
            ? LinearGradient(
                colors: gradientColors!,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(10),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: foregroundColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: foregroundColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Bu Ay İstatistiklerim" bölümünde yer alan tek analitik kart.
Widget buildAnalyticsCard({
  required IconData icon,
  required String title,
  required int count,
  required String subtitle,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    ),
  );
}

/// Gönderi tarihini "Az önce / 5dk önce / 3sa önce / 2g önce / gg/ay ss:dd"
/// biçiminde biçimlendirir. İki ekrandaki _formatItem ile birebir aynı.
String formatRelativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inMinutes < 1) return 'Az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
  if (diff.inHours < 24) return '${diff.inHours}sa önce';
  if (diff.inDays < 7) return '${diff.inDays}g önce';

  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.day}/${date.month} $hour:$minute';
}

/// Avatar/kapak görselini tam ekran, yakınlaştırılabilir şekilde açar.
/// İki ekrandaki _showFullScreenImage ile birebir aynı.
void showFullScreenImage(BuildContext context, String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              errorWidget: (context, url, error) {
                return const Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 48,
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// "Bu Ay İstatistiklerim" açılır-kapanır bölümü.
///
/// Animasyon ve açılmışlık durumu ekrana ait (her iki ekran da kendi
/// AnimationController'ını zaten tutuyor); widget sadece görselleştirme
/// yapar ve başlığa dokunulduğunda [onToggle] çağırır. [onToggle] içinde
/// setState + controller forward/reverse yapılmalıdır.
class ProfileStatsSection extends StatelessWidget {
  final Animation<double> animation;
  final CurrentMonthViewStats? profileStats;
  final CurrentMonthViewStats? postStats;
  final VoidCallback onToggle;

  const ProfileStatsSection({
    super.key,
    required this.animation,
    required this.profileStats,
    required this.postStats,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.pink.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade400, Colors.pink.shade400],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Bu Ay İstatistiklerim',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: animation.value * 3.14159,
                        child: Icon(
                          Icons.expand_more,
                          color: Colors.purple.shade700,
                          size: 20,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1.0,
            child: FadeTransition(
              opacity: animation,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    Divider(color: Colors.purple.shade100, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (profileStats != null)
                          Expanded(
                            child: buildAnalyticsCard(
                              icon: Icons.visibility_rounded,
                              title: 'Profil Ziyaret',
                              count: profileStats!.totalViews,
                              subtitle:
                                  '${profileStats!.uniqueViewers} benzersiz',
                              color: Colors.blue,
                            ),
                          ),
                        if (profileStats != null && postStats != null)
                          const SizedBox(width: 12),
                        if (postStats != null)
                          Expanded(
                            child: buildAnalyticsCard(
                              icon: Icons.auto_graph_rounded,
                              title: 'Post Görüntüleme',
                              count: postStats!.totalViews,
                              subtitle: '${postStats!.uniqueViewers} benzersiz',
                              color: Colors.purple,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
