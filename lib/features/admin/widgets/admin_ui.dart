import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Admin panelindeki yeni ekranların (Kullanıcılar, Kullanıcı Eylemleri,
/// Müzik Çalar, Günün Fırsatı istatistikleri) ortak görsel dili.
///
/// Amaç: aynı kart/rozet/avatar/zaman biçimlerini her ekranda yeniden yazmamak
/// ve panelin tutarlı görünmesi. Renk paleti panelin mor temasıyla uyumludur.
class AdminUi {
  AdminUi._();

  static final Color brand = Colors.purple.shade700;
  static final Color brandSoft = Colors.purple.shade50;
  static const Color ink = Color(0xFF1F2937);
  static const Color muted = Color(0xFF6B7280);
  static const Color line = Color(0xFFE5E7EB);
  static const Color surface = Colors.white;
  static const Color page = Color(0xFFF6F7FB);
}

/// Yuvarlatılmış, hafif gölgeli beyaz kart.
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color ?? AdminUi.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor ?? AdminUi.line),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
    final content = Padding(padding: padding, child: child);
    if (onTap == null) {
      return Container(decoration: decoration, child: content);
    }
    return Container(
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

/// Üst kısımda kullanılan küçük özet kutusu (ikon + büyük sayı + etiket).
class AdminStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const AdminStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AdminUi.ink,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dar satırlarda (3-4 kutu yan yana) kullanılan dikey özet kutusu: ikon üstte,
/// sayı ortada, etiket altta. [AdminStatTile] yatay ve geniş; bu, telefon
/// genişliğinde etiketin kesilmemesi için.
class AdminMiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const AdminMiniStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AdminUi.ink,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AdminUi.muted),
          ),
        ],
      ),
    );
  }
}

/// Avatar: görsel yüklenemezse/yoksa baş harf; isteğe bağlı çevrimiçi noktası.
class AdminAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double radius;
  final bool online;

  const AdminAvatar({
    super.key,
    required this.url,
    required this.name,
    this.radius = 22,
    this.online = false,
  });

  bool get _validUrl {
    final u = url?.trim() ?? '';
    return u.startsWith('http://') || u.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    final fallback = Text(
      initial,
      style: TextStyle(
        fontSize: radius * 0.8,
        fontWeight: FontWeight.bold,
        color: AdminUi.brand,
      ),
    );

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: AdminUi.brandSoft,
      child: _validUrl
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: url!.trim(),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                memCacheWidth: (radius * 4).round(),
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              ),
            )
          : fallback,
    );

    if (!online) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * 0.6,
            height: radius * 0.6,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Küçük renkli rozet (rol, durum, "Yeni" vb.).
class AdminBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const AdminBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Boş/hata durumu.
class AdminEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const AdminEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AdminUi.ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AdminUi.muted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Yatay kaydırmalı seçim çipleri (filtre çubuğu).
class AdminChipBar<T> extends StatelessWidget {
  final List<({T value, String label, IconData? icon, int? count})> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final Color? color;

