import 'package:flutter/material.dart';
import '../../../core/models/ad_settings_model.dart';
import '../../../core/services/rewarded_ad_service.dart';

/// "İzleyerek Kazan" kartı - Bakiye Yükle butonunun altında gösterilir.
/// Reklam kapalıysa (ad_settings.is_enabled = false) hiçbir şey render etmez.
class WatchAdEarnCard extends StatefulWidget {
  final VoidCallback? onRewardEarned;

  const WatchAdEarnCard({super.key, this.onRewardEarned});

  @override
  State<WatchAdEarnCard> createState() => _WatchAdEarnCardState();
}

class _WatchAdEarnCardState extends State<WatchAdEarnCard> {
  final RewardedAdService _adService = RewardedAdService();
  AdSettings? _settings;
  bool _isLoadingSettings = true;
  bool _isPreloading = false;
  bool _isShowing = false;

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
    if (settings != null) {
      _preload();
    }
  }

  Future<void> _preload() async {
    if (_isPreloading || _adService.isReady) return;
    setState(() => _isPreloading = true);
    await _adService.preload();
    if (mounted) setState(() => _isPreloading = false);
  }

  Future<void> _watchAd() async {
    if (!_adService.isReady) {
      _showSnack('Reklam hazırlanıyor, birkaç saniye sonra tekrar dene', isError: true);
      _preload();
      return;
    }

    setState(() => _isShowing = true);
    final result = await _adService.showAndClaim();
    if (!mounted) return;
    setState(() => _isShowing = false);

    if (result.isSuccess) {
      _showSnack(
        '🎉 Tebrikler! ₺${result.rewardAmount!.toStringAsFixed(2)} kazandın',
        isError: false,
      );
      widget.onRewardEarned?.call();
    } else {
      _showLimitSnack(result);
    }

    _preload();
  }

  /// Saniyeyi "X dk Y sn" / "X sn" formatına çevirir.
  String _formatRemaining(int totalSeconds) {
    if (totalSeconds < 60) return '$totalSeconds saniye';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return s == 0 ? '$m dakika' : '$m dakika $s saniye';
  }

  /// Şimdi + ekSaniye sonrasını "HH:MM" formatında yerel saat olarak verir.
  String _clockAfter(int secondsFromNow) {
    final t = DateTime.now().add(Duration(seconds: secondsFromNow));
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _showLimitSnack(AdRewardResult result) {
    final type = result.limitType;
    final secs = result.retryAfterSeconds;

    if (type == 'cooldown' && secs != null) {
      _showSnack(
        'Reklamlar arası bekleme süresi var. ${_formatRemaining(secs)} '
        'kaldı (saat ${_clockAfter(secs)}’te tekrar dene)',
        isError: true,
      );
      return;
    }
    if (type == 'hourly' && secs != null) {
      _showSnack(
        'Saatlik reklam izleme limitine ulaştın. '
        '~${_formatRemaining(secs)} sonra tekrar dene (saat ${_clockAfter(secs)})',
        isError: true,
      );
      return;
    }
    if (type == 'daily' && secs != null) {
      _showSnack(
        'Bugünlük reklam hakkın bitti. Saat ${_clockAfter(secs)}’te '
        '(yarın) yenilenir, o zaman tekrar gel.',
        isError: true,
      );
      return;
    }

    _showSnack(result.errorMessage ?? 'Ödül alınamadı, lütfen tekrar dene', isError: true);
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: isError ? const Duration(seconds: 5) : const Duration(seconds: 3),
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

    final rewardMin = _settings!.rewardMinTry.toStringAsFixed(2);
    final rewardMax = _settings!.rewardMaxTry.toStringAsFixed(2);
    final description = (_settings!.cardDescription?.trim().isNotEmpty ?? false)
        ? _settings!.cardDescription!.trim()
        : '₺$rewardMin - ₺$rewardMax arası şansla bakiye kazan';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade600, Colors.deepOrange.shade400],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
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
          onTap: _isShowing ? null : _watchAd,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _isShowing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'İzleyerek Kazan',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        description,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
