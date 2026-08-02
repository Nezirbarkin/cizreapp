import 'package:flutter/material.dart';

import '../../../core/models/ad_settings_model.dart';
import '../../../core/services/rewarded_ad_service.dart';

/// Reklam puanı, TL cüzdanından ayrı ve yalnız SSV doğrulamasıyla sonuçlanan
/// bir uygulama içi puandır.
class WatchAdEarnCard extends StatefulWidget {
  final VoidCallback? onRewardEarned;
  final RewardedAdService? adService;

  const WatchAdEarnCard({super.key, this.onRewardEarned, this.adService});

  @override
  State<WatchAdEarnCard> createState() => _WatchAdEarnCardState();
}

class _WatchAdEarnCardState extends State<WatchAdEarnCard> {
  late final RewardedAdService _adService =
      widget.adService ?? RewardedAdService();
  AdSettings? _settings;
  bool _isLoadingSettings = true;
  bool _isPreloading = false;
  bool _isShowing = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await _adService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _isLoadingSettings = false;
    });
    if (settings != null) await _preload();
  }

  Future<void> _preload() async {
    if (_isPreloading || _adService.isReady || !mounted) return;
    setState(() => _isPreloading = true);
    await _adService.preload();
    if (mounted) setState(() => _isPreloading = false);
  }

  Future<void> _watchAd() async {
    if (!_adService.isReady) {
      _showSnack('Reklam hazırlanıyor. Lütfen kısa süre sonra tekrar deneyin.');
      await _preload();
      return;
    }

    setState(() {
      _isShowing = true;
      _isVerifying = false;
    });
    final resultFuture = _adService.showAndVerify();

    // Reklam kapanışı ve SSV polling aynı Future içinde olduğundan, kısa bir
    // gecikmeden sonra erişilebilir bekleme durumunu gösteriyoruz.
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _isShowing) setState(() => _isVerifying = true);
    });
    final result = await resultFuture;
    if (!mounted) return;
    setState(() {
      _isShowing = false;
      _isVerifying = false;
    });

    switch (result.state) {
      case AdRewardResultState.credited:
        _showSnack(
          '+${result.rewardPoints} puan hesabına eklendi.',
          isError: false,
        );
        widget.onRewardEarned?.call();
      case AdRewardResultState.testCompleted:
        _showSnack(
          'Test reklamı başarıyla tamamlandı. Test modunda gerçek puan eklenmez.',
          isError: false,
        );
      case AdRewardResultState.duplicate:
        _showSnack(
          'Bu reklam olayı daha önce işlendi; ikinci kez puan eklenmedi.',
        );
        widget.onRewardEarned?.call();
      case AdRewardResultState.verificationPending:
        _showSnack(
          'Puanın doğrulanıyor. Sunucu onayı gelmeden puan eklenmez.',
          isPending: true,
        );
      case AdRewardResultState.rejected:
      case AdRewardResultState.failed:
        _showSnack(
          result.errorMessage ?? 'Puan doğrulanamadı; puan verilmedi.',
        );
    }

    await _preload();
  }

  void _showSnack(
    String message, {
    bool isError = true,
    bool isPending = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isPending
            ? Colors.blueGrey
            : isError
            ? Colors.red
            : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    _adService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSettings || _settings == null) {
      return const SizedBox.shrink();
    }

    final settings = _settings!;
    final range = settings.rewardMinPoints == settings.rewardMaxPoints
        ? '${settings.rewardMinPoints} puan'
        : '${settings.rewardMinPoints}-${settings.rewardMaxPoints} puan';
    final statusText = _isVerifying
        ? 'Puanın sunucuda doğrulanıyor...'
        : _isPreloading
        ? 'Reklam hazırlanıyor...'
        : settings.testMode
        ? 'Google test reklamını güvenle deneyin; puan eklenmez'
        : '$range kazan; uygun dijital ürünlerde kullan';

    return Semantics(
      label: 'Reklam izleyerek puan kazan. Puan nakde çevrilemez.',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange.shade600, Colors.deepOrange.shade400],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isShowing || _isPreloading ? null : _watchAd,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isShowing || _isPreloading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reklam İzle, Puan Kazan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Nakde çevrilemez, devredilemez veya IBAN’a çekilemez.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white70,
                    size: 20,
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
