// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/ai_quick_prompt_model.dart';
import '../../../core/models/ai_prompt_image_model.dart';
import '../../ai_chat/services/ai_chat_service.dart';
import '../../ai_chat/theme/ai_chat_theme.dart';
import '../../ai_chat/widgets/ai_quick_prompt_card.dart';

/// Admin Panel - AI Prompts & Images Yönetimi Sekmesi
/// Görsellı prompt şablonları ve görsel kütüphanesi yönetimi
class AIPromptsImagesTab extends StatefulWidget {
  const AIPromptsImagesTab({super.key});

  @override
  State<AIPromptsImagesTab> createState() => _AIPromptsImagesTabState();
}

class _AIPromptsImagesTabState extends State<AIPromptsImagesTab>
    with SingleTickerProviderStateMixin {
  final AIChatService _service = AIChatService();
  late TabController _tabController;

  // Prompts state
  List<AIQuickPrompt> _prompts = [];
  bool _isLoadingPrompts = true;
  String? _selectedPromptCategory;

  // Images state
  List<AIPromptImage> _images = [];
  bool _isLoadingImages = true;
  String? _selectedImageCategory;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPrompts();
    _loadImages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // =====================================================
  // PROMPTS İŞLEMLERİ
  // =====================================================

  Future<void> _loadPrompts() async {
    setState(() => _isLoadingPrompts = true);
    try {
      final prompts = await _service.getAllQuickPrompts();
      if (mounted) {
        setState(() {
          _prompts = prompts;
          _isLoadingPrompts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPrompts = false);
    }
  }

  Future<void> _addPrompt({
    required String title,
    required String prompt,
    String icon = 'lightbulb_outline',
    String color = '#7B2CBF',
    String? imageUrl,
    String? category,
  }) async {
    try {
      final id = await _service.addQuickPrompt(
        title: title,
        prompt: prompt,
        icon: icon,
        color: color,
        sortOrder: _prompts.length,
      );
      if (id != null) {
        // Update with new fields
        await _service.updateQuickPrompt(AIQuickPrompt(
          id: id,
          title: title,
          prompt: prompt,
          icon: icon,
          color: color,
          imageUrl: imageUrl,
          category: category ?? 'general',
          thumbnailColor: color,
          sortOrder: _prompts.length,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        await _loadPrompts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Şablon eklendi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updatePrompt(AIQuickPrompt prompt) async {
    try {
      await _service.updateQuickPrompt(prompt);
      await _loadPrompts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şablon güncellendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deletePrompt(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sil'),
        content: const Text('Bu şablonu silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.deleteQuickPrompt(id);
      await _loadPrompts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şablon silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _togglePromptActive(AIQuickPrompt prompt) async {
    await _service.updateQuickPrompt(prompt.copyWith(isActive: !prompt.isActive));
    await _loadPrompts();
  }

  // =====================================================
  // IMAGES İŞLEMLERİ
  // =====================================================

  Future<void> _loadImages() async {
    setState(() => _isLoadingImages = true);
    try {
      final images = await _service.getPromptImages(
        category: _selectedImageCategory,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      if (mounted) {
        setState(() {
          _images = images;
          _isLoadingImages = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  Future<void> _uploadImage({
    required File file,
    String? category,
    List<String>? tags,
  }) async {
    try {
      final imageUrl = await _service.uploadPromptImage(
        file,
        category: category,
        tags: tags,
      );
      if (imageUrl != null) {
        await _loadImages();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Görsel yüklendi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteImage(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sil'),
        content: const Text('Bu görseli silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _service.deletePromptImage(id);
        await _loadImages();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Görsel silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // =====================================================
  // WIDGETS
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AIChatTheme.paddingL,
            vertical: AIChatTheme.paddingM,
          ),
          decoration: BoxDecoration(
            color: AIChatTheme.cardBackground,
            borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              gradient: AIChatTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(4),
            labelColor: Colors.white,
            unselectedLabelColor: AIChatTheme.textMuted,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.flash_on_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Promt Şablonları'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Görsel Kütüphanesi'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Tab views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPromptsTab(),
              _buildImagesTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromptsTab() {
    return Column(
      children: [
        // Header with filters and add button
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AIChatTheme.paddingL,
            vertical: AIChatTheme.paddingS,
          ),
          child: Row(
            children: [
              // Category filter
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AIChatTheme.paddingM),
                  decoration: BoxDecoration(
                    color: AIChatTheme.cardBackground,
                    borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedPromptCategory,
                      hint: Text('Tüm Kategoriler', style: AIChatTheme.bodySmall),
                      isExpanded: true,
                      dropdownColor: AIChatTheme.cardBackground,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Tüm Kategoriler'),
                        ),
                        ...AIQuickPrompt.categoryPresets.map((cat) {
                          return DropdownMenuItem(
                            value: cat['value'],
                            child: Text(cat['name']!),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedPromptCategory = value);
                        _loadPrompts();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AIChatTheme.paddingM),
              // Add button
              Container(
                decoration: AIChatTheme.sendButtonDecoration,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showPromptDialog(null),
                    borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                    child: const Padding(
                      padding: EdgeInsets.all(AIChatTheme.paddingM),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text('Ekle', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Prompts grid
        Expanded(
          child: _isLoadingPrompts
              ? const Center(child: CircularProgressIndicator())
              : _prompts.isEmpty
                  ? _buildEmptyPromptsState()
                  : _buildPromptsGrid(),
        ),
      ],
    );
  }

  Widget _buildPromptsGrid() {
    final filteredPrompts = _selectedPromptCategory == null
        ? _prompts
        : _prompts.where((p) => p.category == _selectedPromptCategory).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(AIChatTheme.paddingL),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AIChatTheme.paddingM,
        crossAxisSpacing: AIChatTheme.paddingM,
        childAspectRatio: 1.0,
      ),
      itemCount: filteredPrompts.length,
      itemBuilder: (context, index) {
        final prompt = filteredPrompts[index];
        return AIEditablePromptCard(
          prompt: prompt,
          onEdit: () => _showPromptDialog(prompt),
          onDelete: () => _deletePrompt(prompt.id),
          onToggleActive: (active) => _togglePromptActive(prompt),
        );
      },
    );
  }

  Widget _buildEmptyPromptsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.flash_off_rounded,
            size: 64,
            color: AIChatTheme.textMuted,
          ),
          const SizedBox(height: AIChatTheme.paddingM),
          Text(
            'Henüz prompt şablonu yok',
            style: AIChatTheme.titleMedium.copyWith(
              color: AIChatTheme.textMuted,
            ),
          ),
          const SizedBox(height: AIChatTheme.paddingS),
          Text(
            'Yeni şablon eklemek için "Ekle" butonuna tıklayın',
            style: AIChatTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildImagesTab() {
    return Column(
      children: [
        // Header with search and upload
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AIChatTheme.paddingL,
            vertical: AIChatTheme.paddingS,
          ),
          child: Row(
            children: [
              // Search field
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AIChatTheme.cardBackground,
                    borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                  ),
                  child: TextField(
                    onChanged: (value) {
                      _searchQuery = value;
                      _loadImages();
                    },
                    style: AIChatTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'Görsel ara...',
                      hintStyle: AIChatTheme.bodySmall,
                      prefixIcon: Icon(Icons.search, color: AIChatTheme.textMuted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AIChatTheme.paddingM,
                        vertical: AIChatTheme.paddingM,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AIChatTheme.paddingM),
              // Upload button
              Container(
                decoration: AIChatTheme.sendButtonDecoration,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _showUploadDialog,
                    borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                    child: const Padding(
                      padding: EdgeInsets.all(AIChatTheme.paddingM),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_upload, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text('Yükle', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Category filter
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AIChatTheme.paddingL,
            vertical: AIChatTheme.paddingS,
          ),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryChip(null, 'Tümü'),
                ...AIPromptImage.categoryPresets.map((cat) {
                  return _buildCategoryChip(cat['value'], cat['name']!);
                }),
              ],
            ),
          ),
        ),

        // Images grid
        Expanded(
          child: _isLoadingImages
              ? const Center(child: CircularProgressIndicator())
              : _images.isEmpty
                  ? _buildEmptyImagesState()
                  : _buildImagesGrid(),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String? value, String label) {
    final isSelected = _selectedImageCategory == value;
    return Padding(
      padding: const EdgeInsets.only(right: AIChatTheme.paddingS),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AIChatTheme.textSecondary,
          fontSize: 12,
        ),
        backgroundColor: AIChatTheme.cardBackground,
        selectedColor: AIChatTheme.primaryGradientStart,
        checkmarkColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AIChatTheme.radiusSmall),
        ),
        onSelected: (_) {
          setState(() => _selectedImageCategory = value);
          _loadImages();
        },
      ),
    );
  }

  Widget _buildImagesGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(AIChatTheme.paddingL),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AIChatTheme.paddingM,
        crossAxisSpacing: AIChatTheme.paddingM,
        childAspectRatio: 1,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final image = _images[index];
        return _buildImageCard(image);
      },
    );
  }

  Widget _buildImageCard(AIPromptImage image) {
    return GestureDetector(
      onTap: () => _showImageDetail(image),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
          boxShadow: AIChatTheme.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              CachedNetworkImage(
                imageUrl: image.thumbnailUrl ?? image.imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: AIChatTheme.cardBackground,
                  child: Icon(
                    Icons.broken_image,
                    color: AIChatTheme.textMuted,
                  ),
                ),
              ),
              // Hover overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                ),
              ),
              // Category badge
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AICategoryColors.getColorForCategory(image.category),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    image.category,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
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

  Widget _buildEmptyImagesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: AIChatTheme.textMuted,
          ),
          const SizedBox(height: AIChatTheme.paddingM),
          Text(
            'Henüz görsel yok',
            style: AIChatTheme.titleMedium.copyWith(
              color: AIChatTheme.textMuted,
            ),
          ),
          const SizedBox(height: AIChatTheme.paddingS),
          Text(
            'Görsel yüklemek için "Yükle" butonuna tıklayın',
            style: AIChatTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // =====================================================
  // DIALOGS
  // =====================================================

  void _showPromptDialog(AIQuickPrompt? existingPrompt) {
    final isEditing = existingPrompt != null;
    final titleController = TextEditingController(text: existingPrompt?.title ?? '');
    final promptController = TextEditingController(text: existingPrompt?.prompt ?? '');
    String selectedIcon = existingPrompt?.icon ?? 'lightbulb_outline';
    String selectedColor = existingPrompt?.color ?? '#7B2CBF';
    String selectedCategory = existingPrompt?.category ?? 'general';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AIChatTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AIChatTheme.radiusXLarge),
          ),
          title: Text(
            isEditing ? 'Şablonu Düzenle' : 'Yeni Şablon',
            style: AIChatTheme.titleLarge,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                Text('Başlık', style: AIChatTheme.labelMedium),
                const SizedBox(height: AIChatTheme.paddingS),
                TextField(
                  controller: titleController,
                  style: AIChatTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Örn: Alışveriş Listesi',
                    filled: true,
                    fillColor: AIChatTheme.cardBackgroundLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AIChatTheme.paddingL),

                // Prompt
                Text('Prompt', style: AIChatTheme.labelMedium),
                const SizedBox(height: AIChatTheme.paddingS),
                TextField(
                  controller: promptController,
                  maxLines: 4,
                  style: AIChatTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'AI\'ye sorulacak soru veya komut...',
                    filled: true,
                    fillColor: AIChatTheme.cardBackgroundLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AIChatTheme.paddingL),

                // Kategori
                Text('Kategori', style: AIChatTheme.labelMedium),
                const SizedBox(height: AIChatTheme.paddingS),
                Wrap(
                  spacing: AIChatTheme.paddingS,
                  runSpacing: AIChatTheme.paddingS,
                  children: AIQuickPrompt.categoryPresets.map((cat) {
                    final isSelected = selectedCategory == cat['value'];
                    return ChoiceChip(
                      selected: isSelected,
                      label: Text(cat['name']!),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AIChatTheme.textSecondary,
                        fontSize: 12,
                      ),
                      backgroundColor: AIChatTheme.cardBackgroundLight,
                      selectedColor: AIQuickPrompt.getColorFromString(selectedColor),
                      onSelected: (_) {
                        setDialogState(() => selectedCategory = cat['value']!);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: AIChatTheme.paddingL),

                // Renkler
                Text('Renk', style: AIChatTheme.labelMedium),
                const SizedBox(height: AIChatTheme.paddingS),
                Wrap(
                  spacing: AIChatTheme.paddingS,
                  runSpacing: AIChatTheme.paddingS,
                  children: AIQuickPrompt.colorPresets.map((colorMap) {
                    final isSelected = selectedColor == colorMap['color'];
                    final color = AIQuickPrompt.getColorFromString(colorMap['color']!);
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() => selectedColor = colorMap['color']!);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: isSelected
                              ? AIChatTheme.glowShadow(color)
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('İptal', style: TextStyle(color: AIChatTheme.textMuted)),
            ),
            Container(
              decoration: AIChatTheme.sendButtonDecoration,
              child: TextButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty ||
                      promptController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Başlık ve prompt boş olamaz'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  Navigator.pop(context);
                  if (isEditing) {
                    _updatePrompt(existingPrompt.copyWith(
                      title: titleController.text.trim(),
                      prompt: promptController.text.trim(),
                      icon: selectedIcon,
                      color: selectedColor,
                      category: selectedCategory,
                      thumbnailColor: selectedColor,
                    ));
                  } else {
                    _addPrompt(
                      title: titleController.text.trim(),
                      prompt: promptController.text.trim(),
                      icon: selectedIcon,
                      color: selectedColor,
                      category: selectedCategory,
                    );
                  }
                },
                child: Text(
                  isEditing ? 'Güncelle' : 'Ekle',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadDialog() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;

    String selectedCategory = 'general';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AIChatTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AIChatTheme.radiusXLarge),
          ),
          title: Text('Görsel Yükle', style: AIChatTheme.titleLarge),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AIChatTheme.cardBackgroundLight,
                      borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                    ),
                    child: Image.file(
                      File(xFile.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.image, color: Colors.grey, size: 40),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AIChatTheme.paddingL),

                // Category
                Text('Kategori', style: AIChatTheme.labelMedium),
                const SizedBox(height: AIChatTheme.paddingS),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  dropdownColor: AIChatTheme.cardBackgroundLight,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AIChatTheme.cardBackgroundLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: AIPromptImage.categoryPresets.map((cat) {
                    return DropdownMenuItem(
                      value: cat['value'],
                      child: Text(cat['name']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCategory = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('İptal', style: TextStyle(color: AIChatTheme.textMuted)),
            ),
            Container(
              decoration: AIChatTheme.sendButtonDecoration,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _uploadImage(
                    file: File(xFile.path),
                    category: selectedCategory,
                  );
                },
                child: const Text('Yükle', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageDetail(AIPromptImage image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(AIChatTheme.radiusLarge),
              child: CachedNetworkImage(
                imageUrl: image.imageUrl,
                width: 300,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: AIChatTheme.paddingL),
            // Actions
            Container(
              padding: const EdgeInsets.all(AIChatTheme.paddingM),
              decoration: BoxDecoration(
                color: AIChatTheme.cardBackground,
                borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteImage(image.id);
                    },
                    icon: Icon(Icons.delete, color: AIChatTheme.error),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: AIChatTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
