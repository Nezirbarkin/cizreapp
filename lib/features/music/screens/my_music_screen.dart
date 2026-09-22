import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../okey/services/okey_sound_service.dart';
import '../models/music_track.dart';
import '../services/music_catalog_service.dart';
import '../services/music_library_service.dart';
import '../services/music_settings_service.dart';
import '../widgets/music_chips.dart';
import '../widgets/music_player_widgets.dart';
import '../widgets/music_ui.dart';
import 'artist_upload_screen.dart';
import 'music_player_screen.dart';

/// "Müziğim" — kullanıcının kendi kitaplığı ve Cizre Radyo kataloğu.
///
/// ## Neden ayrı bir oynatıcı yok
///
/// Çalma işini uygulamanın zaten var olan tek ses motoru ([OkeySoundService])
/// yapıyor. Bunun görünür karşılığı şu: buradan başlatılan bir şarkı yan
/// menüdeki plak kartında da görünür, bildirim panelindeki ⏮ ⏯ ⏭ düğmeleri
/// onu da yönetir ve ekrandan çıkınca susmaz. Karışık/tekrar tercihleri de
/// motorda durur; burada değiştirilen tercih her yerde geçerlidir.
///
/// ## Açılışta hiçbir şey yüklenmiyor
///
/// Bu ekran uygulama açılışında değil, yalnızca kullanıcı yan menüden girince
/// kurulur. Kitaplık indeksi küçük bir JSON, katalog ise yalnızca sekme
/// açıldığında sorgulanır.
class MyMusicScreen extends StatefulWidget {
  const MyMusicScreen({super.key});

  @override
  State<MyMusicScreen> createState() => _MyMusicScreenState();
}

enum _Tab { library, catalog }

