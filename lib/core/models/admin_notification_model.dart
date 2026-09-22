import 'package:flutter/material.dart';

/// Admin bildirim merkezinde bir bildirimin (kampanyanın) hedef kitlesi.
enum AdminNotifAudience {
  allUsers,
  customers,
  sellers,
  couriers,
  personal;

  /// Sunucudaki `target_audience` değeri.
  String get key => switch (this) {
        AdminNotifAudience.allUsers => 'all_users',
        AdminNotifAudience.customers => 'customers',
        AdminNotifAudience.sellers => 'sellers',
        AdminNotifAudience.couriers => 'couriers',
        AdminNotifAudience.personal => 'personal',
      };

  String get label => switch (this) {
        AdminNotifAudience.allUsers => 'Herkes',
        AdminNotifAudience.customers => 'Müşteriler',
        AdminNotifAudience.sellers => 'Satıcılar',
        AdminNotifAudience.couriers => 'Kuryeler',
        AdminNotifAudience.personal => 'Kişiye özel',
      };

  String get hint => switch (this) {
        AdminNotifAudience.allUsers => 'Tüm kullanıcılar',
        AdminNotifAudience.customers => 'Alışveriş yapanlar',
        AdminNotifAudience.sellers => 'Dükkan sahipleri',
        AdminNotifAudience.couriers => 'Kurye ve sürücüler',
        AdminNotifAudience.personal => 'Seçtiğiniz kişiler',
      };

  IconData get icon => switch (this) {
        AdminNotifAudience.allUsers => Icons.public_rounded,
        AdminNotifAudience.customers => Icons.person_rounded,
        AdminNotifAudience.sellers => Icons.storefront_rounded,
        AdminNotifAudience.couriers => Icons.delivery_dining_rounded,
        AdminNotifAudience.personal => Icons.person_pin_rounded,
      };

  Color get color => switch (this) {
        AdminNotifAudience.allUsers => Colors.blue,
        AdminNotifAudience.customers => Colors.teal,
        AdminNotifAudience.sellers => Colors.orange,
        AdminNotifAudience.couriers => Colors.indigo,
        AdminNotifAudience.personal => Colors.purple,
      };

  /// Eski kayıtlarda 'all' de geçer.
  static AdminNotifAudience fromKey(String? key) {
    for (final a in AdminNotifAudience.values) {
      if (a.key == key) return a;
    }
    return AdminNotifAudience.allUsers;
  }
}

/// Bildirim ikonu (uygulamadaki bildirim kutusunda görünen simge ve renk).
/// `key` sunucudaki `icon_type` ile ve kullanıcı uygulamasının
/// `entity_id = 'admin_icon:<key>'` biçimiyle aynıdır; anahtarlar değişmemeli.
class AdminNotifIcon {
  const AdminNotifIcon(this.key, this.label, this.icon, this.color);

  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

const List<AdminNotifIcon> kAdminNotifIcons = [
  AdminNotifIcon('announcement', 'Duyuru', Icons.campaign_rounded, Colors.blue),
  AdminNotifIcon('discount', 'İndirim', Icons.discount_rounded, Colors.red),
  AdminNotifIcon('campaign', 'Kampanya', Icons.local_offer_rounded, Colors.orange),
  AdminNotifIcon('news', 'Haber', Icons.newspaper_rounded, Colors.teal),
  AdminNotifIcon('event', 'Etkinlik', Icons.event_rounded, Colors.purple),
  AdminNotifIcon('update', 'Güncelleme', Icons.system_update_rounded, Colors.green),
  AdminNotifIcon('warning', 'Uyarı', Icons.warning_amber_rounded, Colors.amber),
  AdminNotifIcon('gift', 'Hediye', Icons.card_giftcard_rounded, Colors.pink),
  AdminNotifIcon('info', 'Bilgi', Icons.info_rounded, Colors.indigo),
];

AdminNotifIcon adminNotifIcon(String? key) {
  for (final i in kAdminNotifIcons) {
    if (i.key == key) return i;
  }
  return kAdminNotifIcons.firstWhere((i) => i.key == 'info');
}

/// Hazır şablon: başlık, metin ve ikon ön dolduran kısayol.
class AdminNotifTemplate {
  const AdminNotifTemplate({
    required this.name,
    required this.iconKey,
    required this.title,
    required this.body,
  });

