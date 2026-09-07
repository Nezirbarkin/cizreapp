import 'package:flutter/material.dart';

import '../theme/okey_theme.dart';

/// Aksiyon butonunun görsel tonu.
///
/// Renk burada KEYFİ değil, hamlenin oyundaki ağırlığını anlatır:
///  * [normal]   — her tur yapılan rutin hamle (taş işle, taş at)
///  * [ready]    — nadir ve yüksek değerli, ŞU AN yapılabilir hamle
///                 (SERİ AÇ / ÇİFT AÇ barajı geçtiğinde)
///  * [winning]  — eli bitiren hamle
enum OkeyActionTone { normal, ready, winning }

/// Masanın kontrol şeridindeki bütün düğmelerin ORTAK GÖVDESİ.
///
/// ## Neden tek bir gövde
///
/// v2'de her düğme kendi malzemesini seçiyordu: aksiyonlar neredeyse
/// görünmez koyu kutular, DİZ düğmeleri parlak turuncu ahşap bloklar, HUD
/// düğmeleri gri karelerdi. Aynı şeritte üç ayrı görsel dil vardı ve hangi
/// kutunun düğme olduğu ancak deneyerek anlaşılıyordu.
///
/// Artık hepsi buradan çıkar: aynı köşe yarıçapı, aynı kenar çizgisi, aynı
/// gölge, aynı dokunma geri bildirimi. Farklılaşan tek şey RENKTİR ve renk
/// yalnızca anlam taşır (bkz. [OkeyV3]).
class _Control extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  /// Kapalıyken dokunulduğunda çağrılır (bkz. [OkeyActionButton.onBlockedTap]).
  final VoidCallback? onBlockedTap;

  /// Altın/turkuaz gradyan — verilmezse nötr cam yüzey kullanılır.
  final List<Color>? gradient;

  /// Gradyanın etrafına vuran parıltı (yalnızca vurgulu tonlarda).
  final Color? glow;
  final double glowBlur;

  final double radius;
  final EdgeInsets padding;

  const _Control({
    required this.child,
    this.onTap,
    this.enabled = true,
    this.onBlockedTap,
    this.gradient,
    this.glow,
    this.glowBlur = 10,
    this.radius = OkeyV3.radius,
    this.padding = const EdgeInsets.symmetric(horizontal: 5),
  });

  @override
  Widget build(BuildContext context) {
    final on = enabled && onTap != null;
    final useGradient = on && gradient != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: useGradient
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradient!,
              )
            : null,
        color: useGradient
            ? null
            : (on ? OkeyV3.surface : OkeyV3.surfaceDisabled),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: useGradient
              ? const Color(0x33FFFFFF)
              : (on ? OkeyV3.border : OkeyV3.borderDisabled),
        ),
        boxShadow: [
          ...OkeyV3.lift,
          if (useGradient && glow != null)
            BoxShadow(color: glow!, blurRadius: glowBlur),
        ],
      ),
      // Dokunma geri bildirimi modülün geri kalanıyla aynı: Material+InkWell.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          // KAPALIYKEN DE dokunulur — ama farklı bir şey yapar: hamleyi
          // denemez, NEDEN yapılamadığını söyler (bkz. [onBlockedTap]).
          // Görünüş yine kapalı kalır; açık göstermek yapılamayan bir
          // hamleyi yapılabilir sanmaya yol açardı.
          onTap: on ? onTap : onBlockedTap,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: padding,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Kontrol şeridindeki AKSİYON düğmesi: SERİ AÇ / ÇİFT AÇ / İŞLE / TAŞI AT.
///
/// ## Yerleşim: ikon üstte, etiket altta
///
/// v2'de ikon ve etiket YAN YANAYDI ve rozet ("103/101") aynı satırı
/// paylaşıyordu; 78px genişliğinde bir butonda etiket ellipsis'e düşüp
/// "SERİ..." oluyordu. Dikey yerleşimde etiketin tüm genişlik kendisinindir
/// ve rozet ikonun yanına, üst satıra çıkar. Aynı yerde artık iki kat daha
/// büyük yazı okunur.
///
/// Ölçüler butonun GERÇEK yüksekliğinden türer ([LayoutBuilder]): 34px'lik
/// kısa bir ekranla 46px'lik geniş bir ekranda aynı sabitleri kullanmak,
/// birinde sıkışmaya diğerinde boşluğa yol açıyordu.
class OkeyActionButton extends StatelessWidget {
  final String title;
  final String? badge;
  final IconData icon;
  final bool enabled;
  final OkeyActionTone tone;
  final VoidCallback? onPressed;