class _MyMusicScreenState extends State<MyMusicScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  _Tab _tab = _Tab.library;
  List<MusicTrack> _library = const [];
  List<MusicTrack> _catalog = const [];
  List<String> _genres = const [];
  String? _genre;

  bool _loadingLibrary = true;
  bool _loadingCatalog = false;
  bool _adding = false;

  MusicSettings _settings = MusicSettingsService.cached;

  OkeySoundService get _sound => OkeySoundService.instance;

  @override
  void initState() {
    super.initState();
    _sound.musicState.addListener(_onMusicChanged);
    _boot();
  }

  @override
  void dispose() {
    _sound.musicState.removeListener(_onMusicChanged);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onMusicChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    final settings = await MusicSettingsService.fetch();
    final tracks = await MusicLibraryService.instance.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _library = tracks;
      _loadingLibrary = false;
      if (tracks.isEmpty && settings.catalog) _tab = _Tab.catalog;
    });
    if (_tab == _Tab.catalog) {
      unawaited(_search());
      unawaited(_loadGenres());
    }
  }

  Future<void> _loadGenres() async {
    final genres = await MusicCatalogService.instance.genres();
    if (!mounted) return;
    setState(() => _genres = genres);
  }

  Future<void> _search() async {
    if (!_settings.catalog) return;
    setState(() => _loadingCatalog = true);
    final results = await MusicCatalogService.instance.search(
      query: _searchController.text,
      genre: _genre,
      limit: 50,
    );
    if (!mounted) return;
    setState(() {
      _catalog = results;
      _loadingCatalog = false;
    });
  }

  void _onQueryChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _search);
  }

  void _switchTab(_Tab tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
    if (tab == _Tab.catalog) {
      if (_catalog.isEmpty) unawaited(_search());
      if (_genres.isEmpty) unawaited(_loadGenres());
    }
  }

  // ---------------------------------------------------------------- çalma

  List<MusicTrack> get _visible => _tab == _Tab.library ? _library : _catalog;

  String _urlOf(MusicTrack t) =>
      t.isDevice ? (t.localPath ?? '') : (t.url ?? '');

  /// Motorun tuttuğu adresten parçanın ayrıntılarını bulur (sanatçı vb.).
  MusicTrack? _lookup(String url) {
    for (final t in _library) {
      if (t.localPath == url) return t;
    }
    for (final t in _catalog) {
      if (t.url == url) return t;
    }
    return null;
  }

  /// Bu parça şu an oynatıcıda yüklü mü?
  ///
  /// Adres üzerinden karşılaştırıyoruz: aynı şarkı hem kitaplıkta hem
  /// katalogda olabilir ve kimliği farklıdır, ama çalan dosya tektir.
  bool _isCurrent(MusicTrack track) => _sound.currentTrackUrl == _urlOf(track);

  /// Listedeki bir şarkıya dokunuldu.
  ///
  /// Çalan şarkıya tekrar dokunmak duraklatır: liste satırı aynı zamanda
  /// oynatma denetimidir, ikinci bir düğme aramaya gerek kalmaz.
  Future<void> _playFrom(List<MusicTrack> tracks, int index) async {
    final track = tracks[index];

    if (_isCurrent(track) && _sound.isMusicPlaying) {
      await _sound.pauseMusic();
      return;
    }
    if (_isCurrent(track) && _sound.isMusicPaused) {
      await _sound.resumeMusicPlayback();
      return;
    }

    await _sound.playUserPlaylist([
      for (final t in tracks)
        (url: _urlOf(t), name: t.title, isLocal: t.isDevice),
    ], index: index);
  }

  /// "Çal" — listeyi sırayla baştan; "Karışık" — rastgele bir şarkıdan,
  /// karışık açık. İki düğme modu da AYARLAR: kullanıcı neye bastıysa onu
  /// alır, önceki tercihin sürprizine uğramaz.
  Future<void> _playAll({required bool shuffle}) async {
    final tracks = _visible;
    if (tracks.isEmpty) return;
    HapticFeedback.lightImpact();
    if (_sound.isShuffle != shuffle) await _sound.toggleShuffle();
    final start = shuffle ? math.Random().nextInt(tracks.length) : 0;
    await _sound.playUserPlaylist([
      for (final t in tracks)
        (url: _urlOf(t), name: t.title, isLocal: t.isDevice),
    ], index: start);
  }

  void _openPlayer() {
    if (!_sound.hasMusic) return;
    MusicPlayerScreen.open(context, lookup: _lookup);
  }

  // ------------------------------------------------------------- kitaplık

  Future<void> _addFromDevice() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final track = await MusicLibraryService.instance.addFromDevice();
      if (!mounted) return;
      if (track != null) {
        final tracks = await MusicLibraryService.instance.load();
        if (!mounted) return;
        setState(() {
          _library = tracks;
          _tab = _Tab.library;
        });
        _snack('"${track.title}" kitaplığına eklendi');
      }
    } on MusicLibraryException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _renameTrack(MusicTrack track) async {
    final controller = TextEditingController(text: track.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şarkıyı yeniden adlandır'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Şarkı adı'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty) return;
    await MusicLibraryService.instance.rename(track.id, name);
    final tracks = await MusicLibraryService.instance.load(forceRefresh: true);
    if (!mounted) return;
    setState(() => _library = tracks);
  }

  Future<void> _removeTrack(MusicTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şarkıyı kaldır'),
        content: Text(
          '"${track.title}" kitaplığından ve telefonun içindeki uygulama '
          'klasöründen silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await MusicLibraryService.instance.remove(track.id);
    final tracks = await MusicLibraryService.instance.load(forceRefresh: true);
    if (!mounted) return;
    setState(() => _library = tracks);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  void _openUpload() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ArtistUploadScreen()),
  );

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final showAdd =
        _tab == _Tab.library &&
        _settings.deviceAdd &&
        MusicLibraryService.isSupported;

    return Scaffold(
      floatingActionButton: showAdd
          ? FloatingActionButton.extended(
              onPressed: _adding ? null : _addFromDevice,
              backgroundColor: MusicUI.accentDeep,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: _adding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_rounded),
              label: const Text('Müzik ekle'),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text(
              'Müziğim',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              if (_tab == _Tab.catalog && _settings.artistUpload)
                IconButton(
                  tooltip: 'Şarkını yükle',
                  icon: const Icon(Icons.mic_rounded),
                  onPressed: _openUpload,
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _sound.hasMusic
                  ? _HeroPlayer(
                      title: _sound.currentTrackName,
                      subtitle: _heroSubtitle(),
                      playing: _sound.isMusicPlaying,
                      onExpand: _openPlayer,
                    )
                  : const _IdleHero(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: _SegmentedTabs(
                left: _library.isEmpty
                    ? 'Kitaplığım'
                    : 'Kitaplığım · ${_library.length}',
                right: 'Cizre Radyo',
                rightEnabled: _settings.catalog,
                selectedRight: _tab == _Tab.catalog,
                onLeft: () => _switchTab(_Tab.library),
                onRight: () => _switchTab(_Tab.catalog),
              ),
            ),
          ),
          if (_tab == _Tab.catalog && _settings.catalog)
            SliverToBoxAdapter(child: _catalogControls()),
          if (_visible.isNotEmpty && !_isLoadingCurrentTab)
            SliverToBoxAdapter(child: _playAllRow()),
          ..._bodySlivers(),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  bool get _isLoadingCurrentTab =>
      _tab == _Tab.library ? _loadingLibrary : _loadingCatalog;

  String _heroSubtitle() {
    final url = _sound.currentTrackUrl;
    final artist = url == null ? null : _lookup(url)?.artist?.trim();
    final source = _sound.currentTrackIsLocal ? 'Cihazından' : 'Cizre Radyo';
    if (artist == null || artist.isEmpty) return source;
    return '$artist · $source';
  }

  Widget _catalogControls() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onQueryChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Şarkı ya da sanatçı ara',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.04),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_genres.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 8),
              children: [
                _GenreChip(
                  label: 'Tümü',
                  selected: _genre == null,
                  onTap: () {
                    setState(() => _genre = null);
                    unawaited(_search());
                  },
                ),
                for (final g in _genres)
                  _GenreChip(
                    label: g,
                    selected: _genre == g,
                    onTap: () {
                      setState(() => _genre = g);
                      unawaited(_search());
                    },
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _playAllRow() {
    final theme = Theme.of(context);
    final count = _visible.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Text(
            '$count şarkı',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _PillButton(
            icon: Icons.shuffle_rounded,
            label: 'Karışık',
            onTap: () => _playAll(shuffle: true),
          ),
          const SizedBox(width: 8),
          _PillButton(
            icon: Icons.play_arrow_rounded,
            label: 'Çal',
            filled: true,
            onTap: () => _playAll(shuffle: false),
          ),
        ],
      ),
    );
  }

  List<Widget> _bodySlivers() {
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);

    if (_tab == _Tab.library) {
      if (_loadingLibrary) {
        return [fill(const Center(child: CircularProgressIndicator()))];
      }
      if (!MusicLibraryService.isSupported) {
        return [
          fill(
            const MusicEmptyState(
              icon: Icons.phonelink_off_rounded,
              title: 'Kitaplık bu cihazda yok',
              message:
                  'Telefondaki dosyaları eklemek yalnızca mobil uygulamada '
                  'çalışıyor. Cizre Radyo sekmesi burada da açık.',
            ),
          ),
        ];
      }
      if (_library.isEmpty) {
        return [
          fill(
            MusicEmptyState(
              icon: Icons.library_music_outlined,
              title: 'Kendi şarkılarını ekle',
              message: _settings.deviceAdd
                  ? 'Telefonundaki müzik dosyalarını buraya alırsan uygulama '
                        'içinde dinleyebilir, gönderine ve hikayene '
                        'ekleyebilirsin.'
                  : 'Cihazdan müzik ekleme şu anda kapalı.',
            ),
          ),
        ];
      }
      return [_trackList(_library, editable: true)];
    }

    if (!_settings.catalog) {
      return [
        fill(
          const MusicEmptyState(
            icon: Icons.radio_outlined,
            title: 'Cizre Radyo kapalı',
            message: 'Katalog şu anda kullanıma kapalı.',
          ),
        ),
      ];
    }
    if (_loadingCatalog) {
      return [fill(const Center(child: CircularProgressIndicator()))];
    }
    if (_catalog.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return [
        fill(
          MusicEmptyState(
            icon: Icons.search_off_rounded,
            title: searching ? 'Sonuç yok' : 'Katalog boş',
            message: searching
                ? 'Başka bir şarkı adı ya da sanatçı dene.'
                : 'Cizre Radyo\'ya henüz şarkı eklenmemiş.',
            action: _settings.artistUpload
                ? OutlinedButton.icon(
                    onPressed: _openUpload,
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('Şarkını yükle'),
                  )
                : null,
          ),
        ),
      ];
    }
    return [
      _trackList(_catalog, editable: false),
      if (_settings.artistUpload)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _openUpload,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: const Text('Şarkını yükle'),
            ),
          ),
        ),
    ];
  }

  Widget _trackList(List<MusicTrack> tracks, {required bool editable}) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      sliver: SliverList.builder(
        itemCount: tracks.length,
        itemBuilder: (context, i) {
          final t = tracks[i];
          final current = _isCurrent(t);
          return _TrackRow(
            track: t,
            current: current,
            playing: current && _sound.isMusicPlaying,
            onTap: () => _playFrom(tracks, i),
            trailing: editable
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded, size: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (value) {
                      if (value == 'rename') _renameTrack(t);
                      if (value == 'remove') _removeTrack(t);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Yeniden adlandır'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline_rounded),
                          title: Text('Kaldır'),
                        ),
                      ),
                    ],
                  )
                : null,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OYNATICI KARTI