  final String name;
  final String iconKey;
  final String title;
  final String body;
}

const List<AdminNotifTemplate> kAdminNotifTemplates = [
  AdminNotifTemplate(
    name: 'Yeni kampanya',
    iconKey: 'campaign',
    title: 'Yeni kampanya başladı 🎉',
    body: 'Seçili ürünlerde kaçırılmayacak fırsatlar seni bekliyor. Hemen göz at!',
  ),
  AdminNotifTemplate(
    name: 'Yeni sürüm',
    iconKey: 'update',
    title: 'Yeni sürüm yayında',
    body:
        'CizreApp\'in yeni sürümü mağazalarda. Güncelleyerek yeni özellikleri hemen kullanmaya başla.',
  ),
  AdminNotifTemplate(
    name: 'Bakım bilgisi',
    iconKey: 'warning',
    title: 'Kısa süreli bakım',
    body:
        'Sistemimizde kısa süreli bir bakım çalışması yapılacak. Bu sürede bazı özellikler geçici olarak kullanılamayabilir.',
  ),
  AdminNotifTemplate(
    name: 'Hoş geldin',
    iconKey: 'gift',
    title: 'CizreApp\'e hoş geldin 👋',
    body:
        'Aramıza katıldığın için teşekkürler. Keşfetmeye başlamak için ana sayfaya göz atabilirsin.',
  ),
  AdminNotifTemplate(
    name: 'Etkinlik',
    iconKey: 'event',
    title: 'Bu hafta bir etkinlik var',
    body: 'Detaylar için uygulamayı aç. Seni de aramızda görmek isteriz!',
  ),
  AdminNotifTemplate(
    name: 'Teşekkür',
    iconKey: 'info',
    title: 'Teşekkürler',
    body: 'Bizi tercih ettiğin için teşekkür ederiz. Görüşlerin bizim için çok değerli.',
  ),
];

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Bir gönderim: toplu ya da kişiye özel, gönderilmiş ya da zamanlanmış.
/// `admin_notification_history` RPC satırı.
class AdminNotification {
  const AdminNotification({
    required this.id,
    required this.title,
    required this.content,
    required this.iconType,
    required this.audience,
    required this.isScheduled,
    required this.recipientCount,
    required this.readCount,
    required this.liveCount,
    this.scheduledFor,
    this.sentAt,
    this.createdAt,
    this.editedAt,
    this.createdByName,
    this.recipientNames = const [],
  });

  final String id;
  final String title;
  final String content;
  final String iconType;
  final AdminNotifAudience audience;
  final bool isScheduled;
  final DateTime? scheduledFor;
  final DateTime? sentAt;
  final DateTime? createdAt;
  final DateTime? editedAt;

  /// Gönderim anındaki alıcı sayısı (kullanıcı kendi satırını silse de değişmez).
  final int recipientCount;

  /// Okunmuş alıcı satırı sayısı.
  final int readCount;

  /// Şu an bildirim kutusunda duran alıcı satırı sayısı.
  final int liveCount;
  final String? createdByName;

  /// Kişiye özelde ilk birkaç alıcının adı.
  final List<String> recipientNames;

  bool get isPersonal => audience == AdminNotifAudience.personal;
  bool get isEdited => editedAt != null;
  AdminNotifIcon get icon => adminNotifIcon(iconType);

  /// Listede sıralama/gruplama zamanı.
  DateTime get when => sentAt ?? scheduledFor ?? createdAt ?? DateTime.now();

