import 'package:flutter/material.dart';

import '../../../okey/services/okey_sound_service.dart';
import '../models/music_track.dart';
import '../widgets/music_chips.dart';
import '../widgets/music_player_widgets.dart';
import '../widgets/music_ui.dart';

/// Tam ekran "Şimdi çalıyor".
///
/// Müziğim ekranındaki oynatıcı kartına dokununca açılır. Kendine ait bir
/// oynatıcısı yoktur — uygulamanın tek ses motorunu gösterir ve yönetir;
/// ekran kapanınca müzik çalmaya devam eder.
class MusicPlayerScreen extends StatefulWidget {
  /// Çalan parçanın sanatçı/tür gibi ayrıntılarını bulmak için.
  ///
  /// Motor yalnızca ad ve adres tutuyor; ayrıntılar Müziğim ekranının
  /// listelerinde. Bulunamazsa ekran yalnızca adı ve kaynağı gösterir.
  final MusicTrack? Function(String url)? lookup;

  const MusicPlayerScreen({super.key, this.lookup});

  static Future<void> open(
    BuildContext context, {
    MusicTrack? Function(String url)? lookup,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => MusicPlayerScreen(lookup: lookup),
        // Alttan yukarı kayarak açılır: mini oynatıcının "genişlediği"
        // hissini verir.
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(anim),
          child: child,
        ),
      ),
    );
  }

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  OkeySoundService get _sound => OkeySoundService.instance;

  @override
  void initState() {
    super.initState();
    _sound.musicState.addListener(_onChanged);
  }

  @override
  void dispose() {
    _sound.musicState.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String _subtitle() {
    final url = _sound.currentTrackUrl;
    final track = url == null ? null : widget.lookup?.call(url);
    final artist = track?.artist?.trim();
    final source = _sound.currentTrackIsLocal ? 'Cihazından' : 'Cizre Radyo';
    if (artist == null || artist.isEmpty) return source;
    return '$artist · $source';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final discSize = (size.width - 80).clamp(180.0, 320.0);
    final playing = _sound.isMusicPlaying;
    final upNext = _sound.upNextIndices(limit: 30);
    final playlist = _sound.playlist;

    return Scaffold(
      backgroundColor: const Color(0xFF241127),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: kPlayerGradient),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Küçült',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'ŞİMDİ ÇALIYOR',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // Başlığı ortalı tutmak için sağda eşit bir boşluk.
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                  child: Column(
                    children: [
                      Center(
                        child: SpinningDisc(size: discSize, playing: playing),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _sound.hasMusic
                                      ? _sound.currentTrackName
                                      : 'Çalan şarkı yok',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _subtitle(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (playing)
                            const Padding(
                              padding: EdgeInsets.only(left: 12, bottom: 6),
                              child: MusicEqualizer(
                                color: MusicUI.accent,
                                height: 16,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const MusicSeekBar(),
                      const SizedBox(height: 12),
                      const MusicTransportControls(playSize: 72),
                    ],
                  ),
                ),
              ),
              if (upNext.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(28, 36, 28, 8),
                    child: Text(
                      'Sıradaki',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: upNext.length,
                  itemBuilder: (context, i) {
                    final index = upNext[i];
                    if (index >= playlist.length) {
                      return const SizedBox.shrink();
                    }
                    final t = playlist[index];
                    final meta = widget.lookup?.call(t.url);
                    final artist = meta?.artist?.trim();
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 28,
                      ),
                      onTap: () => _sound.playTrackAt(index),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          t.isLocal
                              ? Icons.smartphone_rounded
                              : Icons.radio_rounded,
                          size: 18,
                          color: Colors.white60,
                        ),
                      ),
                      title: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        (artist == null || artist.isEmpty)
                            ? (t.isLocal ? 'Cihazından' : 'Cizre Radyo')
                            : artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54),
                      ),
                    );
                  },
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}
