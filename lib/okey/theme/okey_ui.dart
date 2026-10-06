import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/okey_sound_service.dart';

import 'okey_design.dart';
import 'okey_design_decor.dart';

export 'okey_design.dart';
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
/// ## Değerler artık CANLI (Tasarım Sistemi v6, 2026-10-05)
///
/// Renkler, köşe yarıçapları ve yazı dili eskiden `static const` idi. Artık
/// AKTİF [OkeyDesign]dan okunan getter'lardır (bkz. okey_design.dart):
/// yönetici tasarımı değiştirince aynı `OkeyUI.cardFill` ifadesi başka bir
/// renk döndürür. Bunun iki sonucu var:
///
///  * Bu değerler `const` bir ifadenin içinde KULLANILAMAZ (derleyici zaten
///    reddeder).
///  * Değer build sırasında okunduğundan, tasarım değişince ekranın YENİDEN
///    KURULMASI gerekir — bunu [OkeyDesignScope] yapar (lobinin kökünde).
///
/// Boşluklar ([gapSm] vb.) tasarımdan bağımsızdır ve `const` kalır.
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
  /// Aktif tasarım.
  static OkeyDesign get design => OkeyDesignPrefs.instance.current.value;

  /// Aktif lobi düzeni (yönetici geçersiz kılması dahil).
  static OkeyLobbyLayout get layout => OkeyDesignPrefs.instance.layout.value;

  static bool get isLight => design.isLight;

  // --- Aralıklar (tasarımdan bağımsız) ---------------------------------------
  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gap = 12;
  static const double gapLg = 16;
  static const double gapXl = 24;

  /// Ekran kenar boşluğu.
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(14, 12, 14, 24);

  // --- Köşe yarıçapları --------------------------------------------------------
  static double get radiusSm => design.radiusSm;
  static double get radius => design.radius;
  static double get radiusLg => design.radiusLg;
  static double get heroRadius => design.heroRadius;
  static double get buttonRadius => design.buttonRadius;

  // --- Yüzeyler ------------------------------------------------------------

  /// Oda zemini.
  static LinearGradient get screenGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: design.screenGradient,
    stops: design.screenStops,
  );

  /// [screenGradient]'in en üst rengi. Scaffold zemini olarak da kullanılır:
  /// şeffaf AppBar'ın arkasında kalan bant, gövde gradyanıyla kesintisiz
  /// birleşsin.
  static Color get screenTop => design.screenGradient.first;

  /// En alt renk — sayfa kapanırken altta kalan bant.
  static Color get screenBottom => design.screenGradient.last;

  /// Kart yüzeyi.
  static Color get cardFill => design.cardFill;
  static Color get cardFillRaised => design.cardFillRaised;
  static Color get cardBorder => design.cardBorder;
  static Color get shadow => design.shadow;

  /// Vurgulu yüzey — birincil aksiyonlar.
  static List<Color> get goldGradient => design.accentGradient;
  static Color get onGold => design.onAccent;

  /// Tek vurgu rengi (seçili çip, kazanan satırı, rozet). Adı tarihsel:
  /// Salon tasarımında pirinçti; diğer tasarımlarda kobalt, neon ya da
  /// kiremit olabilir.
  static Color get brass => design.accent;

  /// Birincil düğmenin altındaki "basılabilir kalınlık" gölgesi.
  static Color get goldEdge => design.accentEdge;

  /// Çip sayıları ve vurgulu rakamlar.
  static Color get chipText => design.accentText;

  static Color get secondaryFill => design.secondaryFill;
  static Color get secondaryBorder => design.secondaryBorder;
  static Color get ghostBorder => design.ghostBorder;
  static Color get dangerFill => design.dangerFill;
  static Color get dangerText => design.dangerText;
  static Color get dangerBorder => design.dangerBorder;
  static Color get navFill => design.navFill;
  static Color get pillFill => design.pillFill;
  static Color get pillBorder => design.pillBorder;
  static Color get errorText => design.errorText;

  static List<Color> get heroGradient => design.heroGradient;
  static Color get onHero => design.onHero;
  static Color get onHeroDim => design.onHeroDim;

  static Color get miniFelt => design.miniFelt;
  static Color get miniRim => design.miniRim;
  static Color get seatEmpty => design.seatEmpty;
  static Color get avatarFill => design.avatarFill;
  static Color get avatarIcon => design.avatarIcon;
  static Color get giftColor => design.giftColor;
  static Color get adColor => design.adColor;

  /// "Canlı" işareti — tasarımdan bağımsız sinyal rengi.
  static const Color live = Color(0xFFFF4D5E);

  /// Pastel bir SİNYAL rengini (rozet, durum yazısı) zemine uydurur.
  ///
  /// Koyu tasarımlarda olduğu gibi döner. Açık tasarımlarda aynı ton
  /// koyulaştırılır: beyaz kart üstünde nane yeşili/pastel pembe yazı
  /// okunmuyordu, koyu yeşil/kırmızı okunur — anlam (renk ailesi) aynı kalır.
  static Color signal(Color c) {
    if (!isLight) return c;
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness * 0.32).clamp(0.18, 0.3))
        .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
        .toColor();
  }

  /// Kart ÜSTÜNDE vurgu rengiyle yazılan metin/ikon (kazanan adı, sayı).
  ///
  /// Koyu tasarımlarda vurgunun kendisi; açık tasarımlarda vurgunun koyu
  /// "mürekkep" tonu — kiremit/kobalt dolgu rengi beyaz kartta yazı olarak
  /// yeterli kontrast vermiyordu.
  static Color get accentInk => isLight ? design.accentText : design.accent;

  /// Zeminden bir tık ayrışan iç yüzey (segment kutusu, iç panel).
  static Color get wash => text.withValues(alpha: isLight ? 0.05 : 0.08);

  // --- Metin ---------------------------------------------------------------
  static Color get text => design.text;
  static Color get textDim => design.textDim;
  static Color get textFaint => design.textFaint;

  /// Ekran yazı tipi: başlık, çip sayısı, taş numarası. `null` → sistem.
  static String? get displayFont => design.displayFont;

  static TextStyle display({
    double size = 22,
    Color? color,
    double height = 1.1,
  }) => TextStyle(
    fontFamily: design.displayFont,
    fontWeight: design.displayWeight,
    fontSize: size,
    height: height,
    letterSpacing: design.displayLetterSpacing,
    color: color ?? text,
    // Sayılar sütun halinde dizildiğinde kaymasın.
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle get titleLg => display(size: 22, height: 1.15);

  static TextStyle get title => TextStyle(
    color: text,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  static TextStyle get body =>
      TextStyle(color: textDim, fontSize: 13, height: 1.3);

  static TextStyle get caption =>
      TextStyle(color: textFaint, fontSize: 11, height: 1.25);

  /// Bölüm başlığı: BÜYÜK HARFLİ tasarımlarda küçük ve aralıklı, cümle
  /// düzenli tasarımlarda biraz daha iri ve sıkı.
  static TextStyle get sectionLabel => design.uppercase
      ? TextStyle(
          color: design.sectionLabel,
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        )
      : TextStyle(
          color: design.sectionLabel,
          fontSize: 13.5,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        );

  /// Düğme etiketini tasarımın yazı diline çevirir.
  ///
  /// BÜYÜK HARFLİ tasarımlarda etiket KODDA YAZILDIĞI GİBİ kalır (bazı
  /// düğmeler bilerek cümle düzenindedir: "Lobiye dön", "Vazgeç"). Cümle
  /// düzenli tasarımlarda tamamı büyük harfli etiketler ("MASA KUR") cümle
  /// düzenine çevrilir ("Masa kur"); zaten küçük harf içerenlere dokunulmaz.
  static String label(String s) {
    if (design.uppercase) return s;
    return _isAllCaps(s) ? okeySentenceTr(s) : s;
  }

  /// Bölüm başlığını tasarımın yazı diline çevirir: BÜYÜK HARFLİ
  /// tasarımlarda Türkçe büyük harf ("Seni davet edenler" → "SENİ DAVET
  /// EDENLER"), diğerlerinde verildiği gibi.
  static String heading(String s) {
    if (design.uppercase) return okeyUpperTr(s);
    return _isAllCaps(s) ? okeySentenceTr(s) : s;
  }

  static bool _isAllCaps(String s) =>
      s != okeyLowerTr(s) && s == okeyUpperTr(s);

  /// Kartın gölgesi — açık tasarımlarda yumuşak ve geniş, koyularda dar.
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: shadow,
      blurRadius: isLight ? 18 : 10,
      offset: Offset(0, isLight ? 6 : 4),
    ),
  ];

  /// Okey ekranlarının Material teması: varsayılan bileşenler (TextButton,
  /// TextField imleci, ilerleme halkası, diyalog zemini) tasarımla aynı dili
  /// konuşsun. Diyaloglar/alt sayfalar teması çağıranın bağlamından alır.
  static ThemeData materialTheme(ThemeData base) {
    final d = design;
    final scheme = base.colorScheme.copyWith(
      brightness: d.brightness,
      primary: d.accent,
      onPrimary: d.onAccent,
      secondary: d.accent,
      onSecondary: d.onAccent,
      surface: d.cardFill,
      onSurface: d.text,
      surfaceContainerHighest: d.cardFillRaised,
      onSurfaceVariant: d.textDim,
      outline: d.ghostBorder,
      outlineVariant: d.cardBorder,
      error: d.errorText,
    );
    return base.copyWith(
      colorScheme: scheme,
      canvasColor: d.cardFill,
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: d.cardFill,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: title,
        contentTextStyle: body,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: d.cardFill,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: d.cardFill,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: d.isLight ? d.accentEdge : d.accent,
        ),
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: d.accent,
      ),
      textSelectionTheme: base.textSelectionTheme.copyWith(
        cursorColor: d.accent,
        selectionHandleColor: d.accent,
        selectionColor: d.accent.withValues(alpha: 0.3),
      ),
      iconTheme: base.iconTheme.copyWith(color: d.textDim),
      dividerColor: d.cardBorder,
    );
  }

  /// Durum çubuğu simgeleri: açık tasarımda koyu, koyu tasarımda açık.
  static SystemUiOverlayStyle get overlayStyle => isLight
      ? SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent)
      : SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent);
}

