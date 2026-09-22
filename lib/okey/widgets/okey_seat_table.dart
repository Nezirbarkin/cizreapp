import 'package:flutter/material.dart';

import '../engine/okey_seating.dart';
import '../models/okey_models.dart';
import '../services/okey_sound_service.dart';
import '../theme/okey_ui.dart';

/// EŞLİ MASADA TAKIM KİMLİĞİ — koltuk numarasından türer.
///
/// Takımlar KARŞILIKLI koltuklardır (RULES.md §5): 0-2 ve 1-3. Ad ve sıra,
/// maç sonucu ekranındakiyle aynıdır ("Takım 1" = 1. + 3. koltuk); iki ekranda
/// iki ayrı adlandırma, oyuncuya "hangisi hangisi" sorusunu yeniden sordururdu.
abstract final class OkeyTeamStyle {
  /// Takım 1 (koltuk 0 ve 2) — ferah cam mavisi.
  static const Color first = Color(0xFF6FD3F5);

  /// Takım 2 (koltuk 1 ve 3) — lavanta. Pirinçten (benim rengim) ve
  /// yeşilden (hazır) bilerek ayrıdır: üçü aynı kartta yan yana durabilir.
  static const Color second = Color(0xFFC3A6F5);

  static Color colorOf(int seatNo) => seatNo.isEven ? first : second;
  static String labelOf(int seatNo) => seatNo.isEven ? 'Takım 1' : 'Takım 2';
}

/// BEKLEME ODASINDAKİ MASA — dört koltuk, GERÇEK masadaki yerlerinde.
///
/// ## Neden 2×2 ızgara değil (kullanıcı isteği, 2026-09-21)
///
/// "Oyuncular istediği (eşli) kişinin karşısında oturabilsin." Izgarada
/// eşler ÇAPRAZ duruyordu (0-2 ve 1-3) ve "karşısında" ifadesi ekranda hiçbir
/// yerde görünmüyordu; oyuncu kiminle eş olacağını koltuk numaralarından
/// çıkarmak zorundaydı. Burada koltuklar masanın etrafında durur: KARŞILIKLI
/// koltuk gerçekten karşıdadır ve eşli modda aynı renkte, aralarında bir
/// bağ çizgisiyle görünür.
///
/// Yerleşim oyundaki sıra yönünü izler (bkz. [OkeySeating]): sıra saat
/// yönünün TERSİNE döner; 0. koltuk altta, 1. sağda, 2. üstte, 3. solda.
/// Yerleşim MUTLAKTIR — kimin oturduğuna göre dönmez. Döndürseydik, koltuk
/// değiştirdiğimde tüm masa ben kımıldayınca yerinden oynar ve "kim nereye
/// gitti" izlenemezdi.
///
/// ## Boş koltuk = oturma yeri
///
/// [canPick] doğruysa boş koltuklar kesik çizgili birer "OTUR" düğmesidir.
/// Eşli modda boş koltuğun altında, oraya geçersem KİMİN eşim olacağı yazar —
/// karar için gereken tek bilgi bu.
///
/// Bileşen yalnızca veri alır (Supabase'e dokunmaz), bu yüzden doğrudan
/// widget testiyle sınanır.
class OkeySeatTable extends StatelessWidget {
  /// Odadaki koltuk satırları (eksik olabilir; eksik koltuk boş sayılır).
  final List<OkeyRoomSeat> seats;

  /// Bende oturduğum koltuk; masada oturmuyorsam null.
  final int? mySeatNo;

  /// Eşli mod: takım renkleri ve bağ çizgileri çizilir.
  final bool isTeams;

  /// Boş koltuğa geçilebilir mi (masadayım ve oda bekliyor).
  final bool canPick;

  /// Boş bir koltuğa dokunuldu.
  final ValueChanged<int>? onPickSeat;

  /// Dolu bir koltuğa dokunuldu (profil kartı).
  final ValueChanged<OkeyRoomSeat>? onSeatTap;

