import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/web_promo_service.dart';

/// Admin Panel > Tanıtım Videosu (Web)
///
/// www.cizreapp.com açılışında gösterilen tanıtım ekranını yönetir: video,
/// kapak görseli, başlık/slogan, mağaza bağlantıları ve gösterim davranışı.
/// Ekranın kendisi `web/index.html` içindeki statik HTML'dir; buradan
/// kaydedilen değerleri Supabase'den okur, uygulama derlemesi gerekmez.
class WebPromoSettingsScreen extends StatefulWidget {
  const WebPromoSettingsScreen({super.key});

  @override
  State<WebPromoSettingsScreen> createState() => _WebPromoSettingsScreenState();
}

class _WebPromoSettingsScreenState extends State<WebPromoSettingsScreen> {
  static const String _previewUrl = 'https://www.cizreapp.com/?promo=1';

  final _service = WebPromoService();

  final _videoController = TextEditingController();
  final _posterController = TextEditingController();
  final _headlineController = TextEditingController();
  final _taglineController = TextEditingController();
  final _continueController = TextEditingController();
  final _playStoreController = TextEditingController();
  final _appStoreController = TextEditingController();

  /// Dönen tanıtım maddeleri — her satır bir madde.
  final _linesController = TextEditingController();
  final _rotateMsController = TextEditingController();

  bool _enabled = true;
  bool _continueEnabled = true;
  bool _showAlways = false;
  int _version = 1;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingVideo = false;
  bool _uploadingPoster = false;

  /// Kaydederken artık kullanılmayan eski dosyaları bucket'tan silmek için.
  String _initialVideoUrl = '';
  String _initialPosterUrl = '';

