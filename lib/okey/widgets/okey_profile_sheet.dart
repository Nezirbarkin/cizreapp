import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/okey_profile_service.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';

/// Bir oyuncunun PROFİL KARTI — masada ya da skor tablosunda ada dokununca
/// açılır.
///
/// ## Neden alttan açılan bir sayfa (bottom sheet)
///
/// Kart oyunun ORTASINDA açılır: oyuncu masaya bakarken rakibine dokunur,
/// bakar, kapatır. Tam ekran bir sayfa masayı ağaçtan söker (realtime
/// abonelikleri değil ama görsel bağlamı kaybettirir) ve geri dönüş bir
/// gezinme hareketi gerektirir. Alttan açılan sayfa masayı arkada bırakır,
/// dışına dokunmak kapatır.
///
/// ## Yerleşim
///
/// ```
///   ┌──────────────────────────────┐
///   │        ( avatar )   %46      │  ← kazanma oranı HALKASI
///   │          Ad Soyad            │
///   │   ● 128 takipçi  ● 96 takip  │
///   │        ● 41 arkadaş          │
///   ├──────────────────────────────┤
///   │  MAÇ 214 │ GALİBİYET 98      │
///   │  MAĞLUP 116 │ EN İYİ -181    │
///   ├──────────────────────────────┤
///   │        4.820 okey puanı      │
///   └──────────────────────────────┘
/// ```
class OkeyProfileSheet extends StatefulWidget {
  final String? userId;
  final String? botProfileId;

  /// Sunucu cevabı beklenirken gösterilecek ad/avatar.
  ///
  /// Masadaki kart zaten adı biliyor; boş bir iskelet göstermek yerine
  /// bildiğimizi hemen gösterip sayıları sonra doldurmak, kartı "anında
  /// açıldı" hissettirir.
  final String? initialName;
  final String? initialAvatarUrl;

  /// Kartı getiren çağrı. Verilmezse gerçek servis kullanılır.
  ///
  /// Neden dışarıdan verilebiliyor: bu kartın asıl işi TAKİP DÜĞMESİNİ
  /// göstermek ve o düğme yalnızca kart YÜKLENDİKTEN sonra çiziliyor.
  /// Supabase'e bağlı bir yükleyiciyle bu durum widget testinde hiç
  /// kurulamaz, dolayısıyla "düğme yatay ekranda görünüyor mu" sorusu
  /// ölçülemezdi — oysa kullanıcının bildirdiği sorun tam olarak buydu.
  final Future<OkeyProfileCard?> Function()? loadCard;

  /// Takip et / bırak çağrısı. Verilmezse gerçek servis kullanılır.
  final Future<OkeyFollowState> Function(String userId, bool follow)? setFollow;

  const OkeyProfileSheet({
    super.key,
    this.userId,
    this.botProfileId,
    this.initialName,
    this.initialAvatarUrl,
    this.loadCard,
    this.setFollow,
  });

  /// Kartı alttan açar. [userId] ve [botProfileId]'den biri verilmelidir.
  static Future<void> show(
    BuildContext context, {
    String? userId,
    String? botProfileId,
    String? name,
    String? avatarUrl,
  }) {
    if (userId == null && botProfileId == null) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OkeyProfileSheet(
        userId: userId,
        botProfileId: botProfileId,
        initialName: name,
        initialAvatarUrl: avatarUrl,
      ),
    );
  }

  @override
  State<OkeyProfileSheet> createState() => _OkeyProfileSheetState();
}

class _OkeyProfileSheetState extends State<OkeyProfileSheet> {
  final _service = OkeyProfileService();

  OkeyProfileCard? _card;
  String? _error;
  bool _loading = true;