  const OkeySeatTable({
    super.key,
    required this.seats,
    required this.mySeatNo,
    this.isTeams = false,
    this.canPick = false,
    this.onPickSeat,
    this.onSeatTap,
  });

  /// Masanın çizilebileceği EN GENİŞ genişlik — tablette dört koltuk ekrana
  /// yayılmasın, masa masa gibi kalsın.
  static const double maxTableWidth = 520;

  OkeyRoomSeat? _seatAt(int n) {
    for (final s in seats) {
      if (s.seatNo == n) return s;
    }
    return null;
  }

  /// Boş [seatNo] koltuğuna GEÇERSEM eşim kim olur? (Yalnızca eşli modda ve
  /// koltuk seçilebiliyorken gösterilir.)
  ///
  /// Karşıdaki koltuk bendeki koltuksa (yani [seatNo] ZATEN benim eşimin
  /// koltuğuysa) null döner: o koltuğun kartı zaten "Eşin" yazıyor ve oraya
  /// geçersem karşımdaki koltuk BENİM bıraktığım koltuk olur, yani boşalır —
  /// ikinci bir "Eşin: henüz yok" satırı aynı şeyi ters anlamda tekrar ederdi.
  @visibleForTesting
  static String? partnerHint({
    required int seatNo,
    required int? mySeatNo,
    required List<OkeyRoomSeat> seats,
  }) {
    final partnerNo = OkeySeating(seatNo).acrossSeat;
    if (partnerNo == mySeatNo) return null;
    for (final s in seats) {
      if (s.seatNo != partnerNo || s.isEmpty) continue;
      return 'Eşin: ${s.displayLabel}';
    }
    return 'Eşin: henüz yok';
  }

