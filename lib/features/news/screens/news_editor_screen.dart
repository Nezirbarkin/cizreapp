// ignore_for_file: unused_field, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';

/// Haber Oluşturma/Düzenleme Sayfası
class NewsEditorScreen extends StatefulWidget {
  final NewsModel? news;

  const NewsEditorScreen({super.key, this.news});

  @override
  State<NewsEditorScreen> createState() => _NewsEditorScreenState();
}

class _NewsEditorScreenState extends State<NewsEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newsService = NewsService();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _summaryController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _scrollController = ScrollController();
  
  List<NewsCategoryModel> _categories = [];
  List<InstitutionModel> _institutions = [];
  List<NewsImageModel> _existingImages = [];
  List<File> _newImages = [];
  bool _isLoading = true;
  bool _isSaving = false;
  
  // Form değerleri
  String? _selectedCategory;
  String? _selectedInstitution;
  bool _isFeatured = false;
  bool _isPublished = false;
  bool _isBreaking = false;
  String? _thumbnailUrl;
  File? _newThumbnail;

  bool get isEditing => widget.news != null;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _summaryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _newsService.getCategories(),
        _newsService.getInstitutions(),
      ]);
      
      _categories = results[0] as List<NewsCategoryModel>;
      _institutions = results[1] as List<InstitutionModel>;
      
      if (widget.news != null) {
        _titleController.text = widget.news!.title;
        _contentController.text = widget.news!.content;
        _summaryController.text = widget.news!.summary ?? '';
        _selectedCategory = widget.news!.categoryId;
        _selectedInstitution = widget.news!.institutionId;
        _isFeatured = widget.news!.isFeatured;
        _isPublished = widget.news!.isPublished;
        _isBreaking = widget.news!.isBreaking;
        _thumbnailUrl = widget.news!.thumbnailUrl;
        _existingImages = List.from(widget.news!.images);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veri yükleme hatası: $e')),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Haberi Düzenle' : 'Yeni Haber'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            TextButton.icon(
              onPressed: _saveNews,
              icon: const Icon(Icons.check, color: Colors.white),
              label: Text(
                _isPublished ? 'Güncelle' : 'Kaydet',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Başlık
                    _buildSectionTitle('Başlık *'),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        hintText: 'Haber başlığını girin...',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Başlık gerekli';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Özet
                    _buildSectionTitle('Özet'),
                    TextFormField(
                      controller: _summaryController,
                      decoration: const InputDecoration(
                        hintText: 'Haber özeti...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),

                    // Kategori ve Kurum
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle('Kategori'),
                              DropdownButtonFormField<String?>(
                                value: _selectedCategory,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                                  ..._categories.map((c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  )),
                                ],
                                onChanged: (value) => setState(() => _selectedCategory = value),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle('Kurum'),
                              DropdownButtonFormField<String?>(
                                value: _selectedInstitution,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                                  ..._institutions.map((i) => DropdownMenuItem(
                                    value: i.id,
                                    child: Row(
                                      children: [
                                        if (i.isVerified)
                                          const Icon(Icons.verified, color: Colors.blue, size: 16),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(i.name)),
                                      ],
                                    ),
                                  )),
                                ],
                                onChanged: (value) => setState(() => _selectedInstitution = value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Bayraklar
                    _buildSectionTitle('Özellikler'),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildFlagSwitch(
                            'Yayınla',
                            'Haber yayınlanacak',
                            _isPublished,
                            Icons.publish,
                            Colors.green,
                            (v) => setState(() => _isPublished = v),
                          ),
                          const Divider(),
                          _buildFlagSwitch(
                            'Öne Çıkan',
                            'Ana sayfada öne çıkarılacak',
                            _isFeatured,
                            Icons.star,
                            Colors.purple,
                            (v) => setState(() => _isFeatured = v),
                          ),
                          const Divider(),
                          _buildFlagSwitch(
                            'Son Dakika',
                            'Son dakika haberi olarak işaretle',
                            _isBreaking,
                            Icons.flash_on,
                            Colors.red,
                            (v) => setState(() => _isBreaking = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Ana Görsel
                    _buildSectionTitle('Ana Görsel'),
                    _buildThumbnailPicker(),
                    const SizedBox(height: 24),

                    // Ek Görseller
                    _buildSectionTitle('Galeri Görselleri'),
                    _buildGalleryPicker(),
                    const SizedBox(height: 24),

                    // İçerik
                    _buildSectionTitle('İçerik *'),
                    TextFormField(
                      controller: _contentController,
                      decoration: const InputDecoration(
                        hintText: 'Haber içeriğini yazın...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 15,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'İçerik gerekli';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Kaydet Butonu
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveNews,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _isSaving
                              ? 'Kaydediliyor...'
                              : isEditing
                                  ? 'Haberi Güncelle'
                                  : _isPublished
                                      ? 'Haberi Yayınla'
                                      : 'Taslak Olarak Kaydet',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildFlagSwitch(
    String title,
    String subtitle,
    bool value,
    IconData icon,
    Color color,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: value ? color.withOpacity(0.1) : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: value ? color : Colors.grey),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: color,
        ),
      ],
    );
  }

  Widget _buildThumbnailPicker() {
    return InkWell(
      onTap: _pickThumbnail,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[50],
        ),
        child: _newThumbnail != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_newThumbnail!, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: () => setState(() => _newThumbnail = null),
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    ),
                  ),
                ],
              )
            : _thumbnailUrl != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: _thumbnailUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                          errorWidget: (_, __, ___) => _buildImagePlaceholder(),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: () => setState(() => _thumbnailUrl = null),
                          icon: const Icon(Icons.close, color: Colors.white),
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                        ),
                      ),
                    ],
                  )
                : _buildImagePlaceholder(),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text('Görsel seçmek için tıklayın', style: TextStyle(color: Colors.grey[600])),
        Text('(JPG, PNG, WEBP - Max 5MB)', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
      ],
    );
  }

  Widget _buildGalleryPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mevcut görseller
        if (_existingImages.isNotEmpty) ...[
          const Text('Mevcut görseller:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _existingImages.length,
              itemBuilder: (context, index) {
                final image = _existingImages[index];
                return Stack(
                  children: [
                    Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: image.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: Colors.grey[300],
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 12,
                      child: IconButton(
                        onPressed: () => _deleteExistingImage(image.id),
                        icon: const Icon(Icons.close, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(4),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Yeni görsel ekle butonu
        InkWell(
          onTap: _pickGalleryImages,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[50],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, size: 32, color: Colors.grey[400]),
                  const SizedBox(height: 4),
                  Text('Daha fazla görsel ekle', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          ),
        ),

        // Yeni eklenen görseller önizleme
        if (_newImages.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Eklenecek görseller:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _newImages.length,
              itemBuilder: (context, index) {
                final image = _newImages[index];
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(image, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 12,
                      child: IconButton(
                        onPressed: () => _removeNewImage(index),
                        icon: const Icon(Icons.close, size: 16),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(4),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickThumbnail() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() => _newThumbnail = File(image.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Görsel seçme hatası: $e')),
        );
      }
    }
  }

  Future<void> _pickGalleryImages() async {
    try {
      final images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (images.isNotEmpty) {
        setState(() {
          _newImages.addAll(images.map((e) => File(e.path)));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Görsel seçme hatası: $e')),
        );
      }
    }
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  Future<void> _deleteExistingImage(String imageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Görseli Sil'),
        content: const Text('Bu görseli silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _newsService.deleteNewsImage(imageId);
      if (success) {
        setState(() {
          _existingImages.removeWhere((img) => img.id == imageId);
        });
      }
    }
  }

  Future<void> _saveNews() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      String? thumbnailUrl = _thumbnailUrl;

      // Yeni thumbnail yükle
      if (_newThumbnail != null) {
        final uploaded = await _newsService.uploadNewsImage(
          newsId: widget.news?.id ?? '',
          imageFile: _newThumbnail!,
        );
        if (uploaded != null) {
          thumbnailUrl = uploaded.imageUrl;
        }
      }

      bool success;
      String? newsId = widget.news?.id;

      if (isEditing) {
        success = await _newsService.updateNews(
          id: widget.news!.id,
          title: _titleController.text,
          content: _contentController.text,
          summary: _summaryController.text.isEmpty ? null : _summaryController.text,
          thumbnailUrl: thumbnailUrl,
          categoryId: _selectedCategory,
          institutionId: _selectedInstitution,
          isFeatured: _isFeatured,
          isPublished: _isPublished,
          isBreaking: _isBreaking,
        );
      } else {
        final created = await _newsService.createNews(
          title: _titleController.text,
          content: _contentController.text,
          summary: _summaryController.text.isEmpty ? null : _summaryController.text,
          thumbnailUrl: thumbnailUrl,
          categoryId: _selectedCategory,
          institutionId: _selectedInstitution,
          isFeatured: _isFeatured,
          isPublished: _isPublished,
          isBreaking: _isBreaking,
        );
        
        if (created != null) {
          newsId = created.id;
          success = true;
          
          // Yeni görselleri yükle
          if (_newImages.isNotEmpty) {
            for (final image in _newImages) {
              await _newsService.uploadNewsImage(
                newsId: newsId!,
                imageFile: image,
              );
            }
          }
        } else {
          success = false;
        }
      }

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEditing ? 'Haber güncellendi' : 'Haber oluşturuldu')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }
}