  /// Takip isteği uçuşta — düğme iki kez basılmasın.
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loader = widget.loadCard;
      final c = loader != null
          ? await loader()
          : await _service.card(
              userId: widget.userId,
              botProfileId: widget.botProfileId,
            );
      if (!mounted) return;
      setState(() {
        _card = c;
        _error = c == null ? 'Profil bulunamadı' : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// TAKİP ET / TAKİBİ BIRAK.
  ///
  /// Kartın tamamı yeniden çekilmez: sunucu yalnızca yeni takip durumunu ve
  /// takipçi sayısını döndürür, kart onunla güncellenir. Tam yeniden yükleme
  /// kartı bir anlığına iskelete düşürür ve dokunulan düğme gözden kaybolurdu.
  Future<void> _toggleFollow() async {
    final card = _card;
    final userId = card?.userId;
    if (card == null || userId == null || _followBusy) return;

    final wantFollow = !(card.isFollowing || card.isFollowRequested);
    setState(() => _followBusy = true);
    try {
      final follow = widget.setFollow ?? _service.setFollow;
      final state = await follow(userId, wantFollow);
      if (!mounted) return;
      setState(() {
        _card = card.copyWithFollow(
          following: state.isFollowing,
          requested: state.isRequested,
          followers: state.followersCount,
        );
        _followBusy = false;
      });
      if (state.isRequested && !state.isFollowing) {
        // GİZLİ HESAP: takip HENÜZ başlamadı, onay bekliyor. Sessiz kalmak
        // "düğmeye bastım, bir şey olmadı" hissi verirdi.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Takip isteği gönderildi — onay bekliyor'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _followBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Takip işlemi başarısız: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final name = card?.displayName ?? widget.initialName ?? 'Oyuncu';
    final avatar = card?.avatarUrl ?? widget.initialAvatarUrl;

    // OKEY MASASI YATAY OYNANIR — kart da o ekrana göre kurulur.
    //
    // KULLANICI ŞİKÂYETİ (2026-09-05): "profile tıklandığında takip isteği
    // atabilsin." Düğme aslında vardı; ULAŞILAMIYORDU. Kartın tamamı tek bir
    // kaydırma alanının içindeydi ve yatayda (~360px) avatar halkası + ad +
    // takipçi satırı + 2x2 istatistik + puan şeridi bu yüksekliği tek başına
    // dolduruyordu. Düğmeler en altta, görünür alanın DIŞINDA kalıyordu:
    // oyuncu kartı açıyor, takip düğmesini hiç görmüyordu.
    //
    // Yapısal çözüm gift sayfasındakiyle aynı: kart ekranın en fazla %92'sini
    // kaplar, DÜĞMELER SABİT (kaydırmanın dışında), ARTAN yüksekliği içerik
    // alır ve gerekiyorsa yalnızca o kaydırılır.
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.height < 480;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxHeight: screen.height * 0.92),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16556E), OkeyColors.screenBackground],
          ),
          borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
          border: Border.all(color: OkeyUI.cardBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, compact ? 10 : 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sürükleme tutamağı — sayfanın kapatılabilir olduğunu söyler.
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: OkeyUI.textFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: compact ? OkeyUI.gapSm : OkeyUI.gap),

              // İÇERİK — sığmazsa YALNIZCA bu kısım kaydırılır.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Header(
                        name: name,
                        avatarUrl: avatar,
                        card: card,
                        compact: compact,
                      ),

