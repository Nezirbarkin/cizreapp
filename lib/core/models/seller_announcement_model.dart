import 'package:flutter/material.dart';

/// Duyuru kartının türü. Renk ve ikon türe bağlıdır; böylece satıcı kartın
/// önemini rengine bakarak anlar.
enum AnnouncementType { urgent, warn, promo, info, ok }

/// Türün görsel kimliği (kart arka planı, kenarlığı, yazı ve ikon renkleri).
class AnnouncementStyle {
  final String label;
  final String hint;
  final IconData icon;
  final Color background;
  final Color border;
  final Color title;
  final Color text;
  final Color iconBackground;
  final Color iconColor;

  const AnnouncementStyle({
    required this.label,
    required this.hint,
    required this.icon,
    required this.background,
    required this.border,
    required this.title,
    required this.text,
    required this.iconBackground,
    required this.iconColor,
  });
}

extension AnnouncementTypeX on AnnouncementType {
  String get key => name;

  static AnnouncementType fromKey(String? key) => AnnouncementType.values
      .firstWhere((t) => t.name == key, orElse: () => AnnouncementType.info);

  AnnouncementStyle get style {
    switch (this) {
      case AnnouncementType.urgent:
        return const AnnouncementStyle(
          label: 'Acil',
          hint: 'Kapatılamaz, her zaman en üstte',
          icon: Icons.report_gmailerrorred_rounded,
          background: Color(0xFFFCEBEB),
          border: Color(0xFFF09595),
          title: Color(0xFF791F1F),
          text: Color(0xFFA32D2D),
          iconBackground: Color(0xFFF7C1C1),
          iconColor: Color(0xFFA32D2D),
        );
      case AnnouncementType.warn:
        return const AnnouncementStyle(
          label: 'Uyarı',
          hint: 'Dikkat gerektiren değişiklikler',
          icon: Icons.warning_amber_rounded,
          background: Color(0xFFFAEEDA),
          border: Color(0xFFFAC775),
          title: Color(0xFF633806),
          text: Color(0xFF854F0B),
          iconBackground: Color(0xFFFAC775),
          iconColor: Color(0xFF854F0B),
        );
      case AnnouncementType.promo:
        return const AnnouncementStyle(
          label: 'Kampanya',
          hint: 'Kampanya ve fırsat duyuruları',
          icon: Icons.campaign_rounded,
          background: Color(0xFFFFF3E0),
          border: Color(0xFFFFCC80),
          title: Color(0xFFBF360C),
          text: Color(0xFFB45309),
          iconBackground: Color(0xFFFFE0B2),
          iconColor: Color(0xFFE65100),
        );
      case AnnouncementType.info:
        return const AnnouncementStyle(
          label: 'Bilgi',
          hint: 'Yeni özellik, ipucu, rehber',
          icon: Icons.info_outline_rounded,
          background: Color(0xFFE6F1FB),
          border: Color(0xFFB5D4F4),
          title: Color(0xFF0C447C),
          text: Color(0xFF185FA5),
          iconBackground: Color(0xFFB5D4F4),
          iconColor: Color(0xFF185FA5),
        );
      case AnnouncementType.ok:
        return const AnnouncementStyle(
          label: 'Tebrik',
          hint: 'Başarı ve teşekkür mesajları',
          icon: Icons.emoji_events_outlined,
          background: Color(0xFFEAF3DE),
          border: Color(0xFFC0DD97),
          title: Color(0xFF27500A),
          text: Color(0xFF3B6D11),
          iconBackground: Color(0xFFC0DD97),
          iconColor: Color(0xFF3B6D11),
        );
    }
  }
}

/// Kartın kimlere gösterileceği. Süzme sunucuda yapılır (bkz.
/// get_my_seller_announcements).
enum AnnouncementAudience { all, noCourier, ownCourier, shops }

extension AnnouncementAudienceX on AnnouncementAudience {
  String get key {
    switch (this) {
      case AnnouncementAudience.all:
        return 'all';
      case AnnouncementAudience.noCourier:
        return 'no_courier';
      case AnnouncementAudience.ownCourier:
        return 'own_courier';
      case AnnouncementAudience.shops:
        return 'shops';
    }
  }

  String get label {
    switch (this) {
      case AnnouncementAudience.all:
        return 'Tüm satıcılar';
      case AnnouncementAudience.noCourier:
        return 'Kendi kuryesi olmayanlar';
      case AnnouncementAudience.ownCourier:
        return 'Kendi kuryesi olanlar';
      case AnnouncementAudience.shops:
        return 'Belirli mağazalar';
    }
  }

  static AnnouncementAudience fromKey(String? key) =>
      AnnouncementAudience.values.firstWhere(
        (a) => a.key == key,
        orElse: () => AnnouncementAudience.all,
      );
}

/// Eylem butonunun götüreceği yer.
enum AnnouncementTarget {
  products,
  orders,
  payments,
  coupons,
  reviews,
  shopSettings,
  url,
}

extension AnnouncementTargetX on AnnouncementTarget {
  String get key {
    switch (this) {
      case AnnouncementTarget.shopSettings:
        return 'shop_settings';
      default:
        return name;
    }
  }

  String get label {
    switch (this) {
      case AnnouncementTarget.products:
        return 'Ürünlerim';
      case AnnouncementTarget.orders:
        return 'Siparişler';
      case AnnouncementTarget.payments:
        return 'Ödemeler';
      case AnnouncementTarget.coupons:
        return 'Kuponlar';
      case AnnouncementTarget.reviews:
        return 'Yorumlar';
      case AnnouncementTarget.shopSettings:
        return 'Mağaza ayarları';
      case AnnouncementTarget.url:
        return 'Harici bağlantı';
    }
  }