  @override
  Widget build(BuildContext context) {
    final my = mySeatNo;
    final partnerNo = (isTeams && my != null)
        ? OkeySeating(my).acrossSeat
        : null;
    final anyEmpty = List.generate(
      4,
      _seatAt,
    ).any((s) => s == null || s.isEmpty);

    Widget tile(int n) {
      final seat = _seatAt(n);
      final empty = seat == null || seat.isEmpty;
      return _SeatTile(
        seatNo: n,
        seat: empty ? null : seat,
        isMe: my != null && n == my,
        isPartner: partnerNo != null && n == partnerNo,
        teamed: isTeams,
        pickable: empty && canPick && onPickSeat != null,
        partnerHint: (isTeams && canPick && empty && my != null)
            ? partnerHint(seatNo: n, mySeatNo: my, seats: seats)
            : null,
        onPick: onPickSeat == null ? null : () => onPickSeat!(n),
        onProfile: (empty || onSeatTap == null) ? null : () => onSeatTap!(seat),
      );
    }

    final hint = _hintText(anyEmpty);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxTableWidth),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth.isFinite ? c.maxWidth : 340.0;
            const gap = OkeyUI.gapSm;
            // Masa dar tutulur: yan koltuklar yazı için genişlik ister.
            final feltW = (w * 0.2).clamp(56.0, 120.0);
            final sideW = (w - feltW - gap * 2) / 2;
            final midW = (w * 0.44).clamp(120.0, 200.0);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ÜST (2. koltuk) — alttakinin karşısı.
                SizedBox(width: midW, child: tile(2)),
                const SizedBox(height: gap),
                // ORTA: SOL (3) · MASA · SAĞ (1). Masa, iki yan koltuğun
                // boyuna uzanır (kartlar içeriğine göre uzar, sabit yükseklik
                // yok — yazı büyüyünce taşmasın).
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: sideW, child: tile(3)),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: feltW,
                        child: CustomPaint(
                          painter: _FeltPainter(teamed: isTeams, gap: gap),
                          // Eşsiz masada çizgi yok; çuhanın ortasında silik
                          // bir kağıt simgesi masayı masa gibi okutur.
                          child: isTeams
                              ? null
                              : Center(
                                  child: Icon(
                                    Icons.style,
                                    size: 22,
                                    color: OkeyUI.brass.withValues(alpha: 0.28),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(width: sideW, child: tile(1)),
                    ],
                  ),
                ),
                const SizedBox(height: gap),
                // ALT (0. koltuk).
                SizedBox(width: midW, child: tile(0)),
                if (hint != null) ...[
                  const SizedBox(height: OkeyUI.gap),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: OkeyUI.caption,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Masanın altındaki yönlendirme. Koltuk seçilemiyorsa (oda başladı ya da
  /// masada oturmuyorum) hiçbir şey yazılmaz.
  String? _hintText(bool anyEmpty) {
    if (!canPick) return null;
    if (isTeams) {
      return anyEmpty
          ? 'Karşındaki koltuk eşin olur. İstediğin boş koltuğa dokunup oraya geç.'
          : 'Karşındaki koltuk eşin olur.';
    }
    return anyEmpty ? 'Boş bir koltuğa dokunup oraya geçebilirsin.' : null;
  }
}

/// Tek bir koltuk kartı.
class _SeatTile extends StatelessWidget {
  final int seatNo;

  /// Oturan; boş koltukta null.
  final OkeyRoomSeat? seat;
  final bool isMe;

  /// Eşli modda benim eşim (karşımdaki koltuk).
  final bool isPartner;
  final bool teamed;

  /// Boş ve dokunulunca oturulabilir.
  final bool pickable;
  final String? partnerHint;
  final VoidCallback? onPick;
  final VoidCallback? onProfile;

  const _SeatTile({
    required this.seatNo,
    required this.seat,
    required this.isMe,
    required this.isPartner,
    required this.teamed,
    required this.pickable,
    required this.partnerHint,
    required this.onPick,
    required this.onProfile,
  });

  static const Color _readyGreen = Color(0xFFB9F6CA);

  @override
  Widget build(BuildContext context) {
    final s = seat;
    final empty = s == null;
    final ready = !empty && s.isReady;
    final teamColor = teamed ? OkeyTeamStyle.colorOf(seatNo) : null;

    final name = empty
        ? 'Boş koltuk'
        : isMe
        ? 'Sen'
        // Bot olup olmadığını ELE VERMEZ (bkz. OkeyRoomSeat.displayLabel).
        : s.displayLabel;

    final borderColor = isMe
        ? OkeyUI.brass
        : ready
        ? _readyGreen.withValues(alpha: 0.7)
        : (teamColor?.withValues(alpha: 0.5) ?? OkeyUI.cardBorder);

    // EŞİMİN koltuğu doğrudan "Eşin" yazar (takım adı DEĞİL): takım zaten
    // renkten ve karşımdaki bağ çizgisinden okunur, oysa dar ekranda "Takım 2 ·
    // Eşin" kırpılıyor ve kırpılan kısım tam da en önemli olanıydı.
    final teamLine = teamed
        ? (isPartner ? 'Eşin' : OkeyTeamStyle.labelOf(seatNo))
        : null;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (empty)
          _EmptyChair(pickable: pickable)
        else
          OkeyAvatar(url: s.avatarUrl, size: 44, highlighted: isMe),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: OkeyUI.body.copyWith(
            color: empty ? OkeyUI.textFaint : OkeyUI.text,
            fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        if (empty)
          pickable
              ? const OkeyPill(text: 'OTUR', icon: Icons.event_seat)
              : const Text('bekleniyor…', style: OkeyUI.caption)
        else
          OkeyPill(
            text: ready ? 'Hazır' : 'Bekliyor',
            icon: ready ? Icons.check_circle : Icons.hourglass_empty,
            color: ready ? _readyGreen : OkeyUI.textFaint,
          ),
        if (teamLine != null) ...[
          const SizedBox(height: 5),
          Text(
            teamLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: OkeyUI.caption.copyWith(
              color: teamColor,
              fontWeight: isPartner ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
        if (partnerHint != null) ...[
          const SizedBox(height: 2),
          Text(
            partnerHint!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: OkeyUI.caption.copyWith(color: OkeyUI.textDim),
          ),
        ],
      ],
    );

    final card = Container(
      decoration: BoxDecoration(
        color: empty ? const Color(0x0AFFFFFF) : OkeyUI.cardFill,
        borderRadius: BorderRadius.circular(OkeyUI.radius),
        // Oturulabilir koltuğun kenarı KESİK ÇİZGİDİR (aşağıdaki painter);
        // düz kenar yalnızca oturulmuş / seçilemeyen koltukta çizilir.
        border: pickable
            ? null
            : Border.all(color: borderColor, width: isMe || ready ? 1.6 : 1),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: content,
    );

    final decorated = pickable
        ? CustomPaint(
            foregroundPainter: _DashedBorderPainter(
              color: OkeyUI.brass.withValues(alpha: 0.7),
              radius: OkeyUI.radius,
            ),
            child: card,
          )
        : card;

    if (pickable) {
      return Semantics(
        button: true,
        label: '${seatNo + 1}. koltuk boş. Oturmak için dokun.',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(OkeyUI.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(OkeyUI.radius),
            onTap: withOkeyTapSound(onPick),
            child: decorated,
          ),
        ),
      );
    }

    // KOLTUĞA DOKUNUNCA PROFİL KARTI — masadaki oyuncu levhalarıyla aynı
    // davranış. Masaya oturmadan ÖNCE rakibine bakmak, oturduktan sonra
    // bakmaktan daha da makul bir istek.
    if (onProfile == null) return decorated;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onProfile,
      child: decorated,
    );
  }
}

/// Boş koltuk — oturulabiliyorsa pirinç renkli bir sandalye, değilse silik
/// bir kişi silueti.
class _EmptyChair extends StatelessWidget {
  final bool pickable;

  const _EmptyChair({required this.pickable});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pickable
            ? OkeyUI.brass.withValues(alpha: 0.12)
            : const Color(0x0FFFFFFF),
        border: Border.all(
          color: pickable
              ? OkeyUI.brass.withValues(alpha: 0.6)
              : OkeyUI.cardBorder,
          width: 1.4,
        ),
      ),
      child: Icon(
        pickable ? Icons.event_seat : Icons.person_outline,
        size: 22,
        color: pickable ? OkeyUI.brass : OkeyUI.textFaint,
      ),
    );
  }
}