                      if (_loading) ...[
                        const SizedBox(height: OkeyUI.gapLg),
                        const CircularProgressIndicator(
                          color: OkeyColors.accentGold,
                          strokeWidth: 2.5,
                        ),
                        const SizedBox(height: OkeyUI.gapLg),
                      ] else if (card == null) ...[
                        const SizedBox(height: OkeyUI.gap),
                        Text(
                          _error ?? 'Profil alınamadı',
                          textAlign: TextAlign.center,
                          style: OkeyUI.body,
                        ),
                        const SizedBox(height: OkeyUI.gap),
                      ] else ...[
                        SizedBox(height: compact ? OkeyUI.gapSm : OkeyUI.gap),
                        _SocialRow(card: card),
                        SizedBox(height: compact ? OkeyUI.gapSm : OkeyUI.gap),
                        _StatsGrid(card: card, compact: compact),
                        SizedBox(height: compact ? OkeyUI.gapSm : OkeyUI.gap),
                        _PointsBar(points: card.points),
                      ],
                    ],
                  ),
                ),
              ),

              SizedBox(height: compact ? OkeyUI.gapSm : OkeyUI.gap),

              // DÜĞMELER — KAYDIRMANIN DIŞINDA, her zaman görünür.
              Row(
                children: [
                  // TAKİP ET — yalnızca GERÇEK bir oyuncunun kartında ve
                  // kendi kartımda değil. Bot koltuğunun kullanıcı kimliği
                  // yoktur (userId == null): düğme orada hiç görünmez,
                  // görünseydi "takip edilemedi" hatası botu ele verirdi.
                  if (card != null && !card.isSelf && card.userId != null) ...[
                    Expanded(
                      flex: 3,
                      child: _FollowButton(
                        following: card.isFollowing,
                        requested: card.isFollowRequested,
                        isPrivate: card.isPrivate,
                        busy: _followBusy,
                        onPressed: _toggleFollow,
                      ),
                    ),
                    const SizedBox(width: OkeyUI.gapSm),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: OkeyButton(
                        label: 'KAPAT',
                        tone: OkeyButtonTone.ghost,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar + kazanma oranı halkası + ad.
class _Header extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final OkeyProfileCard? card;

  /// Kısa ekran (okey masası yatayken ~360px): halka küçülür.
  ///
  /// Avatar bu kartın en büyük tek parçası; kısaltılacak ilk yer orası.
  /// Küçülmezse takip düğmesi görünür alanın dışına itiliyordu.
  final bool compact;

  const _Header({
    required this.name,
    this.avatarUrl,
    this.card,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final ring = compact ? 74.0 : 104.0;
    final face = compact ? 58.0 : 82.0;

    return Column(
      children: [
        SizedBox(
          width: ring,
          height: ring,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // KAZANMA ORANI, avatarın ETRAFINDA bir halka olarak durur.
              // Ayrı bir satırda bir yüzde yazmak yerine böyle çizilmesinin
              // sebebi: oran tek bir sayı değil, bir DOLULUK hissidir —
              // %20 ile %70 arasındaki fark gözle anında okunur.
              if (card != null)
                SizedBox(
                  width: ring,
                  height: ring,
                  child: CustomPaint(
                    painter: _WinRingPainter(rate: card!.winRate),
                  ),
                ),
              ClipOval(
                child: SizedBox(
                  width: face,
                  height: face,
                  child: avatarUrl == null
                      ? Container(
                          color: const Color(0xFF0A2C36),
                          child: const Icon(
                            Icons.person,
                            size: 40,
                            color: Color(0xFF9FD9CF),
                          ),
                        )
                      : Image.network(
                          avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFF0A2C36),
                            child: const Icon(
                              Icons.person,
                              size: 40,
                              color: Color(0xFF9FD9CF),
                            ),
                          ),
                        ),
                ),
              ),
              if (card != null)
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: OkeyColors.screenBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OkeyColors.accentGold),
                    ),
                    child: Text(
                      card!.winRateLabel,
                      style: const TextStyle(
                        color: OkeyColors.accentGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: OkeyUI.gapSm),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: OkeyUI.titleLg,
        ),
        if (card?.isSelf == true)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Sen', style: OkeyUI.caption),
          ),
      ],
    );
  }
}

/// Avatarın etrafındaki kazanma oranı halkası.
class _WinRingPainter extends CustomPainter {
  final double rate;

  const _WinRingPainter({required this.rate});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 4,
    );

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0x24FFFFFF),
    );

    if (rate <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * rate.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 6
        ..shader = const SweepGradient(
          colors: [Color(0xFFFFD54F), Color(0xFFB9F6CA), Color(0xFFFFD54F)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_WinRingPainter oldDelegate) => oldDelegate.rate != rate;
}

/// Takipçi · Takip · Arkadaş.
class _SocialRow extends StatelessWidget {
  final OkeyProfileCard card;

  const _SocialRow({required this.card});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, int value) => Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            maxLines: 1,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: OkeyUI.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, style: OkeyUI.caption),
        ],
      ),
    );

    return Row(
      children: [
        item('Takipçi', card.followersCount),
        Container(width: 1, height: 28, color: OkeyUI.cardBorder),
        item('Takip', card.followingCount),
        Container(width: 1, height: 28, color: OkeyUI.cardBorder),
        item('Arkadaş', card.friendsCount),
      ],
    );
  }
}

/// Maç istatistikleri — 2x2 kutu.
class _StatsGrid extends StatelessWidget {
  final OkeyProfileCard card;

  /// Kısa ekranda dört kutu 2x2 yerine TEK SATIRDA dizilir: iki satır,
  /// takip düğmesini görünür alanın dışına itecek kadar yer yiyordu.
  final bool compact;

