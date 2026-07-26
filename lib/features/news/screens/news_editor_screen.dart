import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/models/news_model.dart';
import '../../../core/services/storage_service.dart';
import '../services/news_service.dart';

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
  File? _selectedImage;
  String? _uploadedImageUrl;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.news?.title ?? '');
    _contentController = TextEditingController(text: widget.news?.content ?? '');
    _summaryController = TextEditingController(text: widget.news?.summary ?? '');
    _locationController = TextEditingController(text: widget.news?.locationName ?? '');
    _selectedCategoryId = widget.news?.categoryId;
    _selectedInstitutionId = widget.news?.institutionId;
    _isPublished = widget.news?.isPublished ?? false;
    _isFeatured = widget.news?.isFeatured ?? false;
    _isBreaking = widget.news?.isBreaking ?? false;
    _uploadedImageUrl = widget.news?.thumbnailUrl;
  }

  @override
  void dispose() {
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
      setState(() => _selectedImage = File(image.path));
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_selectedImage!.path.split('/').last}';
      final uploadUrl = await _storageService.uploadFile(
        bucket: 'news-images',
        filePath: 'thumbnails/$fileName',
        file: _selectedImage!,
      );

      if (uploadUrl != null) {
        setState(() {
          _uploadedImageUrl = uploadUrl;
          _selectedImage = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('? Görsel baþarýyla yüklendi')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('? Yükleme hatasý: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _saveNews() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (widget.news == null) {
        // Yeni haber oluþtur
        await _newsService.createNews(
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
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('? Haber baþarýyla oluþturuldu')),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Haberi güncelle
        await _newsService.updateNews(
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
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('? Haber baþarýyla güncellendi')),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('? Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.news == null ? '?? Yeni Haber' : '?? Haberi Düzenle'),
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
              _buildSectionTitle('?? Temel Bilgiler'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Baþlýk *',
                  hintText: 'Haber baþlýðýný girin',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Baþlýk gereklidir' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _summaryController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Özet',
                  hintText: 'Kýsa özeti girin',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: 'Ýçerik *',
                  hintText: 'Haber içeriðini girin',
                  prefixIcon: const Icon(Icons.article),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Ýçerik gereklidir' : null,
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('??? Görsel Yönetimi'),
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
                        onPressed: () => setState(() => _uploadedImageUrl = null),
                        icon: const Icon(Icons.delete),
                        label: const Text('Görseli Kaldýr'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
                    ),
                  ],
                )
              else if (_selectedImage != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(_selectedImage!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isUploadingImage ? null : _uploadImage,
                            icon: _isUploadingImage
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.cloud_upload),
                            label: Text(_isUploadingImage ? 'Yükleniyor...' : '?? Sunucuya Yükle'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _selectedImage = null),
                          icon: const Icon(Icons.clear),
                          label: const Text('Ýptal'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
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
                      Text('Görsel seçilmedi', style: TextStyle(color: Colors.grey[600])),
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
                    label: const Text('?? Görsel Seç'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              _buildSectionTitle('?? Kategorilendirme'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedCategoryId,
                      decoration: InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                        ...widget.categories.map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        )),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                        ...widget.institutions.map((i) => DropdownMenuItem(
                          value: i.id,
                          child: Text(i.name),
                        )),
                      ],
                      onChanged: (v) => setState(() => _selectedInstitutionId = v),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('?? Seçenekler'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _isPublished,
                onChanged: (v) => setState(() => _isPublished = v ?? false),
                title: const Text('? Yayýnla'),
                subtitle: const Text('Haberi yayýnla'),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _isFeatured,
                onChanged: (v) => setState(() => _isFeatured = v ?? false),
                title: const Text('? Öne Çýkan'),
                subtitle: const Text('Ana sayfada öne çýkar'),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _isBreaking,
                onChanged: (v) => setState(() => _isBreaking = v ?? false),
                title: const Text('?? Son Dakika'),
                subtitle: const Text('Son dakika haberi olarak iþaretle'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveNews,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Kaydediliyor...' : '?? Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
}
