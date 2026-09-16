import 'package:flutter/material.dart';

/// Arka planli metin gonderileri / hikayeleri icin ortak palet ve cizim
/// katmani.
///
/// NEDEN KIMLIK SAKLANIYOR: DB'de (posts.background, stories.background)
/// rengin kendisi degil, buradaki [TextBackground.id] saklanir. Boylece palet
/// guncellendiginde eski gonderiler de yeni renklerle cizilir, DB'de renk
/// kopyasi birikmez ve tema/erisilebilirlik duzeltmeleri tek yerden yapilir.
/// Bilinmeyen bir kimlik gelirse [textBackgroundById] null doner ve cagiran
/// taraf SADE (arka plansiz) cizime duser - kirik kart yerine duz metin.
@immutable
class TextBackground {
  /// DB'de saklanan kimlik (DB CHECK: kucuk harf, rakam ve alt cizgi).
  final String id;

  /// Secicide gosterilen okunabilir ad.
  final String label;

  /// En az iki renk; tek renkli zeminler yakin iki ton verir.
  final List<Color> colors;

  final Alignment begin;
  final Alignment end;

  /// Zemin ustundeki yazinin rengi.
  final Color textColor;

  const TextBackground({
    required this.id,
    required this.label,
    required this.colors,
    required this.textColor,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  LinearGradient get gradient =>
      LinearGradient(colors: colors, begin: begin, end: end);

  /// Zemin acik mi? Uzerine binen ikon/rozetlerin rengi bunu kullanir.
  bool get isLightSurface => textColor.computeLuminance() < 0.5;
}

const Color _kInk = Color(0xFF15202B);

/// Secilebilir arka planlar. Sira secicideki siradir; yeni renk EKLENEBILIR,
/// ama var olan bir id DEGISTIRILMEMELI (eski gonderiler o kimligi sakliyor).
const List<TextBackground> kTextBackgrounds = <TextBackground>[
  TextBackground(
    id: 'midnight',
    label: 'Gece',
    colors: [Color(0xFF141E30), Color(0xFF243B55)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'sunset',
    label: 'Gun Batimi',
    colors: [Color(0xFFFF512F), Color(0xFFF09819)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'ocean',
    label: 'Okyanus',
    colors: [Color(0xFF2193B0), Color(0xFF6DD5ED)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'forest',
    label: 'Orman',
    colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'grape',
    label: 'Mor',
    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'candy',
    label: 'Seker',
    colors: [Color(0xFFFF6FD8), Color(0xFF3813C2)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'peach',
    label: 'Seftali',
    colors: [Color(0xFFFFD3A5), Color(0xFFFD6585)],
    textColor: _kInk,
  ),
  TextBackground(
    id: 'lemon',
    label: 'Limon',
    colors: [Color(0xFFF7971E), Color(0xFFFFD200)],
    textColor: _kInk,
  ),
  TextBackground(
    id: 'mint',
    label: 'Nane',
    colors: [Color(0xFF00B09B), Color(0xFF96C93D)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'sky',
    label: 'Gokyuzu',
    colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'rose',
    label: 'Gul',
    colors: [Color(0xFFEE0979), Color(0xFFFF6A00)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'steel',
    label: 'Celik',
    colors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'cherry',
    label: 'Visne',
    colors: [Color(0xFFB31217), Color(0xFFE52D27)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'sand',
    label: 'Kum',
    colors: [Color(0xFFF6F0E4), Color(0xFFE3D5B8)],
    textColor: _kInk,
  ),
  TextBackground(
    id: 'paper',
    label: 'Kagit',
    colors: [Color(0xFFFFFFFF), Color(0xFFEDF1F5)],
    textColor: _kInk,
  ),
  TextBackground(
    id: 'ink',
    label: 'Murekkep',
    colors: [Color(0xFF0F2027), Color(0xFF203A43)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'aurora',
    label: 'Kutup',
    colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
    textColor: _kInk,
  ),
  TextBackground(
    id: 'lavender',
    label: 'Lavanta',
    colors: [Color(0xFFC471F5), Color(0xFFFA71CD)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'coffee',
    label: 'Kahve',
    colors: [Color(0xFF3E2723), Color(0xFF6D4C41)],
    textColor: Colors.white,
  ),
  TextBackground(
    id: 'emerald',
    label: 'Zumrut',
    colors: [Color(0xFF134E5E), Color(0xFF71B280)],
    textColor: Colors.white,
  ),
];

/// Kimlikten arka plan bulur. Bilinmeyen/bos kimlik icin null doner -
/// cagiran taraf sade metin cizimine dusmelidir.
TextBackground? textBackgroundById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final bg in kTextBackgrounds) {
    if (bg.id == id) return bg;
  }
  return null;
}

/// Kimlikten arka plan bulur, bulunamazsa paletin ilk rengine duser.
///
/// Metin HIKAYELERI icin: hikayenin gorseli yoktur, zeminsiz cizim mumkun
/// degil - bilinmeyen kimlikte bos siyah kare yerine gecerli bir zemin cizmek
/// gerekir. Gonderilerde ise sade cizim gecerli bir sonuc oldugu icin
/// [textBackgroundById] kullanilir.
TextBackground textBackgroundOrDefault(String? id) =>
    textBackgroundById(id) ?? kTextBackgrounds.first;

/// Metin uzunluguna ve kutunun kisa kenarina gore punto secer.
///
/// Kisa yazi buyuk ve iddiali, uzun yazi kucuk ama hala okunur. Kutunun kisa
/// kenarina oranli oldugu icin ayni hesap hem 3'lu izgara karesinde hem tam
/// ekran hikayede calisir.
double textBackgroundFontSize(String text, double shortestSide) {
  final length = text.characters.length;
  final double factor;
  if (length <= 20) {
    factor = 0.135;
  } else if (length <= 50) {
    factor = 0.105;
  } else if (length <= 100) {
    factor = 0.080;
  } else if (length <= 200) {
    factor = 0.062;
  } else {
    factor = 0.050;
  }
  return (shortestSide * factor).clamp(11.0, 46.0);
}

/// Arka planli metnin ortak cizimi: zemin + ortalanmis yazi.
///
/// Feed kartinda, gonderi detayinda, profil izgarasinda ve hikaye
/// goruntuleyicide ayni widget kullanilir; boylece bir gonderi nerede
/// gorunurse gorunsun ayni kompozisyona sahip olur.
class TextBackgroundCanvas extends StatelessWidget {
  final TextBackground background;
  final String text;

  /// Izgara karesi gibi dar yerlerde satir siniri; tam ekranda null.
  final int? maxLines;

  final EdgeInsets padding;

  /// Punto carpani (izgarada biraz kucultmek icin).
  final double fontScale;

  final TextAlign textAlign;

  const TextBackgroundCanvas({
    super.key,
    required this.background,
    required this.text,
    this.maxLines,
    this.padding = const EdgeInsets.all(20),
    this.fontScale = 1.0,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: background.gradient),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final shortest = height.isFinite && height < width ? height : width;
          final size = textBackgroundFontSize(text, shortest) * fontScale;

          return Padding(
            padding: padding,
            child: Center(
              child: Text(
                text,
                textAlign: textAlign,
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  color: background.textColor,
                  fontSize: size,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Arka plan secici serit. Yatay kaydirilir; istege bagli ilk oge "arka plan
/// yok" (sade) secenegidir - sade metin gonderisi hala gecerli bir secim.
class TextBackgroundPicker extends StatelessWidget {
  /// Secili arka plan kimligi; null = sade.
  final String? selectedId;

  /// Secim degisince cagrilir (null = sade).
  final ValueChanged<String?> onSelected;

  /// Sade secenegi gosterilsin mi? Hikayelerde metin her zaman zeminli
  /// oldugu icin orada kapatilir.
  final bool allowNone;

  final double itemSize;

  const TextBackgroundPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.allowNone = true,
    this.itemSize = 44,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (allowNone) _noneSwatch(),
      for (final bg in kTextBackgrounds) _swatch(bg),
    ];

    return SizedBox(
      height: itemSize + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) => items[index],
      ),
    );
  }

  Widget _noneSwatch() {
    return _wrap(
      selected: selectedId == null,
      onTap: () => onSelected(null),
      child: Container(
        color: Colors.white,
        alignment: Alignment.center,
        child: const Icon(
          Icons.format_color_reset_outlined,
          size: 20,
          color: _kInk,
        ),
      ),
    );
  }

  Widget _swatch(TextBackground bg) {
    return _wrap(
      selected: bg.id == selectedId,
      onTap: () => onSelected(bg.id),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: bg.gradient),
        child: Center(
          child: Text(
            'Aa',
            style: TextStyle(
              color: bg.textColor,
              fontSize: itemSize * 0.30,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrap({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: itemSize,
        height: itemSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 3 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: ClipOval(child: child),
      ),
    );
  }
}
