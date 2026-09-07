import 'package:flutter/material.dart';

import '../engine/okey_tile.dart';
import '../theme/okey_theme.dart';
import 'okey_drag_payload.dart';
import 'okey_table_metrics.dart';
import 'okey_tile_widget.dart';

/// Masanın ORTASINDAKİ ada: gösterge → okey → kalan deste.
///
/// ## Neden okey taşı da gösteriliyor
///
/// Kural gereği okey, göstergenin aynı renkteki bir üst rakamıdır (Mavi 7 →
/// Mavi 8; Mavi 13 → Mavi 1). Eski şerit yalnızca göstergeyi gösteriyor, bu
/// çevirmeyi oyuncunun zihninden yapmasını bekliyordu — özellikle 13→1
/// sarmasında sık hata kaynağıydı. Okey taşı sunucudan zaten geliyor
/// (`OkeyMatch.okeyTile`), o yüzden doğrudan gösterilir.
///
/// Sıra süre sayacı BURADA DEĞİLDİR: ıstakanın üstündeki azalan çizgiye
/// taşındı (bkz. OkeyTurnTimerBar).
class OkeyIndicatorWidget extends StatelessWidget {
  final OkeyTile indicatorTile;

  /// Göstergeden türeyen okey taşı. Null ise okey bölümü gizlenir.
  final OkeyTile? okeyTile;

  final int deckRemaining;
  final bool isMyTurn;
  final VoidCallback? onTapDeck;

  /// Desteden SÜRÜKLEYEREK çekme aktif mi (ıstakaya bırakılınca tetiklenir).
  final bool canDragFromDeck;

  /// Adadaki taşların genişliği.
  final double tileWidth;

  /// DİKEY sütun yerleşimi — per alanının sağındaki dar bilgi sütunu için.
  ///
  /// Yatay şerit 892px'lik bir masanın üst kenarında sorunsuzdu; 78px'lik
  /// bir sütunda ise FittedBox onu %30'a küçültüyor, gösterge taşı tırnak
  /// ucu kadar kalıyordu. Dikey yerleşim aynı üç bilgiyi sütunun BOYUNU
  /// kullanarak taşır.
  final bool vertical;

  /// DESTE YIĞINININ kendi anahtarı — uçan taşın çıkış noktası.
  ///
  /// Neden ayrı: bu widget üç şeyi birden taşıyor (gösterge, okey, deste) ve
  /// anahtarı en dışa koyduğumuzda uçan taş SÜTUNUN ORTASINDAN, yani
  /// göstergeyle destenin arasındaki boşluktan çıkıyordu. Oyuncunun gördüğü
  /// şey "taş desteden geldi" değil, "taş bir yerlerden belirdi" oluyordu.
  /// Anahtar destenin kendisine bağlanınca çıkış noktası gerçek oluyor
  /// (bkz. OkeyMoveFlightOverlay).
  final Key? deckKey;

  const OkeyIndicatorWidget({
    super.key,
    required this.indicatorTile,
    required this.deckRemaining,
    required this.isMyTurn,
    this.okeyTile,
    this.onTapDeck,
    this.canDragFromDeck = false,
    this.tileWidth = 28,
    this.vertical = false,
    this.deckKey,
  });

  double get _tileHeight => tileWidth / OkeyTableMetrics.tileAspect;

