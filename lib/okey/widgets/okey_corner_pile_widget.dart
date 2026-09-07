import 'package:flutter/material.dart';

import '../engine/okey_tile.dart';
import '../models/okey_models.dart';
import '../theme/okey_theme.dart';
import 'okey_drag_payload.dart';
import 'okey_hud_chrome.dart';
import 'okey_table_metrics.dart';
import 'okey_tile_widget.dart';

/// Oyuncu kartının masanın HANGİ kenarında durduğu.
///
/// Kenar yalnızca kozmetik değildir: üst/alt kenarda kart YATAY bir isim
/// plakasıdır (avatarın yanında ad), sol/sağ kenarda ise DİKEY bir levhadır
/// (avatar üstte, ad 90° döndürülmüş). Dar kenar sütununda yatay bir plaka
/// ya taşardı ya da okunamayacak kadar küçülürdü.
enum OkeySeatSide { top, left, right, bottom }

/// Kartın hangi parçalarının çizileceği.
///
/// v4'te DÖRT koltuğun da ıskartası kimliğinden AYRI çizilir: ıskartalar
/// masanın dört köşesine, kimlikler kenarların ortasına gider. Sebep
/// kozmetik değil, oyunun yönü: her ıskarta onu ATAN ile onu ALAN oyuncunun
/// ARASINDAKİ köşeye aittir (bkz. OkeyTableScaffold).
enum OkeySeatParts {
  /// Kimlik kartı + ıskarta birlikte (tek kutuya sığdırmak gerektiğinde).
  both,

  /// Yalnızca kimlik plakası (avatar, ad, taş sayısı, skor).
  identity,

  /// Yalnızca ıskarta kutusu — bırakma hedefi.
  discard,
}

/// Masanın bir kenarındaki OYUNCU PLAKASI ya da o oyuncunun ıskartası.
///
/// ## v4 (2026-09) — referans masadaki iki plaka biçimi
///
/// * **Dikey levha** (sol/sağ): üstte kare avatar, altında 90° döndürülmüş
///   ad, dibinde hediye çipi. Kenar sütunu dar ve uzundur; ad yatay
///   yazılsaydı üç harf sonra kırpılırdı.
/// * **Yatay plaka** (üst/alt): solda yuvarlak avatar, yanında ad ve
///   sayaçlar. Üst şerit ve konsol geniş ve alçaktır; orada dikey ad okunmaz.
///
/// Sıra kimdeyse onun levhası YEŞİL yanar. Yeşil burada "sıra sende"
/// demektir ve masadaki tek yeşil odur — dolayısıyla dört kartı tek tek
/// okumadan "kim oynuyor" sorusu yanıtlanır.
///
/// ## Değişmeyen KRİTİK kural
///
/// Iskarta kutusu HİÇBİR KOŞULDA gizlenmez. O kutu aynı zamanda taş
/// çekme/atma için bırakma hedefidir; yer kazanmak uğruna gizlenirse oyun
/// oynanamaz hale gelir. Dar alanda yalnızca küçülür.
class OkeyCornerPileWidget extends StatelessWidget {
  final OkeyRoomSeat? seat;
  final int seatNo;
  final OkeyTile? topDiscard;
  final int tileCount;
  final int score;

  /// Bu koltuğun BU ELDEKİ anlık per puanı: masaya açtığı perlerin ve
  /// işlediği taşların toplam değeri (`okey_matches.open_points`).
  ///
  /// [score] ile aynı şey DEĞİLDİR ve levhada da ayrı gösterilir: [score]
  /// kümülatif CEZADIR (düşük olan iyidir), bu ise elin içinde büyüyen bir
  /// kazanımdır. İkisini tek sayıda birleştirmek, oyuncunun "101'i geçtim mi"
  /// sorusunu masaya bakarak yanıtlamasını imkânsız kılardı.
  final int openPoints;

  final bool isCurrentTurn;
  final bool isMe;
  final bool isOpened;

  /// Bu oyuncunun ıskartasından taş ÇEKİLEBİLİR (soldaki oyuncu).
  final bool isDrawSource;

  /// Bu ıskartaya taş BIRAKILABİLİR (kendi ıskartam — atma).
  final bool isDiscardTarget;

