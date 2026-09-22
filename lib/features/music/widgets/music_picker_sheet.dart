import 'dart:async';

import 'package:flutter/material.dart';

import '../models/attached_music.dart';
import '../models/music_track.dart';
import '../services/clip_player.dart';
import '../services/music_attach_service.dart';
import '../services/music_catalog_service.dart';
import '../services/music_library_service.dart';
import '../services/music_settings_service.dart';
import 'music_trim_bar.dart';
import 'music_ui.dart';

/// Gönderi ve hikaye için müzik seçme sayfası.
///
/// [show] bir [AttachedMusic] döndürür (kullanıcı vazgeçerse null). Dönen
/// nesne İLİŞTİRİLMEYE HAZIRDIR: gerekiyorsa klip kesilmiş ve yüklenmiştir.
///
/// ## Neden iki adım tek sayfada
///
/// Şarkı seçmek ve aralık seçmek ayrı sayfalar olsaydı kullanıcı "yanlış
/// şarkıyı seçtim" dediğinde geri gidip baştan başlamak zorunda kalırdı. Liste
/// üstte kalıp kırpma çubuğu altta açılınca ikisi arasında gidip gelmek tek
/// dokunuş.
class MusicPickerSheet extends StatefulWidget {
  const MusicPickerSheet({super.key});

  /// Sayfayı açar. Müzik özelliği ya da iliştirme kapalıysa hiç açılmaz ve
  /// null döner — çağıran tarafın ayrıca kontrol etmesine gerek yok.
  static Future<AttachedMusic?> show(BuildContext context) async {
    final settings = await MusicSettingsService.fetch();
    if (!settings.feature || !settings.attach) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Müzik ekleme şu anda kapalı.')),
        );
      }
      return null;
    }
    if (!context.mounted) return null;

    return showModalBottomSheet<AttachedMusic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const MusicPickerSheet(),
    );
  }

  @override
  State<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

enum _Tab { library, catalog }