  @override
  Widget build(BuildContext context) {
    // Sabit ölçülü oyun kromu — sistem yazı tipi büyütmesiyle büyümez
    // (bkz. OkeyTileWidget'taki aynı gerekçe).
    return MediaQuery.withNoTextScaling(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tileWidth * (vertical ? 0.22 : 0.5),
          vertical: tileWidth * 0.22,
        ),
        decoration: BoxDecoration(
          // Masadaki bütün kontrollerle AYNI cam yüzey (bkz. OkeyV3):
          // ada eskiden yarı saydam, kenarı neredeyse görünmeyen bir
          // lekeydi ve keçenin bir gölgesi gibi duruyordu.
          color: OkeyV3.surface,
          borderRadius: BorderRadius.circular(OkeyV3.radius + 2),
          border: Border.all(
            color: canDragFromDeck
                ? OkeyV3.draw.withValues(alpha: 0.45)
                : OkeyV3.border,
          ),
          boxShadow: [
            ...OkeyV3.lift,
            // Sıra bendeyken ve deste çekilebilirken ada hafifçe yeşile
            // çalar: "buradan taş alabilirsin" sinyali.
            if (canDragFromDeck)
              BoxShadow(
                color: OkeyV3.draw.withValues(alpha: 0.18),
                blurRadius: 14,
              ),
          ],
        ),
        // FittedBox GÜVENLİK AĞI: çok dar bir masada ada, hata vermek yerine
        // birlikte küçülerek sığar.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: vertical ? _verticalBody() : _horizontalBody(),
        ),
      ),
    );
  }

  /// DİKEY yerleşim — per alanının sağındaki dar bilgi sütunu.
  ///
  /// Gösterge ve okey YAN YANA durur, deste altlarında. Üçü alt alta
  /// dizilseydi sütun masanın yüksekliğini aşar, FittedBox hepsini
  /// okunamayacak kadar küçültürdü.
  Widget _verticalBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelled(
              'GÖSTERGE',
              OkeyV3.textFaint,
              OkeyTileWidget(
                tile: indicatorTile,
                width: tileWidth,
                height: _tileHeight,
                tight: true,
              ),
            ),
            if (okeyTile != null) ...[
              SizedBox(width: tileWidth * 0.24),
              _labelled(
                'OKEY',
                OkeyV3.turn,
                OkeyTileWidget(
                  tile: okeyTile!,
                  width: tileWidth,
                  height: _tileHeight,
                  tight: true,
                  highlightAsOkey: true,
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: tileWidth * 0.34),
        _labelled(
          canDragFromDeck ? 'DESTE ▾' : 'DESTE',
          canDragFromDeck ? OkeyV3.draw : OkeyV3.textFaint,
          KeyedSubtree(key: deckKey, child: _buildDeck()),
        ),
      ],
    );
  }

  /// YATAY yerleşim — geniş bir şeride konduğunda (önizleme ve testler).
  Widget _horizontalBody() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _labelled(
          'GÖSTERGE',
          OkeyV3.textFaint,
          OkeyTileWidget(
            tile: indicatorTile,
            width: tileWidth,
            height: _tileHeight,
            tight: true,
          ),
        ),
        if (okeyTile != null) ...[
          SizedBox(width: tileWidth * 0.28),
          Icon(
            Icons.arrow_forward,
            size: tileWidth * 0.46,
            color: const Color(0x4DFFFFFF),
          ),
          SizedBox(width: tileWidth * 0.28),
          _labelled(
            'OKEY',
            OkeyV3.turn,
            OkeyTileWidget(
              tile: okeyTile!,
              width: tileWidth,
              height: _tileHeight,
              tight: true,
              highlightAsOkey: true,
            ),
          ),
        ],
        SizedBox(width: tileWidth * 0.45),
        Container(
          width: 1,
          height: _tileHeight * 0.95,
          color: const Color(0x24FFFFFF),
        ),
        SizedBox(width: tileWidth * 0.45),
        _labelled(
          canDragFromDeck ? 'DESTE ▾' : 'DESTE',
          canDragFromDeck ? OkeyV3.draw : OkeyV3.textFaint,
          KeyedSubtree(key: deckKey, child: _buildDeck()),
        ),
      ],
    );
  }

  Widget _labelled(String label, Color color, Widget child) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8.5,
            height: 1.0,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: color,
          ),
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }

  /// Deste: dokunarak VEYA ıstakaya sürükleyerek taş çekilir.
  ///
  /// Kalan sayı taşın ÜSTÜNDE yüzen ayrı bir etiket değil, taşın İÇİNDE
  /// yazar — deste zaten kapalı taşlardan oluşur, üstünde boş yer vardır ve
  /// sayı orada dururken ada bir satır daha kısalır.
  Widget _buildDeck() {
    final w = tileWidth;
    final h = _tileHeight;

    Widget shadowTile(double dx, double dy, Color color) => Positioned(
      left: dx,
      top: dy,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x33000000)),
        ),
      ),
    );

    final Widget deck = SizedBox(
      // Yığının sağa/yukarı taşan kopyaları için pay.
      width: w + 10,
      height: h + 3,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          shadowTile(10, 0, OkeyColors.tileIvoryDark),
          shadowTile(5, 2, const Color(0xFFE9E1CE)),
          Positioned(
            left: 0,
            top: 3,
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  OkeyTileWidget(
                    tile: const OkeyTile.falseJoker(),
                    faceDown: true,
                    width: w,
                    height: h,
                    tight: true,
                    highlightAsOkey: canDragFromDeck,
                  ),
                  Text(
                    '$deckRemaining',
                    style: TextStyle(
                      fontSize: h * 0.36,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: canDragFromDeck
                          ? const Color(0xFF8A5F1A)
                          : const Color(0xFFA98A5A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Draggable her zaman ağaçtadır; yalnızca etkinliği değişir
    // (bkz. okey_rack_bar_widget.dart'taki gerekçe).
    return Draggable<OkeyDragPayload>(
      data: const OkeyDragPayload.deck(),
      maxSimultaneousDrags: canDragFromDeck ? 1 : 0,
      feedback: const Material(
        color: Colors.transparent,
        child: OkeyTileWidget(tile: OkeyTile.falseJoker(), faceDown: true),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: deck),
      child: GestureDetector(onTap: onTapDeck, child: deck),
    );
  }
}