  /// Sıra bu oyuncuda ve hamlesi BEKLENİYOR — nabız atan üç nokta gösterilir.
  ///
  /// ## Neden "bot düşünüyor" değil
  ///
  /// Bu gösterge eskiden YALNIZCA botlar için yanıyordu (adı da
  /// `isBotThinking`'di). Yani üç noktayı gören oyuncu, karşısındakinin bot
  /// olduğunu anlıyordu — masadaki en net ele veren işaret buydu. Artık sırası
  /// gelen HERKES için yanar ve anlamı da gerçekten bu: "onun hamlesi
  /// bekleniyor".
  final bool isThinking;

  final VoidCallback? onTap;
  final void Function(int fromSlot)? onTileDropped;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// Iskarta taşının genişliği — yüksekliği [OkeyTableMetrics.tileAspect]
  /// ile türetilir, böylece masadaki her taş aynı oranda kalır.
  final double size;

  /// Avatar dairesinin çapı (bkz. [OkeyTableMetrics.avatarSize]).
  final double? avatarSize;

  /// Kartın masadaki kenarı.
  final OkeySeatSide side;

  /// Kartın alabileceği azami genişlik.
  final double? maxWidth;

  /// Kartın hangi parçaları çizilsin.
  ///
  /// DİKKAT: [OkeySeatParts.identity] ile ıskarta kutusunu gizlemek, o kutu
  /// başka bir yerde çizilmiyorsa oyunu oynanamaz hale getirir.
  final OkeySeatParts parts;

  // KALDIRILDI: `showGift` / OkeyGiftChip (2026-09-05, kullanıcı isteği
  // "profillerde bulunan karpuz ikonunu ve diğer profillerde bulunanı
  // kaldır").
  //
  // Levhanın dibinde koltuk başına SABİT, renkli bir yuvarlak çip duruyordu:
  // gerçek bir hediye değil, hediye özelliği gelene kadar yerini tutan
  // dekoratif bir yer tutucu. Kimse göndermediği hâlde her oyuncunun altında
  // bir "ikram" duruyordu; yeşil/koyu-yeşil olanı da karpuz dilimi gibi
  // okunuyordu.
  //
  // Hediyeler artık gerçek ve gönderilen hediye alıcının levhasının YANINDA
  // asılı kalıyor (bkz. OkeySeatGiftBadge) — yer tutucunun tuttuğu yer
  // dolduğu için kendisi gereksizleşti.

  /// KİMLİK levhasına dokununca çağrılır — oyuncunun profil kartını açar.
  ///
  /// [onTap]'ten AYRI tutulur: o, ıskarta kutusunun taş çekme/atma
  /// davranışıdır. İkisi tek geri çağrıda birleştirilseydi, taş atmak
  /// isteyen oyuncunun karşısına profil kartı açılırdı.
  final VoidCallback? onProfileTap;

  const OkeyCornerPileWidget({
    super.key,
    required this.seat,
    required this.seatNo,
    required this.tileCount,
    required this.isCurrentTurn,
    required this.size,
    this.topDiscard,
    this.score = 0,
    this.openPoints = 0,
    this.isMe = false,
    this.isOpened = false,
    this.isDrawSource = false,
    this.isDiscardTarget = false,
    this.isThinking = false,
    this.onTap,
    this.onTileDropped,
    this.onDragStart,
    this.onDragEnd,
    this.side = OkeySeatSide.top,
    this.maxWidth,
    this.parts = OkeySeatParts.both,
    this.avatarSize,
    this.onProfileTap,
  });

  /// Sol/sağ kenar: dar sütun, levha DİKEY.
  bool get _vertical => side == OkeySeatSide.left || side == OkeySeatSide.right;

  // --- Referans plaka renkleri --------------------------------------------
  static const _plateDark = [Color(0xF2101A20), Color(0xF2050B0F)];
  static const _plateTurn = [Color(0xF2A8D14A), Color(0xF23F6B17)];
  static const _plateBorder = Color(0x33FFFFFF);
  static const _plateTurnBorder = Color(0xFFD9F58C);