  const AdminChipBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AdminUi.brand;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final isSelected = item.value == selected;
          return ChoiceChip(
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onSelected(item.value),
            selectedColor: accent,
            backgroundColor: Colors.white,
            side: BorderSide(color: isSelected ? accent : AdminUi.line),
            labelPadding: const EdgeInsets.symmetric(horizontal: 2),
            avatar: item.icon == null
                ? null
                : Icon(
                    item.icon,
                    size: 16,
                    color: isSelected ? Colors.white : AdminUi.muted,
                  ),
            label: Text(
              item.count == null ? item.label : '${item.label} · ${item.count}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AdminUi.ink,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Biçimlendirme yardımcıları
// ---------------------------------------------------------------------------

DateTime? adminParseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "dd.MM.yyyy HH:mm"
String adminDateTime(DateTime? d) {
  if (d == null) return '-';
  return '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

/// "dd.MM.yyyy"
String adminDate(DateTime? d) {
  if (d == null) return '-';
  return '${_two(d.day)}.${_two(d.month)}.${d.year}';
}

/// "şimdi", "5 dk önce", "3 sa önce", "2 gün önce", ya da tarih.
String adminTimeAgo(DateTime? d) {
  if (d == null) return '-';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'şimdi';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  if (diff.inHours < 24) return '${diff.inHours} sa önce';
  if (diff.inDays < 7) return '${diff.inDays} gün önce';
  return adminDate(d);
}

/// Saniyeyi "1 sa 5 dk", "12 dk", "40 sn" olarak yazar.
String adminDuration(num seconds) {
  final s = seconds.toInt();
  if (s < 60) return '$s sn';
  final m = s ~/ 60;
  if (m < 60) return '$m dk';
  final h = m ~/ 60;
  final rm = m % 60;
  return rm == 0 ? '$h sa' : '$h sa $rm dk';
}

/// Binlik ayraçlı sayı: 1290 -> "1.290"; 1.200.000 ve üstü "1,2 Mn".
/// ("1,3B" gibi kısaltmalar milyar gibi okunabildiği için kullanılmıyor.)
String adminCompact(num n) {
  final v = n.toDouble();
  if (v >= 1000000) {
    return '${(v / 1000000).toStringAsFixed(1).replaceAll('.', ',')} Mn';
  }
  final digits = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0 && digits[i - 1] != '-') buf.write('.');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Kullanıcıyı listelerde göstermek için ad: önce ad-soyad, sonra @kullanıcı adı.
String adminDisplayName(Map<String, dynamic> user) {
  final full = (user['full_name'] as String?)?.trim() ?? '';
  final username = (user['username'] as String?)?.trim() ?? '';
  if (full.isNotEmpty) return full;
  if (username.isNotEmpty) return username;
  return 'Silinmiş kullanıcı';
}

/// Eylem günlüğünde bir eylemin Türkçe etiketi, ikonu ve rengi.
({String label, IconData icon, Color color}) adminActionStyle(String action) {
  switch (action) {
    case 'login':
      return (label: 'Giriş', icon: Icons.login_rounded, color: Colors.green);
    case 'logout':
      return (label: 'Çıkış', icon: Icons.logout_rounded, color: Colors.grey);
    case 'app_open':
      return (label: 'Uygulama açıldı', icon: Icons.phone_android, color: Colors.teal);
    case 'signup':
      return (label: 'Kayıt', icon: Icons.person_add_alt_1, color: Colors.green);
    case 'username_changed':
      return (label: 'Kullanıcı adı', icon: Icons.alternate_email, color: Colors.indigo);
    case 'avatar_changed':
      return (label: 'Fotoğraf', icon: Icons.account_circle_outlined, color: Colors.indigo);
    case 'name_changed':
      return (label: 'Ad değişti', icon: Icons.badge_outlined, color: Colors.indigo);
    case 'status_changed':
      return (label: 'Hesap durumu', icon: Icons.shield_outlined, color: Colors.deepOrange);
    case 'role_changed':
      return (label: 'Rol', icon: Icons.admin_panel_settings_outlined, color: Colors.deepOrange);
    case 'post_created':
      return (label: 'Gönderi', icon: Icons.post_add_rounded, color: Colors.blue);
    case 'post_deleted':
      return (label: 'Gönderi silindi', icon: Icons.delete_outline, color: Colors.blueGrey);
    case 'comment_created':
      return (label: 'Yorum', icon: Icons.mode_comment_outlined, color: Colors.blue);
    case 'post_liked':
      return (label: 'Beğeni', icon: Icons.favorite_border, color: Colors.pink);
    case 'post_saved':
      return (label: 'Kaydetti', icon: Icons.bookmark_border, color: Colors.pink);
    case 'product_favorited':
      return (label: 'Favori', icon: Icons.favorite_border, color: Colors.pink);
    case 'followed':
      return (label: 'Takip', icon: Icons.person_add_alt, color: Colors.purple);
    case 'unfollowed':
      return (label: 'Takip bıraktı', icon: Icons.person_remove_alt_1, color: Colors.blueGrey);
    case 'story_created':
      return (label: 'Hikaye', icon: Icons.auto_stories_outlined, color: Colors.purple);
    case 'message_sent':
      return (label: 'Mesaj', icon: Icons.chat_bubble_outline, color: Colors.cyan);
    case 'order_created':
      return (label: 'Sipariş', icon: Icons.shopping_bag_outlined, color: Colors.orange);
    case 'order_status_changed':
      return (label: 'Sipariş durumu', icon: Icons.local_shipping_outlined, color: Colors.orange);
    case 'digital_order_created':
      return (label: 'Dijital sipariş', icon: Icons.bolt_rounded, color: Colors.orange);
    case 'product_viewed':
      return (label: 'Ürüne baktı', icon: Icons.visibility_outlined, color: Colors.blueGrey);
    case 'shop_viewed':
      return (label: 'Dükkana baktı', icon: Icons.storefront_outlined, color: Colors.blueGrey);
    case 'product_reviewed':
    case 'shop_reviewed':
      return (label: 'Değerlendirme', icon: Icons.star_outline_rounded, color: Colors.amber.shade800);
    case 'coupon_used':
      return (label: 'Kupon', icon: Icons.confirmation_number_outlined, color: Colors.orange);
    case 'report_sent':
      return (label: 'Şikayet', icon: Icons.flag_outlined, color: Colors.red);
    case 'ticket_created':
      return (label: 'Destek talebi', icon: Icons.support_agent, color: Colors.teal);
    case 'ilan_created':
      return (label: 'İlan', icon: Icons.campaign_outlined, color: Colors.brown);
    case 'group_joined':
      return (label: 'Grup', icon: Icons.groups_outlined, color: Colors.purple);
    case 'daily_deal_clicked':
      return (label: 'Fırsat tıklaması', icon: Icons.local_fire_department_outlined, color: Colors.deepOrange);
    case 'music_play':
      return (label: 'Müzik', icon: Icons.play_circle_outline, color: Colors.deepPurple);
    case 'music_stopped':
      return (label: 'Müzik kapandı', icon: Icons.stop_circle_outlined, color: Colors.deepPurple);
    default:
      if (action.startsWith('balance_')) {
        return (label: 'Bakiye', icon: Icons.account_balance_wallet_outlined, color: Colors.green);
      }
      return (label: action, icon: Icons.bolt_outlined, color: Colors.blueGrey);
  }
}

const Map<String, String> kAdminCategoryLabels = {
  'auth': 'Oturum',
  'account': 'Hesap',
  'social': 'Sosyal',
  'shop': 'Alışveriş',
  'finance': 'Finans',
  'message': 'Mesaj',
  'music': 'Müzik',
  'engagement': 'Etkileşim',
  'safety': 'Güvenlik',
  'support': 'Destek',
  'listing': 'İlan',
  'app': 'Uygulama',
};