  const _StatsGrid({required this.card, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final boxes = <Widget>[
      _StatBox(
        icon: Icons.sports_esports,
        label: 'Toplam maç',
        value: '${card.matchesPlayed}',
        color: const Color(0xFF80D8FF),
        compact: compact,
      ),
      _StatBox(
        icon: Icons.emoji_events,
        label: 'Kazanılan',
        value: '${card.matchesWon}',
        color: const Color(0xFFB9F6CA),
        compact: compact,
      ),
      _StatBox(
        icon: Icons.trending_down,
        label: 'Kaybedilen',
        value: '${card.matchesLost}',
        color: const Color(0xFFFF8A80),
        compact: compact,
      ),
      _StatBox(
        icon: Icons.military_tech,
        label: 'En iyi skor',
        value: card.bestMatchScore?.toString() ?? '—',
        color: const Color(0xFFE1BEE7),
        compact: compact,
      ),
    ];

    if (compact) {
      return Row(
        children: [
          for (var i = 0; i < boxes.length; i++) ...[
            if (i > 0) const SizedBox(width: OkeyUI.gapXs),
            Expanded(child: boxes[i]),
          ],
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: boxes[0]),
            const SizedBox(width: OkeyUI.gapSm),
            Expanded(child: boxes[1]),
          ],
        ),
        const SizedBox(height: OkeyUI.gapSm),
        Row(
          children: [
            Expanded(child: boxes[2]),
            const SizedBox(width: OkeyUI.gapSm),
            Expanded(child: boxes[3]),
          ],
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool compact;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: OkeyUI.cardFill,
        borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: compact ? 15 : 18, color: color),
          SizedBox(width: compact ? 5 : 8),
          // Sayı ESNER, etiket sabit kalır: dört haneli bir maç sayısı dar
          // ekranda kutuyu taşırmasın.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: OkeyUI.text,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Okey puanı şeridi.
class _PointsBar extends StatelessWidget {
  final int points;

  const _PointsBar({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: OkeyUI.goldGradient),
        borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.stars, size: 18, color: OkeyUI.onGold),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$points okey puanı',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: OkeyUI.onGold,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// TAKİP ET / TAKİP EDİLİYOR / İSTEK GÖNDERİLDİ.
///
/// ## Neden üç durum
///
/// İki durumlu bir düğme (takip et / bırak) gizli hesapları yanlış anlatır:
/// istek gönderildikten sonra takip HENÜZ başlamamıştır. "Takip ediliyor"
/// yazsa yalan olur, "takip et" yazsa oyuncu aynı isteği tekrar gönderir.
/// Üçüncü durum (bekleyen istek) bu ikisinin arasındaki gerçeği söyler ve
/// yine de basılabilir — basılırsa istek geri çekilir.
class _FollowButton extends StatelessWidget {
  final bool following;
  final bool requested;

  /// Hedef hesap gizli mi — etiketin "TAKİP ET" mi "İSTEK GÖNDER" mi
  /// diyeceğini belirler.
  final bool isPrivate;
  final bool busy;
  final VoidCallback onPressed;

  const _FollowButton({
    required this.following,
    required this.requested,
    required this.isPrivate,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final active = following || requested;

    // DÖRT DURUM, DÖRT CÜMLE.
    //
    // İki durumlu bir düğme (takip et / bırak) gizli hesapları yanlış
    // anlatır: istek gönderildikten sonra takip HENÜZ başlamamıştır.
    // "Takip ediyorsun" yazsa yalan olur, "takip et" yazsa oyuncu aynı
    // isteği tekrar gönderir. Üçüncü durum (bekleyen istek) bu ikisinin
    // arasındaki gerçeği söyler ve yine basılabilir — basılırsa istek geri
    // çekilir. Dördüncüsü ise BEKLENTİ KURAR: gizli bir hesapta düğmeye
    // basmanın sonucu takip değil, ONAY BEKLEYEN bir istektir; bunu
    // bastıktan sonra öğrenmek şaşırtıcıdır.
    final String label;
    final IconData icon;
    if (following) {
      label = 'TAKİPTESİN';
      icon = Icons.person_remove_alt_1;
    } else if (requested) {
      label = 'İSTEK GÖNDERİLDİ';
      icon = Icons.hourglass_top;
    } else if (isPrivate) {
      label = 'TAKİP İSTEĞİ GÖNDER';
      icon = Icons.lock_outline;
    } else {
      label = 'TAKİP ET';
      icon = Icons.person_add_alt_1;
    }

    return SizedBox(
      height: 42,
      child: FilledButton.icon(
        // Takip EDİLİYORKEN düğme sönük durur: asıl eylem (takip etmek)
        // bitmiştir, geri alma ikincil bir seçenektir ve dolu altın bir
        // düğme kadar bağırmamalıdır.
        style: FilledButton.styleFrom(
          backgroundColor: active
              ? const Color(0x1FFFFFFF)
              : OkeyColors.accentGold,
          foregroundColor: active ? OkeyUI.text : OkeyUI.onGold,
          side: active
              ? const BorderSide(color: OkeyUI.cardBorder)
              : BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
          ),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 17),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
