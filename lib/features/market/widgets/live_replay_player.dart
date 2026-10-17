import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/live_shopping_model.dart';
import '../services/live_shopping_service.dart';
import 'live_stream_widgets.dart';

/// Oynatılabilir tek kayıt parçası. Uygulama `video_player` kullanır
/// ([VideoPlayerReplayClip]); testler sahte parçayla oynatıcıyı sürer.
abstract class LiveReplayClip implements Listenable {
  Future<void> initialize();
  bool get isInitialized;
  Duration get duration;
  Duration get position;
  bool get isPlaying;
  bool get isBuffering;
  bool get isCompleted;
  bool get hasError;
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Widget buildView();
  Future<void> dispose();
}

typedef LiveReplayClipFactory = LiveReplayClip Function(Uri url);

class VideoPlayerReplayClip implements LiveReplayClip {
  VideoPlayerReplayClip(Uri url) : _controller = VideoPlayerController.networkUrl(url);

  final VideoPlayerController _controller;

  VideoPlayerValue get _value => _controller.value;

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _controller.removeListener(listener);

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  bool get isInitialized => _value.isInitialized;

  @override
  Duration get duration => _value.duration;

  @override
  Duration get position => _value.position;

  @override
  bool get isPlaying => _value.isPlaying;

  @override
  bool get isBuffering => _value.isBuffering;

  @override
  bool get isCompleted => _value.isCompleted;

  @override
  bool get hasError => _value.hasError;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) => _controller.setVolume(volume);

  @override
  Widget buildView() {
    final size = _value.size;
    if (size.isEmpty) return VideoPlayer(_controller);
    // Canlı görüntü gibi ekranı doldurur (dikey yayın, kenarlar kırpılır).
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(_controller)),
    );
  }

  @override
  Future<void> dispose() => _controller.dispose();
}

enum _ReplayPhase { loading, ready, unavailable, failed }

/// Biten canlı yayının kaydı: parçaları (3 dk'lık MP4) art arda oynatır; tek
/// ilerleme çubuğu tüm kaydı kapsar. Sıradaki parça önceden hazırlanır.
/// Yayıncı son parçaları hâlâ yüklüyorsa (processing) sona gelince liste
/// yenilenir ve gelen parçayla sürer.
class LiveReplayPlayer extends StatefulWidget {
  const LiveReplayPlayer({
    super.key,
    required this.sessionId,
    required this.service,
    this.clipFactory,
    this.muted = false,
    this.autoPlay = true,
    this.onUnavailable,
    this.bottomInset = 0,
  });

  final String sessionId;
  final LiveShoppingService service;
  final LiveReplayClipFactory? clipFactory;
  final bool muted;
  final bool autoPlay;

  /// Kayıt izlenemiyor (silindi, süresi doldu, görünür değil, parça yok).
  final VoidCallback? onUnavailable;

  /// Alt denetimlerin üstünde bırakılacak boşluk (ör. ürün şeridi).
  final double bottomInset;

  @override
  State<LiveReplayPlayer> createState() => _LiveReplayPlayerState();
}

class _LiveReplayPlayerState extends State<LiveReplayPlayer> {
  _ReplayPhase _phase = _ReplayPhase.loading;
  LiveReplayManifest? _manifest;
  List<LiveReplayItem> _items = const [];
  List<String?> _urls = const [];

  /// Parça başına süre (sunucudaki ölçüm; parça açılınca gerçeğiyle düzelir).
  List<Duration> _durations = const [];
  final Map<int, LiveReplayClip> _clips = {};
  int _index = 0;
  bool _ended = false;
  bool _controlsVisible = true;
  bool _seeking = false;
  double? _dragValue;
  bool _switching = false;
  bool _refreshing = false;
  Timer? _hideTimer;
  int _loadSeq = 0;

