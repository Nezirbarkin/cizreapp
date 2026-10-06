import 'package:flutter/material.dart';

import '../theme/okey_design.dart';
import '../theme/okey_design_decor.dart';
import '../theme/okey_rack_style.dart';
import '../theme/okey_table_theme.dart';

/// Bir [OkeyDesign]ın KÜÇÜK ÖNİZLEMESİ — telefon biçiminde bir lobi taslağı
/// ve altında o tasarımın masası (zemin + taşlar + ıstaka).
///
/// ## Neden gerçek lobi değil
///
/// [OkeyUI] token'ları AKTİF tasarımdan okunur; yönetici yedi tasarımı yan
/// yana görmek ister. Bu widget her rengi doğrudan verilen [design]dan alır,
/// yani aynı ekranda birbirinden farklı yedi tasarım çizilebilir. Biçimler
/// gerçek lobinin oranlarını taklit eder (başlık, afiş, kartlar, alt çubuk)
/// ve seçili DÜZENE göre değişir: Salon / Arena / Kompakt.
///
/// Metin YOKTUR — çubuklar metnin yerini tutar. Önizleme 90 px genişliğe
/// kadar küçüldüğünde bile taşmaz, çünkü her ölçü genişliğin oranıdır.
class OkeyDesignPreview extends StatelessWidget {
  final OkeyDesign design;

  /// `null` → tasarımın kendi düzeni.
  final OkeyLobbyLayout? layout;

  /// Altta masa şeridi çizilsin mi.
  final bool showTable;

  const OkeyDesignPreview({
    super.key,
    required this.design,
    this.layout,
    this.showTable = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final u = w / 100; // birim: genişliğin yüzdesi
        final d = design;
        final l = layout ?? d.layout;
        final r = (d.radius * u * 0.35).clamp(2.0, 10.0);

        Widget bar(double width, double h, Color color) => Container(
          width: width,
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(h / 2),
          ),
        );

        Widget card({required Widget child, double? height, EdgeInsets? pad}) =>
            Container(
              height: height,
              padding: pad ?? EdgeInsets.all(3 * u),
              decoration: BoxDecoration(
                color: d.cardFill,
                borderRadius: BorderRadius.circular(r),
                border: Border.all(color: d.cardBorder, width: 0.6),
                boxShadow: d.isLight
                    ? [BoxShadow(color: d.shadow, blurRadius: 3 * u)]
                    : null,
              ),
              child: child,
            );

        Widget accentBtn(double h) => Container(
          height: h,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: d.accentGradient),
            borderRadius: BorderRadius.circular(
              d.buttonShape == OkeyButtonShape.pill
                  ? h
                  : d.buttonShape == OkeyButtonShape.sharp
                  ? 1.5
                  : r * 0.8,
            ),
            boxShadow: d.glow
                ? [
                    BoxShadow(
                      color: d.accentGradient.first.withValues(alpha: 0.6),
                      blurRadius: 4 * u,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: bar(22 * u, h * 0.22, d.onAccent.withValues(alpha: 0.8)),
        );

        Widget seatMini(double s) => Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: d.miniFelt,
            border: Border.all(color: d.miniRim, width: s * 0.08),
          ),
        );