  double get readRate =>
      recipientCount <= 0 ? 0 : (readCount / recipientCount).clamp(0.0, 1.0);

  int get unreadCount => (recipientCount - readCount).clamp(0, recipientCount);

  /// "Müşteriler", "Ayşe Kaya", "Ayşe, Ali +3 kişi".
  String get audienceLabel {
    if (!isPersonal) return audience.label;
    final total = recipientCount > 0 ? recipientCount : recipientNames.length;
    if (recipientNames.isEmpty) {
      return total > 0 ? '$total kişi' : audience.label;
    }
    if (total <= 1) return recipientNames.first;
    final shown = recipientNames.take(2).toList();
    final extra = total - shown.length;
    return extra > 0 ? '${shown.join(', ')} +$extra kişi' : shown.join(', ');
  }

  factory AdminNotification.fromJson(Map<String, dynamic> j) {
    final names = (j['recipient_names'] as List?)
            ?.map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    return AdminNotification(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      content: (j['content'] as String?) ?? '',
      iconType: (j['icon_type'] as String?) ?? 'info',
      audience: AdminNotifAudience.fromKey(j['target_audience'] as String?),
      isScheduled: j['status'] == 'scheduled',
      scheduledFor: _date(j['scheduled_for']),
      sentAt: _date(j['sent_at']),
      createdAt: _date(j['created_at']),
      editedAt: _date(j['edited_at']),
      recipientCount: _int(j['recipient_count']),
      readCount: _int(j['read_count']),
      liveCount: _int(j['live_count']),
      createdByName: j['created_by_name'] as String?,
      recipientNames: names,
    );
  }
}

/// Bir bildirimin alıcısı ve okuma durumu.
class AdminNotificationRecipient {
  const AdminNotificationRecipient({
    required this.userId,
    required this.isRead,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.role,
    this.deliveredAt,
  });

  final String userId;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final String? role;
  final bool isRead;
  final DateTime? deliveredAt;

  String get displayName {
    final full = fullName?.trim() ?? '';
    if (full.isNotEmpty) return full;
    final u = username?.trim() ?? '';
    if (u.isNotEmpty) return u;
    return 'Silinmiş kullanıcı';
  }

  factory AdminNotificationRecipient.fromJson(Map<String, dynamic> j) =>
      AdminNotificationRecipient(
        userId: j['user_id'] as String,
        username: j['username'] as String?,
        fullName: j['full_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        role: j['role'] as String?,
        isRead: j['is_read'] == true,
        deliveredAt: _date(j['delivered_at']),
      );
}

/// Kişiye özel gönderimde alıcı seçicisinde gösterilen kullanıcı.
class AdminNotifUser {
  const AdminNotifUser({
    required this.id,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.role,
  });

  final String id;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final String? role;

  String get displayName {
    final full = fullName?.trim() ?? '';
    if (full.isNotEmpty) return full;
    final u = username?.trim() ?? '';
    return u.isNotEmpty ? u : 'Kullanıcı';
  }

  factory AdminNotifUser.fromJson(Map<String, dynamic> j) => AdminNotifUser(
        id: j['id'] as String,
        username: j['username'] as String?,
        fullName: j['full_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        role: j['role'] as String?,
      );
}

/// Gönderim sonucu (admin_send_notification / admin_send_notification_campaign_now).
class AdminNotifSendResult {
  const AdminNotifSendResult({
    required this.campaignId,
    required this.isScheduled,
    required this.recipientCount,
    this.scheduledFor,
  });

  final String campaignId;
  final bool isScheduled;
  final int recipientCount;
  final DateTime? scheduledFor;

  factory AdminNotifSendResult.fromJson(Map<String, dynamic> j) =>
      AdminNotifSendResult(
        campaignId: '${j['campaign_id']}',
        isScheduled: j['status'] == 'scheduled',
        recipientCount: _int(j['recipient_count']),
        scheduledFor: _date(j['scheduled_for']),
      );
}
