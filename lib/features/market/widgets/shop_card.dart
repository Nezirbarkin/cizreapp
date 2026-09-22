import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/models/shop_model.dart';
import '../../../core/theme/app_theme.dart';
import '../screens/shop_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bilgi katmanı: kartın hangi metni/durumu göstereceğine dair TÜM kararlar
// burada. Widget yalnızca çizer; böylece durum önceliği, etiket biçimleri ve
// "Yeni" kuralı widget ağacı kurulmadan test edilebilir.
// ─────────────────────────────────────────────────────────────────────────────

/// Kartın tek bir durum etiketine indirgenmiş hâli. Öncelik sırası (yukarıdan
/// aşağı): global sipariş kapalı > dükkan geçici kapalı > çalışma saati dışı.
enum ShopStatusKind { open, closed, paused, ordersOff }

/// "Yeni" rozeti için dükkanın kaç gün yeni sayılacağı.
const Duration _kNewShopWindow = Duration(days: 45);

@immutable
class ShopCardInfo {
  const ShopCardInfo({
    required this.status,
    required this.tagline,
    required this.rating,
    required this.reviewCount,
    required this.isNew,
    required this.deliveryTime,
    required this.deliveryFee,
    required this.freeDelivery,
    required this.freeOver,
    required this.minOrder,
    required this.pickup,
    required this.coupon,
    required this.sponsored,
    required this.notice,
  });

  final ShopStatusKind status;

  /// Açıklamanın ilk satırı. Satıcılar açıklamaya telefon, emoji, kullanım
  /// talimatı gibi uzun metinler yapıştırıyor; kartta yalnızca slogan kalır.
  final String? tagline;

  /// "4.0"; henüz puan yoksa null (kartta "0.0" göstermek yanıltıcı olurdu).
  final String? rating;
  final int reviewCount;

  /// Puansız ve yakın zamanda açılmış dükkan.
  final bool isNew;
  final String? deliveryTime;

  /// "Ücretsiz teslimat" ya da yalnızca tutar ("₺29"; kartta teslimat simgesiyle).
  final String deliveryFee;
  final bool freeDelivery;

  /// "₺750 üzeri ücretsiz" (yalnızca teslimat ücretliyse ve eşik tanımlıysa).
  final String? freeOver;
  final String? minOrder;
  final bool pickup;
  final bool coupon;
  final bool sponsored;

  /// Kartın altındaki durum şeridi. Yalnızca ek bilgi taşıyorsa doludur.
  final String? notice;

  bool get isOpen => status == ShopStatusKind.open;

  /// Sipariş verilemeyen durumlar (global kapalı ya da dükkan geçici kapalı).
  bool get ordersBlocked =>
      status == ShopStatusKind.paused || status == ShopStatusKind.ordersOff;

  String get statusLabel => isOpen ? 'Açık' : 'Kapalı';

