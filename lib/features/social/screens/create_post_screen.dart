import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../services/post_service.dart';
import '../../profile/services/profile_service.dart';
import '../../../core/utils/image_compression_helper.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/text_background.dart';

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

  // XFile listesi - Web ve Mobile uyumlu
  final List<XFile> _selectedImages = [];
  final List<String> _uploadedImageUrls = [];
  // Web için preview bytes.
  // ÖNEMLİ: Anahtar index DEĞİL dosya yolu. Index kullanıldığında aradan bir
  // görsel silinince kalan görsellerin önizlemeleri kayıyordu (2. resmi
  // silince 3. resim 2. resmin küçük görselini gösteriyordu).
  final Map<String, Uint8List> _imageBytes = {};

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

  bool get _hasImages => _selectedImages.isNotEmpty;

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

    setState(() => _selectedImages.addAll(images));

    // Web için preview bytes'ı yükle
    if (kIsWeb) {
      for (final image in images) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        setState(() => _imageBytes[image.path] = bytes);
      }
    }
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
    setState(() => _selectedImages.add(photo));
  }

  void _removeImage(int index) {
    setState(() {
      final removed = _selectedImages.removeAt(index);
      _imageBytes.remove(removed.path);
    });
  }

  /// Seçili görselleri yükler ve BAŞARISIZ OLANLARIN sayısını döndürür.
  ///
  /// Eskiden hata sadece debugPrint'e yazılıyordu: tüm yüklemeler başarısız
  /// olsa bile gönderi görselsiz oluşturulup "Gönderi paylaşıldı!" deniyordu.
  /// Kullanıcı fotoğrafının kaybolduğunu ancak feed'e bakınca anlıyordu.
  Future<int> _uploadImages() async {
    _uploadedImageUrls.clear();
    int failed = 0;

    for (int i = 0; i < _selectedImages.length; i++) {
      final xFile = _selectedImages[i];
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) continue;

      try {
        // Web ve Mobile'da XFile üzerinden sıkıştır
        debugPrint('📤 Post resmi işleniyor...');
        final compressedBytes = await ImageCompressionHelper.compressXFile(
          xFile: xFile,
          quality: 85,
          maxWidth: 1080,
          maxHeight: 1920,
        );
        final Uint8List imageBytes =
            compressedBytes ?? await xFile.readAsBytes();
        debugPrint(
          '📤 Post resmi boyutu: '
          '${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
        );

        final fileExt = xFile.name.split('.').last.toLowerCase();
        final fileName =
            'post_${userId}_${DateTime.now().millisecondsSinceEpoch}_$i.$fileExt';
        final filePath = 'posts/$fileName';

        await Supabase.instance.client.storage
            .from('posts')
            .uploadBinary(filePath, imageBytes);

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
        background: _background?.id,
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
                      const SizedBox(height: 14),
                      _composerCard(),
                      if (_hasImages) ...[
                        const SizedBox(height: 14),
                        _imageStrip(),
                      ],
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

  /// Tuval: gorsel varsa gorsel onizlemesi + altinda aciklama alani, yoksa
  /// arka planli (ya da sade) metin editoru.
  Widget _composerCard() {
    if (_hasImages) return _imagePreviewCard();

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

  /// Gorselli gonderide tuval: ilk gorselin buyuk onizlemesi + aciklama alani.
  Widget _imagePreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1,
              child: _imageWidget(_selectedImages.first, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
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
        ],
      ),
    );
  }

  Widget _imageStrip() {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == _selectedImages.length) {
            return GestureDetector(
              onTap: _isPosting ? null : _pickImages,
              child: Container(
                width: 88,
                decoration: BoxDecoration(
                  color: _panelBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.add, color: Colors.white70),
              ),
            );
          }

          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: _imageWidget(_selectedImages[index]),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: _isPosting ? null : () => _removeImage(index),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// XFile onizlemesi. Web'de dosya yolu blob URL oldugu icin baytlar
  /// uzerinden cizilir; baytlar bir kez okunup [_imageBytes]'ta tutulur.
  Widget _imageWidget(XFile file, {BoxFit fit = BoxFit.cover}) {
    final cached = _imageBytes[file.path];
    if (cached != null) {
      return Image.memory(cached, fit: fit);
    }

    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _imageBytes[file.path] = snapshot.data!;
          return Image.memory(snapshot.data!, fit: fit);
        }
        return Container(
          color: _panelBg,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),
          ),
        );
      },
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
                  const Spacer(),
                  if (_hasImages)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${_selectedImages.length} fotoğraf',
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
              Icon(icon, size: 21, color: Colors.white70),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
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