  @override
  Widget build(BuildContext context) {
    // DİKEY KİMLİK LEVHASI kutusunu DOLDURUR — kenar sütunu ne kadar
    // uzunsa levha o kadar uzar. FittedBox'a sarılsaydı doğal boyunda
    // kalır, sütunun ortasında asılı küçük bir kutucuk olurdu.
    if (_vertical && parts == OkeySeatParts.identity) {
      return MediaQuery.withNoTextScaling(
        child: _profileTappable(_verticalPlate()),
      );
    }

    final Widget body = switch (parts) {
      OkeySeatParts.identity => _profileTappable(_identityCard()),
      OkeySeatParts.discard => _discardSlot(),
      OkeySeatParts.both =>
        _vertical
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _identityCard(),
                  const SizedBox(height: 6),
                  _discardSlot(),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _identityCard(),
                  const SizedBox(width: 8),
                  _discardSlot(),
                ],
              ),
    };

    // İKİ SAVUNMA KATMANI:
    //
    // 1) withNoTextScaling — kart SABİT ÖLÇÜLÜ oyun kromudur; ölçüleri
    //    OkeyTableMetrics'ten türeyen kutulara sığmak zorunda. Sistemin yazı
    //    tipi büyütmesiyle büyüseydi o hesaplar tutmaz, kart masadan taşardı.
    //
    // 2) FittedBox(scaleDown) — son güvenlik ağı. Beklenmedik derecede dar
    //    bir kutuya konursa kart HATA VERMEK yerine küçülerek sığar. Iskarta
    //    kutusu bırakma hedefi olduğu için "taşarsa kırpılsın" seçeneği yok:
    //    kırpılan bir hedefe taş bırakılamaz.
    return MediaQuery.withNoTextScaling(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: maxWidth == null
            ? body
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth!),
                child: body,
              ),
      ),
    );
  }

  /// Kimlik levhasını dokunulabilir yapar (profil kartı için).
  Widget _profileTappable(Widget child) {
    if (onProfileTap == null || seat == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onProfileTap,
      child: child,
    );
  }

  String get _name {
    if (seat == null) return 'Boş';
    if (isMe) return 'Sen';
    // Bot olup olmadığını ELE VERMEZ (bkz. OkeyRoomSeat.displayLabel).
    return seat!.displayLabel;
  }

  // ---------------------------------------------------------------------
  // DİKEY LEVHA (sol / sağ kenar)
  // ---------------------------------------------------------------------

  /// Referanstaki dar, uzun oyuncu levhası.
  ///
  /// Yapı yukarıdan aşağı: kare avatar → 90° döndürülmüş ad → kalan taş
  /// sayısı → hediye çipi. Ad, sütunun BOYU kadar yer bulur; sütun ne kadar
  /// uzarsa o kadar uzun bir ad sığar.
  Widget _verticalPlate() {
    // Ad, soldaki levhada aşağıdan yukarı, sağdakinde yukarıdan aşağı okunur
    // — iki levha birbirinin AYNASI olur ve masa simetrik görünür.
    final quarterTurns = side == OkeySeatSide.left ? 3 : 1;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isCurrentTurn ? _plateTurn : _plateDark,
        ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isCurrentTurn
              ? _plateTurnBorder
              : (seat == null ? OkeyV3.borderDisabled : _plateBorder),
          width: isCurrentTurn ? 1.4 : 1,
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x8A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
          if (isCurrentTurn)
            const BoxShadow(color: Color(0x66A8D14A), blurRadius: 14),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.hasBoundedWidth ? c.maxWidth : 60.0;
          final h = c.hasBoundedHeight && c.maxHeight.isFinite
              ? c.maxHeight
              : 200.0;
          // Avatar, levhanın genişliği kadar bir KARE; ama levha çok kısaysa
          // (çok kısa ekran) yüksekliğin üçte birini geçemez.
          final avatarBox = (w - 4).clamp(0.0, h * 0.34);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(2),
                child: SizedBox(
                  width: avatarBox,
                  height: avatarBox,
                  child: _avatarSquare(avatarBox),
                ),
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RotatedBox(
                      quarterTurns: quarterTurns,
                      child: Text(
                        _name,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: (w * 0.24).clamp(8.0, 14.0),
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: isCurrentTurn
                              ? const Color(0xFF10220A)
                              : (seat == null
                                    ? OkeyV3.textDisabled
                                    : OkeyV3.text),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (isThinking)
                const Padding(
                  padding: EdgeInsets.only(bottom: 3),
                  child: _Pulse(fade: true, child: _ThinkingDots()),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _counters(compact: true),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Dikey levhanın tepesindeki KARE avatar (referansta fotoğraf oraya
  /// oturur). Yuvarlak avatar dar levhada yanlarda boşluk bırakıyordu.
  Widget _avatarSquare(double d) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        color: const Color(0xFF06222B),
        // BOTUN FOTOĞRAFI DA ÇİZİLİR. Eskiden koşulda `!isBot` vardı: admin
        // panelinden yüklenen avatar masada hiç görünmüyor, bot her zaman
        // ikonla çıkıp kendini ele veriyordu.
        child: (seat?.avatarUrl != null)
            ? Image.network(
                seat!.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _avatarIcon(d),
              )
            : _avatarIcon(d),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // YATAY PLAKA (üst / alt kenar)
  // ---------------------------------------------------------------------

  Widget _identityCard() {
    final d = avatarSize ?? 30.0;

    final Widget content = _vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _avatar(d),
              const SizedBox(height: 4),
              _nameText(),
              const SizedBox(height: 3),
              _counters(),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _avatar(d),
              const SizedBox(width: 7),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_nameText(), const SizedBox(height: 3), _counters()],
              ),
            ],
          );

    return Container(
      constraints: BoxConstraints(maxWidth: _vertical ? 108 : 220),
      padding: EdgeInsets.symmetric(
        horizontal: _vertical ? 6 : 7,
        vertical: _vertical ? 6 : 4,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isCurrentTurn ? _plateTurn : _plateDark,
        ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isCurrentTurn
              ? _plateTurnBorder
              : (seat == null ? OkeyV3.borderDisabled : _plateBorder),
          width: isCurrentTurn ? 1.4 : 1,
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x8A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
          if (isCurrentTurn)
            const BoxShadow(color: Color(0x66A8D14A), blurRadius: 14),
        ],
      ),
      // Ad + sayaçlar sütunu, kartın azami genişliğini birkaç piksel
      // aşabiliyordu ("RenderFlex overflowed by 2.0 pixels"). İçindeki
      // metinler sabit ölçülü olduğu için kendi küçülme yolları yok;
      // küçültmeyi burada veriyoruz.
      child: FittedBox(fit: BoxFit.scaleDown, child: content),
    );
  }

  Widget _nameText() {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _vertical ? 92 : 130),
      child: Text(
        _name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: _vertical ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          fontSize: _vertical ? 10.5 : 11.5,
          height: 1.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: isCurrentTurn
              ? const Color(0xFF10220A)
              : (seat == null ? OkeyV3.textDisabled : OkeyV3.text),
        ),
      ),
    );
  }

  /// Kalan taş sayısı · ANLIK PER PUANI · kümülatif ceza.
  /// Bot düşünüyorsa sayaçların yerini nabız alır.
  ///
  /// ANLIK PUAN dar levhada (compact) da gösterilir, ceza gösterilmez: ceza
  /// el bitene kadar değişmez ve el sonu kartında zaten okunur; anlık puan
  /// ise her hamlede değişen, masaya bakarken gerçekten gereken sayıdır.
  Widget _counters({bool compact = false}) {
    if (isThinking && !compact) {
      return const _Pulse(fade: true, child: _ThinkingDots());
    }
    if (seat == null) return const SizedBox.shrink();

    final fg = isCurrentTurn ? const Color(0xCC10220A) : OkeyV3.textDim;

    Widget dot() => Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Elini AÇMIŞ oyuncu: artık işleyebilir, tehlikelidir. Sessiz bir
        // ikon değil, açık bir rozet — masadaki en önemli durum bilgisi.
        if (isOpened) ...[
          Icon(
            Icons.lock_open,
            size: 10,
            color: isCurrentTurn
                ? const Color(0xFF10220A)
                : const Color(0xFF9BE87C),
          ),
          const SizedBox(width: 3),
        ],
        _TileCountIcon(color: fg),
        const SizedBox(width: 3),
        Text(
          '$tileCount',
          style: TextStyle(
            fontSize: 9.5,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
        // ANLIK PER PUANI — arttığı anda kısa bir parlama ile büyür, çünkü
        // masada değişen tek sayı odur ve değişimi bir HAMLENİN sonucudur
        // (per açıldı ya da taş işlendi).
        const SizedBox(width: 5),
        dot(),
        const SizedBox(width: 5),
        OkeyOpenPointsText(
          points: openPoints,
          fontSize: 9.5,
          color: isCurrentTurn
              ? const Color(0xFF10220A)
              : OkeyColors.accentGold,
        ),
        if (!compact) ...[
          const SizedBox(width: 5),
          dot(),
          const SizedBox(width: 5),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 9.5,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: isCurrentTurn ? const Color(0xFF10220A) : OkeyV3.turn,
            ),
          ),
        ],
      ],
    );
  }

  Widget _avatar(double d) {
    // HALKA RENGİ BOTU AYIRT ETMEZ. Eskiden botun halkası soluk gri
    // çiziliyordu; masadaki dört karttan hangisinin bot olduğu tek bakışta
    // okunuyordu.
    final ringColor = seat == null
        ? const Color(0x2EFFFFFF)
        : (isCurrentTurn ? const Color(0xFFEAFFB8) : OkeyColors.avatarRing);

    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF06222B),
        border: Border.all(color: ringColor, width: 2),
      ),
      child: ClipOval(
        child: (seat?.avatarUrl != null)
            ? Image.network(
                seat!.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _avatarIcon(d),
              )
            : _avatarIcon(d),
      ),
    );
  }

  Widget _avatarIcon(double d) {
    if (seat == null) {
      return Icon(
        Icons.person_off_outlined,
        size: d * 0.46,
        color: const Color(0x47FFFFFF),
      );
    }
    return Icon(
      Icons.person,
      size: d * 0.52,
      color: isCurrentTurn ? const Color(0xFF10220A) : const Color(0xFF9FD9CF),
    );
  }

  // ---------------------------------------------------------------------
  // ISKARTA: çekme kaynağı (yeşil) / atma hedefi (mavi) / sade
  // ---------------------------------------------------------------------

  Widget _discardSlot() {
    final tileW = size;
    final tileH = size / OkeyTableMetrics.tileAspect;

    final highlight = isDrawSource
        ? OkeyV3.draw
        : (isDiscardTarget ? OkeyV3.discard : null);

    Widget tileFace = SizedBox(
      width: tileW,
      height: tileH,
      child: topDiscard == null
          ? DecoratedBox(
              // BOŞ ISKARTA — görünmez değil, "buraya taş gelir" diyen bir
              // yuva. Taş yokken bile hit-test alsın diye BOYANAN bir
              // kutudur (şeffaf bir SizedBox olsaydı buraya taş
              // bırakılamazdı).
              decoration: BoxDecoration(
                color: const Color(0x40000000),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: highlight == null
                      ? const Color(0x24FFFFFF)
                      : highlight.withValues(alpha: 0.45),
                ),
              ),
              child: highlight == null
                  ? null
                  : Center(
                      child: Icon(
                        isDrawSource
                            ? Icons.file_download_outlined
                            : Icons.south,
                        size: tileW * 0.5,
                        color: highlight.withValues(alpha: 0.55),
                      ),
                    ),
            )
          : OkeyTileWidget(
              tile: topDiscard!,
              width: tileW,
              height: tileH,
              tight: true,
            ),
    );

    // Sıradaki oyuncunun ıskartası yumuşak bir nabızla vurgulanır.
    // (flutter_animate DEĞİL — bkz. [_Pulse] notu.)
    if (isCurrentTurn && parts != OkeySeatParts.discard) {
      tileFace = _Pulse(scaleTo: 1.035, child: tileFace);
    }

    // Vurgulu çerçeve: taşın ETRAFINA, taşı büyütmeden.
    final Widget framed = highlight == null
        ? Padding(padding: const EdgeInsets.all(3), child: tileFace)
        : Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: highlight.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(OkeyV3.radiusSm + 1),
              border: Border.all(
                color: highlight.withValues(alpha: 0.8),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: highlight.withValues(alpha: 0.28),
                  blurRadius: 10,
                ),
              ],
            ),
            child: tileFace,
          );

    // !!! Her katman AYRI ve FINAL bir değişkende tutulur.
    // `x = DragTarget(builder: ... => x)` yazımı widget'ı REFERANSLA yakalar
    // ve kendi içine sonsuz kez gömer (bkz. proje geçmişindeki
    // 'owner!._debugCurrentBuildTarget == this' çökmesi).
    final bool canDragPile = isDrawSource && topDiscard != null;

    final Widget draggable = Draggable<OkeyDragPayload>(
      data: const OkeyDragPayload.discard(),
      maxSimultaneousDrags: canDragPile ? 1 : 0,
      onDragStarted: onDragStart,
      onDraggableCanceled: (_, _) => onDragEnd?.call(),
      onDragEnd: (_) => onDragEnd?.call(),
      feedback: Material(
        color: Colors.transparent,
        child: topDiscard == null
            ? const SizedBox.shrink()
            : OkeyTileWidget(tile: topDiscard!),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: framed),
      child: GestureDetector(onTap: onTap, child: framed),
    );

    final bool acceptsDiscard = isDiscardTarget && onTileDropped != null;
    final Widget dropZone = DragTarget<OkeyDragPayload>(
      onWillAcceptWithDetails: (d) => acceptsDiscard && d.data.isFromRack,
      onAcceptWithDetails: (d) {
        onTileDropped?.call(d.data.slotIndex);
        onDragEnd?.call();
      },
      builder: (context, candidate, rejected) {
        if (candidate.isEmpty) return draggable;
        return Container(
          decoration: BoxDecoration(
            color: OkeyV3.discard.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(OkeyV3.radiusSm + 2),
          ),
          child: draggable,
        );
      },
    );

    if (highlight == null) return dropZone;

    // ÇEK / AT etiketi — hangi kutunun ne işe yaradığını yazıyla da söyler.
    // Renk tek başına yetmez: renk körlüğü bir yana, yeşil ve mavi kutunun
    // hangisinin "al" hangisinin "ver" olduğu öğrenilmesi gereken bir şeydir.
    //
    // Etiket kutunun ALTINA değil, ÜSTÜNE biner: köşe kutuları artık kenar
    // sütununun sabit yükseklikli uçlarında duruyor, altına eklenen her
    // piksel oyuncu levhasından çalınıyordu.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        dropZone,
        Positioned(
          bottom: -1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xE6000000),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: highlight.withValues(alpha: 0.75)),
            ),
            child: Text(
              isDrawSource ? 'ÇEK' : 'AT',
              style: TextStyle(
                fontSize: 8,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: highlight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Kalan taş sayısının yanındaki minik "iki taş" ikonu.
class _TileCountIcon extends StatelessWidget {
  final Color color;

  const _TileCountIcon({this.color = OkeyV3.textFaint});

  @override
  Widget build(BuildContext context) {
    Widget bar() => Container(
      width: 3,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [bar(), const SizedBox(width: 1.5), bar()],
    );
  }
}

/// Bot düşünürken sayaçların yerini alan üç nokta.
class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots();

  @override
  Widget build(BuildContext context) {
    Widget dot(double opacity) => Container(
      width: 3.5,
      height: 3.5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(0.85),
        const SizedBox(width: 3),
        dot(0.45),
        const SizedBox(width: 3),
        dot(0.2),
      ],
    );
  }
}