/// TASARIM DEĞİŞİNCE ALT AĞACI YENİDEN KURAR.
///
/// [OkeyUI] değerleri build sırasında okunur. `const` bir alt ağaç, üstü
/// yeniden çizilse bile kendi build'ini çalıştırmaz (Flutter aynı örneği
/// atlar) — tasarım değişikliği yarım uygulanırdı. Bu kapsam tasarım ya da
/// düzen değişince alt ağacı YENİ BİR ANAHTARLA kurar: her widget, `const`
/// olsa bile, yeni değerlerle baştan çizilir.
///
/// Bedeli alt ağacın durumunun (kaydırma, filtre) sıfırlanmasıdır; tasarım
/// nadiren ve yalnızca lobide değiştiği için kabul edilir. Oyun ekranında
/// KULLANILMAZ (maç durumu sıfırlanırdı) — orada tasarım zaten değişmez.
class OkeyDesignScope extends StatelessWidget {
  final Widget child;

  const OkeyDesignScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final prefs = OkeyDesignPrefs.instance;
    return ListenableBuilder(
      listenable: prefs.listenable,
      builder: (context, _) => KeyedSubtree(
        key: ValueKey(
          'okey-design/${prefs.current.value.key}/${prefs.layout.value.name}',
        ),
        child: child,
      ),
    );
  }
}