class _MusicPickerSheetState extends State<MusicPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  _Tab _tab = _Tab.library;
  List<MusicTrack> _library = const [];
  List<MusicTrack> _catalog = const [];
  List<String> _genres = const [];
  String? _genre;
  bool _loadingCatalog = false;
  bool _loadingLibrary = true;

  MusicTrack? _selected;
  int _startMs = 0;
  bool _busy = false;
  String? _error;

  MusicSettings get _settings => MusicSettingsService.cached;

  @override
  void initState() {
    super.initState();
    // Kitaplık boşsa kullanıcıyı boş bir sekmeye düşürmenin anlamı yok;
    // hangi sekmenin açılacağına veri karar versin.
    _loadLibrary();
    _loadGenres();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    // Sayfa kapanırken önizleme susmalı — arkada çalmaya devam eden bir
    // parça, kullanıcının kapattığını sandığı bir sesi sürdürür.
    unawaited(ClipPlayer.instance.stop());
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    final tracks = await MusicLibraryService.instance.load();
    if (!mounted) return;
    setState(() {
      _library = tracks;
      _loadingLibrary = false;
      if (tracks.isEmpty && _settings.catalog) _tab = _Tab.catalog;
    });
    if (_tab == _Tab.catalog) _search();
  }

  Future<void> _loadGenres() async {
    if (!_settings.catalog) return;
    final genres = await MusicCatalogService.instance.genres();
    if (!mounted) return;
    setState(() => _genres = genres);
  }

  void _onQueryChanged(String _) {
    // 300 ms: her tuşta sunucuya gitmek hem bataryayı hem de veritabanını
    // gereksiz yorar; kullanıcı yazmayı bıraktığında arıyoruz.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    if (!_settings.catalog) return;
    setState(() => _loadingCatalog = true);
    final results = await MusicCatalogService.instance.search(
      query: _searchController.text,
      genre: _genre,
    );
    if (!mounted) return;
    setState(() {
      _catalog = results;
      _loadingCatalog = false;
    });
  }

  void _select(MusicTrack track) {
    setState(() {
      _selected = track;
      _startMs = 0;
      _error = null;
    });
    unawaited(ClipPlayer.instance.stop());
  }

  Future<void> _preview() async {
    final track = _selected;
    if (track == null) return;
    await ClipPlayer.instance.preview(
      track,
      startMs: _startMs,
      durationMs: AttachedMusic.clipDurationMs,
    );
  }

  Future<void> _confirm() async {
    final track = _selected;
    if (track == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    await ClipPlayer.instance.stop();

    try {
      final attached = await MusicAttachService.instance.prepare(
        track,
        startMs: _startMs,
      );
      if (!mounted) return;
      Navigator.of(context).pop(attached);
    } on MusicCatalogException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Müzik eklenemedi. Daha sonra dene.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            _handle(),
            _header(theme),
            const Divider(height: 1),
            Expanded(child: _body(theme)),
            if (_selected != null) _trimPanel(theme),
          ],
        ),
      ),
    );
  }

  Widget _handle() => Container(
    width: 38,
    height: 4,
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.grey.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _header(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
    child: Row(
      children: [
        const Icon(Icons.music_note_rounded, color: MusicUI.accentDeep),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Müzik ekle',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Kapat',
        ),
      ],
    ),
  );

  Widget _body(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _tabs(theme),
        ),
        if (_tab == _Tab.catalog) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Şarkı ara',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: MusicUI.radius),
              ),
            ),
          ),
          if (_genres.isNotEmpty) _genreChips(),
        ],
        Expanded(child: _list(theme)),
      ],
    );
  }

  Widget _tabs(ThemeData theme) {
    Widget tab(_Tab value, String label, bool enabled) {
      final active = _tab == value;
      return Expanded(
        child: GestureDetector(
          onTap: enabled
              ? () {
                  setState(() => _tab = value);
                  if (value == _Tab.catalog && _catalog.isEmpty) _search();
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? MusicUI.tint : Colors.transparent,
              borderRadius: MusicUI.radius,
              border: Border.all(
                color: active ? Colors.transparent : theme.dividerColor,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: active
                    ? MusicUI.onTint
                    : enabled
                    ? null
                    : theme.disabledColor,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(
          _Tab.library,
          _library.isEmpty ? 'Kitaplığım' : 'Kitaplığım · ${_library.length}',
          true,
        ),
        const SizedBox(width: 8),
        tab(_Tab.catalog, 'Cizre Radyo', _settings.catalog),
      ],
    );
  }

  Widget _genreChips() => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _GenreChip(
          label: 'Tümü',
          selected: _genre == null,
          onTap: () {
            setState(() => _genre = null);
            _search();
          },
        ),
        for (final g in _genres)
          _GenreChip(
            label: g,
            selected: _genre == g,
            onTap: () {
              setState(() => _genre = g);
              _search();
            },
          ),
      ],
    ),
  );

  Widget _list(ThemeData theme) {
    if (_tab == _Tab.library) {
      if (_loadingLibrary) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!MusicLibraryService.isSupported) {
        return const MusicEmptyState(
          icon: Icons.phonelink_off_rounded,
          title: 'Kitaplık bu cihazda yok',
          message:
              'Cihazdan müzik eklemek yalnızca mobil uygulamada çalışıyor. '
              'Cizre Radyo sekmesini kullanabilirsin.',
        );
      }
      if (_library.isEmpty) {
        return const MusicEmptyState(
          icon: Icons.library_music_outlined,
          title: 'Kitaplığın boş',
          message:
              'Müziğim ekranından telefonundaki şarkıları ekleyince burada '
              'görünürler.',
        );
      }
      return _tracks(_library);
    }

    if (!_settings.catalog) {
      return const MusicEmptyState(
        icon: Icons.radio_outlined,
        title: 'Cizre Radyo kapalı',
        message: 'Katalog şu anda kullanıma kapalı.',
      );
    }
    if (_loadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_catalog.isEmpty) {
      return MusicEmptyState(
        icon: Icons.search_off_rounded,
        title: _searchController.text.trim().isEmpty
            ? 'Katalog boş'
            : 'Sonuç yok',
        message: _searchController.text.trim().isEmpty
            ? 'Cizre Radyo\'ya henüz şarkı eklenmemiş.'
            : 'Başka bir şarkı adı ya da sanatçı dene.',
      );
    }
    return _tracks(_catalog);
  }

  Widget _tracks(List<MusicTrack> tracks) {
    return ValueListenableBuilder<String?>(
      valueListenable: ClipPlayer.instance.nowPlayingKey,
      builder: (context, playingId, _) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
        itemCount: tracks.length,
        itemBuilder: (context, i) {
          final t = tracks[i];
          return MusicTrackTile(
            title: t.title,
            subtitle: _subtitleFor(t),
            selected: _selected?.id == t.id,
            playing: playingId == t.id,
            byLocalArtist: t.byLocalArtist,
            onTap: () => _select(t),
            onPlayTap: () {
              if (_selected?.id != t.id) _select(t);
              unawaited(
                ClipPlayer.instance.preview(
                  t,
                  startMs: _selected?.id == t.id ? _startMs : 0,
                  durationMs: AttachedMusic.clipDurationMs,
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Kesilemeyen dosyalarda uyarıyı SEÇİM ANINDA gösteriyoruz.
  ///
  /// Kullanıcı "Ekle"ye bastıktan sonra 6 MB'lık bir yükleme başladığını
  /// öğrenmemeli; bu bilgi kararı etkiliyorsa karar anında verilmeli.
  String _subtitleFor(MusicTrack t) {
    final base = t.subtitle;
    if (!MusicAttachService.needsFullUpload(t)) return base;
    return base.isEmpty
        ? 'kırpılamıyor — tamamı yüklenir'
        : '$base · kırpılamıyor, tamamı yüklenir';
  }

  Widget _trimPanel(ThemeData theme) {
    final track = _selected!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<String?>(
              valueListenable: ClipPlayer.instance.nowPlayingKey,
              builder: (context, playingId, _) => MusicTrimBar(
                totalMs: track.durationMs,
                startMs: _startMs,
                windowMs: AttachedMusic.clipDurationMs,
                previewing: playingId == track.id,
                onPreviewTap: _preview,
                onChanged: (v) => setState(() => _startMs = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: MusicUI.accentDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Ekle'),
              ),
            ),
          ],
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? MusicUI.tint : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? MusicUI.onTint : null,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
