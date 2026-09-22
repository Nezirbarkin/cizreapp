import 'package:flutter/material.dart';

import '../models/leaderboard_models.dart';
import '../services/leaderboard_service.dart';

/// Hesap Ayarları > Gizlilik: "Liderler tablosunda gizle".
///
/// Kullanıcı kendini Liderler Tablosu'ndaki tüm listelerden çıkarabilir: adı,
/// gönderileri, hikayeleri ve sahibi olduğu dükkanlar artık listelenmez. Sayaçlara
/// ("Toplam üye" vb.) yine dahildir.
///
/// Admin de bir kullanıcıyı gizleyebilir; bu durumda kullanıcı bunu KENDİ anahtarıyla
/// geri alamaz. Bu yüzden iki durum ayrı gösterilir: anahtar yalnız kendi tercihini
/// yönetir, admin gizlemesi altında bir uyarı olarak görünür.
///
/// Yükleyici/kaydedici test için dışarıdan verilebilir.
class LeaderboardVisibilityTile extends StatefulWidget {
  const LeaderboardVisibilityTile({
    super.key,
    this.loader,
    this.saver,
    this.activeColor = Colors.purple,
  });

  final Future<LeaderboardVisibility> Function()? loader;
  final Future<LeaderboardVisibility> Function(bool hidden)? saver;
  final Color activeColor;

  @override
  State<LeaderboardVisibilityTile> createState() =>
      _LeaderboardVisibilityTileState();
}

class _LeaderboardVisibilityTileState extends State<LeaderboardVisibilityTile> {
  LeaderboardVisibility _visibility = const LeaderboardVisibility();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value =
          await (widget.loader ?? LeaderboardService.fetchMyVisibility)();
      if (!mounted) return;
      setState(() {
        _visibility = value;
        _loading = false;
      });
    } catch (_) {
      // Okunamadıysa anahtar kapalı (devre dışı) kalır; yanlış durum göstermeyiz.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool hidden) async {
    final previous = _visibility;
    setState(() {
      _saving = true;
      _visibility = LeaderboardVisibility(
        selfHidden: hidden,
        adminHidden: previous.adminHidden,
      );
    });
    try {
      final saved = await (widget.saver ?? LeaderboardService.setSelfHidden)(
        hidden,
      );
      if (!mounted) return;
      setState(() => _visibility = saved);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            hidden
                ? 'Liderler tablosunda artık görünmüyorsun'
                : 'Liderler tablosunda yeniden görünebilirsin',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _visibility = previous);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi, tekrar dene')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const ValueKey('leaderboard-self-hide-switch'),
          title: const Text('Liderler tablosunda gizle'),
          subtitle: const Text(
            'Açıkken adın, gönderilerin, hikayelerin ve dükkanların liderler '
            'listelerinde görünmez',
          ),
          value: _visibility.selfHidden,
          onChanged: (_loading || _saving) ? null : _toggle,
          contentPadding: EdgeInsets.zero,
          activeThumbColor: widget.activeColor,
        ),
        if (_visibility.adminHidden)
          Container(
            key: const ValueKey('leaderboard-admin-hidden-note'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: .3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 18,
                  color: Colors.orange,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Yönetici seni liderler tablosundan gizledi. Bu durumu '
                    'buradan değiştiremezsin.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