/// Tasarımın Material temasını (ve durum çubuğu biçimini) alt ağaca verir.
///
/// [OkeyScreen] bunu kendisi yapar; kendi Scaffold'unu kuran ekranlar (puan,
/// maç sonucu, skor tablosu, masa) bununla sarılır ki oradan açılan
/// diyalog ve alt sayfalar da tasarımın renklerini alsın.
class OkeyThemed extends StatelessWidget {
  final Widget child;

  /// Masa ekranı her tasarımda koyudur: durum çubuğunu tasarıma göre
  /// değiştirmek orada yanlış olurdu.
  final bool applyOverlayStyle;

  const OkeyThemed({
    super.key,
    required this.child,
    this.applyOverlayStyle = true,
  });

  @override
  Widget build(BuildContext context) {
    final themed = Theme(
      data: OkeyUI.materialTheme(Theme.of(context)),
      child: child,
    );
    if (!applyOverlayStyle) return themed;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: OkeyUI.overlayStyle,
      child: themed,
    );
  }
}

/// Okey ekranlarının ortak zemini: tasarımın gradyanı + dekoru.
class OkeyDesignBackground extends StatelessWidget {
  final Widget child;

  const OkeyDesignBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: OkeyUI.screenGradient),
      child: Stack(
        children: [
          if (OkeyUI.design.decor != OkeyDesignDecor.none)
            Positioned.fill(
              child: IgnorePointer(
                child: OkeyDesignDecorLayer(design: OkeyUI.design),
              ),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
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

    return Theme(
      data: OkeyUI.materialTheme(Theme.of(context)),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: OkeyUI.overlayStyle,
        child: Scaffold(
          backgroundColor: OkeyUI.screenTop,
          bottomNavigationBar: bottomNav,
          appBar: showAppBar
              ? AppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  foregroundColor: OkeyUI.text,
                  systemOverlayStyle: OkeyUI.overlayStyle,
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
          body: OkeyDesignBackground(
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

  /// Vurgulu kart — vurgu kenarlığı ve hafif parıltı (ör. "devam eden oyun").
  final bool highlighted;

  /// Kart yüzeyi yerine verilen dolgu (ör. kazanç kartının hafif tonu).
  final Color? fill;

  const OkeyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(OkeyUI.gap),
    this.onTap,
    this.highlighted = false,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final d = OkeyUI.design;
    final decorated = Container(
      decoration: BoxDecoration(
        color: fill ?? OkeyUI.cardFill,
        borderRadius: BorderRadius.circular(OkeyUI.radius),
        border: Border.all(
          color: highlighted
              ? OkeyUI.brass.withValues(alpha: d.isLight ? 0.7 : 0.55)
              : OkeyUI.cardBorder,
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: [
          ...OkeyUI.cardShadow,
          if (highlighted)
            BoxShadow(
              color: OkeyUI.brass.withValues(alpha: d.glow ? 0.35 : 0.15),
              blurRadius: d.glow ? 20 : 16,
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
  /// Vurgu — ekranın BİRİNCİL eylemi. Ekran başına en fazla bir tane.
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
///
/// Etiket tasarımın yazı diline çevrilir (bkz. [OkeyUI.label]): "MASA KUR"
/// cümle düzenli tasarımlarda "Masa kur" görünür.
class OkeyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final OkeyButtonTone tone;
  final bool busy;
  final bool expand;

  /// Kart içi kompakt düğme (36 px): masa kartındaki OTUR/İZLE gibi.
  final bool dense;

  /// Varsayılan 50 / 36 (dense) yerine özel yükseklik (ör. 58 px afiş
  /// düğmesi).
  final double? height;

  const OkeyButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = OkeyButtonTone.secondary,
    this.busy = false,
    this.expand = true,
    this.dense = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final d = OkeyUI.design;
    final enabled = onPressed != null && !busy;
    final radius = OkeyUI.buttonRadius;

    final (
      Color? fill,
      Gradient? gradient,
      Color fg,
      Color? border,
    ) = switch (tone) {
      OkeyButtonTone.primary => (
        null,
        LinearGradient(
          begin: d.glow ? Alignment.centerLeft : Alignment.topCenter,
          end: d.glow ? Alignment.centerRight : Alignment.bottomCenter,
          colors: OkeyUI.goldGradient,
        ),
        OkeyUI.onGold,
        null,
      ),
      OkeyButtonTone.secondary => (
        OkeyUI.secondaryFill,
        null,
        OkeyUI.text,
        OkeyUI.secondaryBorder,
      ),
      OkeyButtonTone.ghost => (
        Colors.transparent,
        null,
        d.isLight ? OkeyUI.goldEdge : OkeyUI.text,
        OkeyUI.ghostBorder,
      ),
      OkeyButtonTone.danger => (
        OkeyUI.dangerFill,
        null,
        OkeyUI.dangerText,
        OkeyUI.dangerBorder,
      ),
    };

    final content = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
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
                  OkeyUI.label(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? fg : OkeyUI.textFaint,
                    fontSize: dense ? 12 : 14,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: d.uppercase ? 0.6 : 0.1,
                  ),
                ),
              ],
            ),
          );

    final List<BoxShadow>? shadows;
    if (tone == OkeyButtonTone.primary && enabled) {
      shadows = d.glow
          // NEON: kalınlık değil ışık — düğme yüzeyin üstünde parlar.
          ? [
              BoxShadow(
                color: OkeyUI.goldGradient.first.withValues(alpha: 0.45),
                blurRadius: 16,
              ),
              BoxShadow(
                color: OkeyUI.goldGradient.last.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ]
          // Birincil düğme fiziksel bir tuş gibi: altında vurgu kenar
          // kalınlığı + yumuşak gölge.
          : [
              BoxShadow(color: OkeyUI.goldEdge, offset: const Offset(0, 3)),
              BoxShadow(
                color: d.isLight
                    ? OkeyUI.goldEdge.withValues(alpha: 0.25)
                    : const Color(0x59000000),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ];
    } else {
      shadows = null;
    }

    final button = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: height ?? (dense ? 36 : 50),
        decoration: BoxDecoration(
          color: fill,
          gradient: enabled ? gradient : null,
          borderRadius: BorderRadius.circular(radius),
          border: border == null ? null : Border.all(color: border),
          boxShadow: shadows,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            onTap: enabled ? withOkeyTapSound(onPressed) : null,
            borderRadius: BorderRadius.circular(radius),
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
              OkeyUI.heading(label),
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

  /// `null` ise aktif tasarımın vurgusu kullanılır.
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
    final color =
        this.color ?? (OkeyUI.isLight ? OkeyUI.chipText : OkeyUI.brass);
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
                style: OkeyUI.display(size: 20, color: color),
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

  /// `null` ise aktif tasarımın vurgusu kullanılır.
  final Color? color;
  final IconData? icon;

  const OkeyPill({super.key, required this.text, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final color =
        this.color ?? (OkeyUI.isLight ? OkeyUI.chipText : OkeyUI.brass);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: OkeyUI.isLight ? 0.10 : 0.16),
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
    final fallback = Icon(
      Icons.person,
      size: size * 0.5,
      color: OkeyUI.avatarIcon,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: OkeyUI.avatarFill,
        border: Border.all(
          color: highlighted ? OkeyUI.brass : OkeyUI.cardBorder,
          width: 2,
        ),
      ),
      child: ClipOval(
        child: url == null
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
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
