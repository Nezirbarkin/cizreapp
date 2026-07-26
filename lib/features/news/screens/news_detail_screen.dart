import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/models/news_model.dart';
import '../services/news_service.dart';

class NewsDetailScreen extends StatefulWidget {
  final NewsModel? news;
  final List<NewsCategoryModel> categories;
  final List<InstitutionModel> institutions;

  const NewsDetailScreen({
    super.key,
    this.news,
    required this.categories,
    required this.institutions,
  });

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  final NewsService _newsService = NewsService();
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
  File? _selectedImage;

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

  Future<void> _saveNews() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (widget.news == null) {
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
          thumbnailFile: _selectedImage,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Haber başarıyla oluşturuldu')),
          );
          Navigator.pop(context, true);
        }
      } else {
        final updatedNews = widget.news!.copyWith(
          title: _titleController.text,
          content: _contentController.text,
          summary: _summaryController.text,
          categoryId: _selectedCategoryId,
          institutionId: _selectedInstitutionId,
          isPublished: _isPublished,
          isFeatured: _isFeatured,
          isBreaking: _isBreaking,
          locationName: _locationController.text,
        );
        await _newsService.updateNews(updatedNews, _selectedImage);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Haber başarıyla güncellendi')),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
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
        title: Text(widget.news == null ? '📝 Yeni Haber' : '✏️ Haberi Düzenle'),
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
              _buildSectionTitle('📰 Temel Bilgiler'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Başlık *',
                  hintText: 'Haber başlığını girin',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Başlık gereklidir' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _summaryController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Özet',
                  hintText: 'Kısa özeti girin',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: 'İçerik *',
                  hintText: 'Haber içeriğini girin',
                  prefixIcon: const Icon(Icons.article),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'İçerik gereklidir' : null,
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('🖼️ Görsel'),
              const SizedBox(height: 12),
              if (widget.news?.thumbnailUrl != null && _selectedImage == null)
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: NetworkImage(widget.news!.thumbnailUrl!),
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else if (_selectedImage != null)
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Görsel Seç'),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('📂 Kategorilendirme'),
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
              _buildSectionTitle('⚙️ Seçenekler'),
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
                title: const Text('🚨 Son Dakika'),
                subtitle: const Text('Son dakika haberi olarak işaretle'),
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
                  label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet'),
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
