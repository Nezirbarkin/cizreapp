import 'package:flutter/material.dart';

import 'okey_theme.dart';

/// 101 Okey modülünün ORTAK TASARIM SİSTEMİ.
///
/// ## Neden var
///
/// Modülün altı ekranı (lobi, masa kur, oda, oyun, puan, sonuç) ve admin
/// sekmeleri ayrı ayrı, birbirinden habersiz yazılmıştı: her ekran kendi
/// kartını, kendi butonunu, kendi başlık stilini elle kuruyordu. İki sonuç
/// doğurdu:
///
///  1. **Görsel dağınıklık** — aynı işi yapan iki buton iki farklı yükseklik,
///     iki farklı köşe yarıçapı, iki farklı gölge kullanıyordu.
///  2. **Tekrar eden TAŞMA hataları** — her ekran aynı hatayı yeniden yapıyordu:
///     `Row(children: [Icon, Text, Spacer, Text])` içinde uzun bir kullanıcı
///     adı ya da büyütülmüş sistem yazı tipi satırı taşırıyordu.
///
/// ## Taşma garantisi bileşenlerin İÇİNDE
///
/// Bu dosyadaki her bileşen, taşmayı ÇAĞIRANIN dikkatine bırakmaz:
///
///  * [OkeyScreen] gövdeyi her zaman kaydırılabilir yapar → dikey taşma
///    tanım gereği imkânsız.
///  * [OkeyButton] etiketini `FittedBox(scaleDown)` + tek satır + ellipsis
///    ile sarar → dar butonda metin küçülür, taşmaz.
///  * [OkeyRow] esneyen tarafı `Expanded` ile alır → uzun ad satırı ezmez.
///  * [OkeyStatTile] sayıyı `FittedBox` ile ölçekler → 7 haneli puan sığar.
///
/// Yani "taşmasın" diye ayrıca uğraşmak gerekmez; yanlışı yapmak zorlaşır.
abstract final class OkeyUI {
  // --- Aralıklar -----------------------------------------------------------
  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gap = 12;
  static const double gapLg = 16;
  static const double gapXl = 24;

  /// Ekran kenar boşluğu.
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(14, 12, 14, 24);

  // --- Köşe yarıçapları ----------------------------------------------------
  static const double radiusSm = 10;
  static const double radius = 14;
  static const double radiusLg = 20;

  // --- Yüzeyler ------------------------------------------------------------
  /// Ekran zemini: masanın keçesiyle akraba, ama daha koyu ve sakin —
  /// içerik okunurluğu için kontrast masadan yüksek.
  static const LinearGradient screenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0B2E38), Color(0xFF07202A)],
  );

  /// Kart yüzeyi — keçenin üstünde duran cam gibi.
  static const Color cardFill = Color(0xFF0F3B47);
  static const Color cardFillRaised = Color(0xFF144957);
  static const Color cardBorder = Color(0x24FFFFFF);

  /// Vurgulu (altın) yüzey — birincil aksiyonlar.
  static const List<Color> goldGradient = [
    Color(0xFFFFCF5C),
    Color(0xFFE39A16),
  ];
  static const Color onGold = Color(0xFF2A1C05);

  // --- Metin ---------------------------------------------------------------
  static const Color text = Color(0xFFF2F7F8);
  static const Color textDim = Color(0xB3FFFFFF);
  static const Color textFaint = Color(0x73FFFFFF);

  static const TextStyle titleLg = TextStyle(
    color: text,
    fontSize: 20,
    height: 1.15,
    fontWeight: FontWeight.w800,
  );
  static const TextStyle title = TextStyle(
    color: text,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle body = TextStyle(
    color: textDim,
    fontSize: 13,
    height: 1.3,
  );
  static const TextStyle caption = TextStyle(
    color: textFaint,
    fontSize: 11,
    height: 1.25,
  );
  static const TextStyle sectionLabel = TextStyle(
    color: Color(0xFFFFD98A),
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
  );
}

