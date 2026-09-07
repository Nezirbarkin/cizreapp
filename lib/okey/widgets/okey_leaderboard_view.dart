import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/okey_points_provider.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';
import 'okey_profile_sheet.dart';

/// SKOR TABLOSU — hem puan ekranında hem lobinin üst barından açılır.
///
/// ## Neden ayrı bir widget
///
/// Tablo eskiden puan ekranının içinde özel bir sekmeydi ve oraya ulaşmanın
/// tek yolu lobiden puan ekranına gitmekti. Kullanıcı tabloyu masa açma
/// ekranının üst barında istedi; aynı listeyi iki yerde ayrı ayrı yazmak
/// yerine buraya taşındı.
///
/// ## Satırda ne var
///
/// Sıra · avatar · ad · **kazanma oranı halkası** · maç/galibiyet · puan.
/// Kazanma oranı profil kartındakiyle AYNI biçimde gösterilir — oyuncu
/// tabloda gördüğü sayıyı karta dokununca yeniden bulabilmeli.
///
/// Bir satıra dokunmak o oyuncunun profil kartını açar.
class OkeyLeaderboardView extends StatefulWidget {
  /// Üstte bir "senin sıran" özeti gösterilsin mi.
  final bool showMyRank;

  const OkeyLeaderboardView({super.key, this.showMyRank = true});

  @override
  State<OkeyLeaderboardView> createState() => _OkeyLeaderboardViewState();
}

class _OkeyLeaderboardViewState extends State<OkeyLeaderboardView> {
  @override
  void initState() {
    super.initState();
    // Sağlayıcı zaten kurulmuş olabilir; liste yine de tazelenir ki iki
    // farklı yerden açıldığında bayat veri görünmesin.
    Future.microtask(() {
      if (mounted) context.read<OkeyPointsProvider>().refreshLeaderboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OkeyPointsProvider>();
    final list = provider.leaderboard;

    return RefreshIndicator(
      onRefresh: provider.refreshLeaderboard,
      color: OkeyColors.accentGold,
      backgroundColor: OkeyUI.cardFill,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                OkeyEmptyState(
                  icon: Icons.leaderboard_outlined,
                  title: 'Henüz sıralama yok',
                  message: 'İlk maçını oyna, adın buraya gelsin.',
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: OkeyUI.screenPadding,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final e = list[i];
                final rank = i + 1;
                final rate = e.matchesPlayed == 0
                    ? 0.0
                    : e.matchesWon / e.matchesPlayed;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => OkeyProfileSheet.show(
                    context,
                    userId: e.userId,
                    name: e.displayName,
                    avatarUrl: e.avatarUrl,
                  ),
                  child: OkeyCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    highlighted: rank == 1,
                    child: Row(
                      children: [
                        OkeyRankBadge(rank: rank),
                        const SizedBox(width: OkeyUI.gapSm),
                        _AvatarWithRate(
                          url: e.avatarUrl,
                          rate: rate,
                          hasMatches: e.matchesPlayed > 0,
                        ),
                        const SizedBox(width: OkeyUI.gap),
                        // Ad ve istatistik ESNER; puan sütunu sabit kalır.
                        // Tersi olsaydı uzun bir ad puanı ekran dışına iterdi.
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OkeyUI.title,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${e.matchesPlayed} maç · ${e.matchesWon} G · '
                                '${(e.matchesPlayed - e.matchesWon).clamp(0, 1 << 30)} M'
                                '${e.matchesPlayed > 0 ? ' · %${(rate * 100).round()}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OkeyUI.caption,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: OkeyUI.gapSm),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.stars,
                              color: OkeyColors.accentGold,
                              size: 15,
                            ),
                            const SizedBox(height: 2),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 72),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${e.points}',
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: OkeyColors.accentGold,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
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

/// Avatar + etrafında kazanma oranı halkası.
class _AvatarWithRate extends StatelessWidget {
  final String? url;
  final double rate;
  final bool hasMatches;

  const _AvatarWithRate({
    required this.url,
    required this.rate,
    required this.hasMatches,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (hasMatches)
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                value: rate.clamp(0.0, 1.0),
                strokeWidth: 3,
                backgroundColor: const Color(0x24FFFFFF),
                valueColor: const AlwaysStoppedAnimation(OkeyColors.accentGold),
              ),
            ),
          OkeyAvatar(url: url, size: 34),
        ],
      ),
    );
  }
}

/// Sıra numarası — ilk üç madalya renginde.
class OkeyRankBadge extends StatelessWidget {
  final int rank;

  const OkeyRankBadge({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    final color = switch (rank) {
      1 => const Color(0xFFFFD54F),
      2 => const Color(0xFFCFD8DC),
      3 => const Color(0xFFBCAAA4),
      _ => OkeyUI.textFaint,
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$rank',
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Skor tablosunu TAM EKRAN açan sayfa — lobinin üst barından çağrılır.
///
/// Sağlayıcıyı KENDİ kurmaz: çağıran taraf zaten bir [OkeyPointsProvider]
/// tutuyorsa `ChangeNotifierProvider.value` ile onu geçirir; böylece aynı
/// cüzdan iki kez ağdan okunmaz.
class OkeyLeaderboardScreen extends StatelessWidget {
  const OkeyLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OkeyColors.screenBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: OkeyUI.text,
        title: const Text(
          'Skor tablosu',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: OkeyUI.screenGradient),
        child: const SafeArea(top: false, child: OkeyLeaderboardView()),
      ),
    );
  }
}
