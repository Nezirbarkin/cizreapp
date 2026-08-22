// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/news_model.dart';
import '../../../core/services/storage_service.dart';
import '../services/news_service.dart';

/// Haber Editör Ekranı - Yeni haber oluşturma ve düzenleme
class NewsEditorScreen extends StatefulWidget {
  final NewsModel? news;
  final List<NewsCategoryModel> categories;
  final List<InstitutionModel> institutions;

  const NewsEditorScreen({
    super.key,
    this.news,
    required this.categories,
    required this.institutions,
  });

  @override
  State<NewsEditorScreen> createState() => _NewsEditorScreenState();
}

class _NewsEditorScreenState extends State<NewsEditorScreen> {
  final NewsService _newsService = NewsService();
  final StorageService _storageService = StorageService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _summaryController;
  late TextEditingController _locationController;

  String? _selectedCategoryId;
  String? _selectedInstitutionId;
  bool _isPublished = false;
  bool _isFeatured = false;
  bool _isBreaking = false;
  bool _isSaving = false;
  bool _isUploadingImage = false;
  bool _isUploadingMedia = false;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  String? _uploadedImageUrl;
  bool _removeExistingImage = false;
  final List<XFile> _selectedGalleryImages = [];
  final List<Uint8List> _selectedGalleryBytes = [];
  List<NewsImageModel> _existingGalleryImages = [];
  XFile? _selectedVideo;
  Uint8List? _selectedVideoBytes;
  String? _uploadedVideoUrl;
  bool _removeExistingVideo = false;
  Timer? _uploadTimer;
  DateTime? _uploadStartedAt;
  Duration? _estimatedUploadDuration;
  String? _uploadStatusLabel;
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.news?.title ?? '');
    _contentController = TextEditingController(
      text: widget.news?.content ?? '',
    );
    _summaryController = TextEditingController(
      text: widget.news?.summary ?? '',
    );
    _locationController = TextEditingController(
      text: widget.news?.locationName ?? '',
    );
    _selectedCategoryId = widget.news?.categoryId;
    _selectedInstitutionId = widget.news?.institutionId;
    _isPublished = widget.news?.isPublished ?? false;
    _isFeatured = widget.news?.isFeatured ?? false;
    _isBreaking = widget.news?.isBreaking ?? false;
    _uploadedImageUrl = widget.news?.thumbnailUrl;
    _uploadedVideoUrl = widget.news?.videoUrl;
    _existingGalleryImages = [...?widget.news?.images];
    if (widget.news != null) _loadExistingMedia();
  }

  Future<void> _loadExistingMedia() async {
    final news = await _newsService.getNewsById(widget.news!.id);
    if (!mounted || news == null) return;
    setState(() {
      _existingGalleryImages = [...news.images]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _uploadedVideoUrl = news.videoUrl;
    });
  }

  @override
  void dispose() {
    _uploadTimer?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _summaryController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
        _removeExistingImage = false;
      });
    }
  }

  Future<void> _pickGalleryImages() async {
    final remaining =
        10 - _existingGalleryImages.length - _selectedGalleryImages.length;
    if (remaining <= 0) {
      _showMessage('Galeriye en fazla 10 görsel eklenebilir.');
      return;
    }
    final images = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (images.isEmpty) return;

    final accepted = images.take(remaining);
    for (final image in accepted) {
      final bytes = await image.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) {
        _showMessage('${image.name} 15 MB sınırını aşıyor.');
        continue;
      }
      _selectedGalleryImages.add(image);
      _selectedGalleryBytes.add(bytes);
    }
    if (!mounted) return;
    setState(() {});
    if (images.length > remaining) {
      _showMessage(
        'İlk $remaining görsel seçildi; galeri sınırı 10 görseldir.',
      );
    }
  }

  Future<void> _pickVideo() async {
    final video = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (video == null) return;
    final bytes = await video.readAsBytes();
    if (bytes.length > 100 * 1024 * 1024) {
      _showMessage('Tanıtım videosu en fazla 100 MB olabilir.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedVideo = video;
      _selectedVideoBytes = bytes;
      _removeExistingVideo = false;
    });
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final image = _selectedImage!;
      final bytes = _selectedImageBytes ?? await image.readAsBytes();
      _startUploadTracking('Kapak görseli yükleniyor', bytes.length);
      final extension = _fileExtension(image.name);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$extension';
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw StateError('Oturum bulunamadı');
      final uploadUrl = await _storageService.uploadBytes(
        bucket: 'news-images',
        bytes: bytes,
        path: '$userId/thumbnails/$fileName',
        metadata: {'contentType': _contentType(extension)},
      );

      if (uploadUrl != null) {
        setState(() {
          _uploadedImageUrl = uploadUrl;
          _selectedImage = null;
          _selectedImageBytes = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Görsel başarıyla yüklendi')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Yükleme hatası: $e')));
      }
    } finally {
      _finishUploadTracking();
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<bool> _uploadVideo() async {
    if (_selectedVideo == null) return true;
    setState(() => _isUploadingMedia = true);
    try {
      final video = _selectedVideo!;
      final bytes = _selectedVideoBytes ?? await video.readAsBytes();
      _startUploadTracking('Tanıtım videosu yükleniyor', bytes.length);
      final extension = _videoExtension(video.name);
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw StateError('Oturum bulunamadı');
      final url = await _storageService.uploadBytes(
        bucket: 'news-images',
        bytes: bytes,
        path:
            '$userId/videos/${DateTime.now().microsecondsSinceEpoch}.$extension',
        metadata: {'contentType': _videoContentType(extension)},
      );
      if (url == null) return false;
      if (mounted) {
        setState(() {
          _uploadedVideoUrl = url;
          _selectedVideo = null;
          _selectedVideoBytes = null;
        });
      }
      return true;
    } finally {
      _finishUploadTracking();
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<int> _uploadGallery(String newsId) async {
    if (_selectedGalleryImages.isEmpty) return 0;
    setState(() => _isUploadingMedia = true);
    var uploaded = 0;
    try {
      final startOrder = _existingGalleryImages.length;
      for (var i = 0; i < _selectedGalleryImages.length; i++) {
        _startUploadTracking(
          'Galeri görseli ${i + 1}/${_selectedGalleryImages.length} yükleniyor',
          _selectedGalleryBytes[i].length,
        );
        final result = await _newsService.uploadNewsImageBytes(
          newsId: newsId,
          bytes: _selectedGalleryBytes[i],
          extension: _fileExtension(_selectedGalleryImages[i].name),
          sortOrder: startOrder + i,
        );
        if (result != null) uploaded++;
      }
      return uploaded;
    } finally {
      _finishUploadTracking();
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _deleteExistingGalleryImage(NewsImageModel image) async {
    final success = await _newsService.deleteNewsImage(image.id);
    if (!mounted) return;
    if (success) {
      setState(
        () => _existingGalleryImages.removeWhere((e) => e.id == image.id),
      );
    } else {
      _showMessage('Galeri görseli silinemedi.');
    }
  }

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) return 'jpg';

    final extension = fileName.substring(dotIndex + 1).toLowerCase();
    const supportedExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
    return supportedExtensions.contains(extension) ? extension : 'jpg';
  }

  String _contentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  String _videoExtension(String fileName) {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'mp4';
    return const {'mp4', 'mov', 'webm'}.contains(extension) ? extension : 'mp4';
  }

  String _videoContentType(String extension) => switch (extension) {
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    _ => 'video/mp4',
  };

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Supabase SDK byte yüklemesinde transfer callback'i sağlamadığı için
  /// ilerleme, dosya boyutu ve ortalama 1 MB/sn bağlantı üzerinden tahminidir.
  void _startUploadTracking(String label, int byteCount) {
    _uploadTimer?.cancel();
    final estimatedSeconds = (byteCount / (1024 * 1024)).ceil() + 2;
    _uploadStartedAt = DateTime.now();
    _estimatedUploadDuration = Duration(
      seconds: estimatedSeconds.clamp(3, 300),
    );
    _uploadStatusLabel = label;
    _uploadProgress = 0;
    if (mounted) setState(() {});
    _uploadTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _uploadStartedAt == null) return;
      final elapsed = DateTime.now().difference(_uploadStartedAt!);
      final estimate = _estimatedUploadDuration!.inMilliseconds;
      setState(() {
        _uploadProgress = (elapsed.inMilliseconds / estimate).clamp(0, 0.95);
      });
    });
  }

  void _finishUploadTracking() {
    _uploadTimer?.cancel();
    if (!mounted || _uploadStatusLabel == null) return;
    setState(() => _uploadProgress = 1);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  String _estimatedTimeText(int bytes) {
    final seconds = ((bytes / (1024 * 1024)).ceil() + 2).clamp(3, 300);
    if (seconds < 60) return 'yaklaşık $seconds sn';
    final minutes = (seconds / 60).ceil();
    return 'yaklaşık $minutes dk';
  }

  String get _remainingUploadText {
    if (_uploadStartedAt == null || _estimatedUploadDuration == null) return '';
    final elapsed = DateTime.now().difference(_uploadStartedAt!);
    final remaining = _estimatedUploadDuration! - elapsed;
    if (remaining.isNegative) return 'Bağlantıya göre biraz daha sürebilir';
    if (remaining.inSeconds < 60) {
      return 'Tahmini ${remaining.inSeconds + 1} sn kaldı';
    }
    return 'Tahmini ${(remaining.inSeconds / 60).ceil()} dk kaldı';
  }

  Future<void> _saveNews() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (_selectedImage != null) {
        await _uploadImage();
        if (_uploadedImageUrl == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Görsel yüklenemedi. Haber kaydedilmedi.'),
              ),
            );
          }
          return;
        }
      }

      if (!await _uploadVideo()) {
        _showMessage('Video yüklenemedi. Haber kaydedilmedi.');
        return;
      }

      if (widget.news == null) {
        final result = await _newsService.createNews(
          title: _titleController.text,
          content: _contentController.text,
          summary: _summaryController.text,
          categoryId: _selectedCategoryId,
          institutionId: _selectedInstitutionId,
          isPublished: _isPublished,
          isFeatured: _isFeatured,
          isBreaking: _isBreaking,
          locationName: _locationController.text,
          thumbnailUrl: _uploadedImageUrl,
          videoUrl: _uploadedVideoUrl,
          publishedAt: _isPublished ? DateTime.now() : null,
        );
        if (result != null && mounted) {
          final selectedCount = _selectedGalleryImages.length;
          final uploadedCount = await _uploadGallery(result.id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uploadedCount == selectedCount
                    ? 'Haber ve medya dosyaları başarıyla oluşturuldu'
                    : 'Haber kaydedildi; bazı galeri görselleri yüklenemedi',
              ),
            ),
          );
          Navigator.pop(context, true);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hata: Haber kaydedilemedi')),
          );
        }
      } else {
        final success = await _newsService.updateNews(
          id: widget.news!.id,
          title: _titleController.text,
          content: _contentController.text,
          summary: _summaryController.text,
          categoryId: _selectedCategoryId,
          institutionId: _selectedInstitutionId,
          isPublished: _isPublished,
          isFeatured: _isFeatured,
          isBreaking: _isBreaking,
          locationName: _locationController.text,
          thumbnailUrl: _uploadedImageUrl,
          videoUrl: _uploadedVideoUrl,
          clearThumbnail: _removeExistingImage,
          clearVideo: _removeExistingVideo,
          publishedAt: _isPublished ? DateTime.now() : null,
        );
        if (success && mounted) {
          final selectedCount = _selectedGalleryImages.length;
          final uploadedCount = await _uploadGallery(widget.news!.id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uploadedCount == selectedCount
                    ? 'Haber ve medya dosyaları başarıyla güncellendi'
                    : 'Haber güncellendi; bazı galeri görselleri yüklenemedi',
              ),
            ),
          );
          Navigator.pop(context, true);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hata: Haber güncellenemedi')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.news == null ? 'Yeni Haber' : 'Haberi Düzenle'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Temel Bilgiler'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Başlık *',
                  hintText: 'Haber başlığını girin',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (v) =>
                    v?.isEmpty ?? true ? 'Başlık gereklidir' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _summaryController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Özet',
                  hintText: 'Kısa özeti girin',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: 'İçerik *',
                  hintText: 'Haber içeriği girin',
                  prefixIcon: const Icon(Icons.article),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (v) =>
                    v?.isEmpty ?? true ? 'İçerik gereklidir' : null,
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Kapak Görseli'),
              const SizedBox(height: 12),
              if (_uploadedImageUrl != null && _selectedImage == null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: NetworkImage(_uploadedImageUrl!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() {
                          _uploadedImageUrl = null;
                          _removeExistingImage = true;
                        }),
                        icon: const Icon(Icons.delete),
                        label: const Text('Görseli Kaldır'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ),
                  ],
                )
              else if (_selectedImage != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _selectedImageBytes!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isUploadingImage ? null : _uploadImage,
                            icon: _isUploadingImage
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload),
                            label: Text(
                              _isUploadingImage
                                  ? 'Yükleniyor...'
                                  : 'Sunucuya Yükle',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => setState(() {
                            _selectedImage = null;
                            _selectedImageBytes = null;
                          }),
                          icon: const Icon(Icons.clear),
                          label: const Text('İptal'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.image, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'Görsel seçilmedi',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (_selectedImage == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Görsel Seç'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              if (_selectedImageBytes != null && !_isUploadingImage) ...[
                const SizedBox(height: 8),
                _buildEstimateRow(
                  _selectedImageBytes!.length,
                  label: 'Kapak görseli',
                ),
              ],
              const SizedBox(height: 24),
              _buildGalleryEditor(),
              const SizedBox(height: 24),
              _buildVideoEditor(),
              const SizedBox(height: 24),
              if (_uploadStatusLabel != null &&
                  (_isUploadingImage || _isUploadingMedia)) ...[
                _buildUploadProgressPanel(),
                const SizedBox(height: 24),
              ],
              _buildSectionTitle('Kategorilendirme'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedCategoryId,
                      decoration: InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Seçiniz'),
                        ),
                        ...widget.categories.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedInstitutionId,
                      decoration: InputDecoration(
                        labelText: 'Kurum',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Seçiniz'),
                        ),
                        ...widget.institutions.map(
                          (i) => DropdownMenuItem(
                            value: i.id,
                            child: Text(i.name),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedInstitutionId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Konum',
                  hintText: 'Haber konumunu girin',
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Seçenekler'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _isPublished,
                onChanged: (v) => setState(() => _isPublished = v ?? false),
                title: const Text('Yayınla'),
                subtitle: const Text('Haberi yayınla'),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _isFeatured,
                onChanged: (v) => setState(() => _isFeatured = v ?? false),
                title: const Text('Öne Çıkan'),
                subtitle: const Text('Ana sayfada öne çıkar'),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _isBreaking,
                onChanged: (v) => setState(() => _isBreaking = v ?? false),
                title: const Text('Son Dakika'),
                subtitle: const Text('Son dakika haberi olarak işaretle'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_isSaving || _isUploadingMedia)
                      ? null
                      : _saveNews,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildGalleryEditor() {
    final total = _existingGalleryImages.length + _selectedGalleryImages.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Çoklu Görsel Galerisi ($total/10)'),
        const SizedBox(height: 8),
        const Text(
          'Haber detayında sıralı olarak gösterilecek görselleri seçin.',
        ),
        const SizedBox(height: 12),
        if (total > 0)
          SizedBox(
            height: 116,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ..._existingGalleryImages.map(
                  (image) => _mediaPreview(
                    child: Image.network(image.imageUrl, fit: BoxFit.cover),
                    onRemove: () => _deleteExistingGalleryImage(image),
                  ),
                ),
                for (var i = 0; i < _selectedGalleryImages.length; i++)
                  _mediaPreview(
                    child: Image.memory(
                      _selectedGalleryBytes[i],
                      fit: BoxFit.cover,
                    ),
                    onRemove: () => setState(() {
                      _selectedGalleryImages.removeAt(i);
                      _selectedGalleryBytes.removeAt(i);
                    }),
                  ),
              ],
            ),
          ),
        if (_selectedGalleryBytes.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildEstimateRow(
            _selectedGalleryBytes.fold<int>(
              0,
              (sum, bytes) => sum + bytes.length,
            ),
            label: '${_selectedGalleryBytes.length} galeri görseli',
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: total >= 10 ? null : _pickGalleryImages,
            icon: const Icon(Icons.collections_rounded),
            label: const Text('Birden Fazla Görsel Seç'),
          ),
        ),
      ],
    );
  }

  Widget _mediaPreview({
    required Widget child,
    required VoidCallback onRemove,
  }) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton.filled(
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoEditor() {
    final hasVideo = _selectedVideo != null || _uploadedVideoUrl != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Tanıtım Videosu'),
        const SizedBox(height: 8),
        const Text('MP4, MOV veya WebM; en fazla 100 MB.'),
        const SizedBox(height: 12),
        if (hasVideo)
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            leading: const Icon(Icons.play_circle_fill_rounded, size: 42),
            title: Text(_selectedVideo?.name ?? 'Yüklü tanıtım videosu'),
            subtitle: Text(
              _selectedVideo == null
                  ? 'Video kaydedilmiş durumda'
                  : '${_formatBytes(_selectedVideoBytes!.length)} • '
                        '${_estimatedTimeText(_selectedVideoBytes!.length)}',
            ),
            trailing: IconButton(
              tooltip: 'Videoyu kaldır',
              onPressed: () => setState(() {
                _selectedVideo = null;
                _selectedVideoBytes = null;
                _uploadedVideoUrl = null;
                _removeExistingVideo = true;
              }),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_library_rounded),
            label: Text(hasVideo ? 'Videoyu Değiştir' : 'Tanıtım Videosu Seç'),
          ),
        ),
      ],
    );
  }

  Widget _buildEstimateRow(int bytes, {required String label}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: ${_formatBytes(bytes)} • ${_estimatedTimeText(bytes)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadProgressPanel() {
    final progress = _uploadProgress ?? 0;
    final percentage = (progress * 100).round();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _uploadStatusLabel!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text('%$percentage'),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              _remainingUploadText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Süre bağlantı hızına göre değişebilir.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