/// Modülün TÜM ekranlarının iskeleti.
///
/// Gövde HER ZAMAN kaydırılabilir: dikey taşma bu yüzden yapısal olarak
/// imkânsızdır. Ekran sabit bir alt çubuk istiyorsa [bottomBar] kullanır —
/// o da kaydırma alanının DIŞINDA, sabit yükseklikte durur.
class OkeyScreen extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> slivers;

  /// Kaydırma alanının altındaki sabit çubuk (ör. "HAZIRIM" butonu).
  final Widget? bottomBar;

  final Future<void> Function()? onRefresh;
  final Widget? leading;

  const OkeyScreen({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.bottomBar,
    this.onRefresh,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      // Liste kısa olsa bile aşağı çekilebilsin (RefreshIndicator için şart).
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: OkeyUI.screenPadding,
          sliver: SliverList.list(children: const []),
        ),
        ...slivers,
        // Alt güvenlik payı: son kart ekranın en altına yapışmasın.
        const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gapXl)),
      ],
    );

    return Scaffold(
      backgroundColor: OkeyColors.screenBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: OkeyUI.text,
        leading: leading,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: actions,
      ),
      extendBodyBehindAppBar: false,
      body: Container(
        decoration: const BoxDecoration(gradient: OkeyUI.screenGradient),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: onRefresh == null
                    ? scroll
                    : RefreshIndicator(
                        onRefresh: onRefresh!,
                        color: OkeyColors.accentGold,
                        backgroundColor: OkeyUI.cardFill,
                        child: scroll,
                      ),
              ),
              if (bottomBar != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: bottomBar!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modülün standart kartı.
class OkeyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Vurgulu kart — altın kenarlık ve hafif parıltı (ör. "devam eden oyun").
  final bool highlighted;

  const OkeyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(OkeyUI.gap),
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      decoration: BoxDecoration(
        color: OkeyUI.cardFill,
        borderRadius: BorderRadius.circular(OkeyUI.radius),
        border: Border.all(
          color: highlighted
              ? OkeyColors.accentGold.withValues(alpha: 0.55)
              : OkeyUI.cardBorder,
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
          if (highlighted)
            BoxShadow(
              color: OkeyColors.accentGold.withValues(alpha: 0.15),
              blurRadius: 16,
            ),
        ],
      ),
      padding: padding,
      child: child,
    );

    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(OkeyUI.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OkeyUI.radius),
        child: decorated,
      ),
    );
  }
}

/// Butonun görsel ağırlığı.
enum OkeyButtonTone {
  /// Altın — ekranın BİRİNCİL eylemi. Ekran başına en fazla bir tane.
  primary,

  /// Koyu dolgu + ince kenar — ikincil eylemler.
  secondary,

  /// Yalnızca kenarlık — yıkıcı olmayan üçüncül eylemler.
  ghost,

  /// Kırmızı — geri alınamaz/yıkıcı (masadan ayrıl).
  danger,
}

/// Modülün standart butonu.
///
/// TAŞMA GÜVENCESİ: etiket tek satır + ellipsis + `FittedBox(scaleDown)`.
/// Dar bir sütuna konduğunda ya da sistem yazı tipi büyütüldüğünde metin
/// küçülerek sığar; hiçbir koşulda satırı taşırmaz.
class OkeyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final OkeyButtonTone tone;
  final bool busy;
  final bool expand;

  const OkeyButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = OkeyButtonTone.secondary,
    this.busy = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    final (
      Color? fill,
      Gradient? gradient,
      Color fg,
      Color? border,
    ) = switch (tone) {
      OkeyButtonTone.primary => (
        null,
        const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: OkeyUI.goldGradient,
        ),
        OkeyUI.onGold,
        null,
      ),
      OkeyButtonTone.secondary => (
        const Color(0xFF16505E),
        null,
        OkeyUI.text,
        const Color(0x33FFFFFF),
      ),
      OkeyButtonTone.ghost => (
        Colors.transparent,
        null,
        OkeyUI.text,
        const Color(0x59FFFFFF),
      ),
      OkeyButtonTone.danger => (
        const Color(0xFF7A2733),
        null,
        const Color(0xFFFFD9DE),
        const Color(0x4DFF8A9B),
      ),
    };

    final content = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: enabled ? fg : OkeyUI.textFaint),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? fg : OkeyUI.textFaint,
                    fontSize: 14,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          );

    final button = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: fill,
          gradient: enabled ? gradient : null,
          borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
          border: border == null ? null : Border.all(color: border),
          boxShadow: tone == OkeyButtonTone.primary && enabled
              ? const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Bölüm başlığı — ekranın büyük parçalarını ayırır.
class OkeySectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const OkeySectionHeader({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, OkeyUI.gapLg, 2, OkeyUI.gapSm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OkeyUI.sectionLabel,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Etiket + değer satırı.
///
/// TAŞMA GÜVENCESİ: etiket esner ve gerekirse kısalır (ellipsis), değer
/// doğal genişliğini korur — tersi olsaydı uzun bir değer etiketi ezerdi.
class OkeyRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  const OkeyRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: OkeyUI.textFaint),
            const SizedBox(width: OkeyUI.gapSm),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OkeyUI.body,
            ),
          ),
          const SizedBox(width: OkeyUI.gapSm),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: OkeyUI.body.copyWith(
                color: valueColor ?? OkeyUI.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sayı kutucuğu (puan, el sayısı, sıralama...).
///
/// TAŞMA GÜVENCESİ: sayı `FittedBox` ile ölçeklenir — yedi haneli bir puan da
/// aynı kutuya sığar, kutu büyümez.
class OkeyStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const OkeyStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = OkeyColors.accentGold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: OkeyUI.cardFill,
        borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
        border: Border.all(color: OkeyUI.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Sayı: kutunun genişliğine sığmazsa KÜÇÜLÜR.
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Küçük durum rozeti.
class OkeyPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const OkeyPill({
    super.key,
    required this.text,
    this.color = OkeyColors.accentGold,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          // Flexible ŞART: `mainAxisSize.min` taşmayı önlemez, yalnızca
          // rozetin doğal genişliğini alır. Rozet bir `Expanded`in içine ya da
          // dar bir sütuna konduğunda metin kutuyu aşabiliyordu.
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                height: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Oyuncu avatarı — ağ görseli, yoksa ikon.
///
/// ## Neden bir "bot" ayrımı YOK (2026-09, kullanıcı isteği)
///
/// Bu widget'ın eskiden bir `isBot` bayrağı vardı ve bot için robot ikonu
/// çiziyordu. Yani admin panelinden bota ne ad ve fotoğraf verilirse
/// verilsin, avatarın kendisi "ben botum" diyordu. Artık masaya oturan
/// herkes aynı biçimde çizilir; fotoğrafı olan fotoğrafıyla, olmayan kişi
/// ikonuyla görünür.
class OkeyAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final bool highlighted;

  const OkeyAvatar({
    super.key,
    this.url,
    this.size = 40,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0A2C36),
        border: Border.all(
          color: highlighted ? OkeyColors.accentGold : OkeyColors.avatarRing,
          width: 2,
        ),
      ),
      child: ClipOval(
        child: url == null
            ? Icon(
                Icons.person,
                size: size * 0.5,
                color: const Color(0xFF9FD9CF),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: const Color(0xFF9FD9CF),
                ),
              ),
      ),
    );
  }
}

/// Boş durum — liste boşken ne yapılacağını söyler.
class OkeyEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const OkeyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: OkeyUI.textFaint),
          const SizedBox(height: OkeyUI.gap),
          Text(title, textAlign: TextAlign.center, style: OkeyUI.title),
          const SizedBox(height: OkeyUI.gapSm),
          Text(message, textAlign: TextAlign.center, style: OkeyUI.body),
          if (action != null) ...[
            const SizedBox(height: OkeyUI.gapLg),
            action!,
          ],
        ],
      ),
    );
  }
}