  /// Rozetin rengi — "2 işlenebilir taş" gibi olumlu sayaçlar için yeşil.
  final Color? badgeColor;

  /// KAPALIYKEN DOKUNULUNCA çağrılır — "neden yapamıyorum" sorusunun cevabı.
  ///
  /// ## Neden kapalı bir düğme dokunulabilir
  ///
  /// Kapalı düğme, sebebini söylemediği sürece bir hatadan ayırt edilemez:
  /// oyuncu rozette "5/5" görür, düğme sönüktür ve elinde tek bir bilgi
  /// yoktur. Düğmeyi AÇMAK doğru çözüm değil (sunucu hamleyi haklı olarak
  /// reddeder ve oyuncu ham bir hata metniyle karşılaşır); doğru çözüm,
  /// dokunuşun bir CEVAP döndürmesi.
  ///
  /// Düğme yine de KAPALI görünür — açık gibi göstermek, yapılamayan bir
  /// hamleyi yapılabilir sanmaya yol açardı.
  final VoidCallback? onBlockedTap;

  const OkeyActionButton({
    super.key,
    required this.title,
    required this.icon,
    this.badge,
    this.enabled = true,
    this.tone = OkeyActionTone.normal,
    this.onPressed,
    this.badgeColor,
    this.onBlockedTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = enabled && onPressed != null;

    // Ton yalnızca buton GERÇEKTEN etkinken uygulanır: kapalı bir "bitir"
    // butonunun parıldaması, yapılamayan bir hamleyi yapılabilir gösterirdi.
    final effTone = on ? tone : OkeyActionTone.normal;

    final List<Color>? gradient = switch (effTone) {
      OkeyActionTone.ready => OkeyV3.gold,
      OkeyActionTone.winning => OkeyV3.goldBright,
      OkeyActionTone.normal => null,
    };
    final gold = gradient != null;

    final fg = !on ? OkeyV3.textDisabled : (gold ? OkeyV3.onGold : OkeyV3.text);

    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.hasBoundedHeight && c.maxHeight.isFinite
              ? c.maxHeight
              : 40.0;
          final iconSize = (h * 0.34).clamp(11.0, 19.0);
          final fontSize = (h * 0.245).clamp(8.5, 12.5);

          return _Control(
            enabled: enabled,
            onTap: onPressed,
            // Kapalıyken sebebi söyleyen dokunuş (bkz. [onBlockedTap]).
            onBlockedTap: onBlockedTap,
            gradient: gradient,
            glow: effTone == OkeyActionTone.winning
                ? const Color(0x8CFFB300)
                : OkeyV3.goldGlow,
            glowBlur: effTone == OkeyActionTone.winning ? 16 : 9,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(icon, size: iconSize, color: fg),
                      if (badge != null) ...[
                        const SizedBox(width: 4),
                        _Badge(
                          text: badge!,
                          fontSize: fontSize * 0.82,
                          onGold: gold,
                          enabled: on,
                          color: badgeColor,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: h * 0.04),
                  Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Aksiyon düğmesinin üst satırındaki sayaç rozeti ("103/101", "2 per").
class _Badge extends StatelessWidget {
  final String text;
  final double fontSize;
  final bool onGold;
  final bool enabled;
  final Color? color;

  const _Badge({
    required this.text,
    required this.fontSize,
    required this.onGold,
    required this.enabled,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? OkeyV3.textDisabled
        : (onGold
              ? OkeyV3.onGold.withValues(alpha: 0.78)
              : (color ?? OkeyV3.textDim));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: onGold
            ? const Color(0x1F000000)
            : (color ?? Colors.white).withValues(alpha: enabled ? 0.13 : 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.0,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// "SERİ DİZ" / "ÇİFT DİZ" — ıstakayı yeniden dizen ARAÇ düğmeleri.
///
/// ## Neden aksiyonlarla aynı boyda ama farklı renkte
///
/// v2'de bunlar masanın EN BÜYÜK kontrolleriydi (parlak turuncu, iki katlı
/// bloklar). Oysa dizmek bir hamle değil, kendi elini düzenlemektir: geri
/// alınabilir, sunucuya gitmez, kimseyi etkilemez. Ekrandaki en büyük
/// düğmenin en önemsiz eylemi taşıması, oyuncunun gözünü sürekli yanlış
/// yere çekiyordu.
///
/// Artık aksiyonlarla AYNI gövde ve AYNI yükseklikte; ayrımı TURKUAZ renk
/// yapıyor: altın = hamle, turkuaz = düzenleme.
class OkeyDizButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  /// Konsolun verdiği yükseklik (bkz. OkeyTableMetrics.sortButtonHeight).
  final double? height;

  const OkeyDizButton({
    super.key,
    required this.title,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.hasBoundedHeight && c.maxHeight.isFinite
                ? c.maxHeight
                : (height ?? 40.0);
            final iconSize = (h * 0.34).clamp(11.0, 19.0);
            final fontSize = (h * 0.245).clamp(8.5, 12.5);
            final fg = active ? OkeyV3.onTool : OkeyV3.text;

            return _Control(
              onTap: onPressed,
              gradient: active ? OkeyV3.tool : null,
              glow: const Color(0x5C2CC5CE),
              glowBlur: 9,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: iconSize,
                      color: active ? fg : const Color(0xFF57D6DC),
                    ),
                    SizedBox(height: h * 0.04),
                    Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: fontSize,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Masanın sol üstündeki mod rozeti (Eşli / Katlamalı / Yardımlı / 3. El).
///
/// Tur boyunca DEĞİŞMEYEN referans bilgidir: küçük, sakin ve tek satır.
/// v2'de aksiyon düğmeleriyle benzer ağırlıktaydı ve gözü boşuna çekiyordu.
class OkeyModeBadge extends StatelessWidget {
  final String text;
  final Color color;

  const OkeyModeBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: OkeyV3.surface,
          borderRadius: BorderRadius.circular(OkeyV3.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.38)),
        ),
        // ORTALANIR: rozetler [OkeyModeBadgeStack] içinde en uzun rozetin
        // genişliğine gerilir; içerik sola yaslı kalsaydı dört rozetin
        // metinleri düzensiz bir merdiven gibi görünürdü.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8.5,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: OkeyV3.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mod rozetlerinin DİKEY sütunu — per alanının sağındaki bilgi sütunu.
///
/// ## Neden ayrı bir widget
///
/// Rozetler tek tek bir [Column]'a konsaydı her biri kendi metni kadar
/// genişlerdi ve sütun kenarı testere dişi gibi görünürdü. [IntrinsicWidth]
/// hepsini EN UZUN rozetin genişliğine hizalar: dört rozet tek bir blok
/// olarak okunur, referans masadaki gibi.
class OkeyModeBadgeStack extends StatelessWidget {
  /// (etiket, vurgu rengi) çiftleri — sırası oyunun sabit bilgisidir:
  /// eşleşme türü → oyun türü → yardım → kaçıncı el.
  final List<(String, Color)> items;
  final double gap;

  const OkeyModeBadgeStack({super.key, required this.items, this.gap = 3});

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            OkeyModeBadge(text: items[i].$1, color: items[i].$2),
          ],
        ],
      ),
    );
  }
}

/// Istakanın İKİ UCUNDAKİ dizme düğmesi: ÇİFT DİZ (sol) / SERİ DİZ (sağ).
///
/// ## Neden ıstakanın ucunda ve neden bu biçimde
///
/// v3'te bunlar konsolda, hamle düğmelerinin arasındaydı. Oysa dizmek bir
/// hamle değil, ISTAKAYI yeniden düzenlemektir — düğmenin düzenlediği
/// nesneye bitişik durması, ne yaptığını hiç okumadan anlatır. Referans
/// masada da tam olarak orada dururlar.
///
/// Düğmenin üstündeki minik taşlar etiketten daha hızlı okunur: iki eş taş
/// = çift, ardışık üç taş = seri. Etiket yalnızca doğrulama içindir.
class OkeyDizCapButton extends StatelessWidget {
  /// İki satıra bölünmüş etiket ("ÇİFT" / "DİZ").
  final String titleTop;
  final String titleBottom;

  /// Üstteki minik taşların üzerindeki rakamlar.
  final List<String> sampleTiles;

  /// Minik taşların rakam renkleri (sampleTiles ile aynı uzunlukta).
  final List<Color> sampleColors;

  final bool active;
  final VoidCallback onPressed;

  const OkeyDizCapButton({
    super.key,
    required this.titleTop,
    required this.titleBottom,
    required this.sampleTiles,
    required this.sampleColors,
    required this.onPressed,
    this.active = false,
  });

  /// ÇİFT DİZ — iki eş taş.
  factory OkeyDizCapButton.pairs({
    required bool active,
    required VoidCallback onPressed,
  }) => OkeyDizCapButton(
    titleTop: 'ÇİFT',
    titleBottom: 'DİZ',
    sampleTiles: const ['5', '5'],
    sampleColors: const [OkeyColors.tileRed, OkeyColors.tileRed],
    active: active,
    onPressed: onPressed,
  );

  /// SERİ DİZ — ardışık üç taş.
  factory OkeyDizCapButton.series({
    required bool active,
    required VoidCallback onPressed,
  }) => OkeyDizCapButton(
    titleTop: 'SERİ',
    titleBottom: 'DİZ',
    sampleTiles: const ['1', '2', '3'],
    sampleColors: const [
      OkeyColors.tileRed,
      OkeyColors.tileBlack,
      OkeyColors.tileBlue,
    ],
    active: active,
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.hasBoundedWidth ? c.maxWidth : 60.0;
          final h = c.hasBoundedHeight && c.maxHeight.isFinite
              ? c.maxHeight
              : 90.0;
          final font = (w * 0.24).clamp(8.0, 15.0).toDouble();
          final tileH = (h * 0.26).clamp(10.0, 34.0).toDouble();

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: active
                      ? const [Color(0xFF6FC8FF), Color(0xFF15568F)]
                      : const [Color(0xFF2E6E9E), Color(0xFF102E4B)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? const Color(0xFFBFE6FF)
                      : const Color(0x4DFFFFFF),
                  width: active ? 1.6 : 1,
                ),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x8A000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                  if (active)
                    const BoxShadow(color: Color(0x6642B4FF), blurRadius: 14),
                ],
              ),
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.06,
                vertical: h * 0.06,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniTiles(
                      labels: sampleTiles,
                      colors: sampleColors,
                      height: tileH,
                    ),
                    SizedBox(height: h * 0.06),
                    Text(
                      titleTop,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: font,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      titleBottom,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: font,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Dizme düğmesinin üstündeki minik örnek taşlar.
class _MiniTiles extends StatelessWidget {
  final List<String> labels;
  final List<Color> colors;
  final double height;

  const _MiniTiles({
    required this.labels,
    required this.colors,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final w = height * OkeyTableMetricsTileAspect.value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) SizedBox(width: height * 0.06),
          Container(
            width: w,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: OkeyColors.tileGradient,
              borderRadius: BorderRadius.circular(height * 0.14),
              border: Border.all(color: const Color(0x40000000), width: 0.6),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: height * 0.58,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: colors[i % colors.length],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Taş oranının minik taşlar için kopyası.
///
/// [OkeyTableMetrics]'i buraya import etmek, saf bir düğme dosyasını masa
/// ölçü sözleşmesine bağlardı; oran tek bir sabit olduğu için burada
/// tekrarlanır ve testte iki değerin eşitliği doğrulanır.
abstract final class OkeyTableMetricsTileAspect {
  static const double value = 0.74;
}

/// HUD'daki kare ikon düğmesi (ses / müzik / ayarlar).
///
/// 26px'ten 32px'e büyütüldü: dokunma hedefinin altında kalan her düğme,
/// gerçek cihazda "bazen çalışmıyor" olarak yaşanır.
class OkeyHudIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Dikkat çekmesi gereken düğme (ör. kapalı ses) için vurgu rengi.
  final Color? accent;

  const OkeyHudIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent,
  });

  static const double size = 32;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: _Control(
          onTap: onTap,
          radius: OkeyV3.radiusSm + 2,
          padding: EdgeInsets.zero,
          child: Icon(icon, size: 16, color: accent ?? OkeyV3.text),
        ),
      ),
    );
  }
}
