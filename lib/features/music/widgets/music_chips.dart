import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/attached_music.dart';
import '../services/clip_player.dart';
import 'music_ui.dart';

/// Besteci ekranlarında (gönderi/hikaye) iliştirilmiş müziği gösteren çip.
///
/// Kaldırma düğmesi çipin İÇİNDE: müziği eklemek tek dokunuş olduğu gibi
/// vazgeçmek de tek dokunuş olmalı. Ayrı bir menüye saklanan "kaldır", eklemeyi
/// denemekten caydırır.
class AttachedMusicChip extends StatelessWidget {
  final AttachedMusic music;
  final VoidCallback? onRemove;

  /// Koyu zeminler (hikaye önizlemesi) için. Varsayılan açık zemin.
  final bool onDarkSurface;

  const AttachedMusicChip({
    super.key,
    required this.music,
    this.onRemove,
    this.onDarkSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = (music.durationMs / 1000).round();

    return Container(
      padding: EdgeInsets.fromLTRB(10, 6, onRemove == null ? 10 : 4, 6),
      decoration: BoxDecoration(
        color: onDarkSurface
            ? Colors.black.withValues(alpha: 0.55)
            : MusicUI.tint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note_rounded,
            size: 15,
            color: onDarkSurface ? Colors.white : MusicUI.onTint,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${music.label} · $seconds sn',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: onDarkSurface ? Colors.white : MusicUI.onTint,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 15),
              color: onDarkSurface ? Colors.white70 : MusicUI.onTintMuted,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: 'Müziği kaldır',
            ),
        ],
      ),
    );
  }
}

/// Akıştaki gönderi kartında müzik rozeti.
///
/// ## Otomatik çalmaz
///
/// Akış kaydırılırken kendiliğinden ses çıkarmaz; yalnızca dokunulunca çalar.
/// Otomatik çalma hem veri harcar hem de kullanıcının sessiz sandığı bir
/// ortamda sesi açar — sosyal akışta kazanan davranış her zaman sessizliktir.
class FeedMusicPill extends StatelessWidget {
  final AttachedMusic music;

  const FeedMusicPill({super.key, required this.music});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ClipPlayer.instance.nowPlayingKey,
      builder: (context, playingKey, _) {
        final playing = playingKey == music.url;
        return InkWell(
          onTap: () => ClipPlayer.instance.toggle(music),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
            decoration: BoxDecoration(
              color: MusicUI.tint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: playing ? MusicUI.accentDeep : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 15,
                    color: playing ? Colors.white : MusicUI.onTint,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    music.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MusicUI.onTint,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (playing) ...[
                  const SizedBox(width: 8),
                  const MusicEqualizer(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Çalarken oynayan küçük ekolayzır.
///
/// YALNIZCA görünürken ve çalarken canlandırılır: dekoratif bir animasyonun
/// arka planda dönmeye devam etmesi pil yakar ve akışta yüzlerce kez tekrarlanır.
/// Bu yüzden widget yalnızca "çalıyor" durumunda ağaca giriyor ve
/// [dispose] ile denetleyicisini bırakıyor.
class MusicEqualizer extends StatefulWidget {
  final Color color;
  final double height;

  const MusicEqualizer({
    super.key,
    this.color = MusicUI.accentDeep,
    this.height = 12,
  });

  @override
  State<MusicEqualizer> createState() => _MusicEqualizerState();
}

class _MusicEqualizerState extends State<MusicEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => SizedBox(
        width: 14,
        height: widget.height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            // Her çubuk farklı fazda: aynı anda inip kalkan üç çubuk
            // ekolayzır değil, yanıp sönen bir blok gibi görünür.
            final phase = _c.value * 2 * math.pi + i * 2.1;
            final t = (math.sin(phase) + 1) / 2;
            return Container(
              width: 3,
              height: widget.height * (0.3 + t * 0.7),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        ),
      ),
    );
  }
}
