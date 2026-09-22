import 'package:flutter/material.dart';

/// Müzik yüzeylerinin ortak paleti.
///
/// Renkler BİLEREK aktif temadan (ThemeProvider.primaryColor) bağımsız:
/// yan menüdeki plak kartı ([NowPlayingPanel]) da aynı iki tonu kullanıyor ve
/// oradaki gerekçe burada da geçerli — müzik yüzeyleri, üstünde durdukları
/// ekranın teması kırmızı, yeşil ya da mavi olsun, hep aynı kimliği taşısın.
/// Kullanıcı "müzik olan yer" ile "uygulamanın geri kalanı"nı renkten ayırt
/// edebilmeli.
class MusicUI {
  MusicUI._();

  /// Plak etiketinin açık tonu — vurgular, ekolayzır çubukları.
  static const Color accent = Color(0xFFFF6FAE);

  /// Koyu ton — birincil düğmeler, dolgu.
  static const Color accentDeep = Color(0xFFD91A73);

  /// Açık pembe zemin — çipler, seçili satırlar.
  static const Color tint = Color(0xFFFBEAF0);

  /// Pembe zemin üstündeki yazı. Düz siyah kullanmıyoruz: aynı renk ailesinin
  /// koyu tonu, çipi rastgele bir kutu değil aynı nesnenin parçası gösterir.
  static const Color onTint = Color(0xFF4B1528);

  /// Açık zemin üzerindeki ikinci derece yazı.
  static const Color onTintMuted = Color(0xFF993556);

  /// Koyu dolgu üstündeki ikon rengi — plağın en koyu durağıyla aynı aile.
  static const Color ink = Color(0xFF1E1B27);

  static BorderRadius get radius => BorderRadius.circular(12);
}

/// Listede bir şarkı satırı.
///
/// Hem "Kitaplığım" hem "Cizre Radyo" hem de seçim sayfası aynı satırı
/// kullanır; üç yerde üç farklı satır çizmek, aynı şarkının üç farklı
/// görünmesi demekti.
class MusicTrackTile extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Bu satır ŞU AN çalıyor mu? İkon ve vurgu buna göre değişir.
  final bool playing;

  /// Seçim sayfasında işaretli satır (çalmaktan farklı: seçili ama sessiz
  /// olabilir).
  final bool selected;

  /// Yerel sanatçı rozetini göster.
  final bool byLocalArtist;

  final VoidCallback? onTap;
  final VoidCallback? onPlayTap;

  /// Sağ uçtaki ek düğme (ör. "⋮" menüsü ya da "+" ekle).
  final Widget? trailing;

  const MusicTrackTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.playing = false,
    this.selected = false,
    this.byLocalArtist = false,
    this.onTap,
    this.onPlayTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected ? MusicUI.tint : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              _PlayBadge(playing: playing, onTap: onPlayTap ?? onTap),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: playing
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: selected ? MusicUI.onTint : null,
                            ),
                          ),
                        ),
                        if (byLocalArtist) ...[
                          const SizedBox(width: 6),
                          const _ArtistBadge(),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected
                              ? MusicUI.onTintMuted
                              : theme.textTheme.bodySmall?.color?.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  final bool playing;
  final VoidCallback? onTap;

  const _PlayBadge({required this.playing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Duraklat' : 'Çal',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: playing ? MusicUI.accentDeep : MusicUI.tint,
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 20,
            color: playing ? Colors.white : MusicUI.onTint,
          ),
        ),
      ),
    );
  }
}

class _ArtistBadge extends StatelessWidget {
  const _ArtistBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: MusicUI.tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'yerel',
        style: TextStyle(
          fontSize: 10,
          color: MusicUI.onTintMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Şarkı yokken gösterilen davet.
///
/// "Burada bir şey yok" demek yerine ne yapılacağını söyler: boş durum bir
/// özür değil, bir çağrıdır.
class MusicEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const MusicEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: MusicUI.tint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: MusicUI.onTintMuted),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