  @override
  void initState() {
    super.initState();
    _load();
    // Önizleme kartı yazdıkça güncellensin.
    for (final c in [
      _headlineController,
      _taglineController,
      _continueController,
      _appStoreController,
      _playStoreController,
      _linesController,
    ]) {
      c.addListener(_refreshPreview);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _videoController,
      _posterController,
      _headlineController,
      _taglineController,
      _continueController,
      _playStoreController,
      _appStoreController,
      _linesController,
      _rotateMsController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await _service.getSettings();
      if (!mounted) return;
      setState(() {
        _enabled = settings.enabled;
        _continueEnabled = settings.continueEnabled;
        _showAlways = settings.showAlways;
        _version = settings.version;
        _videoController.text = settings.videoUrl;
        _posterController.text = settings.posterUrl;
        _headlineController.text = settings.headline;
        _taglineController.text = settings.tagline;
        _linesController.text = settings.rotatingLines.join('\n');
        _rotateMsController.text = settings.rotateMs.toString();
        _continueController.text = settings.continueText;
        _playStoreController.text = settings.playStoreUrl;
        _appStoreController.text = settings.appStoreUrl;
        _initialVideoUrl = settings.videoUrl;
        _initialPosterUrl = settings.posterUrl;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Tanıtım ayarları yüklenemedi: $error', error: true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final settings = WebPromoSettings(
        enabled: _enabled,
        videoUrl: _videoController.text,
        posterUrl: _posterController.text,
        headline: _headlineController.text,
        tagline: _taglineController.text,
        playStoreUrl: _playStoreController.text,
        appStoreUrl: _appStoreController.text,
        continueText: _continueController.text,
        continueEnabled: _continueEnabled,
        rotatingLines: WebPromoSettings.splitLines(_linesController.text),
        rotateMs:
            int.tryParse(_rotateMsController.text.trim()) ??
            WebPromoSettings.defaults.rotateMs,
        showAlways: _showAlways,
        version: _version,
      );
      await _service.saveSettings(settings);

      // Değiştirilen medyanın eski dosyasını bucket'tan temizle.
      final newVideo = settings.videoUrl.trim();
      final newPoster = settings.posterUrl.trim();
      if (_initialVideoUrl.isNotEmpty && _initialVideoUrl != newVideo) {
        await _service.deleteMediaIfOwned(_initialVideoUrl);
      }
      if (_initialPosterUrl.isNotEmpty && _initialPosterUrl != newPoster) {
        await _service.deleteMediaIfOwned(_initialPosterUrl);
      }
      _initialVideoUrl = newVideo;
      _initialPosterUrl = newPoster;

      if (!mounted) return;
      setState(() => _saving = false);
      _snack(
        'Tanıtım ekranı kaydedildi. Site yenilendiğinde geçerli olur.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Kaydedilemedi: $error', error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Medya yükleme
  // ---------------------------------------------------------------------------

  static const _videoTypes = {
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
  };
  static const _imageTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  Future<void> _pickAndUpload({required bool isVideo}) async {
    final allowed = isVideo ? _videoTypes : _imageTypes;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowed.keys.toList(),
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _snack('Dosya okunamadı.', error: true);
      return;
    }

    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    final contentType = allowed[ext];
    if (contentType == null) {
      _snack(
        'Desteklenmeyen dosya türü (.$ext). '
        'Kabul edilenler: ${allowed.keys.join(", ")}',
        error: true,
      );
      return;
    }

    final sizeMb = bytes.length / (1024 * 1024);
    if (isVideo && sizeMb > WebPromoService.maxVideoMb) {
      _snack(
        'Video çok büyük (${sizeMb.toStringAsFixed(1)} MB). '
        'En fazla ${WebPromoService.maxVideoMb} MB yüklenebilir.',
        error: true,
      );
      return;
    }

    setState(() {
      if (isVideo) {
        _uploadingVideo = true;
      } else {
        _uploadingPoster = true;
      }
    });

    try {
      final url = await _service.uploadMedia(
        bytes: bytes,
        fileName: file.name,
        contentType: contentType,
      );
      if (!mounted) return;
      setState(() {
        if (isVideo) {
          _videoController.text = url;
          _uploadingVideo = false;
        } else {
          _posterController.text = url;
          _uploadingPoster = false;
        }
      });
      final warn = isVideo && sizeMb > WebPromoService.recommendedVideoMb
          ? ' Dosya ${sizeMb.toStringAsFixed(1)} MB — açılış ekranında '
                'yavaş yüklenebilir, sıkıştırmanız önerilir.'
          : '';
      _snack('Yüklendi. Yayına almak için Kaydet\'e basın.$warn');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploadingVideo = false;
        _uploadingPoster = false;
      });
      _snack('Yükleme başarısız: $error', error: true);
    }
  }

  Future<void> _openPreview() async {
    final uri = Uri.parse(_previewUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _snack('Önizleme açılamadı: $_previewUrl', error: true);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tanıtım Videosu (Web)'),
        actions: [
          IconButton(
            tooltip: 'Sitede önizle',
            onPressed: _openPreview,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          IconButton(
            tooltip: 'Yenile',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                  children: [
                    _introCard(),
                    const SizedBox(height: 16),
                    _previewCard(),
                    const SizedBox(height: 16),
                    _statusCard(),
                    const SizedBox(height: 16),
                    _mediaCard(),
                    const SizedBox(height: 16),
                    _textsCard(),
                    const SizedBox(height: 16),
                    _storesCard(),
                  ],
                ),
              ),
            ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
            ),
    );
  }

  Widget _introCard() {
    return Card(
      color: Colors.purple.shade50,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.smart_display_rounded, color: Colors.purple),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'www.cizreapp.com açıldığında, uygulama yüklenmeden önce '
                'gösterilen tanıtım ekranı. Buradaki değişiklikler yeni bir '
                'sürüm yayınlamadan, ziyaretçi sayfayı yenilediğinde geçerli '
                'olur. Video yüklemezseniz animasyonlu marka sahnesi gösterilir.',
                style: TextStyle(height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ayarların siteye nasıl yansıyacağını gösteren küçük maket.
  Widget _previewCard() {
    final headline = _headlineController.text.trim().isEmpty
        ? WebPromoSettings.defaults.headline
        : _headlineController.text.trim();
    final tagline = _taglineController.text.trim().isEmpty
        ? WebPromoSettings.defaults.tagline
        : _taglineController.text.trim();
    final continueText = _continueController.text.trim().isEmpty
        ? WebPromoSettings.defaults.continueText
        : _continueController.text.trim();

    return _section('Önizleme', [
      Container(
        // Sitedeki yerleşimin aynısı: tanıtım yazıları üstte, indirme ve
        // "devam et" düğmeleri altta.
        height: 360,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B3B2C), Color(0xFF04110D), Color(0xFF0A2E33)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // --- Üst blok: yazılar ---
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text(
                    "CİZRE'NİN DİJİTAL PAZARI & SOSYAL AĞI",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tagline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            // --- Alt blok: düğmeler ---
            Column(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _previewBadge(
                      icon: Icons.play_arrow_rounded,
                      label: 'Google Play',
                      active: _playStoreController.text.trim().isNotEmpty,
                    ),
                    _previewBadge(
                      icon: Icons.apple_rounded,
                      label: 'App Store',
                      active: _appStoreController.text.trim().isNotEmpty,
                    ),
                  ],
                ),
                if (_continueEnabled) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white30),
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    child: Text(
                      '$continueText  →',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        _videoController.text.trim().isEmpty
            ? 'Arka plan: animasyonlu marka sahnesi (video yüklenmedi).'
            : 'Arka plan: yüklenen tanıtım videosu.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
    ]);
  }

  Widget _previewBadge({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return Opacity(
      opacity: active ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'ŞİMDİ İNDİR' : 'YAKINDA',
                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    return _section('1. Yayın durumu', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _enabled,
        onChanged: (v) => setState(() => _enabled = v),
        title: const Text('Tanıtım ekranı açık'),
        subtitle: Text(
          _enabled
              ? 'Ziyaretçiler siteye girdiğinde tanıtım ekranını görür.'
              : 'Kapalı: site doğrudan uygulamayla açılır.',
        ),
      ),
      const Divider(height: 24),
      const Text(
        'Gösterim sıklığı',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('Ziyaretçiye bir kez'),
            icon: Icon(Icons.looks_one_rounded),
          ),
          ButtonSegment(
            value: true,
            label: Text('Her açılışta'),
            icon: Icon(Icons.repeat_rounded),
          ),
        ],
        selected: {_showAlways},
        onSelectionChanged: (s) => setState(() => _showAlways = s.first),
      ),
      const SizedBox(height: 8),
      Text(
        _showAlways
            ? 'Her açılışta gösterilir. Sık gelen kullanıcılar için yorucu '
                  'olabilir; kampanya dönemlerinde tercih edin.'
            : 'Tanıtımı kapatan ziyaretçiye tekrar gösterilmez.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
      const Divider(height: 24),
      Row(
        children: [
          Expanded(
            child: Text(
              'Tanıtım sürümü: $_version\n'
              'Yeni bir video yayınladığınızda sürümü artırın; tanıtımı daha '
              'önce kapatmış ziyaretçiler de yeniden görür.',
              style: const TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() => _version += 1),
            icon: const Icon(Icons.campaign_rounded),
            label: const Text('Herkese tekrar göster'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _openPreview,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Sitede önizle (cizreapp.com/?promo=1)'),
        ),
      ),
    ]);
  }

  Widget _mediaCard() {
    return _section('2. Tanıtım videosu ve kapak görseli', [
      TextField(
        controller: _videoController,
        onChanged: (_) => _refreshPreview(),
        decoration: const InputDecoration(
          labelText: 'Video adresi (mp4 / webm)',
          hintText: 'Boş bırakılırsa animasyonlu marka sahnesi gösterilir',
          prefixIcon: Icon(Icons.movie_rounded),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          FilledButton.icon(
            onPressed: _uploadingVideo ? null : () => _pickAndUpload(isVideo: true),
            icon: _uploadingVideo
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_rounded),
            label: Text(_uploadingVideo ? 'Yükleniyor...' : 'Video yükle'),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: _videoController.text.isEmpty
                ? null
                : () => setState(() => _videoController.clear()),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Kaldır'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _posterController,
        onChanged: (_) => _refreshPreview(),
        decoration: const InputDecoration(
          labelText: 'Kapak görseli adresi (poster)',
          hintText: 'Video inene kadar gösterilir',
          prefixIcon: Icon(Icons.image_rounded),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          FilledButton.tonalIcon(
            onPressed:
                _uploadingPoster ? null : () => _pickAndUpload(isVideo: false),
            icon: _uploadingPoster
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_rounded),
            label: Text(_uploadingPoster ? 'Yükleniyor...' : 'Kapak yükle'),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: _posterController.text.isEmpty
                ? null
                : () => setState(() => _posterController.clear()),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Kaldır'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.blue, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Video sessiz ve döngüde oynar (tarayıcılar sesli otomatik '
                'oynatmaya izin vermez; ziyaretçi sağ alttaki düğmeyle sesi '
                'açabilir). 15-30 saniyelik, 1080p ve ${WebPromoService.recommendedVideoMb} MB '
                'altında bir mp4 en iyi sonucu verir. Yatay (16:9) çekim önerilir.',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _textsCard() {
    return _section('3. Metinler', [
      TextField(
        controller: _headlineController,
        decoration: const InputDecoration(
          labelText: 'Başlık',
          hintText: 'CizreApp',
          prefixIcon: Icon(Icons.title_rounded),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _taglineController,
        decoration: const InputDecoration(
          labelText: 'Slogan',
          hintText: 'Her an, her kapıda!',
          prefixIcon: Icon(Icons.format_quote_rounded),
          border: OutlineInputBorder(),
        ),
      ),
      const Divider(height: 32),
      const Text(
        'Dönen tanıtım maddeleri',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      const SizedBox(height: 4),
      const Text(
        'Sloganın altında sırayla dönerler. HER SATIR BİR MADDEDİR; madde '
        'eklemek için alt satıra yazmanız yeterli. Tamamen boş bırakırsanız '
        'şerit hiç gösterilmez.',
        style: TextStyle(fontSize: 12, height: 1.45),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _linesController,
        minLines: 4,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: 'Maddeler (her satır bir madde)',
          hintText: 'İlan ver, alıcını bul\nAlışveriş yap, kapına gelsin',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _rotateMsController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Geçiş süresi (ms)',
                hintText: '2600',
                helperText: '1200 - 10000 arası',
                prefixIcon: Icon(Icons.timer_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '${WebPromoSettings.splitLines(_linesController.text).length} '
                'madde tanımlı.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      const Divider(height: 32),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _continueEnabled,
        onChanged: (v) => setState(() => _continueEnabled = v),
        title: const Text('"Webte devam et" düğmesi görünsün'),
        subtitle: Text(
          _continueEnabled
              ? 'Ziyaretçi tanıtımı kapatıp web uygulamasına geçebilir.'
              : 'Gizli: tanıtım ekranı kalıcı iniş sayfası olur, ziyaretçi '
                    'yalnızca mağazalara yönlendirilir. (Paylaşılan derin '
                    'bağlantılar ve cizreapp.com/?promo=0 yine uygulamayı '
                    'açar.)',
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _continueController,
        enabled: _continueEnabled,
        decoration: const InputDecoration(
          labelText: 'Devam bağlantısının metni',
          hintText: 'Webte devam et',
          prefixIcon: Icon(Icons.arrow_forward_rounded),
          border: OutlineInputBorder(),
        ),
      ),
    ]);
  }

  Widget _storesCard() {
    return _section('4. Mağaza bağlantıları', [
      TextField(
        controller: _playStoreController,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Google Play adresi',
          prefixIcon: Icon(Icons.shop_rounded),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _appStoreController,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'App Store adresi',
          hintText: 'Uygulama henüz yayında değilse boş bırakın',
          prefixIcon: Icon(Icons.apple_rounded),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Adres girilmeyen mağazanın düğmesi ekranda kalır ama "Yakında" '
        'yazısıyla pasifleşir; tıklanamaz.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
    ]);
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}
