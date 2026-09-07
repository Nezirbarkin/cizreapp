import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/okey_points_provider.dart';
import '../services/okey_ad_reward.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';
import '../widgets/okey_leaderboard_view.dart';

/// Okey puanları: bakiye, saatlik hediye, reklamla puan ve skor tablosu.
///
/// ## Yeniden tasarım (2026-09)
///
/// İki sekme de artık kaydırılabilir sliver listeleri. Skor tablosundaki
/// satır `ListTile` idi: uzun bir kullanıcı adı + üç bilgi taşıyan alt satır +
/// sağdaki puan sütunu, büyütülmüş yazı tipinde taşıyordu. Artık ad esner,
/// alt satır kısalır, puan sütunu sabit genişlikte durur.
class OkeyPointsScreen extends StatelessWidget {
  const OkeyPointsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OkeyPointsProvider(),
      child: const _OkeyPointsView(),
    );
  }
}

class _OkeyPointsView extends StatefulWidget {
  const _OkeyPointsView();

  @override
  State<_OkeyPointsView> createState() => _OkeyPointsViewState();
}

class _OkeyPointsViewState extends State<_OkeyPointsView> {
  bool _adBusy = false;

  /// Reklamı izlet, SUNUCU doğrulaması geçerse Okey puanı ver.
  ///
  /// Akışın kendisi [okeyWatchRewardedAd]'da: aynı düğme artık lobide de
  /// var ve doğrulama kuralı iki yerde ayrı ayrı yaşamamalı.
  Future<void> _watchAd(BuildContext context) async {
    final provider = context.read<OkeyPointsProvider>();
    setState(() => _adBusy = true);
    try {
      await okeyWatchRewardedAd(context: context, provider: provider);
    } finally {
      if (mounted) setState(() => _adBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OkeyPointsProvider>();

    // Bilgi/hata mesajlarını göster.
    final msg = provider.info ?? provider.error;
    if (msg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        provider.consumeMessages();
      });
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: OkeyColors.screenBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: OkeyUI.text,
          title: const Text(
            'Çiplerim',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          bottom: const TabBar(
            labelColor: OkeyColors.accentGold,
            unselectedLabelColor: OkeyUI.textDim,
            indicatorColor: OkeyColors.accentGold,
            tabs: [
              Tab(text: 'Çiplerim', icon: Icon(Icons.stars, size: 18)),
              Tab(
                text: 'Skor tablosu',
                icon: Icon(Icons.leaderboard, size: 18),
              ),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(gradient: OkeyUI.screenGradient),
          child: SafeArea(
            top: false,
            child: TabBarView(
              children: [
                _WalletTab(
                  provider: provider,
                  adBusy: _adBusy,
                  onWatchAd: () => _watchAd(context),
                ),
                const OkeyLeaderboardView(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletTab extends StatelessWidget {
  final OkeyPointsProvider provider;
  final bool adBusy;
  final VoidCallback onWatchAd;

  const _WalletTab({
    required this.provider,
    required this.adBusy,
    required this.onWatchAd,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: provider.refresh,
      color: OkeyColors.accentGold,
      backgroundColor: OkeyUI.cardFill,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: OkeyUI.screenPadding,
        children: [
          _BalanceCard(points: provider.points),
          const OkeySectionHeader(label: 'Çip kazan'),
          _ActionCard(
            icon: Icons.card_giftcard,
            color: const Color(0xFFB9F6CA),
            title: 'Saatlik hediye',
            description: provider.canClaimGift
                ? '${provider.wallet.hourlyGiftPoints} çip seni bekliyor!'
                : 'Sonraki hediye: ${provider.giftCountdownText}',
            buttonText: provider.canClaimGift ? 'HEDİYE AL' : 'BEKLEMEDE',
            enabled: provider.canClaimGift && !provider.isBusy,
            onPressed: provider.claimHourlyGift,
          ),
          const SizedBox(height: OkeyUI.gapSm),
          _ActionCard(
            icon: Icons.ondemand_video,
            color: const Color(0xFF80D8FF),
            title: 'Reklam izle',
            description:
                'Kısa bir reklam izleyerek '
                '${provider.wallet.adRewardPoints} çip kazan',
            buttonText: adBusy ? 'YÜKLENİYOR…' : 'REKLAM İZLE',
            enabled: !adBusy && !provider.isBusy,
            onPressed: onWatchAd,
          ),
          const OkeySectionHeader(label: 'Nasıl çip kazanılır?'),
          OkeyCard(
            child: Column(
              children: const [
                _InfoRow(
                  icon: Icons.emoji_events,
                  text: 'Maçı kazanarak potu al',
                ),
                _InfoRow(
                  icon: Icons.card_giftcard,
                  text: 'Saatte bir hediyeni al',
                ),
                _InfoRow(
                  icon: Icons.ondemand_video,
                  text: 'Reklam izleyerek çip kazan',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Büyük bakiye kartı.
class _BalanceCard extends StatelessWidget {
  final int points;

  const _BalanceCard({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: OkeyUI.goldGradient,
        ),
        borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'OKEY ÇİPİM',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: OkeyUI.onGold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          // Yedi haneli bakiye de sığar: kutu büyümez, sayı küçülür.
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$points',
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFF1B1204),
                  fontSize: 42,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Bu çipler yalnızca Okey masalarında kullanılır',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Color(0x99000000), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String buttonText;
  final bool enabled;
  final VoidCallback onPressed;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: OkeyUI.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.title,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OkeyUI.gap),
          OkeyButton(
            label: buttonText,
            tone: enabled ? OkeyButtonTone.primary : OkeyButtonTone.secondary,
            onPressed: enabled ? onPressed : null,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: OkeyColors.accentGold),
          const SizedBox(width: OkeyUI.gap),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: OkeyUI.body,
            ),
          ),
        ],
      ),
    );
  }
}