/// Masanın çuhası ve — eşli modda — eşleri bağlayan çizgiler.
///
/// Dikey çizgi ÜST ile ALT koltuğu (Takım 1: 0-2), yatay çizgi SOL ile SAĞ
/// koltuğu (Takım 2: 1-3) bağlar. Çizgiler kendi hücresinin dışına, koltuk
/// kartlarına kadar [gap] kadar uzanır (CustomPaint kırpmaz), böylece iki
/// eş gerçekten "birbirine bağlı" görünür.
class _FeltPainter extends CustomPainter {
  final bool teamed;
  final double gap;

  const _FeltPainter({required this.teamed, required this.gap});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final felt = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    canvas.drawRRect(
      felt,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1E5C4F), Color(0xFF14322E)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      felt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = OkeyUI.brass.withValues(alpha: 0.35),
    );

    if (!teamed) return;

    final cx = size.width / 2;
    final cy = size.height / 2;

    Paint line(Color color) => Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.9);

    // Takım 1: üst ↔ alt.
    canvas.drawLine(
      Offset(cx, -gap),
      Offset(cx, size.height + gap),
      line(OkeyTeamStyle.first),
    );
    // Takım 2: sol ↔ sağ.
    canvas.drawLine(
      Offset(-gap, cy),
      Offset(size.width + gap, cy),
      line(OkeyTeamStyle.second),
    );
    // Kesişim noktası: çizgilerin "masanın ortasından geçtiği" yer.
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = OkeyUI.brass);
  }

  @override
  bool shouldRepaint(_FeltPainter old) =>
      old.teamed != teamed || old.gap != gap;
}

/// Kesik çizgili yuvarlatılmış dikdörtgen kenar — "buraya otur" işareti.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  static const double _dash = 6;
  static const double _space = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color;

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += _dash + _space;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
