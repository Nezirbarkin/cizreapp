import 'package:flutter/material.dart';

import '../services/okey_sound_service.dart';

import 'okey_theme.dart';

export 'okey_salon.dart';

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
  //
  // SALON TASARIM DİLİ (2026-09-20): lobi/oda/puan/sonuç ekranları artık
  // masayla AYNI malzemeyi konuşur — espresso zemin, ceviz kartlar, pirinç
  // vurgu. Eskiden bu ekranlar düz koyu turkuazdı ve masadan (ceviz + çuha +
  // fildişi) ayrı bir uygulama gibi duruyordu.

  /// Oda zemini: espresso, üstte çuhanın hafif yeşil ışığı.
  static const LinearGradient screenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF14322E), Color(0xFF120C09), Color(0xFF0D0806)],
    stops: [0, 0.38, 1],
  );

  /// [screenGradient]'in en üst rengi. Scaffold zemini olarak da kullanılır:
  /// şeffaf AppBar'ın arkasında kalan bant, gövde gradyanıyla kesintisiz
  /// birleşsin (eskiden masa temasının turkuazı görünüyordu).
  static const Color screenTop = Color(0xFF14322E);

  /// Kart yüzeyi — espresso üstünde duran koyu cam.
  static const Color cardFill = Color(0xFF1F1811);
  static const Color cardFillRaised = Color(0xFF2B2018);
  static const Color cardBorder = Color(0x24FFF0D2);

  /// Vurgulu (pirinç) yüzey — birincil aksiyonlar.
  static const List<Color> goldGradient = [
    Color(0xFFF5CB6A),
    Color(0xFFD9972A),
  ];
  static const Color onGold = Color(0xFF2A1A05);

  /// Pirinç — tek vurgu rengi (seçili çip, kazanan satırı, rozet).
  static const Color brass = Color(0xFFE4B04C);

  /// Pirinç düğmenin altındaki "basılabilir kalınlık" gölgesi.
  static const Color goldEdge = Color(0xFF9A6A17);

  /// Çip sayıları ve altın vurgulu rakamlar.
  static const Color chipText = Color(0xFFFFE7A8);

  // --- Metin ---------------------------------------------------------------
  static const Color text = Color(0xFFF5EBD8);
  static const Color textDim = Color(0xC7F5EBD8);
  static const Color textFaint = Color(0x94F5EBD8);

  /// Ekran yazı tipi: başlık, çip sayısı, taş numarası. Yalnızca büyük ve
  /// kısa metinde kullanılır; gövde metni sistem yazı tipinde kalır.
  static const String displayFont = 'Fraunces';

  static TextStyle display({
    double size = 22,
    Color color = text,
    double height = 1.1,
  }) => TextStyle(
    fontFamily: displayFont,
    fontWeight: FontWeight.w800,
    fontSize: size,
    height: height,
    color: color,
    // Sayılar sütun halinde dizildiğinde kaymasın.
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static const TextStyle titleLg = TextStyle(
    fontFamily: displayFont,
    color: text,
    fontSize: 22,
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
    color: Color(0xFFF0C462),
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

  /// Tam genişlikte alt gezinme çubuğu (bkz. [OkeyBottomNav]). Kaydırma
  /// alanının ve [bottomBar]'ın DIŞINDA, ekranın en altında durur.
  final Widget? bottomNav;

  /// `false` ise üst çubuk çizilmez; ekran kendi başlığını slivers içinde
  /// çizer (lobi: kimlik satırı + çip hapı).
  final bool showAppBar;

  const OkeyScreen({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.bottomBar,
    this.onRefresh,
    this.leading,
    this.bottomNav,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      // Liste kısa olsa bile aşağı çekilebilsin (RefreshIndicator için şart).
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (showAppBar)
          SliverPadding(
            padding: OkeyUI.screenPadding,
            sliver: SliverList.list(children: const []),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gapSm)),
        ...slivers,
        // Alt güvenlik payı: son kart ekranın en altına yapışmasın.
        const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gapXl)),
      ],
    );

    return Scaffold(
      backgroundColor: OkeyUI.screenTop,
      bottomNavigationBar: bottomNav,
      appBar: showAppBar
          ? AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              foregroundColor: OkeyUI.text,
              leading: leading,
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OkeyUI.display(size: 20),
              ),
              actions: actions,
            )
          : null,
      extendBodyBehindAppBar: false,
      body: Container(
        decoration: const BoxDecoration(gradient: OkeyUI.screenGradient),
        child: SafeArea(
          top: !showAppBar,
          child: Column(
            children: [
              Expanded(
                child: onRefresh == null
                    ? scroll
                    : RefreshIndicator(
                        onRefresh: onRefresh!,
                        color: OkeyUI.brass,
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
              ? OkeyUI.brass.withValues(alpha: 0.55)
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
              color: OkeyUI.brass.withValues(alpha: 0.15),
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
        // Dokunulabilir kart da bir düğmedir: tık sesi buradan gelir
        // (bkz. [withOkeyTapSound]).
        onTap: withOkeyTapSound(onTap),
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

  /// Kart içi kompakt düğme (36 px): masa kartındaki OTUR/İZLE gibi.
  final bool dense;

  const OkeyButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = OkeyButtonTone.secondary,
    this.busy = false,
    this.expand = true,
    this.dense = false,
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
        const Color(0xFF2B2018),
        null,
        OkeyUI.text,
        const Color(0x3DFFF0D2),
      ),
      OkeyButtonTone.ghost => (
        Colors.transparent,
        null,
        OkeyUI.text,
        const Color(0x59FFF0D2),
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
                  Icon(
                    icon,
                    size: dense ? 15 : 18,
                    color: enabled ? fg : OkeyUI.textFaint,
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? fg : OkeyUI.textFaint,
                    fontSize: dense ? 12 : 14,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          );

    final button = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: dense ? 36 : 50,
        decoration: BoxDecoration(
          color: fill,
          gradient: enabled ? gradient : null,
          borderRadius: BorderRadius.circular(OkeyUI.radius),
          border: border == null ? null : Border.all(color: border),
          // Birincil düğme fiziksel bir tuş gibi: altında pirinç kenar
          // kalınlığı + yumuşak gölge.
          boxShadow: tone == OkeyButtonTone.primary && enabled
              ? const [
                  BoxShadow(color: OkeyUI.goldEdge, offset: Offset(0, 3)),
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(OkeyUI.radius),
          child: InkWell(
            onTap: enabled ? withOkeyTapSound(onPressed) : null,
            borderRadius: BorderRadius.circular(OkeyUI.radius),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 16 : 14),
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

  /// `null` ise aktif MASA TEMASININ altın vurgusu kullanılır — bu artık
  /// bir derleme zamanı sabiti değil (bkz. OkeyTableTheme), o yüzden
  /// varsayılan değer burada değil [build] içinde çözülür.
  final Color? color;

  const OkeyStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? OkeyUI.brass;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: OkeyUI.cardFill,
        borderRadius: BorderRadius.circular(OkeyUI.radius),
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

  /// `null` ise aktif MASA TEMASININ altın vurgusu kullanılır (bkz.
  /// OkeyStatTile.color üzerindeki not — aynı gerekçe).
  final Color? color;
  final IconData? icon;

  const OkeyPill({super.key, required this.text, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? OkeyUI.brass;
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
        color: const Color(0xFF2B2018),
        border: Border.all(
          color: highlighted ? OkeyUI.brass : OkeyColors.avatarRing,
          width: 2,
        ),
      ),
      child: ClipOval(
        child: url == null
            ? Icon(
                Icons.person,
                size: size * 0.5,
                color: const Color(0xFFC9B88F),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: const Color(0xFFC9B88F),
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