  LiveReplayClip? get _current => _clips[_index];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LiveReplayPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.muted != widget.muted) {
      for (final clip in _clips.values) {
        unawaited(clip.setVolume(widget.muted ? 0 : 1));
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final clip in _clips.values) {
      clip.removeListener(_onTick);
      unawaited(clip.dispose());
    }
    _clips.clear();
    super.dispose();
  }

  LiveReplayClip _createClip(Uri url) => (widget.clipFactory ?? VideoPlayerReplayClip.new)(url);

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() {
      _phase = _ReplayPhase.loading;
      _ended = false;
    });
    try {
      final manifest = await widget.service.fetchReplay(widget.sessionId);
      if (!mounted || seq != _loadSeq) return;
      if (manifest == null || manifest.items.isEmpty || manifest.replay.isGone) {
        setState(() => _phase = _ReplayPhase.unavailable);
        widget.onUnavailable?.call();
        return;
      }
      final urls = await widget.service.signReplayUrls([for (final item in manifest.items) item.path]);
      if (!mounted || seq != _loadSeq) return;
      _disposeClips();
      setState(() {
        _manifest = manifest;
        _items = manifest.items;
        _urls = urls;
        _durations = [for (final item in manifest.items) item.duration];
        _index = 0;
        _phase = _ReplayPhase.ready;
      });
      await _activate(0, play: widget.autoPlay);
    } catch (e) {
      debugPrint('live replay load: $e');
      if (mounted && seq == _loadSeq) setState(() => _phase = _ReplayPhase.failed);
    }
  }

  void _disposeClips() {
    for (final clip in _clips.values) {
      clip.removeListener(_onTick);
      unawaited(clip.dispose());
    }
    _clips.clear();
  }

  /// [index]. parçayı hazırlar (gerekirse oluşturur ve açar).
  Future<LiveReplayClip?> _prepare(int index) async {
    if (index < 0 || index >= _items.length) return null;
    final existing = _clips[index];
    if (existing != null) {
      if (!existing.isInitialized && !existing.hasError) await existing.initialize();
      return existing;
    }
    final url = _urls[index];
    if (url == null) return null;
    final clip = _createClip(Uri.parse(url));
    _clips[index] = clip;
    clip.addListener(_onTick);
    await clip.initialize();
    await clip.setVolume(widget.muted ? 0 : 1);
    if (!mounted) return clip;
    final real = clip.duration;
    if (real > Duration.zero && real != _durations[index]) {
      setState(() => _durations = [..._durations]..[index] = real);
    }
    return clip;
  }

  /// [index]. parçaya geçer ve [at] konumundan oynatır; sıradakini hazırlar,
  /// diğerlerini bırakır.
  Future<void> _activate(int index, {Duration at = Duration.zero, required bool play}) async {
    if (_switching) return;
    _switching = true;
    try {
      // İmzalanamayan (silinmiş) parçayı atla.
      while (index < _items.length && _urls[index] == null) {
        index++;
      }
      if (index >= _items.length) {
        await _reachedEnd();
        return;
      }
      final previous = _current;
      if (previous != null && _clips[index] != previous) await previous.pause();
      setState(() {
        _index = index;
        _ended = false;
      });
      final clip = await _prepare(index);
      if (!mounted || clip == null) return;
      if (clip.hasError) {
        setState(() => _phase = _ReplayPhase.failed);
        return;
      }
      if (at > Duration.zero || clip.position > Duration.zero) await clip.seekTo(at);
      if (play) await clip.play();
      for (final key in _clips.keys.toList()) {
        if (key != index && key != index + 1) {
          final old = _clips.remove(key)!;
          old.removeListener(_onTick);
          unawaited(old.dispose());
        }
      }
      if (mounted) setState(() {});
      if (play) _scheduleHide();
      // Sıradaki parça arka planda açılır (geçiş takılmasın).
      unawaited(_prepare(index + 1).then((_) {}, onError: (_) {}));
    } finally {
      _switching = false;
    }
  }

  Future<void> _reachedEnd() async {
    // Yayıncı son parçaları hâlâ yüklüyorsa listeyi yenile, geleni oynat.
    if (_manifest?.replay.isProcessing == true && !_refreshing) {
      _refreshing = true;
      try {
        final fresh = await widget.service.fetchReplay(widget.sessionId);
        if (mounted && fresh != null && fresh.items.length > _items.length) {
          final known = _items.length;
          final added = fresh.items.sublist(known);
          final urls = await widget.service.signReplayUrls([for (final item in added) item.path]);
          if (!mounted) return;
          setState(() {
            _manifest = fresh;
            _items = fresh.items;
            _urls = [..._urls, ...urls];
            _durations = [..._durations, for (final item in added) item.duration];
          });
          _switching = false;
          await _activate(known, play: true);
          return;
        }
        if (mounted && fresh != null) setState(() => _manifest = fresh);
      } catch (e) {
        debugPrint('live replay refresh: $e');
      } finally {
        _refreshing = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _ended = true;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
  }

  void _onTick() {
    if (!mounted) return;
    final clip = _current;
    if (clip != null && clip.isCompleted && !_switching && !_ended && !_seeking) {
      unawaited(_activate(_index + 1, play: true));
      return;
    }
    setState(() {});
  }

  Duration get _total => _durations.fold(Duration.zero, (sum, d) => sum + d);

  Duration _offsetOf(int index) {
    var sum = Duration.zero;
    for (var i = 0; i < index && i < _durations.length; i++) {
      sum += _durations[i];
    }
    return sum;
  }

  Duration get _position {
    if (_ended) return _total;
    final clip = _current;
    return _offsetOf(_index) + (clip?.position ?? Duration.zero);
  }

  bool get _isPlaying => _current?.isPlaying ?? false;

  Future<void> _togglePlay() async {
    if (_ended) {
      await _activate(0, play: true);
      return;
    }
    final clip = _current;
    if (clip == null) return;
    if (clip.isPlaying) {
      await clip.pause();
      _hideTimer?.cancel();
      setState(() => _controlsVisible = true);
    } else {
      await clip.play();
      _scheduleHide();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekTo(Duration target) async {
    final total = _total;
    if (total <= Duration.zero) return;
    final clamped = target < Duration.zero ? Duration.zero : (target > total ? total : target);
    var index = 0;
    var offset = Duration.zero;
    while (index < _durations.length - 1 && offset + _durations[index] <= clamped) {
      offset += _durations[index];
      index++;
    }
    final play = _isPlaying || _ended;
    _seeking = true;
    try {
      if (index == _index && !_ended) {
        await _current?.seekTo(clamped - offset);
        if (play && !(_current?.isPlaying ?? true)) await _current?.play();
      } else {
        await _activate(index, at: clamped - offset, play: play);
      }
    } finally {
      _seeking = false;
    }
    if (mounted) setState(() => _ended = false);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible && _isPlaying) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _ReplayPhase.loading => const LiveStageMessage(icon: Icons.history, text: 'Kayıt yükleniyor…', busy: true),
      _ReplayPhase.unavailable => const LiveStageMessage(
        icon: Icons.videocam_off_outlined,
        text: 'Bu yayının kaydı yok.',
      ),
      _ReplayPhase.failed => _failure(),
      _ReplayPhase.ready => _stage(),
    };
  }

  Widget _failure() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          const Text('Kayıt oynatılamadı', style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('live-replay-retry'),
            onPressed: _load,
            style: FilledButton.styleFrom(backgroundColor: kLiveRed),
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }

  Widget _stage() {
    final clip = _current;
    final busy = clip == null || !clip.isInitialized || (clip.isBuffering && !_ended) || _switching;
    final total = _total;
    final position = _position;
    final sliderMax = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
    final sliderValue = (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, sliderMax);
    final showControls = _controlsVisible || !_isPlaying;
    return GestureDetector(
      key: const ValueKey('live-replay-stage'),
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (clip != null && clip.isInitialized) clip.buildView(),
          if (busy && !_ended) const Center(child: CircularProgressIndicator(color: Colors.white)),
          if ((showControls && !busy) || _ended)
            Center(
              child: IconButton(
                key: const ValueKey('live-replay-center'),
                iconSize: 64,
                tooltip: _ended ? 'Baştan izle' : (_isPlaying ? 'Duraklat' : 'Oynat'),
                onPressed: _togglePlay,
                icon: Icon(
                  _ended
                      ? Icons.replay_circle_filled
                      : (_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          AnimatedOpacity(
            opacity: showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !showControls,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: EdgeInsets.fromLTRB(12, 24, 12, 8 + widget.bottomInset),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        IconButton(
                          key: const ValueKey('live-replay-play'),
                          tooltip: _isPlaying ? 'Duraklat' : 'Oynat',
                          onPressed: busy && !_ended ? null : _togglePlay,
                          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                        ),
                        Text(
                          formatLiveDuration(Duration(milliseconds: sliderValue.round())),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Expanded(
                          // Slider dikeyde verilen tüm yüksekliği kaplar: sabitlenmezse
                          // denetim satırı ekranın ortasına iner.
                          child: SizedBox(
                            height: 40,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: kLiveRed,
                                inactiveTrackColor: Colors.white30,
                                thumbColor: Colors.white,
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              ),
                              child: Slider(
                                key: const ValueKey('live-replay-slider'),
                                value: sliderValue,
                                max: sliderMax,
                                onChangeStart: (v) {
                                  _hideTimer?.cancel();
                                  setState(() => _dragValue = v);
                                },
                                onChanged: (v) => setState(() => _dragValue = v),
                                onChangeEnd: (v) async {
                                  setState(() => _dragValue = null);
                                  await _seekTo(Duration(milliseconds: v.round()));
                                  if (_isPlaying) _scheduleHide();
                                },
                              ),
                            ),
                          ),
                        ),
                        Text(
                          formatLiveDuration(total),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
