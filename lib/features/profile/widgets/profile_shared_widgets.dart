// ignore_for_file: deprecated_member_use

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/models/analytics_model.dart';

/// Profil ekranları (ProfileScreen + UserProfileScreen) arasında tekrar eden
/// yardımcı widget ve fonksiyonlar. İki ekran birebir aynı mantığı taşıdığı
/// için burada tek kaynakta toplanır.

/// Tek istatistik kutusu (Gönderi / Takipçi / Takip / Arkadaş).
/// Tıklanabilir alanın boşluklarda bile tepki vermesi için opaque davranış
/// kullanılır (user_profile_screen.dart ile uyumlu).
Widget buildStatItem(String count, String label, VoidCallback? onTap) {
  return GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
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
                    child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 16),
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
                              subtitle: '${profileStats!.uniqueViewers} benzersiz',
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