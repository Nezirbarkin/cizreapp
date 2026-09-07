import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../services/post_service.dart';
import '../../profile/services/profile_service.dart';
import '../../../core/utils/image_compression_helper.dart';
import '../../../core/utils/app_error_handler.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _postService = PostService();
  final _profileService = ProfileService();
  final _contentController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  
  // XFile listesi - Web ve Mobile uyumlu
  List<XFile> _selectedImages = [];
  List<String> _uploadedImageUrls = [];
  // Web için preview bytes.
  // ÖNEMLİ: Anahtar index DEĞİL dosya yolu. Index kullanıldığında aradan bir
  // görsel silinince kalan görsellerin önizlemeleri kayıyordu (2. resmi
  // silince 3. resim 2. resmin küçük görselini gösteriyordu).
  final Map<String, Uint8List> _imageBytes = {};
  bool _isPosting = false;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await _profileService.getUserProfile(userId);
      setState(() => _userProfile = profile);
    } catch (e) {
      debugPrint('Profil yüklenirken hata: $e');
    }
  }

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
      if (file != null) {
        images = [file];
      } else {
        images = [];
      }
    } else {
      // Mobile'da çoklu seçim
      images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    }

    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
      
      // Web için preview bytes'ı yükle
      if (kIsWeb) {
        for (final image in images) {
          final bytes = await image.readAsBytes();
          if (!mounted) return;
          setState(() {
            _imageBytes[image.path] = bytes;
          });
        }
      }
    }
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
        Uint8List imageBytes;
        
        // Web ve Mobile'da XFile üzerinden sıkıştır
        debugPrint('📤 Post resmi işleniyor...');
        final compressedBytes = await ImageCompressionHelper.compressXFile(
          xFile: xFile,
          quality: 85,
          maxWidth: 1080,
          maxHeight: 1920,
        );
        imageBytes = compressedBytes ?? await xFile.readAsBytes();
        debugPrint('📤 Post resmi boyutu: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
        
        final fileExt = xFile.name.split('.').last.toLowerCase();
        final fileName = 'post_${userId}_${DateTime.now().millisecondsSinceEpoch}_$i.$fileExt';
        final filePath = 'posts/$fileName';

        // Resmi yükle
        await Supabase.instance.client.storage
            .from('posts')
            .uploadBinary(filePath, imageBytes);

        // Public URL al
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

  Future<void> _createPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen içerik veya resim ekleyin')),
      );
      return;
    }

    setState(() => _isPosting = true);

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isPosting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oturum açmanız gerekiyor')),
        );
      }
      return;
    }

    try {
      // Resimleri yükle
      int failedUploads = 0;
      if (_selectedImages.isNotEmpty) {
        failedUploads = await _uploadImages();

        // Hiçbiri yüklenemediyse ve yazı da yoksa boş gönderi oluşturmayalım.
        if (_uploadedImageUrls.isEmpty && content.isEmpty) {
          if (mounted) {
            setState(() => _isPosting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Fotoğraflar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Gönderiyi oluştur
      await _postService.createPost(
        userId: userId,
        content: content,
        images: _uploadedImageUrls,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorHandler.handleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Yeni Gönderi'),
        actions: [
          if (_isPosting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _createPost,
              child: Text(
                'Paylaş',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kullanıcı bilgisi
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: primaryColor,
                  backgroundImage: _userProfile?['avatar_url'] != null
                      ? NetworkImage(_userProfile!['avatar_url'])
                      : null,
                  child: _userProfile?['avatar_url'] == null
                      ? Text(
                          () {
                            final username = _userProfile?['username'] ?? 'U';
                            return username.length >= 2
                                ? username.substring(0, 2).toUpperCase()
                                : username.toUpperCase();
                          }(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userProfile?['full_name'] ?? _userProfile?['username'] ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '@${_userProfile?['username'] ?? 'user'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // İçerik alanı
            TextField(
              controller: _contentController,
              maxLines: null,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Ne düşünüyorsun?',
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 16),

            // Seçilen resimler
            if (_selectedImages.isNotEmpty)
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _imageBytes[_selectedImages[index].path] != null
                                ? Image.memory(
                                    _imageBytes[_selectedImages[index].path]!,
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  )
                                : FutureBuilder<Uint8List>(
                                    future: _selectedImages[index].readAsBytes(),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        // Bytes'ı cache'e ekle
                                        _imageBytes[_selectedImages[index].path] =
                                            snapshot.data!;
                                        return Image.memory(
                                          snapshot.data!,
                                          width: 200,
                                          height: 200,
                                          fit: BoxFit.cover,
                                        );
                                      }
                                      return Container(
                                        width: 200,
                                        height: 200,
                                        color: Colors.grey.shade300,
                                        child: const Center(
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 12,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                            onPressed: () {
                              setState(() {
                                final removed = _selectedImages.removeAt(index);
                                _imageBytes.remove(removed.path);
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            const SizedBox(height: 16),

            // Resim ekle butonu
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: _pickImages,
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, color: primaryColor, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Fotoğraf Ekle',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _selectedImages.isEmpty
                                ? 'Galeriden resim seç'
                                : '${_selectedImages.length} resim seçili',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ElevatedButton(
            onPressed: _isPosting ? null : _createPost,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: Colors.grey.shade300,
            ),
            child: _isPosting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Paylaş',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
