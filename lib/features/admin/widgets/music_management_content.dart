import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../music/music.dart';
import 'admin_ui.dart';
import 'music_stats_content.dart';

/// Admin > Müzik Çalar.
///
/// Dört sekme: mevcut istatistik ekranı, katalog, sanatçı başvuruları ve
/// özelliği parça parça açıp kapatan anahtarlar.
///
/// ## Anahtarlar neden bu kadar ince taneli
///
/// Tek bir "müzik açık/kapalı" düğmesi yeterli görünür ama gerçek bir olayda
/// yeterli olmaz. Telif şikâyeti geldiğinde durdurulması gereken şey
/// PAYLAŞIMDIR — kullanıcıların dinlemesi değil. Kötüye kullanılan şey
/// yüklemeyse kapatılması gereken tek şey başvurulardır. Her anahtarın ayrı
/// olması, bir sorunu çözmek için tüm özelliği kapatmak zorunda kalmamak
/// demek.
class MusicManagementContent extends StatefulWidget {
  const MusicManagementContent({super.key});

  @override
  State<MusicManagementContent> createState() => _MusicManagementContentState();
}

class _MusicManagementContentState extends State<MusicManagementContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AdminUi.page,
      child: Column(
        children: [
          Material(
            color: AdminUi.surface,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AdminUi.brand,
              unselectedLabelColor: AdminUi.muted,
              indicatorColor: AdminUi.brand,
              tabs: const [
                Tab(text: 'İstatistik'),
                Tab(text: 'Katalog'),
                Tab(text: 'Başvurular'),
                Tab(text: 'Ayarlar'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                MusicStatsContent(),
                _CatalogTab(),
                _SubmissionsTab(),
                _SettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- katalog

class _CatalogTab extends StatefulWidget {
  const _CatalogTab();

  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client.rpc(
        'admin_music_list_catalog',
        params: {
          'p_query': _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
          'p_limit': 300,
        },
      );
      if (!mounted) return;
      setState(() {
        _rows = ((rows as List?) ?? const [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = MusicCatalogService.describeRpcError(e);
        _loading = false;
      });
    }
  }

  Future<void> _setActive(Map<String, dynamic> row, bool active) async {
    try {
      await Supabase.instance.client.rpc(
        'admin_music_update_track',
        params: {'p_id': row['id'], 'p_is_active': active},
      );
      await _load();
    } catch (e) {
      _snack(MusicCatalogService.describeRpcError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şarkıyı sil'),
        content: Text(
          '"${row['title']}" katalogdan kalıcı olarak silinecek. '
          'Bu şarkıyı gönderisine eklemiş kullanıcıların kliplerine '
          'dokunulmaz; yalnızca katalogdan kaldırılır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final path =
          await Supabase.instance.client.rpc(
                'admin_okey_clear_sound',
                params: {'p_sound_key': 'music:${row['id']}'},
              )
              as String?;
      if (path != null && path.isNotEmpty) {
        // Dosya, parçanın nereden geldiğine göre FARKLI kepçede duruyor:
        // admin yüklemeleri Okey ses kepçesinde, sanatçı başvuruları kendi
        // kepçesinde. Yanlış kepçeden silmek sessizce hiçbir şey yapardı.
        final bucket = row['source'] == 'artist'
            ? 'artist-music'
            : 'okey-sounds';
        // Depo dosyası ayrı bir adım: RPC yalnızca kaydı siliyor. Başarısız
        // olursa katalogdan düşmüş olur, yetim dosya kimseyi etkilemez.
        try {
          await Supabase.instance.client.storage.from(bucket).remove([path]);
        } catch (_) {
          // yetim dosya
        }
      }
      await _load();
    } catch (e) {
      _snack(MusicCatalogService.describeRpcError(e), error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Katalog yüklenemedi',
        subtitle: _error,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar dene'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: 'Şarkı ya da sanatçı ara',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: AdminUi.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Yenile',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rows.isEmpty
              ? const AdminEmpty(
                  icon: Icons.library_music_outlined,
                  title: 'Katalog boş',
                  subtitle:
                      'Okey ses ayarlarından şarkı ekleyebilir ya da '
                      'sanatçı başvurularını onaylayabilirsin.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    final active = r['is_active'] == true;
                    final artist = (r['artist'] as String?)?.trim();
                    final duration = (r['duration_ms'] as num?)?.toInt();

                    return AdminCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        r['title'] as String? ?? 'Şarkı',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AdminUi.ink,
                                        ),
                                      ),
                                    ),
                                    if (r['source'] == 'artist') ...[
                                      const SizedBox(width: 6),
                                      const AdminBadge(
                                        label: 'yerel sanatçı',
                                        color: Colors.teal,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (artist != null && artist.isNotEmpty)
                                      artist,
                                    if (r['genre'] != null)
                                      r['genre'] as String,
                                    if (duration != null && duration > 0)
                                      formatDuration(duration),
                                  ].join(' · '),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AdminUi.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: active,
                            activeThumbColor: AdminUi.brand,
                            onChanged: (v) => _setActive(r, v),
                          ),
                          IconButton(
                            tooltip: 'Sil',
                            onPressed: () => _delete(r),
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ başvurular

class _SubmissionsTab extends StatefulWidget {
  const _SubmissionsTab();

  @override
  State<_SubmissionsTab> createState() => _SubmissionsTabState();
}

class _SubmissionsTabState extends State<_SubmissionsTab> {
  String _status = 'pending';
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Admin başka sekmeye geçince önizleme susmalı.
    ClipPlayer.instance.stop();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client.rpc(
        'admin_music_list_submissions',
        params: {'p_status': _status, 'p_limit': 100},
      );
      if (!mounted) return;
      setState(() {
        _rows = ((rows as List?) ?? const [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = MusicCatalogService.describeRpcError(e);
        _loading = false;
      });
    }
  }

  Future<void> _review(
    Map<String, dynamic> row, {
    required bool approve,
  }) async {
    String? reason;

    if (!approve) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Başvuruyu reddet'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Sebep',
              hintText: 'Kullanıcı bu metni görecek',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Reddet'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    }

    setState(() => _busyId = row['id'] as String?);
    try {
      await Supabase.instance.client.rpc(
        'admin_music_review_submission',
        params: {'p_id': row['id'], 'p_approve': approve, 'p_reason': reason},
      );
      await ClipPlayer.instance.stop();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Şarkı katalogda yayında' : 'Başvuru reddedildi',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MusicCatalogService.describeRpcError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Onaylamadan önce DİNLEMEK şart.
  ///
  /// Onay adımının tek anlamı bir insanın dosyayı gerçekten duymuş olması;
  /// bu yüzden çalma düğmesi listenin merkezinde, menüye gömülü değil.
  void _preview(Map<String, dynamic> row) {
    final url = row['public_url'] as String?;
    if (url == null || url.isEmpty) return;
    ClipPlayer.instance.toggle(
      AttachedMusic(
        url: url,
        title: row['title'] as String? ?? 'Şarkı',
        startMs: 0,
        // Admin önizlemesi 15 saniyeyle sınırlı değil: kararı verebilmek için
        // parçanın devamını duymak gerekebilir.
        durationMs: (row['duration_ms'] as num?)?.toInt() ?? 120000,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: AdminChipBar<String>(
            selected: _status,
            onSelected: (v) {
              setState(() => _status = v);
              _load();
            },
            items: const [
              (
                value: 'pending',
                label: 'Bekleyen',
                icon: Icons.hourglass_empty,
                count: null,
              ),
              (
                value: 'approved',
                label: 'Onaylanan',
                icon: Icons.check_circle_outline,
                count: null,
              ),
              (
                value: 'rejected',
                label: 'Reddedilen',
                icon: Icons.block,
                count: null,
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return AdminEmpty(
        icon: Icons.error_outline,
        title: 'Başvurular yüklenemedi',
        subtitle: _error,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar dene'),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const AdminEmpty(
        icon: Icons.inbox_outlined,
        title: 'Bu durumda başvuru yok',
      );
    }

    return ValueListenableBuilder<String?>(
      valueListenable: ClipPlayer.instance.nowPlayingKey,
      builder: (context, playingUrl, _) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: _rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final r = _rows[i];
          final busy = _busyId == r['id'];
          final playing = playingUrl == r['public_url'];
          final sizeMb =
              ((r['size_bytes'] as num?)?.toDouble() ?? 0) / (1024 * 1024);
          final duration = (r['duration_ms'] as num?)?.toInt();

          return AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: playing ? 'Durdur' : 'Dinle',
                      onPressed: () => _preview(r),
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        size: 34,
                        color: AdminUi.brand,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${r['title']} — ${r['artist']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AdminUi.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (r['username'] != null) '@${r['username']}',
                              if (duration != null && duration > 0)
                                formatDuration(duration),
                              '${sizeMb.toStringAsFixed(1)} MB',
                              if (r['genre'] != null) r['genre'] as String,
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AdminUi.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if ((r['reject_reason'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Sebep: ${r['reject_reason']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminUi.muted,
                      ),
                    ),
                  ),
                if (_status == 'pending') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => _review(r, approve: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Onayla'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => _review(r, approve: false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Reddet'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// --------------------------------------------------------------- ayarlar

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  MusicSettings _settings = MusicSettingsService.cached;
  bool _loading = true;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await MusicSettingsService.fetch(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loading = false;
    });
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _busyKey = key);
    try {
      await MusicSettingsService.setFlag(key, value);
      if (!mounted) return;
      setState(() => _settings = MusicSettingsService.cached);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MusicCatalogService.describeRpcError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _editMaxMb() async {
    final controller = TextEditingController(
      text: _settings.maxUploadMb.toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yükleme boyut sınırı'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'MB',
            helperText: 'Sanatçı başvurusunda dosya başına üst sınır',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;

    await MusicSettingsService.setMaxUploadMb(value);
    if (!mounted) return;
    setState(() => _settings = MusicSettingsService.cached);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        _tile(
          key: 'music_feature_enabled',
          title: 'Müzik özelliği',
          subtitle:
              'Kapalıyken yan menüdeki Müziğim girişi ve tüm müzik düğmeleri '
              'gizlenir, katalog araması boş döner.',
          value: _settings.feature,
        ),
        _tile(
          key: 'music_catalog_enabled',
          title: 'Cizre Radyo kataloğu',
          subtitle:
              'Katalog sekmesi ve içindeki arama. Kapalıyken Okey masasının '
              'fon müziği çalmaya devam eder.',
          value: _settings.catalog,
        ),
        _tile(
          key: 'music_device_add_enabled',
          title: 'Cihazdan müzik ekleme',
          subtitle:
              'Kullanıcının kendi telefonundaki dosyaları kitaplığına '
              'alması. Bu dosyalar sunucuya hiç gelmez — bu anahtar yalnızca '
              'arayüzü kapatır.',
          value: _settings.deviceAdd,
        ),
        _tile(
          key: 'music_attach_enabled',
          title: 'Gönderi ve hikayeye müzik',
          subtitle:
              'Telif şikâyetinde tek anahtarla paylaşımı durdurur; dinleme '
              'açık kalır. Var olan gönderilerin verisi silinmez, anahtar '
              'geri açılınca müzikleri geri gelir.',
          value: _settings.attach,
        ),
        _tile(
          key: 'music_artist_uploads_enabled',
          title: 'Sanatçı yükleme başvuruları',
          subtitle:
              'Kapalıyken yeni başvuru alınmaz; onaylanmış şarkılar '
              'katalogda kalmaya ve çalmaya devam eder.',
          value: _settings.artistUpload,
        ),
        const SizedBox(height: 8),
        AdminCard(
          onTap: _editMaxMb,
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Yükleme boyut sınırı',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AdminUi.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sanatçı başvurusunda dosya başına üst sınır',
                      style: TextStyle(fontSize: 12, color: AdminUi.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AdminUi.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_settings.maxUploadMb} MB',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AdminUi.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required String key,
    required String title,
    required String subtitle,
    required bool value,
  }) {
    final busy = _busyKey == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AdminCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AdminUi.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminUi.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: value,
                    activeThumbColor: AdminUi.brand,
                    onChanged: (v) => _toggle(key, v),
                  ),
          ],
        ),
      ),
    );
  }
}
