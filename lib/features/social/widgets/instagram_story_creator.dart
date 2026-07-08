// ignore_for_file: deprecated_member_use, use_key_in_widget_constructors

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../core/services/permission_service.dart';

// Instagram tarzı story oluşturma widget'ı
class InstagramStoryCreator extends StatefulWidget {
  final ImagePicker imagePicker;
  final Function(XFile, String) onMediaSelected;

  const InstagramStoryCreator({
    required this.imagePicker,
    required this.onMediaSelected,
  });

  @override
  State<InstagramStoryCreator> createState() => InstagramStoryCreatorState();
}

class InstagramStoryCreatorState extends State<InstagramStoryCreator> {
  XFile? _selectedMedia;
  String? _mediaType; // 'image' veya 'video'
  bool _isUploading = false;
  VideoPlayerController? _videoController;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  /// Seçilen video için oynatıcıyı hazırla (gerçek önizleme).
  Future<void> _initVideoController(XFile file) async {
    // Önceki controller'ı temizle
    final old = _videoController;
    _videoController = null;
    if (mounted) setState(() {});
    await old?.dispose();

    try {
      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(file.path))
          : VideoPlayerController.file(File(file.path));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _videoController = controller);
    } catch (e) {
      debugPrint('Video önizleme başlatılamadı: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: screenSize.height * 0.92,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Üst kısım: Kapat butonu, başlık, İleri butonu
          _buildTopBar(isDark),
          // Ana alan: Önizleme veya kamera/galeri placeholder
          Expanded(
            child: _buildPreviewArea(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Kapat (X) butonu
            IconButton(
              onPressed: _isUploading ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(),
            ),
            // Başlık
            const Text(
              'Hikaye Oluştur',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            // İleri butonu
            IconButton(
              onPressed: _selectedMedia != null && !_isUploading ? _onNext : null,
              icon: Icon(
                Icons.arrow_forward,
                color: _selectedMedia != null && !_isUploading
                    ? Colors.white
                    : Colors.white38,
                size: 28,
              ),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewArea(bool isDark) {
    if (_selectedMedia != null) {
      return _buildMediaPreview(isDark);
    }

    // Varsayılan durum: Kamera/galeri placeholder
    return Container(
      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A2E),
      child: Stack(
        children: [
          // Arka plan gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF667eea).withValues(alpha: 0.3),
                  const Color(0xFF764ba2).withValues(alpha: 0.3),
                  const Color(0xFFf093fb).withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
          // Şeffaf gradient overlay (üst kısım)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // İçerik
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Büyük kamera ikonu
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 2),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.15),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white70,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Hikaye Oluştur',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fotoğraf veya video seçerek başla',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 40),
                // Hızlı seçim butonları
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildQuickOption(
                      icon: Icons.photo_library_outlined,
                      label: 'Galeri',
                      onTap: () => _pickFromGallery(),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 24),
                    if (!kIsWeb) ...[
                      _buildQuickOption(
                        icon: Icons.camera_alt,
                        label: 'Kamera',
                        onTap: () => _pickFromCamera(),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 24),
                    ],
                    _buildQuickOption(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      onTap: () => _pickVideo(),
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Alt gradient overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 100,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: _isUploading ? null : onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview(bool isDark) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Medya önizlemesi
        Container(
          color: Colors.black,
          child: kIsWeb
              ? _buildWebPreview()
              : _buildMobilePreview(),
        ),
        // Üst gradient overlay
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Alt gradient overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 120,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.5),
                ],
              ),
            ),
          ),
        ),
        // Medya türü badge'i
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _mediaType == 'video' ? Icons.videocam : Icons.photo,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _mediaType == 'video' ? 'Video' : 'Fotoğraf',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Değiştir butonu
        Positioned(
          bottom: 100,
          right: 16,
          child: GestureDetector(
            onTap: _isUploading ? null : _clearSelection,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black54,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(
                Icons.refresh,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        // Yükleniyor overlay
        if (_isUploading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Yükleniyor...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWebPreview() {
    // Web'de dosya yolu blob URL olabilir
    return FutureBuilder<Uint8List>(
      future: _selectedMedia!.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          if (_mediaType == 'video') {
            return _buildVideoPreview();
          }
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
          );
        }
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
    );
  }

  Widget _buildMobilePreview() {
    if (_mediaType == 'video') {
      return _buildVideoPreview();
    }
    return Image.file(
      File(_selectedMedia!.path),
      fit: BoxFit.contain,
    );
  }

  /// Seçilen videonun gerçek oynatılan önizlemesi (dokununca duraklat/oynat).
  Widget _buildVideoPreview() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white70),
              SizedBox(height: 16),
              Text(
                'Video hazırlanıyor...',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          controller.value.isPlaying ? controller.pause() : controller.play();
        });
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            // İlerleme çubuğu
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
            // Duraklatıldığında oynat ikonu
            if (!controller.value.isPlaying)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.play_arrow,
                    color: Colors.white, size: 48),
              ),
          ],
        ),
      ),
    );
  }

  // ---- Medya seçim metodları ----

  /// Fotoğraf galerisi izni reddedildiğinde gösterilecek dialog
  void _showPhotosPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.photo_library, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Fotoğraf Galerisi İzni Gerekli')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CizreApp\'in fotoğraf galerinize erişmesi gerekiyor; böylece galerinizden fotoğraf seçip gönderi veya hikaye paylaşabilir, ürün fotoğraflarını mağazanıza yükleyebilir ve profil fotoğrafınızı değiştirebilirsiniz.',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  /// Kamera izni reddedildiğinde gösterilecek dialog
  void _showCameraPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.camera_alt, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Kamera İzni Gerekli')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CizreApp\'in kamera erişimine ihtiyacı var; böylece fotoğraf çekip profil fotoğrafınızı güncelleyebilir, gönderi ve hikaye paylaşabilir, satışa sunmak istediğiniz ürünlerin fotoğraflarını çekebilirsiniz.',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      // İzin kontrolü
      final permissionService = PermissionService();
      final isGranted = await permissionService.isPhotosGranted();
      if (!isGranted) {
        if (!mounted) return;
        final result = await permissionService.checkAndRequestAllPermissions();
        final photosResult = result['photos'];
        if (photosResult != null && !photosResult.isGranted) {
          if (mounted) {
            _showPhotosPermissionDialog();
          }
          return;
        }
      }
      
      // Orijinal boyut korunsun: maxWidth/maxHeight/imageQuality verilmiyor.
      final XFile? image = await widget.imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (image != null) {
        setState(() {
          _selectedMedia = image;
          _mediaType = 'image';
        });
      }
    } catch (e) {
      debugPrint('Galeriden fotoğraf seçme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    }
  }

  Future<void> _pickFromCamera() async {
    if (kIsWeb) return; // Web'de kamera desteği yok
    try {
      // İzin kontrolü
      final permissionService = PermissionService();
      final isGranted = await permissionService.isCameraGranted();
      if (!isGranted) {
        if (!mounted) return;
        final result = await permissionService.checkAndRequestAllPermissions();
        final cameraResult = result['camera'];
        if (cameraResult != null && !cameraResult.isGranted) {
          if (mounted) {
            _showCameraPermissionDialog();
          }
          return;
        }
      }
      
      // Orijinal boyut korunsun: maxWidth/maxHeight/imageQuality verilmiyor.
      final XFile? photo = await widget.imagePicker.pickImage(
        source: ImageSource.camera,
      );
      if (photo != null) {
        setState(() {
          _selectedMedia = photo;
          _mediaType = 'image';
        });
      }
    } catch (e) {
      debugPrint('Kamera çekim hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamera çekimi başarısız: $e')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      // İzin kontrolü (video seçmek için galeri izni gerekli)
      final permissionService = PermissionService();
      final isGranted = await permissionService.isPhotosGranted();
      if (!isGranted) {
        if (!mounted) return;
        final result = await permissionService.checkAndRequestAllPermissions();
        final photosResult = result['photos'];
        if (photosResult != null && !photosResult.isGranted) {
          if (mounted) {
            _showPhotosPermissionDialog();
          }
          return;
        }
      }
      
      final XFile? video = await widget.imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (video != null) {
        setState(() {
          _selectedMedia = video;
          _mediaType = 'video';
        });
        // Gerçek video önizlemesini başlat
        _initVideoController(video);
      }
    } catch (e) {
      debugPrint('Video seçme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video seçilemedi: $e')),
        );
      }
    }
  }

  void _clearSelection() {
    final old = _videoController;
    _videoController = null;
    old?.dispose();
    setState(() {
      _selectedMedia = null;
      _mediaType = null;
    });
  }

  Future<void> _onNext() async {
    if (_selectedMedia == null) return;

    setState(() => _isUploading = true);

    // Bottom sheet'i kapat
    Navigator.pop(context);

    // Mevcut story oluşturma akışını başlat
    widget.onMediaSelected(_selectedMedia!, _mediaType ?? 'image');
  }
}