        Widget tableRow() => Padding(
          padding: EdgeInsets.only(bottom: 2.5 * u),
          child: card(
            pad: EdgeInsets.all(2.5 * u),
            child: Row(
              children: [
                seatMini(9 * u),
                SizedBox(width: 3 * u),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      bar(32 * u, 2.4 * u, d.text),
                      SizedBox(height: 1.6 * u),
                      bar(22 * u, 1.8 * u, d.textFaint),
                    ],
                  ),
                ),
                SizedBox(width: 13 * u, child: accentBtn(6 * u)),
              ],
            ),
          ),
        );

        final header = Row(
          children: [
            Container(
              width: 9 * u,
              height: 9 * u,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: d.avatarFill,
                border: Border.all(color: d.accent, width: 0.8),
              ),
            ),
            SizedBox(width: 2.5 * u),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  bar(26 * u, 2.6 * u, d.text),
                  SizedBox(height: 1.4 * u),
                  bar(18 * u, 1.8 * u, d.textFaint),
                ],
              ),
            ),
            Container(
              width: 20 * u,
              height: 7 * u,
              decoration: BoxDecoration(
                color: d.pillFill,
                borderRadius: BorderRadius.circular(4 * u),
                border: Border.all(color: d.pillBorder, width: 0.6),
              ),
              alignment: Alignment.center,
              child: bar(10 * u, 2 * u, d.accentText),
            ),
          ],
        );

        Widget hero(double h) => Container(
          height: h,
          padding: EdgeInsets.all(3.5 * u),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: d.heroGradient,
            ),
            borderRadius: BorderRadius.circular(d.heroRadius * u * 0.3),
            border: d.glow
                ? Border.all(color: d.accent.withValues(alpha: 0.6), width: 0.8)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(36 * u, 4 * u, d.onHero),
                        SizedBox(height: 2 * u),
                        bar(28 * u, 1.8 * u, d.onHeroDim),
                      ],
                    ),
                  ),
                  seatMini(13 * u),
                ],
              ),
              const Spacer(),
              accentBtn(8 * u),
            ],
          ),
        );

        final List<Widget> body = switch (l) {
          OkeyLobbyLayout.salon => [
            hero(40 * u),
            SizedBox(height: 2.5 * u),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: card(
                    height: 8 * u,
                    pad: EdgeInsets.zero,
                    child: const SizedBox(),
                  ),
                ),
                SizedBox(width: 2 * u),
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 8 * u,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(r * 0.8),
                      border: Border.all(color: d.ghostBorder, width: 0.6),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 3.5 * u),
            bar(18 * u, 1.8 * u, d.sectionLabel),
            SizedBox(height: 2.5 * u),
            tableRow(),
            tableRow(),
          ],
          OkeyLobbyLayout.arena => [
            hero(50 * u),
            SizedBox(height: 2.5 * u),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: 2 * u),
                  Expanded(
                    child: card(
                      height: 14 * u,
                      pad: EdgeInsets.all(2 * u),
                      child: Center(
                        child: Container(
                          width: 6 * u,
                          height: 6 * u,
                          decoration: BoxDecoration(
                            color: d.accent.withValues(alpha: 0.25),
                            shape: d.buttonShape == OkeyButtonShape.sharp
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 3 * u),
            Row(
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i > 0) SizedBox(width: 2 * u),
                  Expanded(
                    child: card(
                      height: 26 * u,
                      pad: EdgeInsets.all(2.5 * u),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          seatMini(8 * u),
                          SizedBox(height: 2 * u),
                          bar(24 * u, 2 * u, d.text),
                          const Spacer(),
                          accentBtn(5.5 * u),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          OkeyLobbyLayout.kompakt => [
            card(
              height: 10 * u,
              pad: EdgeInsets.symmetric(horizontal: 3 * u),
              child: Row(
                children: [
                  bar(6 * u, 6 * u, d.giftColor.withValues(alpha: 0.7)),
                  SizedBox(width: 2 * u),
                  bar(16 * u, 2 * u, d.text),
                  const Spacer(),
                  bar(6 * u, 6 * u, d.adColor.withValues(alpha: 0.7)),
                  SizedBox(width: 2 * u),
                  bar(16 * u, 2 * u, d.text),
                ],
              ),
            ),
            SizedBox(height: 2.5 * u),
            Container(
              height: 8 * u,
              padding: EdgeInsets.all(1.2 * u),
              decoration: BoxDecoration(
                color: d.text.withValues(alpha: d.isLight ? 0.05 : 0.08),
                borderRadius: BorderRadius.circular(4 * u),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: d.cardFill,
                        borderRadius: BorderRadius.circular(3 * u),
                      ),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
            SizedBox(height: 2.5 * u),
            card(
              pad: EdgeInsets.symmetric(horizontal: 2.5 * u, vertical: 1 * u),
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 1.6 * u),
                      child: Row(
                        children: [
                          seatMini(7 * u),
                          SizedBox(width: 2.5 * u),
                          bar(30 * u, 2.2 * u, d.text),
                          const Spacer(),
                          bar(8 * u, 2.2 * u, d.accentText),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        };

        final phone = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: d.screenGradient,
              stops: d.screenStops,
            ),
          ),
          child: Stack(
            children: [
              if (d.decor != OkeyDesignDecor.none)
                Positioned.fill(
                  child: OkeyDesignDecorLayer(design: d, scale: u * 0.45),
                ),
              Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(4 * u, 5 * u, 4 * u, 0),
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          maxHeight: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              header,
                              SizedBox(height: 4 * u),
                              ...body,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (l == OkeyLobbyLayout.kompakt)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        4 * u,
                        1.5 * u,
                        4 * u,
                        2 * u,
                      ),
                      child: accentBtn(8 * u),
                    ),
                  // Alt gezinme çubuğu.
                  Container(
                    height: 10 * u,
                    decoration: BoxDecoration(
                      color: d.navFill,
                      border: Border(
                        top: BorderSide(color: d.cardBorder, width: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < 4; i++)
                          Container(
                            width: i == 0 ? 9 * u : 3 * u,
                            height: 3 * u,
                            decoration: BoxDecoration(
                              color: i == 0
                                  ? d.accent.withValues(alpha: 0.8)
                                  : d.textFaint,
                              borderRadius: BorderRadius.circular(2 * u),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        return ClipRRect(
          borderRadius: BorderRadius.circular(3 * u),
          child: Column(
            children: [
              Expanded(child: phone),
              if (showTable)
                OkeyTableSwatch(
                  theme: d.tableTheme,
                  rack: d.rackStyle,
                  height: 22 * u,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Masa şeridi: tema zemininde dört taş ve altında ıstaka gövdesi.
///
/// Admin kartlarında ve oyuncunun Görünüm sayfasında "masa nasıl
/// görünecek" sorusunun cevabı — kelimeyle değil gözle.
class OkeyTableSwatch extends StatelessWidget {
  final OkeyTableTheme theme;
  final OkeyRackStyle rack;
  final double height;

  const OkeyTableSwatch({
    super.key,
    required this.theme,
    required this.rack,
    required this.height,
  });

  static const _inks = [
    Color(0xFFE53935),
    Color(0xFFF9A825),
    Color(0xFF212121),
    Color(0xFF1E88E5),
  ];

  @override
  Widget build(BuildContext context) {
    final h = height;
    return Container(
      height: h,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.6,
          colors: [theme.damaskLight, theme.damaskMid, theme.damaskDeep],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: h * 0.34,
                    height: h * 0.46,
                    margin: EdgeInsets.symmetric(horizontal: h * 0.04),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [theme.tileIvoryLight, theme.tileIvoryDark],
                      ),
                      borderRadius: BorderRadius.circular(h * 0.05),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: h * 0.12,
                      height: h * 0.18,
                      decoration: BoxDecoration(
                        color: _inks[i],
                        borderRadius: BorderRadius.circular(h * 0.03),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Istaka gövdesi + vurgu ipi.
          Container(
            height: h * 0.2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: rack.body,
                stops: const [0.0, 0.18, 0.74, 1.0],
              ),
              border: Border(top: BorderSide(color: rack.accent, width: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