  static AnnouncementTarget? fromKey(String? key) {
    if (key == null) return null;
    for (final t in AnnouncementTarget.values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// Admin listesinde görünen yayın durumu.
enum AnnouncementStatus { draft, scheduled, live, ended }

class SellerAnnouncement {
  final String? id;
  final AnnouncementType type;
  final String title;
  final String message;
  final String? actionLabel;
  final AnnouncementTarget? actionTarget;
  final String? actionUrl;
  final AnnouncementAudience audience;
  final List<String> shopIds;
  final bool isDismissible;
  final bool isPinned;
  final bool isPublished;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;

  /// Satıcı tarafı: bu satıcı kartı henüz görmedi (turuncu "yeni" noktası).
  final bool isNew;

  /// Admin tarafı sayaçları.
  final int seenCount;
  final int dismissedCount;
  final int targetCount;

  const SellerAnnouncement({
    this.id,
    this.type = AnnouncementType.info,
    this.title = '',
    this.message = '',
    this.actionLabel,
    this.actionTarget,
    this.actionUrl,
    this.audience = AnnouncementAudience.all,
    this.shopIds = const [],
    this.isDismissible = true,
    this.isPinned = false,
    this.isPublished = false,
    this.startsAt,
    this.endsAt,
    this.createdAt,
    this.isNew = false,
    this.seenCount = 0,
    this.dismissedCount = 0,
    this.targetCount = 0,
  });

  bool get hasAction =>
      actionTarget != null && (actionLabel?.trim().isNotEmpty ?? false);

  AnnouncementStatus statusAt(DateTime now) {
    if (!isPublished) return AnnouncementStatus.draft;
    if (startsAt != null && startsAt!.isAfter(now)) {
      return AnnouncementStatus.scheduled;
    }
    if (endsAt != null && !endsAt!.isAfter(now)) return AnnouncementStatus.ended;
    return AnnouncementStatus.live;
  }

  SellerAnnouncement copyWith({
    AnnouncementType? type,
    String? title,
    String? message,
    String? actionLabel,
    AnnouncementTarget? actionTarget,
    String? actionUrl,
    bool clearAction = false,
    AnnouncementAudience? audience,
    List<String>? shopIds,
    bool? isDismissible,
    bool? isPinned,
    bool? isPublished,
    DateTime? startsAt,
    bool clearStartsAt = false,
    DateTime? endsAt,
    bool clearEndsAt = false,
  }) {
    return SellerAnnouncement(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      actionLabel: clearAction ? null : (actionLabel ?? this.actionLabel),
      actionTarget: clearAction ? null : (actionTarget ?? this.actionTarget),
      actionUrl: clearAction ? null : (actionUrl ?? this.actionUrl),
      audience: audience ?? this.audience,
      shopIds: shopIds ?? this.shopIds,
      isDismissible: isDismissible ?? this.isDismissible,
      isPinned: isPinned ?? this.isPinned,
      isPublished: isPublished ?? this.isPublished,
      startsAt: clearStartsAt ? null : (startsAt ?? this.startsAt),
      endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
      createdAt: createdAt,
      isNew: isNew,
      seenCount: seenCount,
      dismissedCount: dismissedCount,
      targetCount: targetCount,
    );
  }

  factory SellerAnnouncement.fromJson(Map<String, dynamic> json) {
    DateTime? date(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    int count(dynamic v) => (v as num?)?.toInt() ?? 0;

    return SellerAnnouncement(
      id: json['id'] as String?,
      type: AnnouncementTypeX.fromKey(json['type'] as String?),
      title: (json['title'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      actionLabel: json['action_label'] as String?,
      actionTarget: AnnouncementTargetX.fromKey(json['action_target'] as String?),
      actionUrl: json['action_url'] as String?,
      audience: AnnouncementAudienceX.fromKey(json['audience'] as String?),
      shopIds: ((json['shop_ids'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      isDismissible: json['is_dismissible'] as bool? ?? true,
      isPinned: json['is_pinned'] as bool? ?? false,
      isPublished: json['is_published'] as bool? ?? false,
      startsAt: date(json['starts_at']),
      endsAt: date(json['ends_at']),
      createdAt: date(json['created_at']),
      isNew: json['is_new'] as bool? ?? false,
      seenCount: count(json['seen_count']),
      dismissedCount: count(json['dismissed_count']),
      targetCount: count(json['target_count']),
    );
  }

  /// INSERT/UPDATE yükü. Hedef kitle "belirli mağazalar" değilse mağaza
  /// listesi boşaltılır; eylem yoksa üç eylem alanı birlikte null olur (DB
  /// CHECK'i ikisinin birlikte dolu/boş olmasını ister). Acil kart asla
  /// kapatılabilir kaydedilmez.
  Map<String, dynamic> toDbPayload() {
    final action = hasAction;
    return {
      'type': type.key,
      'title': title.trim(),
      'message': message.trim(),
      'action_label': action ? actionLabel!.trim() : null,
      'action_target': action ? actionTarget!.key : null,
      'action_url': action && actionTarget == AnnouncementTarget.url
          ? actionUrl?.trim()
          : null,
      'audience': audience.key,
      'shop_ids':
          audience == AnnouncementAudience.shops ? shopIds : const <String>[],
      'is_dismissible': type == AnnouncementType.urgent ? false : isDismissible,
      'is_pinned': isPinned,
      'is_published': isPublished,
      'starts_at': (startsAt ?? DateTime.now()).toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
    };
  }
}