  factory ShopCardInfo.from(
    Shop shop, {
    required bool globalOrdersEnabled,
    bool hasCoupon = false,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();

    final status = !globalOrdersEnabled
        ? ShopStatusKind.ordersOff
        : !shop.isAcceptingOrders
        ? ShopStatusKind.paused
        : !shop.isOpen
        ? ShopStatusKind.closed
        : ShopStatusKind.open;

    final rating = shop.rating > 0 ? shop.rating.toStringAsFixed(1) : null;
    final isNew =
        rating == null &&
        shop.reviewCount == 0 &&
        clock.difference(shop.createdAt) < _kNewShopWindow;

    final fee = shop.deliveryFee;
    final freeMin = shop.freeDeliveryMinAmount ?? 0;
    final free = fee <= 0;

    final String? notice;
    switch (status) {
      case ShopStatusKind.ordersOff:
        notice = 'Sipariş alma şu anda kapalı';
      case ShopStatusKind.paused:
        notice = 'Geçici kapalı · şu an sipariş almıyor';
      case ShopStatusKind.closed:
        final opensAt = shopOpensAtLabel(
          shop,
          nowTurkey: clock.toUtc().add(const Duration(hours: 3)),
        );
        notice = opensAt == null ? null : 'Şu an kapalı · $opensAt';
      case ShopStatusKind.open:
        notice = null;
    }

    return ShopCardInfo(
      status: status,
      tagline: shopTagline(shop.description),
      rating: rating,
      reviewCount: shop.reviewCount,
      isNew: isNew,
      deliveryTime: shopDeliveryTimeLabel(shop.deliveryTime),
      deliveryFee: free ? 'Ücretsiz teslimat' : formatShopMoney(fee),
      freeDelivery: free,
      freeOver: !free && freeMin > 0
          ? '${formatShopMoney(freeMin)} üzeri ücretsiz'
          : null,
      minOrder: shop.minOrderAmount > 0
          ? 'Min. ${formatShopMoney(shop.minOrderAmount)}'
          : null,
      pickup: shop.pickupEnabled,
      coupon: hasCoupon,
      sponsored: shop.isPinned,
      notice: notice,
    );
  }
}

/// "₺29" / "₺12,50". Kuruşlu tutarı tam sayıya yuvarlamak yanıltıcı olur
/// (ör. 0,08 → "₺0"); bu yüzden yalnızca tam sayıysa kuruşsuz yazılır.
String formatShopMoney(double amount) {
  if (amount == amount.roundToDouble()) return '₺${amount.toInt()}';
  return '₺${amount.toStringAsFixed(2).replaceAll('.', ',')}';
}

/// Açıklamanın ilk dolu satırı (boşluklar toparlanmış); yoksa null.
String? shopTagline(String? description) {
  if (description == null) return null;
  for (final line in description.split(RegExp(r'[\r\n]+'))) {
    final text = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// "30-60 dakika" → "30-60 dk"; salt sayı/aralık → "45 dk"; "Otomatik" olduğu
/// gibi kalır (dijital hizmet dükkanları serbest metin giriyor).
String? shopDeliveryTimeLabel(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  if (RegExp(r'^\d+(\s*[-–]\s*\d+)?$').hasMatch(text)) return '$text dk';
  return text.replaceAll(RegExp(r'\bdakika\b', caseSensitive: false), 'dk');
}

const List<String> _dayKeys = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

const List<String> _dayNames = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

int? _minutesOf(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Kapalı bir dükkanın ilk sonraki açılışı: "Açılış: 09:00", "Açılış: yarın
/// 09:00" ya da "Açılış: Pazartesi 09:00". Elle kapatılmışsa ya da çalışma
/// saati okunamıyorsa null (olmayan bir vaat verilmez).
///
/// Türkiye saati (UTC+3) — [Shop.isOpen] ile aynı saat dilimi.
String? shopOpensAtLabel(Shop shop, {DateTime? nowTurkey}) {
  if (shop.isManuallyClosed) return null;
  final hours = shop.workingHours;
  if (hours == null || hours.isEmpty) return null;

  final now = nowTurkey ?? DateTime.now().toUtc().add(const Duration(hours: 3));
  final nowMinutes = now.hour * 60 + now.minute;

  for (var offset = 0; offset < 8; offset++) {
    final index = (now.weekday - 1 + offset) % 7;
    final day = hours[_dayKeys[index]];
    if (day is! Map || day['active'] == false) continue;
    final open = day['open'];
    if (open is! String) continue;
    final openMinutes = _minutesOf(open);
    if (openMinutes == null) continue;
    // Bugünkü açılış saati geçtiyse (kapanış sonrası) sıradaki güne bak.
    if (offset == 0 && openMinutes <= nowMinutes) continue;

    final when = offset == 0
        ? open
        : offset == 1
        ? 'yarın $open'
        : '${_dayNames[index]} $open';
    return 'Açılış: $when';
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dükkan kartı
// ─────────────────────────────────────────────────────────────────────────────

const double _kCardRadius = 18;

/// Açık amber (shade50) zeminler üzerindeki metin/ikon rengi (≈7:1 kontrast).
const Color _kAmberInk = Color(0xFF92400E);

/// Ana sayfadaki "Dükkanlar", "Tüm Dükkanlar", kategori içi ve arama
/// sonuçlarında kullanılan TEK dükkan kartı.
///
/// Tasarım kararları:
///  * Kimlik logoda; kapak görseli kullanılmaz. Satıcıların kapakları çoğunlukla
///    metni görsele gömülü logo düzenleri ve oranları 1:1 ile 2,5:1 arasında —
///    geniş bir şeride kırpınca ortadan kesiliyor.
///  * Kapalı dükkan kartı bütün olarak soluklaştırılmaz (okunmaz hâle geliyordu);
///    logo gri tonlanır ve altta ne olduğunu söyleyen bir durum şeridi çıkar.
///  * "Sponsor" (sabitlenmiş) dükkan uygulamanın diğer yerlerindeki (hikâye,
///    ürün) amber "Sponsor" diliyle üstte ince bir şeritle işaretlenir.
///
/// Kupon var mı ve uzaklık gibi liste düzeyinde hesaplanan veriler dışarıdan
/// verilir; kart kendi başına ağ isteği atmaz.
class ShopCard extends StatelessWidget {
  const ShopCard({
    super.key,
    required this.shop,
    this.globalOrdersEnabled = true,
    this.hasCoupon = false,
    this.distanceLabel,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.logoImageProvider,
  });

  final Shop shop;

  /// false ise tüm dükkanlarda sipariş alma kapalıdır (admin ayarı).
  final bool globalOrdersEnabled;

  /// Dükkanın şu an geçerli kuponu var mı ([ShopService.getShopIdsWithActiveCoupons]).
  final bool hasCoupon;

  /// "850 m" / "1,2 km"; konum bilinmiyorsa null.
  final String? distanceLabel;
  final EdgeInsetsGeometry margin;

  /// Verilmezse dükkan detay sayfası açılır.
  final VoidCallback? onTap;

  /// Yalnızca testler için: ağ yerine bu görseli kullanır.
  final ImageProvider? logoImageProvider;

  void _open(BuildContext context) {
    final custom = onTap;
    if (custom != null) {
      custom();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: shop.id)),
    );
  }

  String _semanticsLabel(ShopCardInfo info) {
    final parts = <String>[shop.name];
    if (shop.isVerified) parts.add('doğrulanmış dükkan');
    if (info.sponsored) parts.add('sponsor');
    parts.add(info.isOpen ? 'açık' : (info.notice ?? 'kapalı'));
    if (info.rating != null) {
      parts.add(
        info.reviewCount > 0
            ? 'puan ${info.rating}, ${info.reviewCount} değerlendirme'
            : 'puan ${info.rating}',
      );
    } else if (info.isNew) {
      parts.add('yeni dükkan');
    }
    if (info.deliveryTime != null) parts.add('teslimat ${info.deliveryTime}');
    if (distanceLabel != null) parts.add('$distanceLabel uzaklıkta');
    parts.add(
      info.freeDelivery
          ? info.deliveryFee
          : 'teslimat ücreti ${info.deliveryFee}',
    );
    if (info.freeOver != null) parts.add('teslimat ${info.freeOver!}');
    if (info.minOrder != null) parts.add(info.minOrder!);
    if (info.pickup) parts.add('gel al seçeneği var');
    if (info.coupon) parts.add('kupon var');
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final info = ShopCardInfo.from(
      shop,
      globalOrdersEnabled: globalOrdersEnabled,
      hasCoupon: hasCoupon,
    );
    final muted = !info.isOpen;
    final radius = BorderRadius.circular(_kCardRadius);

    final chips = <Widget>[
      if (info.coupon) const _CouponChip(),
      _ShopChip(
        icon: Icons.delivery_dining_rounded,
        label: info.deliveryFee,
        tone: info.freeDelivery ? _ChipTone.green : _ChipTone.neutral,
      ),
      if (info.freeOver != null)
        _ShopChip(
          icon: Icons.delivery_dining_rounded,
          label: info.freeOver!,
          tone: _ChipTone.green,
        ),
      if (info.minOrder != null)
        _ShopChip(icon: Icons.shopping_bag_outlined, label: info.minOrder!),
      if (info.pickup)
        const _ShopChip(
          icon: Icons.storefront_rounded,
          label: 'Gel Al',
          tone: _ChipTone.blue,
        ),
    ];

    return Padding(
      padding: margin,
      child: Semantics(
        container: true,
        button: true,
        excludeSemantics: true,
        label: _semanticsLabel(info),
        onTap: () => _open(context),
        child: Container(
          // Kenarlık içeriğin ÜSTÜNDE çizilir (foregroundDecoration): şeritler
          // köşelere kadar uzansa da çerçeveyi örtmez.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: info.sponsored
                  ? Colors.amber.shade300
                  : Colors.black.withValues(alpha: 0.07),
              width: info.sponsored ? 1.4 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => _open(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (info.sponsored) const _SponsorStrip(),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShopLogoTile(
                              name: shop.name,
                              logoUrl: shop.logoUrl,
                              muted: muted,
                              imageProvider: logoImageProvider,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Headline(
                                shop: shop,
                                info: info,
                                distanceLabel: distanceLabel,
                                muted: muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Kapalı dükkanda kampanya/koşul chip'leri soluk durur;
                        // kartın tamamı değil, yalnızca bu satır (okunabilirlik).
                        Opacity(
                          opacity: muted ? 0.6 : 1,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: chips,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (info.notice != null)
                    _NoticeStrip(status: info.status, text: info.notice!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ad, doğrulama rozeti, slogan ve durum/puan/süre/uzaklık satırı.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.shop,
    required this.info,
    required this.distanceLabel,
    required this.muted,
  });

  final Shop shop;
  final ShopCardInfo info;
  final String? distanceLabel;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tagline = info.tagline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ad 2 satıra kadar açılır: BÜYÜK HARFLİ uzun adlar ("CİZRE MEMİLHEVA
        // KURABİYE") tek satırda kesilip tanınmaz hâle geliyordu. Doğrulama
        // rozeti adın son satırında, adın hemen yanında durur.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: shop.name),
              if (shop.isVerified)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: muted ? AppTheme.gray600 : AppTheme.gray900,
          ),
        ),
        // Slogan + (varsa) uzaklık. Uzaklık meta satırına konunca 360 dp'de her
        // kartı ikinci satıra taşıyordu; slogan zaten kısalabilir bir metin.
        if (tagline != null || distanceLabel != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  tagline ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    color: AppTheme.gray500,
                  ),
                ),
              ),
              if (distanceLabel != null) ...[
                const SizedBox(width: 8),
                // Üst sınır: çok büyük yazı ölçeğinde slogan satırını
                // taşırmasın (slogan kalan alanı alır, gerekirse kısalır).
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: _MetaItem(
                    icon: Icons.near_me_rounded,
                    iconSize: 13,
                    label: distanceLabel!,
                    iconColor: Colors.blueGrey.shade400,
                    textColor: Colors.blueGrey.shade700,
                    bold: true,
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 7),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusLabel(open: info.isOpen),
            if (info.rating != null)
              _RatingLabel(rating: info.rating!, reviewCount: info.reviewCount)
            else if (info.isNew)
              const _NewBadge(),
            if (info.deliveryTime != null)
              _MetaItem(
                icon: RegExp(r'\d').hasMatch(info.deliveryTime!)
                    ? Icons.schedule_rounded
                    : Icons.bolt_rounded,
                label: info.deliveryTime!,
                iconColor: AppTheme.gray400,
                textColor: AppTheme.gray600,
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final dot = open ? Colors.green.shade500 : Colors.red.shade500;
    final text = open ? Colors.green.shade700 : Colors.red.shade700;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            open ? 'Açık' : 'Kapalı',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingLabel extends StatelessWidget {
  const _RatingLabel({required this.rating, required this.reviewCount});

  final String rating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 15, color: Colors.amber.shade600),
        const SizedBox(width: 2),
        Text(
          rating,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.gray800,
          ),
        ),
        if (reviewCount > 0)
          Flexible(
            child: Text(
              ' ($reviewCount)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.gray400),
            ),
          ),
      ],
    );
  }
}

/// Puansız ve yeni açılmış dükkan için "0.0" yerine gösterilir. Tema renginden
/// türer (sabit marka rengi eklenmez).
class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 11, color: primary),
          const SizedBox(width: 3),
          Text(
            'Yeni',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
    this.iconSize = 14,
    this.bold = false,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  final double iconSize;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: iconColor),
        const SizedBox(width: 3),
        // Teslimat süresi satıcının yazdığı serbest metin; uzunsa satırı
        // taşırmak yerine kısaltılır.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}

enum _ChipTone { neutral, green, blue }

class _ShopChip extends StatelessWidget {
  const _ShopChip({
    required this.icon,
    required this.label,
    this.tone = _ChipTone.neutral,
  });

  final IconData icon;
  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (tone) {
      case _ChipTone.neutral:
        bg = AppTheme.gray100;
        fg = AppTheme.gray600;
      case _ChipTone.green:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
      case _ChipTone.blue:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.1,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Kupon Var". Eskiden bütün rozet yanıp sönüyordu; birden çok kartta aynı
/// anda göz yoruyor ve hareketi kısıtlayan kullanıcılar için sorun oluyordu.
/// Artık yalnızca bilet simgesi hafifçe nabız atar, sistem "animasyonları
/// azalt" ayarındaysa hiç oynamaz.
class _CouponChip extends StatefulWidget {
  const _CouponChip();

  @override
  State<_CouponChip> createState() => _CouponChipState();
}

class _CouponChipState extends State<_CouponChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _pulse = Tween<double>(
    begin: 0.35,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFFB45309);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFCE9E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _pulse,
            child: const Icon(
              Icons.confirmation_number_rounded,
              size: 13,
              color: Color(0xFFEA580C),
            ),
          ),
          const SizedBox(width: 4),
          const Flexible(
            child: Text(
              'Kupon Var',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sabitlenmiş (sponsor) dükkanın üstündeki ince şerit.
class _SponsorStrip extends StatelessWidget {
  const _SponsorStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border(bottom: BorderSide(color: Colors.amber.shade100)),
      ),
      child: Row(
        children: [
          Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade700),
          const SizedBox(width: 4),
          const Text(
            'Sponsor',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: _kAmberInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartın altındaki durum şeridi (geçici kapalı / sipariş kapalı / açılış).
class _NoticeStrip extends StatelessWidget {
  const _NoticeStrip({required this.status, required this.text});

  final ShopStatusKind status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    switch (status) {
      case ShopStatusKind.paused:
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        icon = Icons.pause_circle_filled_rounded;
      case ShopStatusKind.ordersOff:
        bg = Colors.amber.shade50;
        fg = _kAmberInk;
        icon = Icons.block_rounded;
      case ShopStatusKind.closed:
      case ShopStatusKind.open:
        bg = AppTheme.gray100;
        fg = AppTheme.gray600;
        icon = Icons.schedule_rounded;
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logo karosu
// ─────────────────────────────────────────────────────────────────────────────

const ColorFilter _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// Dükkan logosu. Logolar rastgele oranlarda geliyor (yatay yazılı düzen, dikey
/// vitrin fotoğrafı, kare amblem); `BoxFit.cover` bunları kırpıp yazıyı
/// kesiyordu. Burada görsel HİÇ kırpılmadan (`contain`) gösterilir, kalan
/// boşluk aynı görselin yumuşak renk alanıyla dolar — böylece koyu zeminli bir
/// logo beyaz bir karonun içinde şerit gibi durmaz.
///
/// Yumuşak zemin gerçek bir Gauss bulanıklığıyla (`ImageFiltered`) elde edilir,
/// kenarları `TileMode.mirror` ile sarılır. Önce görseli birkaç piksele
/// küçültüp büyütme yolu denendi: yüksek kaliteli upsample filtresi keskin
/// renk sınırlarında "ringing" yapıyor (SALIPAZARI'nin vitrin fotoğrafındaki
/// koyu pencere/kutu kenarlarında hayalet leke/halka olarak görünüyor);
/// gerçek bulanıklıkta bu yok. `TileMode.mirror` şart — varsayılan `decal`
/// kenarları şeffaflığa soldurup köşelerde renk sızıntısı yapıyordu.
///
/// Görsel gelene kadar (ya da hiç yoksa/yüklenemezse) baş harf gösterilir.
class ShopLogoTile extends StatelessWidget {
  const ShopLogoTile({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 68,
    this.muted = false,
    this.imageProvider,
  });

  final String name;
  final String? logoUrl;
  final double size;

  /// Kapalı dükkan: gri tonlama.
  final bool muted;

  /// Yalnızca testler için: ağ yerine bu görseli kullanır.
  final ImageProvider? imageProvider;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    final ImageProvider? base =
        imageProvider ??
        ((url == null || url.isEmpty) ? null : CachedNetworkImageProvider(url));
    final radius = BorderRadius.circular(size * 0.24);

    Widget tile = ClipRRect(
      borderRadius: radius,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _InitialFallback(name: name, size: size),
            if (base != null) _LogoImage(provider: base),
          ],
        ),
      ),
    );

    if (muted) tile = ColorFiltered(colorFilter: _grayscale, child: tile);

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: tile,
    );
  }
}

/// Logonun kendisi + yumuşak zemini. Tüm grup, görselin ilk karesi gelince tek
/// parça hâlinde belirir; beyaz taban, şeffaf PNG logoların arkasından baş
/// harfin sızmasını engeller.
class _LogoImage extends StatelessWidget {
  const _LogoImage({required this.provider});

  final ImageProvider provider;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ResizeImage(provider, width: 220),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        return AnimatedOpacity(
          opacity: (wasSynchronouslyLoaded || frame != null) ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.white),
              ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 8,
                  sigmaY: 8,
                  tileMode: TileMode.mirror,
                ),
                child: Image(
                  image: ResizeImage(provider, width: 48),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              child,
            ],
          ),
        );
      },
      // Hata olursa alttaki baş harf karosu görünür kalır.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

class _InitialFallback extends StatelessWidget {
  const _InitialFallback({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: 0.18),
            primary.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Center(
        child: Text(
          shopInitial(name),
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            color: primary,
          ),
        ),
      ),
    );
  }
}

/// Baş harf. Dart'ın `toUpperCase`'i 'i' → 'I' yapar (Türkçe'de 'İ' olmalı).
String shopInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final first = String.fromCharCode(trimmed.runes.first);
  switch (first) {
    case 'i':
      return 'İ';
    case 'ı':
      return 'I';
    default:
      return first.toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yükleme iskeleti
// ─────────────────────────────────────────────────────────────────────────────

/// Dükkan listesi yüklenirken kartın iskeleti (dönen çember yerine): liste
/// geldiğinde içerik zıplamaz.
class ShopCardSkeleton extends StatelessWidget {
  const ShopCardSkeleton({
    super.key,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final EdgeInsetsGeometry margin;

  static Widget _block(double? width, double height, [double radius = 6]) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        ),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(68, 68, 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _block(150, 16),
                        const SizedBox(height: 8),
                        _block(200, 12),
                        const SizedBox(height: 10),
                        _block(120, 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _block(110, 22, 8),
                  const SizedBox(width: 6),
                  _block(72, 22, 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopCardSkeletonList extends StatelessWidget {
  const ShopCardSkeletonList({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.all(16),
  });

  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Dükkanlar yükleniyor',
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: count,
        itemBuilder: (_, _) => const ShopCardSkeleton(),
      ),
    );
  }
}