/// Sonsuz döngülü, hafif bir nabız — [scaleTo] verilirse büyü/küçül,
/// [fade] true ise sönümlen/parla. Saf Flutter [AnimationController] +
/// [SingleTickerProviderStateMixin] kullanır; State.dispose() Ticker'ı
/// düzgün iptal eder, bu yüzden flutter_animate'in aksine widget
/// testlerinde "Timer is still pending" hatası bırakmaz.
class _Pulse extends StatefulWidget {
  final Widget child;
  final double? scaleTo;
  final bool fade;

  const _Pulse({required this.child, this.scaleTo, this.fade = false});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  // SINIRLI tekrar (sonsuz DEĞİL): bu widget sıra bende/bot düşünürken
  // uzun süre ekranda kalabilir. Sonsuz repeat(), pumpAndSettle()
  // kullanan widget testlerini asla ayarlanmayan bir animasyonla zaman
  // aşımına düşürür — birkaç döngüden sonra kendiliğinden durması hem
  // testlerle uyumlu hem de gözü daha az yorar.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true, count: 4);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // REPAINT SINIRI — nabız, MASAYI yeniden boyamasın.
    //
    // Bu widget saniyede 60 kare boyunca kendini yeniden çizer ve masada
    // aynı anda üç tanesi birden yanabilir (sırası gelen oyuncu + iki
    // vurgu). Sınır olmadan her kare, nabzı barındıran katmanın TAMAMINI —
    // keçe, ıskarta kutuları, oradaki taşlar — yeniden boyamak zorunda
    // bırakıyordu. Sınırla birlikte GPU yalnızca bu küçük dikdörtgeni
    // yeniden çizer.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final t = _controller.value;
          Widget result = child!;
          if (widget.scaleTo != null) {
            final scale = 1.0 + (widget.scaleTo! - 1.0) * t;
            result = Transform.scale(scale: scale, child: result);
          }
          if (widget.fade) {
            // Opacity yerine FadeTransition DEĞİL, doğrudan Opacity: değer
            // zaten bu builder'da hesaplanıyor. Ama saveLayer maliyeti
            // yukarıdaki repaint sınırının içinde kalır.
            result = Opacity(opacity: 0.4 + 0.6 * t, child: result);
          }
          return result;
        },
      ),
    );
  }
}
