import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../models/post_image_format.dart';
import '../services/post_image_preparer.dart';
import '../services/post_service.dart';
import '../widgets/post_image_composer.dart';
import '../../profile/services/profile_service.dart';
import '../../profile/widgets/immersive_crop_screen.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/image_crop_utils.dart';
import '../../../core/widgets/text_background.dart';
import '../../music/music.dart';

/// Gonderi olusturma ekrani.
///
/// TASARIM: Ekran bastan yazildi ve hikaye olusturucuyla AYNI dile oturtuldu -
/// koyu tam ekran tuval, ustte gradyanli ince bir baslik cubugu, altta arac
/// seridi. Eskiden burasi duz bir form (AppBar + TextField + "Fotograf Ekle"
/// kutusu) idi; hikaye akisiyla hic benzemiyordu ve kullanicinin gonderisinin
/// yayinlaninca neye benzeyecegini gorme sansi yoktu.
///
/// ONIZLEME SOZLESMESI: Buradaki tuval, gonderinin feed'de/izgarada
/// gorunecegi bicimin aynisidir - ayni [TextBackgroundCanvas] palet ve punto
/// hesabi kullanilir (lib/core/widgets/text_background.dart). Yani "ne
/// goruyorsan onu paylasirsin".
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxLength = 500;

  static const Color _canvasBg = Color(0xFF0E1116);
  static const Color _panelBg = Color(0xFF161B22);

  final _postService = PostService();
  final _profileService = ProfileService();
  final _contentController = TextEditingController();
  final _contentFocus = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  // Seçili fotoğraflar — orijinal baytlarıyla birlikte (Web ve Mobile
  // uyumlu). Kırpma her zaman ORİJİNALDEN yapılır; önizleme ve yükleme
  // fotoğrafın kendisine bağlı olduğundan aradan biri silinince diğerlerinin
  // önizlemesi kaymaz.
  final List<PostDraftImage> _images = [];
  final List<String> _uploadedImageUrls = [];

  /// Fotoğrafların çerçevesi (Görev 2.8): akışta bu oranda görünürler. İlk
  /// fotoğraf eklenince — kullanıcı henüz kendisi seçmediyse — fotoğrafın
  /// kendi oranına göre önerilir.
  PostImageFormat _format = PostImageFormat.portrait;
  bool _formatChosen = false;

  static const PostImagePreparer _imagePreparer = PostImagePreparer();

  /// Secili arka plan kimligi; null = sade metin gonderisi.
  String? _backgroundId;

  bool _isPosting = false;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    // Punto ve "Paylas" butonunun etkinligi yaziya bagli: her tusa basista
    // tuvali tazele.
    _contentController.addListener(_onTextChanged);
    _loadMusicFlag();
  }

  @override
  void dispose() {
    _contentController.removeListener(_onTextChanged);
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadUserProfile() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await _profileService.getUserProfile(userId);
      if (!mounted) return;
      setState(() => _userProfile = profile);
    } catch (e) {
      debugPrint('Profil yüklenirken hata: $e');
    }
  }

  // ---------------------------------------------------------------- durum

  String get _text => _contentController.text.trim();

  bool get _hasImages => _images.isNotEmpty;

  /// Gorsel varken arka plan uygulanmaz: gorselin uzerine gradyan basmak hem
  /// gorseli bozar hem de feed'de karsiligi yoktur (model ve servis de ayni
  /// kurali uygular).
  TextBackground? get _background =>
      _hasImages ? null : textBackgroundById(_backgroundId);

  bool get _canShare => !_isPosting && (_text.isNotEmpty || _hasImages);

  // -------------------------------------------------------------- gorsel

  Future<void> _pickImages() async {
    List<XFile> images;

    if (kIsWeb) {
      // Web'de pickMultiImage desteklenmiyor, tek tek seç
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      images = file != null ? [file] : [];
    } else {
      // Mobile'da çoklu seçim
      images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    }

    if (images.isEmpty) return;
    await _addPicked(images);
  }

  Future<void> _takePhoto() async {
    if (kIsWeb) return;
    final photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;
    await _addPicked([photo]);
  }

  /// Seçilen dosyaları baytlarıyla birlikte ekler (önizleme, kırpma ve
  /// yükleme aynı baytları kullanır).
  Future<void> _addPicked(List<XFile> files) async {
    final drafts = <PostDraftImage>[];
    for (final file in files) {
      try {
        drafts.add(PostDraftImage(file: file, bytes: await file.readAsBytes()));
      } catch (e) {
        debugPrint('❌ Fotoğraf okunamadı: $e');
      }
    }
    if (!mounted || drafts.isEmpty) return;

    final wasEmpty = _images.isEmpty;
    setState(() => _images.addAll(drafts));

    // İlk fotoğrafta çerçeve fotoğrafın kendi oranına göre önerilir: dikey
    // fotoğraf Dikey'e, yatay fotoğraf Yatay'a oturur, kimse bir şeye
    // dokunmadan paylaşsa bile fotoğraf en az kırpılır.
    if (wasEmpty && !_formatChosen) {
      final first = drafts.first;
      final ratio = await readImageAspectRatio(first.bytes);
      if (!mounted || ratio == null || _formatChosen) return;
      if (_images.isEmpty || !identical(_images.first, first)) return;
      setState(() => _format = PostImageFormat.suggestForAspect(ratio));
    }
  }

  void _removeImage(int index) {
    if (index < 0 || index >= _images.length) return;
    setState(() => _images.removeAt(index));
  }

  void _setFormat(PostImageFormat format) {
    setState(() {
      _format = format;
      _formatChosen = true;
    });
  }

  /// Önizlemedeki fotoğrafı kırpma editöründe açar. Editörde çerçeve de
  /// değiştirilebilir; seçilen çerçeve gönderinin tüm fotoğraflarına uygulanır.
  Future<void> _cropImage(int index) async {
    if (_isPosting || index < 0 || index >= _images.length) return;
    final draft = _images[index];

    final result = await showImmersiveAspectCropEditor(
      context,
      imageBytes: draft.bytes,
      title: 'Fotoğrafı Kırp',
      aspects: [
        for (final format in PostImageFormat.values)
          ImmersiveCropAspect(
            label: format.label,
            ratioLabel: format.ratioLabel,
            ratio: format.aspectRatio,
          ),
      ],
      initialAspect: _format.aspectRatio,
      footnote: _images.length > 1
          ? 'Seçtiğin çerçeve gönderideki tüm fotoğraflara uygulanır'
          : '',
    );
    if (!mounted || result == null || !_images.contains(draft)) return;

    final format = PostImageFormat.fromAspectRatio(result.aspectRatio) ?? _format;
    setState(() {
      _format = format;
      _formatChosen = true;
      draft.setCrop(result.bytes, format.aspectRatio);
    });
  }

  /// Seçili görselleri yükler ve BAŞARISIZ OLANLARIN sayısını döndürür.
  ///
  /// Eskiden hata sadece debugPrint'e yazılıyordu: tüm yüklemeler başarısız
  /// olsa bile gönderi görselsiz oluşturulup "Gönderi paylaşıldı!" deniyordu.
  /// Kullanıcı fotoğrafının kaybolduğunu ancak feed'e bakınca anlıyordu.
  ///
  /// Her fotoğraf yüklenmeden önce seçili çerçeveye oturtulur (elle
  /// kırpıldıysa o, değilse ortası) ve JPEG'e sıkıştırılır — bkz.
  /// [PostImagePreparer].
  Future<int> _uploadImages() async {
    _uploadedImageUrls.clear();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return _images.length;

    final aspectRatio = _format.aspectRatio;
    int failed = 0;

    for (int i = 0; i < _images.length; i++) {
      try {
        debugPrint('📤 Post resmi işleniyor...');
        final prepared = await _imagePreparer.prepare(_images[i], aspectRatio);
        debugPrint(
          '📤 Post resmi boyutu: '
          '${(prepared.bytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
        );

        final fileName =
            'post_${userId}_${DateTime.now().millisecondsSinceEpoch}_$i.${prepared.extension}';
        final filePath = 'posts/$fileName';

        await Supabase.instance.client.storage
            .from('posts')
            .uploadBinary(
              filePath,
              prepared.bytes,
              fileOptions: FileOptions(contentType: prepared.contentType),
            );

        final imageUrl = Supabase.instance.client.storage
            .from('posts')
            .getPublicUrl(filePath);

        _uploadedImageUrls.add(imageUrl);
        debugPrint('✅ Post resmi yüklendi: $imageUrl');
      } catch (e) {
        failed++;
        debugPrint('❌ Resim yükleme hatası: $e');
      }
    }

    return failed;
  }

  // ------------------------------------------------------------- paylasim

  /// Gönderiye iliştirilmiş müzik. Seçilirken klip zaten kesilip
  /// yüklendiği için burada tutulan nesne paylaşıma hazırdır.
  AttachedMusic? _music;

  /// "Müzik" aracı görünsün mü? Admin anahtarına bağlı; ayar okunana kadar
  /// önbellekteki değer kullanılır.
  bool _musicEnabled = MusicSettingsService.cached.feature &&
      MusicSettingsService.cached.attach;

  Future<void> _loadMusicFlag() async {
    final settings = await MusicSettingsService.fetch();
    if (!mounted) return;
    final enabled = settings.feature && settings.attach;
    if (enabled != _musicEnabled) setState(() => _musicEnabled = enabled);
  }

  Future<void> _pickMusic() async {
    final picked = await MusicPickerSheet.show(context);
    if (!mounted || picked == null) return;
    setState(() => _music = picked);
  }

  Future<void> _createPost() async {
    final content = _text;
    if (content.isEmpty && !_hasImages) {
      _snack('Lütfen bir şeyler yaz ya da fotoğraf ekle');
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _snack('Oturum açmanız gerekiyor');
      return;
    }

    setState(() => _isPosting = true);
    FocusScope.of(context).unfocus();

    try {
      int failedUploads = 0;
      if (_hasImages) {
        failedUploads = await _uploadImages();

        // Hiçbiri yüklenemediyse ve yazı da yoksa boş gönderi oluşturmayalım.
        if (_uploadedImageUrls.isEmpty && content.isEmpty) {
          if (!mounted) return;
          setState(() => _isPosting = false);
          _snack(
            'Fotoğraflar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
            error: true,
          );
          return;
        }
      }

      await _postService.createPost(
        userId: userId,
        content: content,
        images: _uploadedImageUrls,
        imageAspectRatio: _hasImages ? _format.aspectRatio : null,
        background: _background?.id,
        music: _music,
      );

      if (!mounted) return;

      // Snackbar POP'tan ÖNCE alınmalı: pop sonrası bu ekranın context'i
      // artık ağaçta olmadığı için ScaffoldMessenger.of(context) patlıyordu.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failedUploads > 0
                ? 'Gönderi paylaşıldı ama $failedUploads fotoğraf yüklenemedi'
                : 'Gönderi paylaşıldı!',
          ),
          backgroundColor: failedUploads > 0 ? Colors.orange : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      _snack(AppErrorHandler.handleError(e), error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Yazi veya gorsel varken geri tuslanirsa onay iste - yanlislikla kaybolan
  /// taslak eski ekranin en cok sikayet edilen davranisiydi.
  Future<bool> _confirmDiscard() async {
    if (_isPosting) return false;
    if (_text.isEmpty && !_hasImages) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gönderiyi silelim mi?'),
        content: const Text(
          'Yazdıkların paylaşılmadan kaybolacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          if (!context.mounted) return;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: _canvasBg,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            _topBar(),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _contentFocus.requestFocus(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _authorRow(),
                      if (_music != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AttachedMusicChip(
                            music: _music!,
                            onDarkSurface: true,
                            onRemove: _isPosting
                                ? null
                                : () => setState(() => _music = null),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _composerCard(),
                    ],
                  ),
                ),
              ),
            ),
            _bottomTools(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2530), _canvasBg],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
          child: Row(
            children: [
              IconButton(
                onPressed: _isPosting
                    ? null
                    : () async {
                        if (await _confirmDiscard() && mounted) {
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        }
                      },
                icon: const Icon(Icons.close, color: Colors.white, size: 26),
                tooltip: 'Kapat',
              ),
              const Expanded(
                child: Text(
                  'Yeni Gönderi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              _shareButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareButton() {
    if (_isPosting) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    final enabled = _canShare;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled ? _createPost : null,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            child: Text(
              'Paylaş',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _authorRow() {
    final avatarUrl = _userProfile?['avatar_url'] as String?;
    final username = (_userProfile?['username'] as String?) ?? 'kullanici';
    final fullName =
        (_userProfile?['full_name'] as String?) ?? username;

    return Row(
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: Theme.of(context).colorScheme.primary,
          backgroundImage:
              (avatarUrl != null && avatarUrl.isNotEmpty)
              ? NetworkImage(avatarUrl)
              : null,
          child: (avatarUrl == null || avatarUrl.isEmpty)
              ? Text(
                  username.length >= 2
                      ? username.substring(0, 2).toUpperCase()
                      : username.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                '@$username',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
        Text(
          '${_contentController.text.characters.length}/$_maxLength',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _contentController.text.characters.length > _maxLength - 40
                ? Colors.orange.shade300
                : Colors.white38,
          ),
        ),
      ],
    );
  }

  /// Tuval: gorsel varsa cerceveli gorsel onizlemesi + aciklama alani, yoksa
  /// arka planli (ya da sade) metin editoru.
  Widget _composerCard() {
    if (_hasImages) return _imageComposer();

    final bg = _background;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: bg == null ? _plainEditor() : _backgroundEditor(bg),
      ),
    );
  }

  /// Sade gonderi: beyaz kagit hissi, sola hizali normal yazi. Feed'de ve
  /// izgarada da bu gonderi ZEMINSIZ cizilir.
  Widget _plainEditor() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: TextField(
        controller: _contentController,
        focusNode: _contentFocus,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        maxLength: _maxLength,
        inputFormatters: [LengthLimitingTextInputFormatter(_maxLength)],
        cursorColor: Theme.of(context).colorScheme.primary,
        style: const TextStyle(
          fontSize: 17,
          height: 1.45,
          color: Color(0xFF15202B),
        ),
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          hintText: 'Ne düşünüyorsun?',
          hintStyle: TextStyle(color: Color(0xFF9AA5B1), fontSize: 17),
        ),
      ),
    );
  }

  /// Arka planli gonderi: yazi tam ortada, punto uzunluga gore kuculur -
  /// yayinlandiginda gorunecek kompozisyonun aynisi.
  Widget _backgroundEditor(TextBackground bg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortest = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final fontSize = textBackgroundFontSize(_text, shortest);

        return DecoratedBox(
          decoration: BoxDecoration(gradient: bg.gradient),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
            child: Center(
              child: SingleChildScrollView(
                child: TextField(
                  controller: _contentController,
                  focusNode: _contentFocus,
                  maxLines: null,
                  textAlign: TextAlign.center,
                  maxLength: _maxLength,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(_maxLength),
                  ],
                  cursorColor: bg.textColor,
                  style: TextStyle(
                    color: bg.textColor,
                    fontSize: fontSize,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Ne düşünüyorsun?',
                    hintStyle: TextStyle(
                      color: bg.textColor.withValues(alpha: 0.55),
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Gorselli gonderide tuval: fotograflar secili cercevede, akista
  /// gorunecekleri haliyle onizlenir; cerceve secici, kirpma ve kucuk resim
  /// seridi [PostImageComposer]'da (Görev 2.8).
  Widget _imageComposer() {
    return PostImageComposer(
      images: _images,
      format: _format,
      enabled: !_isPosting,
      onFormatChanged: _setFormat,
      onCrop: _cropImage,
      onRemove: _removeImage,
      onAdd: _pickImages,
      caption: TextField(
        controller: _contentController,
        focusNode: _contentFocus,
        maxLines: 4,
        minLines: 2,
        maxLength: _maxLength,
        inputFormatters: [LengthLimitingTextInputFormatter(_maxLength)],
        cursorColor: Theme.of(context).colorScheme.primary,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.4,
        ),
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          hintText: 'Bir açıklama ekle...',
          hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
        ),
      ),
    );
  }

  Widget _bottomTools() {
    return Container(
      decoration: const BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Klavye boşluğunu Scaffold hallediyor (resizeToAvoidBottomInset: true
      // gövdenin MediaQuery'sinden alt viewInset'i zaten düşürüyor), burada
      // ayrıca eklemek çift sayardı.
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Arka plan seridi yalnizca metin gonderisinde anlamli.
            if (!_hasImages) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 18),
                  Text(
                    'Arka plan',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              TextBackgroundPicker(
                selectedId: _backgroundId,
                onSelected: (id) => setState(() => _backgroundId = id),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(
                children: [
                  _toolButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Galeri',
                    onTap: _isPosting ? null : _pickImages,
                  ),
                  if (!kIsWeb)
                    _toolButton(
                      icon: Icons.photo_camera_outlined,
                      label: 'Kamera',
                      onTap: _isPosting ? null : _takePhoto,
                    ),
                  if (_musicEnabled)
                    _toolButton(
                      icon: Icons.music_note_rounded,
                      label: 'Müzik',
                      onTap: _isPosting ? null : _pickMusic,
                      highlighted: _music != null,
                    ),
                  const Spacer(),
                  if (_hasImages)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${_images.length} fotoğraf',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool highlighted = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 21,
                color: highlighted ? MusicUI.accent : Colors.white70,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: highlighted ? MusicUI.accent : Colors.white70,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