// ---------------------------------------------------------------------------

/// Ekranın tepesindeki oynatıcı: dönen plak, ad, sürüklenebilir ilerleme ve
/// karışık · önceki · çal · sonraki · tekrar.
///
/// Kapağa ya da genişletme düğmesine dokunmak tam ekran oynatıcıyı açar.
class _HeroPlayer extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool playing;
  final VoidCallback onExpand;

  const _HeroPlayer({
    required this.title,
    required this.subtitle,
    required this.playing,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 6),
      decoration: BoxDecoration(
        gradient: kPlayerGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: MusicUI.accentDeep.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onExpand,
                child: SpinningDisc(size: 64, playing: playing),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onExpand,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (playing) ...[
                            const MusicEqualizer(
                              color: MusicUI.accent,
                              height: 10,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            playing ? 'ŞİMDİ ÇALIYOR' : 'DURAKLATILDI',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 10.5,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tam ekran oynatıcı',
                onPressed: onExpand,
                icon: const Icon(
                  Icons.open_in_full_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: MusicSeekBar(),
          ),
          const MusicTransportControls(playSize: 56),
        ],
      ),
    );
  }
}

/// Hiçbir şey yüklü değilken oynatıcının yerinde duran davet.
class _IdleHero extends StatelessWidget {
  const _IdleHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: kPlayerGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        children: [
          SpinningDisc(size: 56, playing: false),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Müziğin burada çalsın',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Aşağıdan bir şarkı seç ya da "Çal"a bas.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SEKME SEÇİCİ
// ---------------------------------------------------------------------------

/// İki seçenekli kayan seçici. Seçili sekmenin arkasındaki beyaz "hap" yana
/// kayar — iki ayrı düğmenin yanıp sönmesinden daha net bir durum geçişi.
class _SegmentedTabs extends StatelessWidget {
  final String left;
  final String right;
  final bool selectedRight;
  final bool rightEnabled;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _SegmentedTabs({
    required this.left,
    required this.right,
    required this.selectedRight,
    required this.rightEnabled,
    required this.onLeft,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    // AnimatedDefaultTextStyle üstteki stili DEĞİŞTİRİR, birleştirmez; temanın
    // yazı tipini kaybetmemek için temel stil temadan alınıyor.
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    Widget label(String text, bool selected, bool enabled, VoidCallback tap) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? tap : null,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: base.copyWith(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: !enabled
                    ? Colors.black26
                    : selected
                    ? MusicUI.onTint
                    : Colors.black54,
              ),
              child: Text(text),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: selectedRight
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              label(left, !selectedRight, true, onLeft),
              label(right, selectedRight, rightEnabled, onRight),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ŞARKI SATIRI
// ---------------------------------------------------------------------------

class _TrackRow extends StatelessWidget {
  final MusicTrack track;
  final bool current;
  final bool playing;
  final VoidCallback onTap;
  final Widget? trailing;

  const _TrackRow({
    required this.track,
    required this.current,
    required this.playing,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = track.subtitle.isEmpty
        ? (track.isDevice ? 'Cihazından' : 'Cizre Radyo')
        : track.subtitle;

    return Material(
      color: current ? MusicUI.tint : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              _TrackThumb(
                current: current,
                playing: playing,
                device: track.isDevice,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: current ? MusicUI.accentDeep : null,
                            ),
                          ),
                        ),
                        if (track.byLocalArtist) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: MusicUI.tint,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'yerel',
                              style: TextStyle(
                                fontSize: 10,
                                color: MusicUI.onTintMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Satırın solundaki kare. Çalan şarkıda ekolayzır oynar, duraklatılmışta
/// durur; diğerlerinde kaynağını söyleyen sade bir simge.
class _TrackThumb extends StatelessWidget {
  final bool current;
  final bool playing;
  final bool device;

  const _TrackThumb({
    required this.current,
    required this.playing,
    required this.device,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: current
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [MusicUI.accent, MusicUI.accentDeep],
              )
            : null,
        color: current ? null : Colors.black.withValues(alpha: 0.05),
      ),
      child: Center(
        child: playing
            ? const MusicEqualizer(color: Colors.white, height: 16)
            : Icon(
                // Yüklü ama duraklatılmış şarkıda ▶: satıra dokunmak devam
                // ettirir, ikon da bunu söylemeli.
                current
                    ? Icons.play_arrow_rounded
                    : device
                    ? Icons.music_note_rounded
                    : Icons.radio_rounded,
                size: 22,
                color: current ? Colors.white : Colors.black38,
              ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? MusicUI.accentDeep : MusicUI.tint,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: filled ? Colors.white : MusicUI.onTint,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : MusicUI.onTint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? MusicUI.accentDeep : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Colors.transparent : Colors.black12,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: selected ? Colors.white : Colors.black87,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
